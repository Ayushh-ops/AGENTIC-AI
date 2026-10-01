from fastapi import FastAPI, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from backend.app.core.config import settings
from backend.app.models.research import ResearchRequest, ResearchResponse
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
