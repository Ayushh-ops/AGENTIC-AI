"""
Unit tests for backend services (LLM and Search).
All tests use mocks (respx or monkeypatch) and require no network or real API keys.
"""

import json
import pytest
import respx
import httpx
from backend.app.core.config import settings
from backend.app.services.llm_service import chat, LLMError, GROQ_API_URL
from backend.app.services.search_service import search, SearchError, TAVILY_API_URL


# --- LLM Service Tests ---

def test_llm_chat_missing_key(monkeypatch):
    """Verify that chat() raises LLMError if GROQ_API_KEY is not set."""
    monkeypatch.setattr(settings, "groq_api_key", None)
    with pytest.raises(LLMError, match="Groq API key is not configured"):
        chat(system="system prompt", user="user prompt")


@respx.mock
def test_llm_chat_success(monkeypatch):
    """Verify that chat() returns generated text content on 200 OK."""
    monkeypatch.setattr(settings, "groq_api_key", "mock-groq-key")
    respx.post(GROQ_API_URL).mock(
        return_value=httpx.Response(
            200,
            json={
                "choices": [
                    {"message": {"role": "assistant", "content": "Generated research content."}}
                ]
            },
        )
    )

    result = chat(system="You are an analyst.", user="Explain quantum physics.")
    assert result == "Generated research content."


@respx.mock
def test_llm_chat_api_failure(monkeypatch):
    """Verify that chat() raises LLMError when Groq returns an error status."""
    monkeypatch.setattr(settings, "groq_api_key", "mock-groq-key")
    respx.post(GROQ_API_URL).mock(
        return_value=httpx.Response(500, text="Internal Server Error")
    )

    with pytest.raises(LLMError, match="Groq API error"):
        chat(system="sys", user="user")


# --- Search Service Tests ---

def test_search_missing_key(monkeypatch):
    """Verify that search() raises SearchError if TAVILY_API_KEY is not set."""
    monkeypatch.setattr(settings, "tavily_api_key", None)
    with pytest.raises(SearchError, match="Tavily API key is not configured"):
        search(query="artificial intelligence")


@respx.mock
def test_search_success(monkeypatch):
    """Verify that search() returns normalized results on 200 OK."""
    monkeypatch.setattr(settings, "tavily_api_key", "mock-tavily-key")
    respx.post(TAVILY_API_URL).mock(
        return_value=httpx.Response(
            200,
            json={
                "results": [
                    {
                        "title": "AI Overview",
                        "url": "https://example.com/ai",
                        "content": "AI is transforming industries.",
                    },
                    {
                        "title": "Machine Learning",
                        "url": "https://example.com/ml",
                        "content": "ML is a subset of AI.",
                    },
                ]
            },
        )
    )

    results = search(query="AI Overview", max_results=2)
    assert len(results) == 2
    assert results[0] == {
        "title": "AI Overview",
        "url": "https://example.com/ai",
        "content": "AI is transforming industries.",
    }
    assert results[1]["url"] == "https://example.com/ml"


@respx.mock
def test_search_api_failure(monkeypatch):
    """Verify that search() raises SearchError when Tavily returns an error status."""
    monkeypatch.setattr(settings, "tavily_api_key", "mock-tavily-key")
    respx.post(TAVILY_API_URL).mock(
        return_value=httpx.Response(401, text="Unauthorized: Invalid API key")
    )

    with pytest.raises(SearchError, match="Tavily API error"):
        search(query="test query")


@respx.mock
def test_search_excludes_domains(monkeypatch):
    """Verify that search() sends exclude_domains and filters out excluded domain results."""
    monkeypatch.setattr(settings, "tavily_api_key", "mock-tavily-key")
    route = respx.post(TAVILY_API_URL).mock(
        return_value=httpx.Response(
            200,
            json={
                "results": [
                    {
                        "title": "Allowed Source",
                        "url": "https://nature.com/article",
                        "content": "Quantum advances.",
                    },
                    {
                        "title": "YouTube Video",
                        "url": "https://www.youtube.com/watch?v=123",
                        "content": "Video transcript.",
                    },
                ]
            },
        )
    )

    results = search(query="quantum", max_results=5)
    assert len(results) == 1
    assert results[0]["url"] == "https://nature.com/article"

    # Verify payload included exclude_domains
    sent_payload = json.loads(route.calls.last.request.content)
    assert "exclude_domains" in sent_payload
    assert "youtube.com" in sent_payload["exclude_domains"]
    assert "reddit.com" in sent_payload["exclude_domains"]
