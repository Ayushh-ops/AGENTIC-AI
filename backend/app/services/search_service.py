"""
Search service module for querying the Tavily Search REST API via direct HTTP.
"""

import contextvars
import time
from typing import Dict, List, Optional
import urllib.parse
import httpx
from backend.app.core.config import settings

TAVILY_API_URL = "https://api.tavily.com/search"

search_call_counter: contextvars.ContextVar[Optional[list]] = contextvars.ContextVar(
    "search_call_counter", default=None
)

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

ACADEMIC_INCLUDE_DOMAINS = [
    "arxiv.org",
    "nature.com",
    "science.org",
    "sciencedirect.com",
    "springer.com",
    "ieee.org",
    "acm.org",
    "nih.gov",
    "pubmed.ncbi.nlm.nih.gov",
    "jstor.org",
    "plos.org",
    "mdpi.com",
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


def _execute_tavily_request(payload: dict) -> List[Dict[str, str]]:
    """Execute a single HTTP request to Tavily with retries and rate limit handling."""
    counter = search_call_counter.get()
    if counter is not None:
        counter.append(1)

    headers = {
        "Content-Type": "application/json",
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


def search(
    query: str,
    max_results: int = 5,
    research_type: str = "general",
) -> List[Dict[str, str]]:
    """
    Query the Tavily Search API and return normalized search results.

    Args:
        query: Search query string.
        max_results: Maximum number of search results to return (default 5).
        research_type: 'general', 'news', or 'academic' (default 'general').

    Returns:
        List of dicts, each containing 'title', 'url', and 'content' (truncated to 800 chars).

    Raises:
        SearchError: If TAVILY_API_KEY is not configured or the request fails.
    """
    api_key = settings.tavily_api_key
    if not api_key:
        raise SearchError("Tavily API key is not configured.")

    base_payload = {
        "api_key": api_key,
        "query": query,
        "max_results": max_results,
    }

    type_clean = (research_type or "general").strip().lower()

    if type_clean == "news":
        payload = {
            **base_payload,
            "topic": "news",
            "days": 30,
            "exclude_domains": EXCLUDED_DOMAINS,
        }
        return _execute_tavily_request(payload)

    elif type_clean == "academic":
        payload = {
            **base_payload,
            "include_domains": ACADEMIC_INCLUDE_DOMAINS,
        }
        results = _execute_tavily_request(payload)
        # If academic search returns ZERO results, retry once without include_domains
        if not results:
            fallback_payload = {
                **base_payload,
                "exclude_domains": EXCLUDED_DOMAINS,
            }
            results = _execute_tavily_request(fallback_payload)
        return results

    else:
        # general (default)
        payload = {
            **base_payload,
            "exclude_domains": EXCLUDED_DOMAINS,
        }
        return _execute_tavily_request(payload)
