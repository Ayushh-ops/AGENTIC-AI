"""
Unit tests for the three agents: Researcher, Fact Checker, and Synthesizer.
All tests use mocking to verify deterministic agent logic without external APIs.
"""

from unittest.mock import patch
from backend.app.agents.researcher import research_topic
from backend.app.agents.fact_checker import check_facts, _validate_quote_for_claim
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
        {
            "title": "T1",
            "url": "https://valid.com/page",
            "content": "Quantum processors operate using superconducting qubits at millikelvin scales.",
        },
        {
            "title": "T2",
            "url": "https://corroborated.org/doc",
            "content": "Independent researchers confirmed quantum processors operate using superconducting qubits effectively.",
        },
    ]
    mock_extract_reply = """
    ```json
    [
      {
        "statement": "Quantum processors operate using superconducting qubits.",
        "evidence": "Quantum processors operate using superconducting qubits at millikelvin scales.",
        "source_urls": ["https://valid.com/page"]
      },
      {
        "statement": "Superconducting qubits maintain coherence for microseconds.",
        "evidence": "Quantum processors operate using superconducting qubits at millikelvin scales.",
        "source_urls": ["https://valid.com/page"]
      },
      {
        "statement": "Optical quantum computing uses photons for logic gates.",
        "evidence": "Optical quantum computing uses photons for logic gates.",
        "source_urls": ["https://hallucinated.com"]
      },
      {
        "statement": "Unsupported claim regarding quantum supremacy.",
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
        {"source_index": 0, "quote": "Quantum processors operate using superconducting qubits at millikelvin scales."},
        {"source_index": 1, "quote": "confirmed quantum processors operate using superconducting qubits effectively."}
      ],
      "claim_1": [
        {"source_index": 0, "quote": "Quantum processors operate using superconducting qubits at millikelvin scales."}
      ]
    }
    """

    with patch("backend.app.agents.fact_checker.chat", side_effect=[mock_extract_reply, mock_cross_check]):
        claims = check_facts("Quantum Computing", sources=sources)
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


def test_quote_shorter_than_six_words_rejected():
    """Verify that candidate quotes shorter than 6 words are rejected."""
    claim = "Quantum systems demonstrate entanglement across physical qubits."
    source_text = "In laboratories, quantum systems demonstrate entanglement across physical qubits with high fidelity."
    short_quote = "Quantum systems demonstrate entanglement"  # 4 words

    is_valid, ratio, terms = _validate_quote_for_claim(short_quote, source_text, claim)
    assert not is_valid
    assert ratio == 0.0


def test_quote_without_claim_term_overlap_rejected():
    """
    Verify that candidate quotes from unrelated pages (like search filter docs)
    that do not share at least 2 meaningful terms with the claim are rejected.
    """
    claim = "Quantum error correction encodes a logical qubit using multiple physical qubits."
    sonar_text = "Filters allow users to restrict search results to specific domains and dates."
    quote = "Filters allow users to restrict search results to specific domains"

    is_valid, ratio, terms = _validate_quote_for_claim(quote, sonar_text, claim)
    assert not is_valid
    assert len(terms) < 2


def test_cross_check_upgrades_claim_to_supported():
    """Verify that a batched cross-check finding corroboration in another source upgrades status to supported."""
    sources = [
        {"title": "Source A", "url": "https://site-a.com/article", "content": "Superconducting qubits operate at millikelvin temperatures in dilution refrigerators."},
        {"title": "Source B", "url": "https://site-b.org/paper", "content": "Research shows superconducting qubits operate at millikelvin temperatures reliably."},
    ]
    mock_extract = """
    [
      {
        "statement": "Superconducting qubits operate at millikelvin temperatures.",
        "evidence": "Superconducting qubits operate at millikelvin temperatures in dilution refrigerators.",
        "source_urls": ["https://site-a.com/article"]
      }
    ]
    """
    mock_cross = """
    {
      "claim_0": [
        {"source_index": 0, "quote": "Superconducting qubits operate at millikelvin temperatures in dilution refrigerators."},
        {"source_index": 1, "quote": "shows superconducting qubits operate at millikelvin temperatures reliably."}
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
        {"title": "Source A", "url": "https://site-a.com/a", "content": "Quantum systems experience decoherence over time in noisy environments."},
        {"title": "Source B", "url": "https://site-b.org/b", "content": "Optical computing systems use photonics rather than conventional electrons."},
    ]
    mock_extract = """
    [
      {
        "statement": "Quantum systems experience decoherence over time.",
        "evidence": "Quantum systems experience decoherence over time in noisy environments.",
        "source_urls": ["https://site-a.com/a"]
      }
    ]
    """
    mock_cross = """
    {
      "claim_0": [
        {"source_index": 0, "quote": "Quantum systems experience decoherence over time in noisy environments."},
        {"source_index": 1, "quote": "Decoherence destroys quantum states immediately in physical devices."}
      ]
    }
    """
    with patch("backend.app.agents.fact_checker.chat", side_effect=[mock_extract, mock_cross]):
        claims = check_facts("Decoherence", sources=sources)
        assert len(claims) == 1
        # The quote from site-b is rejected because it doesn't appear in site-b's text
        assert claims[0]["status"] == "single_source"
        assert claims[0]["source_urls"] == ["https://site-a.com/a"]


def test_same_domain_duplicates_do_not_count_twice():
    """Verify that multiple URLs from subdomains of the same registrable domain count as 1 domain (single_source)."""
    sources = [
        {"title": "Blog", "url": "https://blog.techcorp.com/quantum", "content": "TechCorp developed 100 logical qubits for quantum processing."},
        {"title": "Research", "url": "https://research.techcorp.com/paper", "content": "Our team fabricated 100 logical qubits for quantum processing applications."},
    ]
    mock_extract = """
    [
      {
        "statement": "TechCorp developed 100 logical qubits for quantum processing.",
        "evidence": "TechCorp developed 100 logical qubits for quantum processing.",
        "source_urls": ["https://blog.techcorp.com/quantum"]
      }
    ]
    """
    mock_cross = """
    {
      "claim_0": [
        {"source_index": 0, "quote": "TechCorp developed 100 logical qubits for quantum processing."},
        {"source_index": 1, "quote": "fabricated 100 logical qubits for quantum processing applications."}
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
        {"title": "Initial", "url": "https://initial-lab.org/press", "content": "Neutral atom processors achieved 256 physical qubits in laboratory demonstrations."}
    ]
    mock_extract = """
    [
      {
        "statement": "Neutral atom processors achieved 256 physical qubits in laboratory demonstrations.",
        "evidence": "Neutral atom processors achieved 256 physical qubits in laboratory demonstrations.",
        "source_urls": ["https://initial-lab.org/press"]
      }
    ]
    """
    mock_cross = "{}"

    fallback_search_results = [
        {"title": "Independent News", "url": "https://physicstoday.org/news", "content": "Neutral atom processors achieved 256 physical qubits in recent benchmark experiments."}
    ]
    mock_fallback_llm = """
    [
      {"source_index": 0, "quote": "Neutral atom processors achieved 256 physical qubits in recent benchmark experiments."}
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
        {"title": "Initial", "url": "https://initial-lab.org/press", "content": "Pioneering research in topological qubits continues across international consortia."}
    ]
    mock_extract = """
    [
      {
        "statement": "Research in topological qubits continues across international consortia.",
        "evidence": "Pioneering research in topological qubits continues across international consortia.",
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


def test_source_cap_at_twelve():
    """Verify that total returned sources are capped at 12, preserving all supporting sources."""
    # 15 sources
    sources = [
        {"title": f"Source {i}", "url": f"https://site{i}.com/page", "content": f"Content {i} discusses quantum algorithms."}
        for i in range(16)
    ]
    # Let source 14 and 15 be supporting sources
    sources[14]["content"] = "Fault-tolerant quantum computing requires surface codes for error correction."
    sources[15]["content"] = "Surface codes for error correction are essential for fault-tolerant quantum computing."

    mock_extract = """
    [
      {
        "statement": "Fault-tolerant quantum computing requires surface codes for error correction.",
        "evidence": "Fault-tolerant quantum computing requires surface codes for error correction.",
        "source_urls": ["https://site14.com/page"]
      }
    ]
    """
    mock_cross = """
    {
      "claim_0": [
        {"source_index": 14, "quote": "Fault-tolerant quantum computing requires surface codes for error correction."},
        {"source_index": 15, "quote": "Surface codes for error correction are essential for fault-tolerant quantum computing."}
      ]
    }
    """

    with patch("backend.app.agents.fact_checker.chat", side_effect=[mock_extract, mock_cross]):
        claims = check_facts("Surface Codes", sources=sources)
        assert len(claims) == 1
        assert claims[0]["status"] == "supported"
        # Total sources capped at 12
        assert len(sources) == 12
        # Both supporting sources must be preserved
        urls = [s["url"] for s in sources]
        assert "https://site14.com/page" in urls
        assert "https://site15.com/page" in urls


def test_fact_checker_graceful_fallback_on_invalid_json():
    """Verify Fact Checker falls back safely when LLM output is malformed."""
    sources = [{"title": "T1", "url": "https://valid.com/doc", "content": "Some fallback content regarding quantum computing."}]
    with patch("backend.app.agents.fact_checker.chat", return_value="This is not JSON at all."):
        claims = check_facts("Test Topic", sources=sources)
        assert len(claims) >= 1
        assert "statement" in claims[0]
        # Single source available -> single_source status
        assert claims[0]["status"] == "single_source"
        assert claims[0]["source_url"] == "https://valid.com/doc"
        assert claims[0]["source_urls"] == ["https://valid.com/doc"]


def test_tag_stripping_and_synthesizer_wording():
    """Verify that synthesizer strips leaked 【...】 status tags and follows wording constraints."""
    topic = "Quantum Computing"
    claims = [
        {
            "statement": "Superconducting qubits operate at millikelvin temperatures.",
            "status": "supported",
            "evidence": "Superconducting qubits operate at millikelvin temperatures in dilution refrigerators.",
            "source_urls": ["https://qc.org/qubits", "https://phys.org/qubits"],
            "source_url": "https://qc.org/qubits",
        },
        {
            "statement": "A single laboratory demonstrated an experimental 10-qubit prototype.",
            "status": "single_source",
            "evidence": "A single laboratory demonstrated an experimental 10-qubit prototype.",
            "source_urls": ["https://qc.org/qubits"],
            "source_url": "https://qc.org/qubits",
        },
    ]
    sources = [
        {"title": "Quantum Basics", "url": "https://qc.org/qubits", "content": "Details on qubits."},
        {"title": "Physics Org", "url": "https://phys.org/qubits", "content": "Physics coverage."},
    ]

    mock_llm_output = (
        "## Executive Summary\n"
        "Quantum computing is advancing. 【SUPPORTED】 Superconducting qubits are verified. "
        "【SINGLE_SOURCE】 According to one laboratory, a prototype was created.\n\n"
        "## Key Findings\n"
        "- Superconducting qubits operate at low temperatures.\n"
        "- A 10-qubit prototype was reported by one source."
    )

    with patch("backend.app.agents.synthesizer.chat", return_value=mock_llm_output) as mock_chat:
        report = synthesize_report(topic, claims, sources)

        # Check prompt content sent to LLM
        prompt_args = mock_chat.call_args[1]
        system_content = prompt_args["system"]
        user_content = prompt_args["user"]

        # Prompt must clearly differentiate wording rules
        assert "verified" in system_content
        assert "[Reported by only one source]" in user_content
        assert "[Corroborated by multiple independent sources]" in user_content

        # Leaked tags must be stripped from report prose
        assert "【SUPPORTED】" not in report
        assert "【SINGLE_SOURCE】" not in report
        assert "## Executive Summary" in report
        assert "## Key Findings" in report
        assert "## Evaluated Claims & Verification Audit" in report
        assert "✓ Verified" in report
        assert "⚠ Single source" in report
        assert "## References" in report
