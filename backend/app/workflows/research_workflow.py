"""
Research Workflow: Coordinates the Researcher, Fact Checker, and Synthesizer agents
to produce a validated research report from a user topic.
"""

from typing import Any, Dict, List, Optional
from backend.app.agents.researcher import research_topic
from backend.app.agents.fact_checker import check_facts
from backend.app.agents.synthesizer import synthesize_report
from backend.app.services.llm_service import LLMError
from backend.app.services.search_service import SearchError


DEPTH_SETTINGS: Dict[str, Dict[str, Any]] = {
    "quick": {
        "skip_query_generation": True,
        "max_queries": 1,
        "search_max_results": 6,
        "max_fallback_claims": 0,
        "sources_cap": 8,
        "source_cap": 8,
        "max_claims": 3,
        "claim_cap": 3,
        "max_findings": 3,
        "findings": 3,
        "summary_length": "2-3 sentences (~70 words)",
        "excerpt_chars": 800,
    },
    "standard": {
        "skip_query_generation": False,
        "max_queries": 3,
        "search_max_results": 3,
        "max_fallback_claims": 3,
        "sources_cap": 12,
        "source_cap": 12,
        "max_claims": 5,
        "claim_cap": 5,
        "max_findings": 5,
        "findings": 5,
        "summary_length": "~130 words",
        "excerpt_chars": 800,
    },
    "deep": {
        "skip_query_generation": False,
        "max_queries": 4,
        "search_max_results": 3,
        "max_fallback_claims": 6,
        "sources_cap": 20,
        "source_cap": 20,
        "max_claims": 8,
        "claim_cap": 8,
        "max_findings": 7,
        "findings": 7,
        "summary_length": "~220 words",
        "excerpt_chars": 600,
    },
}


class ResearchError(Exception):
    """Exception raised when the research workflow fails."""
    pass


def run_research(
    topic: str,
    depth: str = "standard",
    research_type: str = "general",
    groq_keys: Optional[List[str]] = None,
    tavily_keys: Optional[List[str]] = None,
    language: str = "English",
) -> Dict[str, Any]:
    """
    Execute the full end-to-end multi-agent research workflow.

    Args:
        topic: The user's research topic.
        depth: "quick" | "standard" | "deep" (default "standard").
        research_type: "general" | "news" | "academic" (default "general").
        groq_keys: Optional per-request Groq API key list for rotation.
        tavily_keys: Optional per-request Tavily API key list for rotation.
        language: Language for report output (default "English").

    Returns:
        Dict with keys: 'topic', 'report_markdown', 'sources', 'claims'.

    Raises:
        ResearchError: If an underlying LLM or Search failure occurs.
    """
    topic_clean = topic.strip()
    if not topic_clean:
        raise ResearchError("Research topic must not be empty.")

    depth_key = (depth or "standard").strip().lower()
    depth_config = DEPTH_SETTINGS.get(depth_key, DEPTH_SETTINGS["standard"])
    type_clean = (research_type or "general").strip().lower()

    try:
        # Step 1: Researcher agent generates queries and retrieves web sources
        sources = research_topic(
            topic=topic_clean,
            depth_config=depth_config,
            research_type=type_clean,
            groq_keys=groq_keys,
            tavily_keys=tavily_keys,
        )

        # Step 2: Fact checker audits the retrieved sources and extracts verified claims
        claims = check_facts(
            topic=topic_clean,
            sources=sources,
            depth_config=depth_config,
            research_type=type_clean,
            groq_keys=groq_keys,
            tavily_keys=tavily_keys,
            language=language,
        )

        # Step 3: Synthesizer agent compiles verified claims and sources into Markdown report
        report_markdown = synthesize_report(
            topic=topic_clean,
            claims=claims,
            sources=sources,
            depth_config=depth_config,
            language=language,
            groq_keys=groq_keys,
        )

        return {
            "topic": topic_clean,
            "report_markdown": report_markdown,
            "sources": sources,
            "claims": claims,
        }
    except (LLMError, SearchError) as exc:
        raise ResearchError(f"Research workflow failed: {exc}") from exc
    except Exception as exc:
        raise ResearchError(f"Unexpected error in research workflow: {exc}") from exc
