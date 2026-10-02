"""
Tests for Task 14B: per-request API keys (rotation) and report language.
All HTTP calls are mocked — no real API calls are made.
"""

import json
import logging
from unittest.mock import MagicMock, patch

import pytest
import httpx
from fastapi.testclient import TestClient

from backend.main import app
from backend.app.core.config import settings
from backend.app.services.llm_service import chat, LLMError
from backend.app.services.search_service import search, SearchError
from backend.app.models.research import AskRequest, ALLOWED_LANGUAGES
from backend.app.workflows.research_workflow import DEPTH_SETTINGS, run_research

client = TestClient(app)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

TEST_KEY_GROQ = "gsk_TESTKEY_GROQ_SAFE"
TEST_KEY_TAVILY = "tvly-TESTKEY_TAVILY_SAFE"

_MOCK_WORKFLOW_RESULT = {
    "topic": "Test Topic",
    "report_markdown": "## Executive Summary\nTest summary.\n\n## Key Findings\n- Finding.",
    "sources": [{"title": "T", "url": "https://example.com", "content": "c"}],
    "claims": [
        {
            "statement": "Test claim.",
            "status": "supported",
            "evidence": "Test evidence here for the claim.",
            "source_urls": ["https://example.com"],
            "source_url": "https://example.com",
        }
    ],
}


def _make_groq_ok_response(text: str = "OK response") -> MagicMock:
    """Return a mock httpx.Response for a successful Groq call."""
    mock_resp = MagicMock(spec=httpx.Response)
    mock_resp.status_code = 200
    mock_resp.json.return_value = {
        "choices": [{"message": {"content": text}}]
    }
    mock_resp.text = json.dumps(mock_resp.json())
    mock_resp.headers = {}
    return mock_resp


def _make_groq_429_response() -> MagicMock:
    mock_resp = MagicMock(spec=httpx.Response)
    mock_resp.status_code = 429
    mock_resp.text = "Rate limit exceeded"
    mock_resp.headers = {}
    mock_resp.json.return_value = {}
    return mock_resp


def _make_tavily_ok_response() -> MagicMock:
    mock_resp = MagicMock(spec=httpx.Response)
    mock_resp.status_code = 200
    mock_resp.json.return_value = {
        "results": [{"title": "T", "url": "https://good.com/a", "content": "Content text here."}]
    }
    mock_resp.text = ""
    mock_resp.headers = {}
    return mock_resp


# ---------------------------------------------------------------------------
# 1. Header keys override .env keys
# ---------------------------------------------------------------------------

def test_header_keys_override_env(monkeypatch):
    """Keys supplied in X-Groq-Keys / X-Tavily-Keys must be used instead of .env."""
    monkeypatch.setattr(settings, "groq_api_key", "env-groq-key")
    monkeypatch.setattr(settings, "tavily_api_key", "env-tavily-key")

    captured_groq_keys = []
    captured_tavily_keys = []

    with patch("backend.main.run_research") as mock_run:
        mock_run.return_value = _MOCK_WORKFLOW_RESULT

        def _capture(**kwargs):
            captured_groq_keys.extend(kwargs.get("groq_keys") or [])
            captured_tavily_keys.extend(kwargs.get("tavily_keys") or [])
            return _MOCK_WORKFLOW_RESULT

        mock_run.side_effect = _capture

        resp = client.post(
            "/ask",
            json={"message": "Tell me about quantum computing"},
            headers={
                "X-Groq-Keys": TEST_KEY_GROQ,
                "X-Tavily-Keys": TEST_KEY_TAVILY,
            },
        )

    # Either 200 or the mock was called; either way the keys were forwarded
    assert mock_run.called
    assert TEST_KEY_GROQ in captured_groq_keys
    assert TEST_KEY_TAVILY in captured_tavily_keys
    # Env key must NOT appear when header keys are present
    assert "env-groq-key" not in captured_groq_keys
    assert "env-tavily-key" not in captured_tavily_keys


# ---------------------------------------------------------------------------
# 2. Key rotation on 429 then success (llm_service.chat)
# ---------------------------------------------------------------------------

def test_llm_rotation_on_429_then_success():
    """First key gets 429; second key succeeds; result is returned."""
    bad_key = "gsk_BAD_KEY"
    good_key = "gsk_GOOD_KEY"

    call_count = [0]

    def mock_post(url, **kwargs):
        # Determine which key was used (from the Authorization header)
        auth = kwargs.get("headers", {}).get("Authorization", "")
        call_count[0] += 1
        if bad_key in auth:
            return _make_groq_429_response()
        return _make_groq_ok_response("rotation worked")

    with patch("httpx.Client") as mock_client_cls:
        mock_ctx = MagicMock()
        mock_client_cls.return_value.__enter__ = lambda s: mock_ctx
        mock_client_cls.return_value.__exit__ = MagicMock(return_value=False)
        mock_ctx.post.side_effect = mock_post

        result = chat(
            system="sys",
            user="user",
            api_keys=[bad_key, good_key],
        )

    assert result == "rotation worked"
    # Both keys should have been tried
    assert call_count[0] >= 2


# ---------------------------------------------------------------------------
# 3. All keys fail → LLMError raised; error does not leak keys
# ---------------------------------------------------------------------------

def test_all_llm_keys_fail_no_key_leak():
    """When all keys fail with 429, LLMError is raised; keys must not appear in the message."""
    bad_key_1 = "gsk_SECRETKEY_ONE"
    bad_key_2 = "gsk_SECRETKEY_TWO"

    def always_429(url, **kwargs):
        return _make_groq_429_response()

    with patch("httpx.Client") as mock_client_cls:
        mock_ctx = MagicMock()
        mock_client_cls.return_value.__enter__ = lambda s: mock_ctx
        mock_client_cls.return_value.__exit__ = MagicMock(return_value=False)
        mock_ctx.post.side_effect = always_429

        with pytest.raises(LLMError) as exc_info:
            chat(system="s", user="u", api_keys=[bad_key_1, bad_key_2])

    error_msg = str(exc_info.value)
    assert bad_key_1 not in error_msg, "Secret key must not appear in error message"
    assert bad_key_2 not in error_msg, "Secret key must not appear in error message"


# ---------------------------------------------------------------------------
# 4. Response/log body never contains a test key string
# ---------------------------------------------------------------------------

def test_key_not_in_response_body(monkeypatch):
    """The HTTP response body from /ask must never contain the raw key string."""
    monkeypatch.setattr(settings, "groq_api_key", None)
    monkeypatch.setattr(settings, "tavily_api_key", None)

    resp = client.post(
        "/ask",
        json={"message": "hello world quantum computing"},
        headers={
            "X-Groq-Keys": TEST_KEY_GROQ,
            "X-Tavily-Keys": TEST_KEY_TAVILY,
        },
    )
    body = resp.text
    assert TEST_KEY_GROQ not in body, "Groq key must not appear in response body"
    assert TEST_KEY_TAVILY not in body, "Tavily key must not appear in response body"


def test_key_not_in_log_output(monkeypatch, caplog):
    """Log output must never contain the raw key string."""
    monkeypatch.setattr(settings, "groq_api_key", None)
    monkeypatch.setattr(settings, "tavily_api_key", None)

    with caplog.at_level(logging.DEBUG):
        client.post(
            "/ask",
            json={"message": "hello world quantum computing"},
            headers={
                "X-Groq-Keys": TEST_KEY_GROQ,
                "X-Tavily-Keys": TEST_KEY_TAVILY,
            },
        )

    full_log = caplog.text
    assert TEST_KEY_GROQ not in full_log, "Groq key must not appear in log output"
    assert TEST_KEY_TAVILY not in full_log, "Tavily key must not appear in log output"


# ---------------------------------------------------------------------------
# 5. Invalid key format → 400
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("header_name,header_value,expected_fragment", [
    # More than 10 keys
    ("X-Groq-Keys", ",".join([f"key{i}" for i in range(11)]), "at most 10"),
    # Key with internal whitespace
    ("X-Groq-Keys", "key with space", "whitespace"),
    # Key exceeding 200 chars
    ("X-Groq-Keys", "k" * 201, "exceeds maximum"),
    # Tavily key with internal whitespace
    ("X-Tavily-Keys", "tvly bad key", "whitespace"),
])
def test_invalid_key_format_returns_400(header_name, header_value, expected_fragment, monkeypatch):
    """Malformed key headers must return HTTP 400 with a descriptive message."""
    monkeypatch.setattr(settings, "groq_api_key", "some-key")
    monkeypatch.setattr(settings, "tavily_api_key", "some-key")

    resp = client.post(
        "/ask",
        json={"message": "quantum computing research"},
        headers={header_name: header_value},
    )

    assert resp.status_code == 400, f"Expected 400, got {resp.status_code}: {resp.text}"
    assert expected_fragment in resp.json()["detail"].lower()


# ---------------------------------------------------------------------------
# 6. Language: default is English
# ---------------------------------------------------------------------------

def test_language_defaults_to_english():
    req = AskRequest(message="test topic")
    assert req.language == "English"


# ---------------------------------------------------------------------------
# 7. Language: allowlist accepted
# ---------------------------------------------------------------------------

@pytest.mark.parametrize("lang", list(ALLOWED_LANGUAGES))
def test_language_allowlist_accepted(lang):
    req = AskRequest(message="test topic", language=lang)
    assert req.language == lang


# ---------------------------------------------------------------------------
# 8. Language: invalid value → 422 from /ask
# ---------------------------------------------------------------------------

def test_invalid_language_returns_422(monkeypatch):
    """Unsupported language string must be rejected with HTTP 422."""
    monkeypatch.setattr(settings, "groq_api_key", "k")
    monkeypatch.setattr(settings, "tavily_api_key", "k")

    resp = client.post("/ask", json={"message": "quantum", "language": "Klingon"})
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# 9. Language reaches the synthesizer prompt
# ---------------------------------------------------------------------------

def test_language_reaches_synthesizer_prompt():
    """The language parameter must be present in the synthesizer's system prompt."""
    from backend.app.agents.synthesizer import synthesize_report

    captured_system_prompts = []

    def mock_chat(system, user, temperature=0.2, max_tokens=None, api_keys=None):
        captured_system_prompts.append(system)
        return "## Executive Summary\nTest.\n\n## Key Findings\n- Finding."

    with patch("backend.app.agents.synthesizer.chat", side_effect=mock_chat):
        synthesize_report(
            topic="Test",
            claims=[{
                "statement": "A claim.",
                "status": "supported",
                "evidence": "evidence text here for testing",
                "source_urls": ["https://example.com"],
                "source_url": "https://example.com",
            }],
            sources=[{"title": "T", "url": "https://example.com", "content": "c"}],
            language="Hindi",
        )

    assert any("Hindi" in p for p in captured_system_prompts), (
        "Language 'Hindi' must appear in the synthesizer system prompt"
    )


# ---------------------------------------------------------------------------
# 10. Language reaches the fact-checker extraction prompt
# ---------------------------------------------------------------------------

def test_language_reaches_fact_checker_prompt():
    """The language parameter must appear in the claim-extraction system prompt."""
    from backend.app.agents.fact_checker import check_facts

    captured_system_prompts = []

    def mock_chat(system, user, temperature=0.2, max_tokens=None, api_keys=None):
        captured_system_prompts.append(system)
        return json.dumps([
            {"statement": "A claim.", "evidence": "evidence text here for check", "source_urls": ["https://x.com"]}
        ])

    with patch("backend.app.agents.fact_checker.chat", side_effect=mock_chat):
        check_facts(
            topic="Test",
            sources=[{"title": "T", "url": "https://x.com", "content": "evidence text here for check"}],
            language="Spanish",
        )

    assert any("Spanish" in p for p in captured_system_prompts), (
        "Language 'Spanish' must appear in the fact-checker extraction prompt"
    )


# ---------------------------------------------------------------------------
# 11. Existing tests still pass: /research endpoint unaffected
# ---------------------------------------------------------------------------

def test_existing_research_endpoint_still_works(monkeypatch):
    """The /research endpoint must remain functional after these changes."""
    monkeypatch.setattr(settings, "groq_api_key", "mock-key")
    monkeypatch.setattr(settings, "tavily_api_key", "mock-key")

    with patch("backend.main.run_research", return_value=_MOCK_WORKFLOW_RESULT):
        resp = client.post("/research", json={"topic": "Quantum computing"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["topic"] == "Test Topic"
