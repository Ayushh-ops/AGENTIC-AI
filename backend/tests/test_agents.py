"""
Unit tests for the three agents: Researcher, Fact Checker, and Synthesizer.
All tests use mocking to verify deterministic agent logic without external APIs.
"""

from unittest.mock import patch
from backend.app.agents.researcher import research_topic
from backend.app.agents.fact_checker import check_facts
from backend.app.agents.synthesizer import synthesize_report


def test_researcher_generates_queries_and_deduplicates():
    """Verify Researcher splits queries and removes duplicate URLs."""
    mock_llm_response = "1. AI history overview\n2. AI developments 2026\n3. Future of AI"
    mock_search_results = [
        {"title": "AI Source 1", "url": "https://example.com/1", "content": "Info 1"},
        {"title": "Duplicate Source", "url": "https://example.com/1", "content": "Info 1 dup"},
        {"title": "AI Source 2", "url": "https://example.com/2", "content": "Info 2"},
    ]

    with patch("backend.app.agents.researcher.chat", return_value=mock_llm_response) as mock_chat:
        with patch("backend.app.agents.researcher.search", return_value=mock_search_results) as mock_search:
            sources = research_topic("Artificial Intelligence")
            assert mock_chat.called
            assert mock_search.called
            # Sources must be de-duplicated by URL
            urls = [s["url"] for s in sources]
            assert len(urls) == len(set(urls))
            assert "https://example.com/1" in urls
            assert "https://example.com/2" in urls


def test_fact_checker_parses_json_and_validates_urls():
    """Verify Fact Checker classifies multi-domain support, single source, and invalid URLs."""
    sources = [
        {"title": "T1", "url": "https://valid.com/page", "content": "Real fact confirmed here."},
        {"title": "T2", "url": "https://corroborated.org/doc", "content": "Independent confirmation."},
    ]
    mock_json_reply = """
    ```json
    [
      {
        "statement": "Multi-source claim",
        "evidence": "Real fact confirmed here.",
        "source_urls": ["https://valid.com/page", "https://corroborated.org/doc"]
      },
      {
        "statement": "Single domain claim",
        "evidence": "Found in one place.",
        "source_urls": ["https://valid.com/page"]
      },
      {
        "statement": "Fake URL claim",
        "evidence": "Hallucinated link.",
        "source_urls": ["https://hallucinated.com"]
      },
      {
        "statement": "Unsupported claim",
        "status": "unsupported",
        "evidence": "",
        "source_urls": ["https://valid.com/page"]
      }
    ]
    ```
    """

    with patch("backend.app.agents.fact_checker.chat", return_value=mock_json_reply):
        claims = check_facts("Test Topic", sources=sources)
        assert len(claims) == 4

        # First claim corroborated by 2 distinct domains -> supported
        assert claims[0]["status"] == "supported"
        assert len(claims[0]["source_urls"]) == 2
        assert claims[0]["source_url"] == "https://valid.com/page"
        assert claims[0]["evidence"] == "Real fact confirmed here."

        # Second claim supported by 1 domain -> single_source
        assert claims[1]["status"] == "single_source"
        assert claims[1]["source_urls"] == ["https://valid.com/page"]
        assert claims[1]["source_url"] == "https://valid.com/page"
        assert claims[1]["evidence"] == "Found in one place."

        # Third claim had hallucinated URL -> unsupported
        assert claims[2]["status"] == "unsupported"
        assert claims[2]["source_urls"] == []
        assert claims[2]["source_url"] is None
        assert claims[2]["evidence"] == ""

        # Fourth claim was explicitly marked unsupported -> unsupported
        assert claims[3]["status"] == "unsupported"
        assert claims[3]["source_urls"] == []
        assert claims[3]["source_url"] is None


def test_fact_checker_graceful_fallback_on_invalid_json():
    """Verify Fact Checker falls back safely when LLM output is malformed."""
    sources = [{"title": "T1", "url": "https://valid.com/doc", "content": "Some fallback content."}]
    with patch("backend.app.agents.fact_checker.chat", return_value="This is not JSON at all."):
        claims = check_facts("Test Topic", sources=sources)
        assert len(claims) >= 1
        assert "statement" in claims[0]
        # Single source available -> single_source status
        assert claims[0]["status"] == "single_source"
        assert claims[0]["source_url"] == "https://valid.com/doc"
        assert claims[0]["source_urls"] == ["https://valid.com/doc"]
        assert "Some fallback content" in claims[0]["evidence"]


def test_synthesizer_assembles_markdown_report():
    """Verify Synthesizer builds Markdown with summary, claims markers, and references."""
    topic = "Quantum Computing"
    claims = [
        {
            "statement": "Qubits exhibit superposition.",
            "status": "supported",
            "evidence": "Superposition confirmed.",
            "source_urls": ["https://qc.org/qubits", "https://phys.org/qubits"],
            "source_url": "https://qc.org/qubits",
        },
        {
            "statement": "Specific prototype achieved speedup.",
            "status": "single_source",
            "evidence": "Prototype details.",
            "source_urls": ["https://qc.org/qubits"],
            "source_url": "https://qc.org/qubits",
        },
    ]
    sources = [
        {"title": "Quantum Basics", "url": "https://qc.org/qubits", "content": "Details on qubits."},
        {"title": "Physics Org", "url": "https://phys.org/qubits", "content": "Physics coverage."},
    ]

    with patch("backend.app.agents.synthesizer.chat", return_value="Quantum computers leverage quantum mechanics."):
        report = synthesize_report(topic, claims, sources)
        assert "# Research Report: Quantum Computing" in report
        assert "## Executive Summary & Findings" in report
        assert "## Evaluated Claims & Verification Audit" in report
        assert "✓ Verified" in report
        assert "⚠ Single source" in report
        assert "## References" in report
        assert "https://qc.org/qubits" in report
