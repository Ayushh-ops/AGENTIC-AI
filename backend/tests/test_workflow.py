"""
Unit tests for the research workflow orchestration.
"""

import pytest
from unittest.mock import patch
from backend.app.workflows.research_workflow import run_research, ResearchError
from backend.app.services.llm_service import LLMError
from backend.app.services.search_service import SearchError


def test_run_research_success():
    """Verify run_research returns expected dictionary structure on success."""
    mock_sources = [{"title": "S1", "url": "https://example.com", "content": "Text"}]
    mock_claims = [{"statement": "Claim", "status": "supported", "source_url": "https://example.com"}]
    mock_report = "# Report\nSummary"

    with patch("backend.app.workflows.research_workflow.research_topic", return_value=mock_sources):
        with patch("backend.app.workflows.research_workflow.check_facts", return_value=mock_claims):
            with patch("backend.app.workflows.research_workflow.synthesize_report", return_value=mock_report):
                result = run_research("Sample Topic")
                assert result["topic"] == "Sample Topic"
                assert result["report_markdown"] == mock_report
                assert result["sources"] == mock_sources
                assert result["claims"] == mock_claims


def test_run_research_empty_topic():
    """Verify run_research raises ResearchError if topic is empty string."""
    with pytest.raises(ResearchError, match="must not be empty"):
        run_research("   ")


def test_run_research_handles_llm_failure():
    """Verify run_research wraps LLMError into ResearchError."""
    with patch("backend.app.workflows.research_workflow.research_topic", side_effect=LLMError("Groq failed")):
        with pytest.raises(ResearchError, match="Research workflow failed"):
            run_research("AI Safety")


def test_run_research_handles_search_failure():
    """Verify run_research wraps SearchError into ResearchError."""
    with patch("backend.app.workflows.research_workflow.research_topic", side_effect=SearchError("Tavily down")):
        with pytest.raises(ResearchError, match="Research workflow failed"):
            run_research("Robotics")
