"""
Research Workflow: Coordinates the Researcher, Fact Checker, and Synthesizer agents
to produce a validated research report from a user topic.
"""

from typing import Any, Dict
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
        "sources_cap": 12,
    },
    "standard": {
        "skip_query_generation": False,
        "max_queries": 3,
        "search_max_results": 3,
        "max_fallback_claims": 3,
        "sources_cap": 12,
    },
    "deep": {
        "skip_query_generation": False,
        "max_queries": 4,
        "search_max_results": 3,
        "max_fallback_claims": 5,
        "sources_cap": 15,
    },
}


class ResearchError(Exception):
    """Exception raised when the research workflow fails."""
    pass


def run_research(
    topic: str,
    depth: str = "standard",
    research_type: str = "general",
) -> Dict[str, Any]:
    """
    Execute the full end-to-end multi-agent research workflow.

    Args:
        topic: The user's research topic.
        depth: "quick" | "standard" | "deep" (default "standard").
        research_type: "general" | "news" | "academic" (default "general").

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
        )

        # Step 2: Fact checker audits the retrieved sources and extracts verified claims
        claims = check_facts(
            topic=topic_clean,
            sources=sources,
            depth_config=depth_config,
            research_type=type_clean,
        )

        # Step 3: Synthesizer agent compiles verified claims and sources into Markdown report
        report_markdown = synthesize_report(
            topic=topic_clean, claims=claims, sources=sources
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
