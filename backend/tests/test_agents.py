"""
Unit tests for the three agents: Researcher, Fact Checker, and Synthesizer.
All tests use mocking to verify deterministic agent logic without external APIs.
"""

from unittest.mock import patch
from backend.app.agents.researcher import research_topic
from backend.app.agents.fact_checker import check_facts
from backend.app.agents.synthesizer import synthesize_report
from backend.app.services.search_service import SearchError
from backend.app.services.llm_service import LLMError


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
    mock_extract_reply = """
    ```json
    [
      {
        "statement": "Multi-source claim",
        "evidence": "Real fact confirmed here.",
        "source_urls": ["https://valid.com/page"]
      },
      {
        "statement": "Single domain claim",
        "evidence": "Real fact confirmed here.",
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
    mock_cross_check = """
    {
      "claim_0": [
        {"source_index": 0, "quote": "Real fact confirmed here."},
        {"source_index": 1, "quote": "Independent confirmation."}
      ],
      "claim_1": [
        {"source_index": 0, "quote": "Real fact confirmed here."}
      ]
    }
    """

    with patch("backend.app.agents.fact_checker.chat", side_effect=[mock_extract_reply, mock_cross_check]):
        claims = check_facts("Test Topic", sources=sources)
        assert len(claims) == 4

        # First claim corroborated by 2 distinct domains -> supported
        assert claims[0]["status"] == "supported"
        assert len(claims[0]["source_urls"]) == 2
        assert "https://valid.com/page" in claims[0]["source_urls"]
        assert "https://corroborated.org/doc" in claims[0]["source_urls"]
        assert claims[0]["source_url"] == "https://valid.com/page"
        assert len(claims[0]["evidence"]) > 0

        # Second claim supported by 1 domain -> single_source
        assert claims[1]["status"] == "single_source"
        assert claims[1]["source_urls"] == ["https://valid.com/page"]
        assert claims[1]["source_url"] == "https://valid.com/page"

        # Third claim had hallucinated URL -> unsupported
        assert claims[2]["status"] == "unsupported"
        assert claims[2]["source_urls"] == []
        assert claims[2]["source_url"] is None
        assert claims[2]["evidence"] == ""

        # Fourth claim was explicitly marked unsupported -> unsupported
        assert claims[3]["status"] == "unsupported"
        assert claims[3]["source_urls"] == []
        assert claims[3]["source_url"] is None


def test_cross_check_upgrades_claim_to_supported():
    """Verify that a batched cross-check finding corroboration in another source upgrades status to supported."""
    sources = [
        {"title": "Source A", "url": "https://site-a.com/article", "content": "Superconducting qubits operate at millikelvin temperatures."},
        {"title": "Source B", "url": "https://site-b.org/paper", "content": "Qubits based on superconductors require millikelvin dilution refrigerators."},
    ]
    mock_extract = """
    [
      {
        "statement": "Superconducting qubits require millikelvin temperatures.",
        "evidence": "Superconducting qubits operate at millikelvin temperatures.",
        "source_urls": ["https://site-a.com/article"]
      }
    ]
    """
    mock_cross = """
    {
      "claim_0": [
        {"source_index": 0, "quote": "Superconducting qubits operate at millikelvin temperatures."},
        {"source_index": 1, "quote": "require millikelvin dilution refrigerators"}
      ]
    }
    """
    with patch("backend.app.agents.fact_checker.chat", side_effect=[mock_extract, mock_cross]):
        claims = check_facts("Qubits", sources=sources)
        assert len(claims) == 1
        assert claims[0]["status"] == "supported"
        assert len(claims[0]["source_urls"]) == 2
        assert "https://site-a.com/article" in claims[0]["source_urls"]
        assert "https://site-b.org/paper" in claims[0]["source_urls"]


def test_hallucinated_quote_rejected():
    """Verify that a quote not present in the source text is rejected, preventing false corroboration."""
    sources = [
        {"title": "Source A", "url": "https://site-a.com/a", "content": "Quantum systems experience decoherence over time."},
        {"title": "Source B", "url": "https://site-b.org/b", "content": "Optical computing uses photonics rather than electrons."},
    ]
    mock_extract = """
    [
      {
        "statement": "Quantum systems experience decoherence.",
        "evidence": "Quantum systems experience decoherence over time.",
        "source_urls": ["https://site-a.com/a"]
      }
    ]
    """
    # LLM hallucinates a quote for Source B that does NOT exist in Source B's text
    mock_cross = """
    {
      "claim_0": [
        {"source_index": 0, "quote": "Quantum systems experience decoherence over time."},
        {"source_index": 1, "quote": "Decoherence destroys quantum states immediately."}
      ]
    }
    """
    with patch("backend.app.agents.fact_checker.chat", side_effect=[mock_extract, mock_cross]):
        claims = check_facts("Decoherence", sources=sources)
        assert len(claims) == 1
        # The hallucinated quote from site-b is rejected; only site-a is retained
        assert claims[0]["status"] == "single_source"
        assert claims[0]["source_urls"] == ["https://site-a.com/a"]


def test_same_domain_duplicates_do_not_count_twice():
    """Verify that multiple URLs from subdomains of the same registrable domain count as 1 domain (single_source)."""
    sources = [
        {"title": "Blog", "url": "https://blog.techcorp.com/quantum", "content": "TechCorp achieved 100 logical qubits."},
        {"title": "Research", "url": "https://research.techcorp.com/paper", "content": "Our team fabricated 100 logical qubits with high fidelity."},
    ]
    mock_extract = """
    [
      {
        "statement": "TechCorp built 100 logical qubits.",
        "evidence": "TechCorp achieved 100 logical qubits.",
        "source_urls": ["https://blog.techcorp.com/quantum"]
      }
    ]
    """
    mock_cross = """
    {
      "claim_0": [
        {"source_index": 0, "quote": "TechCorp achieved 100 logical qubits."},
        {"source_index": 1, "quote": "fabricated 100 logical qubits with high fidelity"}
      ]
    }
    """
    with patch("backend.app.agents.fact_checker.chat", side_effect=[mock_extract, mock_cross]):
        claims = check_facts("Logical Qubits", sources=sources)
        assert len(claims) == 1
        # Both URLs are from techcorp.com -> only 1 distinct domain -> single_source
        assert claims[0]["status"] == "single_source"
        assert len(claims[0]["source_urls"]) == 2


def test_fallback_search_upgrades_claim():
    """Verify targeted fallback search finds a corroborating source from a new domain and upgrades claim."""
    initial_sources = [
        {"title": "Initial", "url": "https://initial-lab.org/press", "content": "Neutral atom processors achieved 256 qubits."}
    ]
    mock_extract = """
    [
      {
        "statement": "Neutral atom processors achieved 256 qubits.",
        "evidence": "Neutral atom processors achieved 256 qubits.",
        "source_urls": ["https://initial-lab.org/press"]
      }
    ]
    """
    # Cross-check finds nothing new (only 1 source available initially)
    mock_cross = "{}"

    fallback_search_results = [
        {"title": "Independent News", "url": "https://physicstoday.org/news", "content": "Neutral atom quantum computers now boast 256 physical qubits."}
    ]
    mock_fallback_llm = """
    [
      {"source_index": 0, "quote": "Neutral atom quantum computers now boast 256 physical qubits."}
    ]
    """

    with patch("backend.app.agents.fact_checker.chat", side_effect=[mock_extract, mock_cross, mock_fallback_llm]):
        with patch("backend.app.agents.fact_checker.search", return_value=fallback_search_results) as mock_search:
            claims = check_facts("Neutral Atoms", sources=initial_sources)
            assert mock_search.called
            assert len(claims) == 1
            # Upgraded from single_source to supported
            assert claims[0]["status"] == "supported"
            assert "https://physicstoday.org/news" in claims[0]["source_urls"]
            # The newly found source must be added to initial_sources
            assert any(s["url"] == "https://physicstoday.org/news" for s in initial_sources)


def test_fallback_failure_leaves_single_source():
    """Verify that if fallback search or its LLM evaluation fails, the claim cleanly remains single_source."""
    initial_sources = [
        {"title": "Initial", "url": "https://initial-lab.org/press", "content": "Pioneering research in topological qubits."}
    ]
    mock_extract = """
    [
      {
        "statement": "Research in topological qubits is ongoing.",
        "evidence": "Pioneering research in topological qubits.",
        "source_urls": ["https://initial-lab.org/press"]
      }
    ]
    """
    mock_cross = "{}"

    with patch("backend.app.agents.fact_checker.chat", side_effect=[mock_extract, mock_cross]):
        with patch("backend.app.agents.fact_checker.search", side_effect=SearchError("Network timeout")):
            claims = check_facts("Topological Qubits", sources=initial_sources)
            assert len(claims) == 1
            # Remains single_source, workflow does not crash
            assert claims[0]["status"] == "single_source"
            assert claims[0]["source_urls"] == ["https://initial-lab.org/press"]


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
