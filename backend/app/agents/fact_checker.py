"""
Fact Checker Agent: Audits sources, extracts key factual claims, and evaluates
verification status and URL attribution.
"""

import json
import re
from typing import Any, Dict, List, Optional
import urllib.parse
from backend.app.services.llm_service import chat


def _extract_domain(url: str) -> str:
    """Extract normalized domain from a URL."""
    try:
        netloc = urllib.parse.urlparse(url).netloc.lower()
        if netloc.startswith("www."):
            netloc = netloc[4:]
        return netloc
    except Exception:
        return ""


def check_facts(topic: str, sources: List[Dict[str, str]]) -> List[Dict[str, Any]]:
    """
    Extract key claims from sources and verify their factual support.
    Claims are classified based on the count of DISTINCT supporting domains:
    - 'supported': corroborated by >= 2 distinct domains
    - 'single_source': corroborated by exactly 1 domain
    - 'unsupported': 0 supporting domains or unsubstantiated

    Args:
        topic: The research topic.
        sources: List of source dictionaries containing 'title', 'url', and 'content'.

    Returns:
        List of claim dicts with 'statement', 'status', 'evidence', 'source_urls', and 'source_url'.
    """
    if not sources:
        return [
            {
                "statement": f"No web sources available to substantiate claims for '{topic}'.",
                "status": "unsupported",
                "evidence": "",
                "source_urls": [],
                "source_url": None,
            }
        ]

    valid_urls = {s.get("url", "").strip() for s in sources if s.get("url")}

    sources_summary = "\n\n".join(
        f"Source URL: {s.get('url')}\nTitle: {s.get('title')}\nExcerpt: {s.get('content')}"
        for s in sources[:6]
    )

    system_prompt = (
        "You are an impartial fact-checking agent. Analyze the provided research topic and source excerpts.\n"
        "Extract 3 to 5 key factual claims.\n"
        "For each claim:\n"
        "1. Identify all supporting Source URLs from the provided excerpts that substantiate it.\n"
        "2. Extract a direct evidence excerpt (max 200 characters) from the source text.\n"
        "3. List all supporting Source URLs in 'source_urls' (empty list [] if unsupported).\n\n"
        "Return ONLY a valid JSON array of objects with keys: 'statement', 'evidence', 'source_urls'.\n"
        "Example:\n"
        '[{"statement": "Quantum computers use qubits.", "evidence": "qubits exhibit superposition...", '
        '"source_urls": ["https://example.com/a", "https://another.org/b"]}]\n'
        "Do not include markdown code fences or any conversational prose."
    )
    user_prompt = f"Topic: {topic}\n\nRetrieved Sources:\n{sources_summary}"

    raw_response = chat(system=system_prompt, user=user_prompt, temperature=0.1)

    # Clean potential reasoning blocks (<think>...</think>)
    cleaned = re.sub(r"<think>.*?</think>", "", raw_response, flags=re.DOTALL).strip()

    # Clean potential markdown fences
    if cleaned.startswith("```json"):
        cleaned = cleaned[7:]
    elif cleaned.startswith("```"):
        cleaned = cleaned[3:]
    if cleaned.endswith("```"):
        cleaned = cleaned[:-3]
    cleaned = cleaned.strip()

    # Extract JSON array substring if surrounded by extra commentary or thought text
    start_bracket = cleaned.find("[")
    end_bracket = cleaned.rfind("]")
    if start_bracket != -1 and end_bracket != -1 and end_bracket > start_bracket:
        cleaned = cleaned[start_bracket : end_bracket + 1]

    claims: List[Dict[str, Any]] = []
    try:
        parsed = json.loads(cleaned)
        if isinstance(parsed, list):
            for item in parsed:
                if isinstance(item, dict) and "statement" in item:
                    stmt = str(item["statement"]).strip()

                    # Collect candidate URLs (support both source_urls list and source_url string)
                    raw_urls = item.get("source_urls")
                    if raw_urls is None:
                        raw_urls = []
                    elif isinstance(raw_urls, str):
                        raw_urls = [raw_urls]
                    elif not isinstance(raw_urls, list):
                        raw_urls = []

                    single_url = item.get("source_url")
                    if single_url and isinstance(single_url, str) and single_url not in raw_urls:
                        raw_urls.append(single_url)

                    # Validate URLs against genuine sources
                    matched_urls = [u.strip() for u in raw_urls if isinstance(u, str) and u.strip() in valid_urls]

                    # Check if model explicitly indicated unsupported
                    raw_status = str(item.get("status", "")).strip().lower()
                    if raw_status == "unsupported":
                        matched_urls = []

                    # Count distinct domains
                    distinct_domains = {_extract_domain(u) for u in matched_urls if _extract_domain(u)}
                    num_domains = len(distinct_domains)

                    if num_domains >= 2:
                        status = "supported"
                    elif num_domains == 1:
                        status = "single_source"
                    else:
                        status = "unsupported"
                        matched_urls = []

                    # Extract or backfill evidence snippet
                    evidence = str(item.get("evidence", "")).strip()[:200]
                    if not evidence and matched_urls and status != "unsupported":
                        first_source = next((s for s in sources if s.get("url") == matched_urls[0]), {})
                        evidence = (first_source.get("content", "") or "")[:200].strip()

                    first_url = matched_urls[0] if (matched_urls and status != "unsupported") else None

                    claims.append({
                        "statement": stmt,
                        "status": status,
                        "evidence": evidence if status != "unsupported" else "",
                        "source_urls": matched_urls if status != "unsupported" else [],
                        "source_url": first_url,
                    })
    except (json.JSONDecodeError, TypeError):
        pass

    # Graceful fallback if JSON parsing failed or produced empty list
    if not claims:
        first_url = next(iter(valid_urls), None)
        first_source = next((s for s in sources if s.get("url") == first_url), {})
        evidence = (first_source.get("content", "") or "")[:200].strip() if first_url else ""
        claims = [
            {
                "statement": f"Preliminary evidence gathered for {topic}.",
                "status": "single_source" if first_url else "unsupported",
                "evidence": evidence,
                "source_urls": [first_url] if first_url else [],
                "source_url": first_url,
            }
        ]

    return claims
