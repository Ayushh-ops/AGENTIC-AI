"""
Multi-Agent Research Assistant - Root Application Entry Point

Thin entrypoint that boots the FastAPI backend service via Uvicorn.
Points to the canonical FastAPI instance defined in `backend.main:app`.
"""

import uvicorn

if __name__ == "__main__":
    uvicorn.run(
        "backend.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
    )
