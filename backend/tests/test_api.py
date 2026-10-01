"""
API integration tests for the /research endpoint.
Uses FastAPI TestClient with mocked workflows and configuration.
"""

from unittest.mock import patch
from fastapi.testclient import TestClient
from backend.main import app
from backend.app.core.config import settings
from backend.app.workflows.research_workflow import ResearchError

client = TestClient(app)


def test_post_research_success(monkeypatch):
    """Verify POST /research returns 200 and research report on success."""
    monkeypatch.setattr(settings, "groq_api_key", "mock-groq-key")
    monkeypatch.setattr(settings, "tavily_api_key", "mock-tavily-key")

    mock_workflow_result = {
        "topic": "Quantum Computing",
        "report_markdown": "# Quantum Computing\n\nExecutive summary...",
        "sources": [{"title": "QC Intro", "url": "https://example.com/qc", "content": "QC details"}],
        "claims": [{"statement": "Superposition is real", "status": "supported", "source_url": "https://example.com/qc"}],
    }

    with patch("backend.main.run_research", return_value=mock_workflow_result) as mock_run:
        response = client.post("/research", json={"topic": "Quantum Computing"})
        assert response.status_code == 200
        data = response.json()
        assert data["topic"] == "Quantum Computing"
        assert "# Quantum Computing" in data["report_markdown"]
        assert len(data["sources"]) == 1
        assert len(data["claims"]) == 1
        mock_run.assert_called_once_with(topic="Quantum Computing")


def test_post_research_empty_topic(monkeypatch):
    """Verify POST /research rejects empty or whitespace-only topic with HTTP 422."""
    monkeypatch.setattr(settings, "groq_api_key", "mock-groq-key")
    monkeypatch.setattr(settings, "tavily_api_key", "mock-tavily-key")

    response_empty = client.post("/research", json={"topic": ""})
    assert response_empty.status_code == 422

    response_whitespace = client.post("/research", json={"topic": "   "})
    assert response_whitespace.status_code == 422


def test_post_research_topic_too_long(monkeypatch):
    """Verify POST /research rejects topics exceeding 200 characters with HTTP 422."""
    monkeypatch.setattr(settings, "groq_api_key", "mock-groq-key")
    monkeypatch.setattr(settings, "tavily_api_key", "mock-tavily-key")

    response = client.post("/research", json={"topic": "A" * 201})
    assert response.status_code == 422


def test_post_research_missing_keys(monkeypatch):
    """Verify POST /research returns HTTP 503 when API keys are not configured."""
    monkeypatch.setattr(settings, "groq_api_key", None)
    monkeypatch.setattr(settings, "tavily_api_key", None)

    response = client.post("/research", json={"topic": "Machine Learning"})
    assert response.status_code == 503
    assert response.json()["detail"] == "API keys not configured."


def test_post_research_workflow_error(monkeypatch):
    """Verify POST /research maps ResearchError to HTTP 502 Bad Gateway."""
    monkeypatch.setattr(settings, "groq_api_key", "mock-groq-key")
    monkeypatch.setattr(settings, "tavily_api_key", "mock-tavily-key")

    with patch("backend.main.run_research", side_effect=ResearchError("External service timeout")):
        response = client.post("/research", json={"topic": "Robotics"})
        assert response.status_code == 502
        assert "Research workflow error" in response.json()["detail"]
