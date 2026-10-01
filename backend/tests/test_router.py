"""
Unit and integration tests for the message router service and POST /ask endpoint.
"""

from unittest.mock import patch, MagicMock
import pytest
from fastapi.testclient import TestClient

from backend.main import app
from backend.app.core.config import settings
from backend.app.services.router import classify, check_canned
from backend.app.services.llm_service import LLMError
from backend.app.workflows.research_workflow import ResearchError

client = TestClient(app)

MOCK_RESEARCH_RESULT = {
    "topic": "Quantum computing in 2026",
    "report_markdown": "# Research Report: Quantum computing in 2026\n\n## Executive Summary\nSummary...",
    "sources": [{"title": "Source 1", "url": "https://example.com/1", "content": "Text 1"}],
    "claims": [
        {
            "statement": "Quantum supremacy demonstrated.",
            "status": "supported",
            "source_urls": ["https://example.com/1"],
            "source_url": "https://example.com/1",
            "evidence": "Quantum supremacy demonstrated.",
        }
    ],
}


def test_greeting_chat_zero_llm_calls(monkeypatch):
    """Verify greeting returns canned chat with zero LLM calls and works without API keys."""
    monkeypatch.setattr(settings, "groq_api_key", None)
    monkeypatch.setattr(settings, "tavily_api_key", None)

    with patch("backend.main.chat") as mock_chat:
        response = client.post("/ask", json={"message": "hello"})
        assert response.status_code == 200
        data = response.json()
        assert data["mode"] == "chat"
        assert data["research"] is None
        assert data["llm_calls"] == 0
        assert data["search_calls"] == 0
        assert "research" in data["reply"].lower()
        mock_chat.assert_not_called()


def test_hinglish_greeting_chat(monkeypatch):
    """Verify Hinglish greeting is routed to chat with zero LLM calls."""
    monkeypatch.setattr(settings, "groq_api_key", None)
    with patch("backend.main.chat") as mock_chat:
        response = client.post("/ask", json={"message": "kaise ho bhai"})
        assert response.status_code == 200
        data = response.json()
        assert data["mode"] == "chat"
        assert data["llm_calls"] == 0
        assert data["search_calls"] == 0
        mock_chat.assert_not_called()

    # Also test 'namaste'
    with patch("backend.main.chat") as mock_chat:
        response = client.post("/ask", json={"message": "namaste"})
        assert response.status_code == 200
        data = response.json()
        assert data["mode"] == "chat"
        assert data["llm_calls"] == 0
        mock_chat.assert_not_called()


def test_thanks_canned(monkeypatch):
    """Verify thanks message returns canned response with zero LLM calls."""
    monkeypatch.setattr(settings, "groq_api_key", None)
    with patch("backend.main.chat") as mock_chat:
        response = client.post("/ask", json={"message": "thanks!"})
        assert response.status_code == 200
        data = response.json()
        assert data["mode"] == "chat"
        assert data["llm_calls"] == 0
        assert data["search_calls"] == 0
        assert "welcome" in data["reply"].lower()
        mock_chat.assert_not_called()


def test_quantum_computing_2026_research_no_classifier_call(monkeypatch):
    """Verify 'Quantum computing in 2026' triggers research without any classifier LLM call."""
    monkeypatch.setattr(settings, "groq_api_key", "test-key")
    monkeypatch.setattr(settings, "tavily_api_key", "test-key")

    with patch("backend.main.classify", wraps=classify) as spy_classify:
        with patch("backend.main.chat") as mock_chat:
            with patch("backend.main.run_research", return_value=MOCK_RESEARCH_RESULT) as mock_run:
                response = client.post("/ask", json={"message": "Quantum computing in 2026"})
                assert response.status_code == 200
                data = response.json()
                assert data["mode"] == "research"
                assert data["research"]["topic"] == "Quantum computing in 2026"
                mock_run.assert_called_once_with(
                    topic="Quantum computing in 2026",
                    depth="standard",
                    research_type="general",
                )
                # Classify was called but made NO chat calls
                mock_chat.assert_not_called()


def test_unclear_one_word_input_one_classifier_call(monkeypatch):
    """Verify unclear one-word input triggers exactly one classifier LLM call."""
    monkeypatch.setattr(settings, "groq_api_key", "test-key")
    monkeypatch.setattr(settings, "tavily_api_key", "test-key")

    # Classifier returns 'RESEARCH', then run_research is executed
    with patch("backend.app.services.router.chat", return_value="RESEARCH") as mock_classifier_chat:
        with patch("backend.main.run_research", return_value=MOCK_RESEARCH_RESULT) as mock_run:
            response = client.post("/ask", json={"message": "quantum"})
            assert response.status_code == 200
            data = response.json()
            assert data["mode"] == "research"
            assert mock_classifier_chat.call_count == 1
            call_kwargs = mock_classifier_chat.call_args[1]
            assert call_kwargs.get("max_tokens") == 5
            assert call_kwargs.get("temperature") == 0.0
            mock_run.assert_called_once_with(
                topic="quantum",
                depth="standard",
                research_type="general",
            )


def test_classifier_failure_defaults_to_research(monkeypatch):
    """Verify that if the classifier LLM call fails, the router defaults to research."""
    monkeypatch.setattr(settings, "groq_api_key", "test-key")
    monkeypatch.setattr(settings, "tavily_api_key", "test-key")

    with patch("backend.app.services.router.chat", side_effect=LLMError("Classifier timeout")):
        with patch("backend.main.run_research", return_value=MOCK_RESEARCH_RESULT) as mock_run:
            response = client.post("/ask", json={"message": "quantum"})
            assert response.status_code == 200
            data = response.json()
            assert data["mode"] == "research"
            mock_run.assert_called_once_with(
                topic="quantum",
                depth="standard",
                research_type="general",
            )


def test_chat_reply_uses_exactly_one_llm_call_and_zero_search_calls(monkeypatch):
    """Verify non-canned chat message uses exactly one LLM call and zero search calls."""
    monkeypatch.setattr(settings, "groq_api_key", "test-key")

    # 'ok' is small talk (0 classifier calls), but not in pure canned list
    with patch("backend.main.chat", return_value="I am ready to help you research any topic.") as mock_chat:
        response = client.post("/ask", json={"message": "ok"})
        assert response.status_code == 200
        data = response.json()
        assert data["mode"] == "chat"
        assert data["reply"] == "I am ready to help you research any topic."
        assert data["llm_calls"] == 1
        assert data["search_calls"] == 0
        mock_chat.assert_called_once()


def test_ask_research_path_calls_workflow(monkeypatch):
    """Verify research path calls run_research with topic."""
    monkeypatch.setattr(settings, "groq_api_key", "test-key")
    monkeypatch.setattr(settings, "tavily_api_key", "test-key")

    with patch("backend.main.run_research", return_value=MOCK_RESEARCH_RESULT) as mock_run:
        response = client.post("/ask", json={"message": "Compare solar and wind energy"})
        assert response.status_code == 200
        data = response.json()
        assert data["mode"] == "research"
        assert data["research"]["topic"] == "Quantum computing in 2026"
        mock_run.assert_called_once_with(
            topic="Compare solar and wind energy",
            depth="standard",
            research_type="general",
        )


def test_ask_validation_errors():
    """Verify POST /ask returns 422 for empty, whitespace-only, missing, or oversized message."""
    # Empty string
    res1 = client.post("/ask", json={"message": ""})
    assert res1.status_code == 422

    # Whitespace only
    res2 = client.post("/ask", json={"message": "   "})
    assert res2.status_code == 422

    # Missing message field
    res3 = client.post("/ask", json={})
    assert res3.status_code == 422

    # Exceeding 200 characters
    res4 = client.post("/ask", json={"message": "a" * 201})
    assert res4.status_code == 422


def test_ask_missing_keys_and_error_handling(monkeypatch):
    """Verify 503 for missing keys in research mode and 502 for workflow errors."""
    monkeypatch.setattr(settings, "groq_api_key", None)
    monkeypatch.setattr(settings, "tavily_api_key", None)

    # Research signal with missing keys -> 503
    res_503 = client.post("/ask", json={"message": "Quantum computing in 2026"})
    assert res_503.status_code == 503
    assert res_503.json()["detail"] == "API keys not configured."

    # Workflow error -> 502
    monkeypatch.setattr(settings, "groq_api_key", "test-key")
    monkeypatch.setattr(settings, "tavily_api_key", "test-key")
    with patch("backend.main.run_research", side_effect=ResearchError("Search failed")):
        res_502 = client.post("/ask", json={"message": "Quantum computing in 2026"})
        assert res_502.status_code == 502
        assert "Research workflow error" in res_502.json()["detail"]
