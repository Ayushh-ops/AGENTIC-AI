from fastapi import FastAPI, HTTPException, Request, status
from fastapi.middleware.cors import CORSMiddleware
from backend.app.core.config import settings
from backend.app.models.research import (
    ALLOWED_LANGUAGES,
    ResearchRequest,
    ResearchResponse,
    AskRequest,
    AskResponse,
)
from backend.app.services.router import check_canned, classify
from backend.app.services.llm_service import chat, LLMError, llm_call_counter
from backend.app.services.search_service import search_call_counter
from backend.app.workflows.research_workflow import run_research, ResearchError
from typing import List, Optional

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

# -------------------------------------------------------------------------
# Key parsing helpers (request-scoped; keys never stored globally)
# -------------------------------------------------------------------------

_MAX_KEYS = 10
_MAX_KEY_LEN = 200


def _parse_key_header(raw: Optional[str], header_name: str) -> Optional[List[str]]:
    """
    Parse a comma-separated API key header.

    Rules (all checked before use):
    - At most 10 keys.
    - Each key trimmed; must not be empty.
    - Each key max 200 chars, no internal whitespace.

    Returns None when the header is absent.
    Raises HTTPException(400) on any validation violation.
    Keys are never included in error messages.
    """
    if raw is None:
        return None

    parts = raw.split(",")
    if len(parts) > _MAX_KEYS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"{header_name} must contain at most {_MAX_KEYS} keys.",
        )

    keys: List[str] = []
    for i, part in enumerate(parts, 1):
        key = part.strip()
        if not key:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"{header_name} key #{i} must not be empty.",
            )
        if len(key) > _MAX_KEY_LEN:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"{header_name} key #{i} exceeds maximum length of {_MAX_KEY_LEN} characters.",
            )
        # No internal whitespace
        if any(c.isspace() for c in key):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"{header_name} key #{i} must not contain whitespace.",
            )
        keys.append(key)

    return keys if keys else None


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
def ask_assistant(request: AskRequest, http_request: Request) -> AskResponse:
    """
    Cost-saving router endpoint:
    - Pure small talk returns a canned reply (0 LLM calls, 0 Tavily searches, no API keys needed).
    - Other chat messages make 1 plain LLM call (max_tokens ~150).
    - Research topics execute the full multi-agent research workflow.

    Optional headers:
    - X-Groq-Keys: comma-separated Groq API keys (max 10, each max 200 chars, no whitespace)
    - X-Tavily-Keys: comma-separated Tavily API keys (same rules)
    Keys override .env; on 429/401/403, the next key is tried automatically.
    """
    # --- Extract and validate per-request API key headers ---
    groq_keys = _parse_key_header(
        http_request.headers.get("X-Groq-Keys"), "X-Groq-Keys"
    )
    tavily_keys = _parse_key_header(
        http_request.headers.get("X-Tavily-Keys"), "X-Tavily-Keys"
    )

    # --- Language validation (already done by Pydantic validator; language is safe) ---
    language: str = request.language  # always a value from ALLOWED_LANGUAGES

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
            # Determine effective Groq key availability
            effective_groq = groq_keys or ([settings.groq_api_key] if settings.groq_api_key else [])
            if not effective_groq:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="No API key configured. Add keys in Settings or in the backend .env.",
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
                    api_keys=groq_keys,
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
                if "not configured" in msg.lower() or "no groq api key" in msg.lower() or "no api key" in msg.lower():
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="No API key configured. Add keys in Settings or in the backend .env.",
                    ) from exc
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"Chat error: {msg}",
                ) from exc
        else:
            # Research mode — check key availability
            effective_groq = groq_keys or ([settings.groq_api_key] if settings.groq_api_key else [])
            effective_tavily = tavily_keys or ([settings.tavily_api_key] if settings.tavily_api_key else [])
            if not effective_groq or not effective_tavily:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="No API key configured. Add keys in Settings or in the backend .env.",
                )
            try:
                depth_val = (
                    request.depth.value
                    if hasattr(request.depth, "value")
                    else str(request.depth or "standard")
                )
                type_val = (
                    request.research_type.value
                    if hasattr(request.research_type, "value")
                    else str(request.research_type or "general")
                )
                result = run_research(
                    topic=request.message,
                    depth=depth_val,
                    research_type=type_val,
                    groq_keys=groq_keys,
                    tavily_keys=tavily_keys,
                    language=language,
                )
                return AskResponse(
                    mode="research",
                    reply=None,
                    research=ResearchResponse(**result),
                    llm_calls=len(llm_call_counter.get() or []),
                    search_calls=len(search_call_counter.get() or []),
                )
            except ResearchError as exc:
                msg = str(exc)
                if "not configured" in msg.lower() or "no api key" in msg.lower():
                    raise HTTPException(
                        status_code=status.HTTP_400_BAD_REQUEST,
                        detail="No API key configured. Add keys in Settings or in the backend .env.",
                    ) from exc
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail=f"Research workflow error: {msg}",
                ) from exc
    finally:
        llm_call_counter.reset(token_llm)
        search_call_counter.reset(token_search)
