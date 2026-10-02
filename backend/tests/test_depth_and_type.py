"""
Mocked unit tests for research depth and research type options in POST /ask and services.
All tests use mocks (respx or monkeypatch) and require no network or real API keys.
"""

import json
from unittest.mock import patch, MagicMock
import httpx
import pytest
import respx
from fastapi.testclient import TestClient

from backend.main import app
from backend.app.core.config import settings
from backend.app.models.research import ResearchType, ResearchDepth
from backend.app.services.llm_service import GROQ_API_URL
from backend.app.services.search_service import (
    search,
    TAVILY_API_URL,
    ACADEMIC_INCLUDE_DOMAINS,
    EXCLUDED_DOMAINS,
)
from backend.app.workflows.research_workflow import DEPTH_SETTINGS, run_research
from backend.app.agents.researcher import research_topic
from backend.app.agents.fact_checker import check_facts

client = TestClient(app)

MOCK_RESEARCH_RESULT = {
    "topic": "Quantum computing",
    "report_markdown": "# Report\n\nVerified findings.",
    "sources": [{"title": "Qubit Info", "url": "https://example.org/qubit", "content": "Qubit text"}],
    "claims": [
        {
            "statement": "Qubits exist in superposition.",
            "status": "supported",
            "evidence": "Qubits exist in superposition.",
            "source_urls": ["https://example.org/qubit", "https://nature.com/qubit"],
            "source_url": "https://example.org/qubit",
        }
    ],
}


def test_defaults_apply_when_fields_are_missing(monkeypatch):
    """Verify that when depth and research_type are omitted or None, defaults apply."""
    monkeypatch.setattr(settings, "groq_api_key", "test-key")
    monkeypatch.setattr(settings, "tavily_api_key", "test-key")

    with patch("backend.main.run_research", return_value=MOCK_RESEARCH_RESULT) as mock_run:
        # Case A: fields completely omitted
        res1 = client.post("/ask", json={"message": "Quantum computing in 2026"})
        assert res1.status_code == 200
        mock_run.assert_called_with(
            topic="Quantum computing in 2026",
            depth="standard",
            research_type="general",
        )

        # Case B: explicit None / null passed
        res2 = client.post(
            "/ask",
            json={"message": "Quantum computing in 2026", "depth": None, "research_type": None},
        )
        assert res2.status_code == 200
        mock_run.assert_called_with(
            topic="Quantum computing in 2026",
            depth="standard",
            research_type="general",
        )


def test_invalid_enum_returns_422():
    """Verify that invalid depth or research_type returns HTTP 422 Unprocessable Entity."""
    # Invalid depth
    res1 = client.post("/ask", json={"message": "Quantum", "depth": "super_deep"})
    assert res1.status_code == 422
    assert "depth" in res1.text

    # Invalid research_type
    res2 = client.post("/ask", json={"message": "Quantum", "research_type": "crypto"})
    assert res2.status_code == 422
    assert "research_type" in res2.text


def test_quick_makes_no_query_generation_call_and_no_fallback_search():
    """Verify quick depth skips query-generation chat call and skips fallback searches."""
    quick_config = DEPTH_SETTINGS["quick"]
    assert quick_config["skip_query_generation"] is True
    assert quick_config["max_fallback_claims"] == 0

    # 1. Researcher agent in quick mode
    with patch("backend.app.agents.researcher.chat") as mock_chat:
        with patch(
            "backend.app.agents.researcher.search",
            return_value=[
                {"title": "Quantum Basics", "url": "https://example.com/q", "content": "Qubit text"}
            ],
        ) as mock_search:
            sources = research_topic(topic="Quantum computing", depth_config=quick_config)
            # Chat query generation must be skipped
            mock_chat.assert_not_called()
            # Search must be called once with topic as query and max_results 6
            mock_search.assert_called_once_with(
                query="Quantum computing",
                max_results=6,
                research_type="general",
            )
            assert len(sources) == 1

    # 2. Fact checker in quick mode skips fallback search
    mock_sources = [
        {
            "title": "S1",
            "url": "https://example.com/1",
            "content": "Quantum supercomputers exist and operate in laboratories worldwide today.",
        }
    ]
    claims_extract_json = json.dumps([
        {
            "statement": "Quantum supercomputers exist and operate in laboratories worldwide today.",
            "evidence": "Quantum supercomputers exist and operate in laboratories worldwide today.",
            "source_urls": ["https://example.com/1"],
        }
    ])
    cross_check_json = json.dumps({"claim_0": []})

    with patch("backend.app.agents.fact_checker.chat", side_effect=[claims_extract_json, cross_check_json]) as mock_fc_chat:
        with patch("backend.app.agents.fact_checker.search") as mock_fc_search:
            claims = check_facts(
                topic="Quantum computing",
                sources=mock_sources,
                depth_config=quick_config,
            )
            # Exactly 2 LLM calls (extraction + cross-check), ZERO fallback searches
            assert mock_fc_chat.call_count == 2
            mock_fc_search.assert_not_called()
            assert len(claims) == 1
            assert claims[0]["status"] == "single_source"


def test_deep_uses_more_queries():
    """Verify deep depth config generates up to 4 search queries, allows 6 fallback claims, and caps sources at 20."""
    deep_config = DEPTH_SETTINGS["deep"]
    assert deep_config["skip_query_generation"] is False
    assert deep_config["max_queries"] == 4
    assert deep_config["max_fallback_claims"] == 6
    assert deep_config["sources_cap"] == 20

    queries_output = "quantum computing overview\nqubit hardware architecture\nquantum supremacy benchmarks\npost-quantum cryptography algorithms"

    with patch("backend.app.agents.researcher.chat", return_value=queries_output) as mock_chat:
        with patch("backend.app.agents.researcher.search", return_value=[]) as mock_search:
            research_topic(topic="Quantum computing", depth_config=deep_config)
            mock_chat.assert_called_once()
            # Prompt must ask for up to 4 queries
            user_prompt = mock_chat.call_args[1]["user"]
            assert "up to 4" in user_prompt
            # Search must be called 4 times
            assert mock_search.call_count == 4


@respx.mock
def test_news_sets_topic_news_in_tavily_payload(monkeypatch):
    """Verify research_type='news' sends topic: news and days: 30 in Tavily payload."""
    monkeypatch.setattr(settings, "tavily_api_key", "mock-tavily-key")
    route = respx.post(TAVILY_API_URL).mock(
        return_value=httpx.Response(
            200,
            json={
                "results": [
                    {
                        "title": "Quantum Tech News",
                        "url": "https://reuters.com/tech-news",
                        "content": "Recent quantum breakthrough reported.",
                    }
                ]
            },
        )
    )

    results = search(query="Quantum advances", research_type="news")
    assert len(results) == 1
    assert results[0]["url"] == "https://reuters.com/tech-news"

    sent_payload = json.loads(route.calls.last.request.content)
    assert sent_payload.get("topic") == "news"
    assert sent_payload.get("days") == 30
    assert "exclude_domains" in sent_payload
    assert "youtube.com" in sent_payload["exclude_domains"]


@respx.mock
def test_academic_sets_include_domains_and_retries_without_it_when_empty(monkeypatch):
    """Verify research_type='academic' sends include_domains and retries without it when empty."""
    monkeypatch.setattr(settings, "tavily_api_key", "mock-tavily-key")

    # Sequence: first call returns 0 results, second call (retry) returns 1 result
    route = respx.post(TAVILY_API_URL).mock(
        side_effect=[
            httpx.Response(200, json={"results": []}),
            httpx.Response(
                200,
                json={
                    "results": [
                        {
                            "title": "General Scientific Report",
                            "url": "https://phys.org/news/quantum",
                            "content": "Study findings on quantum states.",
                        }
                    ]
                },
            ),
        ]
    )

    results = search(query="Quantum entanglement metrics", research_type="academic")
    assert len(results) == 1
    assert results[0]["url"] == "https://phys.org/news/quantum"

    # Exactly 2 requests made
    assert route.call_count == 2

    # First request: included academic domains
    payload_1 = json.loads(route.calls[0].request.content)
    assert "include_domains" in payload_1
    assert "arxiv.org" in payload_1["include_domains"]
    assert "nature.com" in payload_1["include_domains"]
    assert "exclude_domains" not in payload_1

    # Second request (retry): include_domains removed, exclude_domains added
    payload_2 = json.loads(route.calls[1].request.content)
    assert "include_domains" not in payload_2
    assert "exclude_domains" in payload_2
    assert "youtube.com" in payload_2["exclude_domains"]


def test_chat_mode_ignores_fields(monkeypatch):
    """Verify that chat mode (small talk) completely ignores depth and research_type."""
    monkeypatch.setattr(settings, "groq_api_key", "test-key")

    # Canned greeting with deep + academic
    res_canned = client.post(
        "/ask",
        json={"message": "hello!", "depth": "deep", "research_type": "academic"},
    )
    assert res_canned.status_code == 200
    data_canned = res_canned.json()
    assert data_canned["mode"] == "chat"
    assert data_canned["research"] is None
    assert data_canned["llm_calls"] == 0
    assert data_canned["search_calls"] == 0
    assert "hello" in data_canned["reply"].lower()

    # Non-canned small talk with quick + news
    with patch("backend.main.classify", return_value=("chat", "rule_based")):
        with patch("backend.main.chat", return_value="Hello! How can I assist you with research today?"):
            res_chat = client.post(
                "/ask",
                json={"message": "how are you doing", "depth": "quick", "research_type": "news"},
            )
            assert res_chat.status_code == 200
            data_chat = res_chat.json()
            assert data_chat["mode"] == "chat"
            assert data_chat["research"] is None
            assert data_chat["llm_calls"] == 1
            assert data_chat["search_calls"] == 0


def test_depth_settings_differ_and_extractor_receives_per_depth_cap():
    """
    Verify quick, standard, and deep settings differ in claim cap, findings,
    summary length, and source cap, and that the claims extractor receives the
    per-depth cap.
    """
    quick = DEPTH_SETTINGS["quick"]
    standard = DEPTH_SETTINGS["standard"]
    deep = DEPTH_SETTINGS["deep"]

    # 1. Assert claim caps differ and match requirements
    assert quick["claim_cap"] == 3
    assert standard["claim_cap"] == 5
    assert deep["claim_cap"] == 8
    assert quick["claim_cap"] < standard["claim_cap"] < deep["claim_cap"]

    # 2. Assert key findings caps differ and match requirements
    assert quick["findings"] == 3
    assert standard["findings"] == 5
    assert deep["findings"] == 7
    assert quick["findings"] < standard["findings"] < deep["findings"]

    # 3. Assert summary length specifications differ and match requirements
    assert quick["summary_length"] != standard["summary_length"]
    assert standard["summary_length"] != deep["summary_length"]
    assert "70 words" in quick["summary_length"]
    assert "130 words" in standard["summary_length"]
    assert "220 words" in deep["summary_length"]

    # 4. Assert source caps differ and match requirements
    assert quick["source_cap"] == 8
    assert standard["source_cap"] == 12
    assert deep["source_cap"] == 20
    assert quick["source_cap"] < standard["source_cap"] < deep["source_cap"]

    # 5. Assert claims extractor receives the per-depth cap in its prompt
    mock_sources = [
        {"title": "Src 1", "url": "https://example.com/1", "content": "Evidence text for testing claim extraction."}
    ]
    empty_claims_json = "[]"

    for depth_name, expected_cap in [("quick", 3), ("standard", 5), ("deep", 8)]:
        cfg = DEPTH_SETTINGS[depth_name]
        with patch("backend.app.agents.fact_checker.chat", return_value=empty_claims_json) as mock_fc_chat:
            check_facts(topic="Quantum computing", sources=mock_sources, depth_config=cfg)
            # First LLM call is the claims extraction pass
            assert mock_fc_chat.called
            extract_system_prompt = mock_fc_chat.call_args_list[0][1]["system"]
            assert f"Extract up to {expected_cap} key factual claims" in extract_system_prompt

