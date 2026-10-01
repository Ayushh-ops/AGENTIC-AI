"""
Researcher Agent: Deconstructs topics into focused search queries, executes
web searches via Tavily, and returns de-duplicated sources.
"""

from typing import Any, Dict, List, Optional, Set
from backend.app.services.llm_service import chat
from backend.app.services.search_service import search


def research_topic(
    topic: str,
    depth_config: Optional[Dict[str, Any]] = None,
    research_type: str = "general",
) -> List[Dict[str, str]]:
    """
    Generate focused search queries for a topic, query Tavily, and return unique sources.

    Args:
        topic: The user's research topic.
        depth_config: Configuration dict controlling query generation and search count.
        research_type: "general" | "news" | "academic" (default "general").

    Returns:
        A list of de-duplicated source dictionaries containing 'title', 'url', and 'content'.
    """
    if depth_config is None:
        depth_config = {
            "skip_query_generation": False,
            "max_queries": 3,
            "search_max_results": 3,
        }

    skip_query_gen = depth_config.get("skip_query_generation", False)
    max_queries = depth_config.get("max_queries", 3)
    search_max_results = depth_config.get("search_max_results", 3)

    if skip_query_gen:
        # Quick depth: skip query-generation LLM call and use topic itself as single query
        queries = [topic]
    else:
        system_prompt = (
            f"You are an expert research analyst. Your task is to generate up to {max_queries} focused, "
            "concise search queries that will find relevant, factual web information on the topic. "
            "Provide each query on a separate line. Do not include numbering, bullets, or extra text."
        )
        user_prompt = f"Topic: {topic}\nProvide up to {max_queries} search queries:"

        llm_output = chat(system=system_prompt, user=user_prompt, temperature=0.2)

        # Parse queries from output lines defensively
        queries = []
        for line in llm_output.splitlines():
            cleaned = line.strip().lstrip("0123456789.-*• ").strip()
            if cleaned and cleaned not in queries:
                queries.append(cleaned)
            if len(queries) >= max_queries:
                break

        if not queries:
            queries = [topic]

    # Execute searches and de-duplicate by URL
    sources: List[Dict[str, str]] = []
    seen_urls: Set[str] = set()

    for query in queries:
        results = search(
            query=query,
            max_results=search_max_results,
            research_type=research_type,
        )
        for item in results:
            url = item.get("url", "").strip()
            if url and url not in seen_urls:
                seen_urls.add(url)
                sources.append({
                    "title": item.get("title", "").strip(),
                    "url": url,
                    "content": item.get("content", "").strip(),
                })

    return sources
