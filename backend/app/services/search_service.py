"""
Search service module for querying the Tavily Search REST API via direct HTTP.
"""

import time
from typing import Dict, List
import urllib.parse
import httpx
from backend.app.core.config import settings

TAVILY_API_URL = "https://api.tavily.com/search"

EXCLUDED_DOMAINS = [
    "youtube.com",
    "reddit.com",
    "quora.com",
    "facebook.com",
    "x.com",
    "twitter.com",
    "medium.com",
    "substack.com",
    "perplexity.ai",
    "docs.perplexity.ai",
    "pinterest.com",
]


class SearchError(Exception):
    """Exception raised when a search operation fails or API key is missing."""
    pass


def _is_excluded_domain(url: str) -> bool:
    """Check if the URL belongs to any excluded domain."""
    try:
        domain = urllib.parse.urlparse(url).netloc.lower()
        if domain.startswith("www."):
            domain = domain[4:]
        return any(domain == d or domain.endswith("." + d) for d in EXCLUDED_DOMAINS)
    except Exception:
        return False


def search(query: str, max_results: int = 5) -> List[Dict[str, str]]:
    """
    Query the Tavily Search API and return normalized search results.

    Args:
        query: Search query string.
        max_results: Maximum number of search results to return (default 5).

    Returns:
        List of dicts, each containing 'title', 'url', and 'content' (truncated to 800 chars).

    Raises:
        SearchError: If TAVILY_API_KEY is not configured or the request fails.
    """
    api_key = settings.tavily_api_key
    if not api_key:
        raise SearchError("Tavily API key is not configured.")

    headers = {
        "Content-Type": "application/json",
    }
    payload = {
        "api_key": api_key,
        "query": query,
        "max_results": max_results,
        "exclude_domains": EXCLUDED_DOMAINS,
    }

    max_retries = 2
    for attempt in range(max_retries + 1):
        try:
            with httpx.Client(timeout=20.0) as client:
                response = client.post(TAVILY_API_URL, headers=headers, json=payload)
                if response.status_code == 429 and attempt < max_retries:
                    retry_after_str = response.headers.get("retry-after")
                    try:
                        wait_time = float(retry_after_str) if retry_after_str else 2.0 * (attempt + 1)
                    except ValueError:
                        wait_time = 2.0 * (attempt + 1)
                    time.sleep(min(wait_time, 5.0))
                    continue
                if response.status_code != 200:
                    raise SearchError(
                        f"Tavily API error (status {response.status_code}): {response.text}"
                    )
                data = response.json()
                raw_results = data.get("results", [])
                results: List[Dict[str, str]] = []
                for item in raw_results:
                    url = item.get("url", "") or ""
                    if _is_excluded_domain(url):
                        continue
                    raw_content = item.get("content", "") or ""
                    results.append({
                        "title": item.get("title", "") or "",
                        "url": url,
                        "content": raw_content[:800],
                    })
                return results
        except httpx.RequestError as exc:
            if attempt < max_retries:
                time.sleep(1.5)
                continue
            raise SearchError(f"HTTP request to Tavily failed: {exc}") from exc
        except Exception as exc:
            if isinstance(exc, SearchError):
                raise
            raise SearchError(f"Unexpected error in search service: {exc}") from exc

    raise SearchError("Tavily search failed after retries.")
