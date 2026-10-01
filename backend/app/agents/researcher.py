"""
Researcher Agent: Deconstructs topics into focused search queries, executes
web searches via Tavily, and returns de-duplicated sources.
"""

from typing import Dict, List, Set
from backend.app.services.llm_service import chat
from backend.app.services.search_service import search


def research_topic(topic: str) -> List[Dict[str, str]]:
    """
    Generate focused search queries for a topic, query Tavily, and return unique sources.

    Args:
        topic: The user's research topic.

    Returns:
        A list of de-duplicated source dictionaries containing 'title', 'url', and 'content'.
    """
    system_prompt = (
        "You are an expert research analyst. Your task is to generate up to 3 focused, "
        "concise search queries that will find relevant, factual web information on the topic. "
        "Provide each query on a separate line. Do not include numbering, bullets, or extra text."
    )
    user_prompt = f"Topic: {topic}\nProvide up to 3 search queries:"

    llm_output = chat(system=system_prompt, user=user_prompt, temperature=0.2)

    # Parse queries from output lines defensively
    queries: List[str] = []
    for line in llm_output.splitlines():
        cleaned = line.strip().lstrip("0123456789.-*• ").strip()
        if cleaned and cleaned not in queries:
            queries.append(cleaned)
        if len(queries) >= 3:
            break

    if not queries:
        queries = [topic]

    # Execute searches and de-duplicate by URL
    sources: List[Dict[str, str]] = []
    seen_urls: Set[str] = set()

    for query in queries:
        results = search(query=query, max_results=3)
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
