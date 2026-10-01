"""
Unit tests for the Multi-Agent Research Assistant backend.
"""

from fastapi.testclient import TestClient
from backend.main import app
from backend.app.config import settings

client = TestClient(app)


def test_health_check_status_code():
    """Verify that GET /health returns HTTP 200 OK."""
    response = client.get("/health")
    assert response.status_code == 200


def test_health_check_payload():
    """Verify that GET /health returns the expected JSON structure."""
    response = client.get("/health")
    data = response.json()
    assert data == {
        "status": "ok",
        "service": "multi-agent-research-assistant",
    }


def test_configuration_loading():
    """Verify that Settings safely loads environment configurations."""
    assert hasattr(settings, "environment")
    assert hasattr(settings, "openai_api_key")
    assert hasattr(settings, "gemini_api_key")
    assert hasattr(settings, "groq_api_key")
    assert hasattr(settings, "tavily_api_key")
    assert hasattr(settings, "database_url")
