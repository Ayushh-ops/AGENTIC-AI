from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from backend.app.core.config import settings
from backend.app.models.research import (
    ResearchRequest,
    ResearchResponse,
    AskRequest,
    AskResponse,
)
from backend.app.services.router import check_canned, classify
from backend.app.services.llm_service import chat, LLMError, llm_call_counter
from backend.app.services.search_service import search_call_counter
from backend.app.workflows.research_workflow import run_research, ResearchError

app = FastAPI(
    title="Multi-Agent Research Assistant API",
    description="Core API for multi-agent research assistant.",
    version="0.1.0",
)

# WARNING: Permissive CORS configuration for local development only.
# In a production environment, replace allow_origins=["*"] with explicit
# domain origins (e.g., https://yourdomain.com) to prevent security vulnerabilities.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def get_health() -> dict[str, str]:
    """Health check endpoint to verify backend service availability."""
    return {
        "status": "ok",
        "service": "multi-agent-research-assistant",
    }


@app.post(
    "/research",
    response_model=ResearchResponse,
    status_code=status.HTTP_200_OK,
    summary="Execute multi-agent research on a topic",
)
def create_research(request: ResearchRequest) -> ResearchResponse:
    """
    Execute autonomous multi-agent research on the specified topic.
    Synchronous endpoint runs in Starlette's threadpool to prevent blocking the event loop.
    """
    if not settings.groq_api_key or not settings.tavily_api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="API keys not configured.",
        )

    try:
        result = run_research(topic=request.topic)
        return ResearchResponse(**result)
    except ResearchError as exc:
        msg = str(exc)
        if "not configured" in msg.lower():
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="API keys not configured.",
            ) from exc
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Research workflow error: {msg}",
        ) from exc


@app.post(
    "/ask",
    response_model=AskResponse,
    status_code=status.HTTP_200_OK,
    summary="Route user message to chat reply or full multi-agent research pipeline",
)
def ask_assistant(request: AskRequest) -> AskResponse:
    """
    Cost-saving router endpoint:
    - Pure small talk returns a canned reply (0 LLM calls, 0 Tavily searches, no API keys needed).
    - Other chat messages make 1 plain LLM call (max_tokens ~150).
    - Research topics execute the full multi-agent research workflow.
    """
    token_llm = llm_call_counter.set([])
    token_search = search_call_counter.set([])

    try:
        # Step 1: Zero-cost canned reply for pure small talk (works without API keys)
        is_canned, canned_reply = check_canned(request.message)
        if is_canned and canned_reply:
            return AskResponse(
                mode="chat",
                reply=canned_reply,
                research=None,
                llm_calls=0,
                search_calls=0,
            )

        # Step 2: Classify message into chat or research
        mode, reason = classify(request.message)

        if mode == "chat":
            if not settings.groq_api_key:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="API keys not configured.",
                )
            chat_system = (
                "You are a friendly, concise AI research assistant. You research topics using live web search, "
                "verify claims across independent sources, and compile cited reports. Keep your response brief "
                "(1-2 sentences) and encourage the user to provide a research topic."
            )
            try:
                calls_before = len(llm_call_counter.get() or [])
                reply_text = chat(
                    system=chat_system,
                    user=request.message,
                    temperature=0.3,
                    max_tokens=150,
                )
                calls_after = len(llm_call_counter.get() or [])
                if calls_after == calls_before and llm_call_counter.get() is not None:
                    llm_call_counter.get().append(1)

                return AskResponse(
                    mode="chat",
                    reply=reply_text,
                    research=None,
                    llm_calls=len(llm_call_counter.get() or []),
                    search_calls=len(search_call_counter.get() or []),
                )
            except LLMError as exc:
                msg = str(exc)
                if "not configured" in msg.lower():
                    raise HTTPException(
                        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                        detail="API keys not configured.",
                    ) from exc
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"Chat error: {msg}",
                ) from exc
        else:
            # Research mode
            if not settings.groq_api_key or not settings.tavily_api_key:
                raise HTTPException(
                    status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                    detail="API keys not configured.",
                )
            try:
                result = run_research(topic=request.message)
                return AskResponse(
                    mode="research",
                    reply=None,
                    research=ResearchResponse(**result),
                    llm_calls=len(llm_call_counter.get() or []),
                    search_calls=len(search_call_counter.get() or []),
                )
            except ResearchError as exc:
                msg = str(exc)
                if "not configured" in msg.lower():
                    raise HTTPException(
                        status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                        detail="API keys not configured.",
                    ) from exc
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"Research workflow error: {msg}",
                ) from exc
    finally:
        llm_call_counter.reset(token_llm)
        search_call_counter.reset(token_search)
