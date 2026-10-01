"""
Fact Checker Agent: Audits sources, extracts key factual claims, and evaluates
corroboration across multiple distinct sources with cross-checking and targeted search fallback.
"""

import json
import re
from typing import Any, Dict, List, Optional
import urllib.parse
from backend.app.services.llm_service import chat, LLMError
from backend.app.services.search_service import search, SearchError


def _extract_registrable_domain(url: str) -> str:
    """
    Extract registrable domain from a URL:
    - strips 'www.'
    - treats subdomains of the same site as one (e.g. blog.example.com -> example.com)
    - handles common two-part TLDs (e.g. .co.uk, .gov.in)
    """
    try:
        netloc = urllib.parse.urlparse(url).netloc.lower()
        if not netloc:
            return ""
        if ":" in netloc:
            netloc = netloc.split(":")[0]
        if netloc.startswith("www."):
            netloc = netloc[4:]

        parts = netloc.split(".")
        if len(parts) <= 2:
            return netloc

        common_two_part_tlds = {
            "co.uk", "gov.uk", "ac.uk", "org.uk", "net.uk",
            "co.in", "gov.in", "ac.in", "org.in", "net.in",
            "com.au", "net.au", "org.au", "edu.au", "gov.au",
            "co.jp", "ne.jp", "ac.jp", "go.jp",
        }
        last_two = f"{parts[-2]}.{parts[-1]}"
        if last_two in common_two_part_tlds and len(parts) >= 3:
            return f"{parts[-3]}.{last_two}"

        return f"{parts[-2]}.{parts[-1]}"
    except Exception:
        return ""


def _clean_json_response(raw: str) -> str:
    """Clean <think> tags, markdown code fences, and whitespace."""
    cleaned = re.sub(r"<think>.*?</think>", "", raw, flags=re.DOTALL).strip()
    if cleaned.startswith("```json"):
        cleaned = cleaned[7:]
    elif cleaned.startswith("```"):
        cleaned = cleaned[3:]
    if cleaned.endswith("```"):
        cleaned = cleaned[:-3]
    return cleaned.strip()


def _is_quote_in_text(quote: str, text: str) -> bool:
    """
    Accept a quote ONLY if it actually appears in that source's text:
    - Case-insensitive, whitespace-normalized
    - Lenient match allowing >= 80% word overlap
    """
    if not quote or not text:
        return False

    norm_quote = " ".join(quote.lower().split())
    norm_text = " ".join(text.lower().split())

    if not norm_quote or not norm_text:
        return False

    if norm_quote in norm_text:
        return True

    quote_words = re.findall(r"\w+", norm_quote)
    if not quote_words:
        return False

    text_words = set(re.findall(r"\w+", norm_text))
    if len(quote_words) <= 3:
        return all(w in text_words for w in quote_words)

    matched = sum(1 for w in quote_words if w in text_words)
    return (matched / len(quote_words)) >= 0.8


def _parse_cross_check_json(raw: str) -> Dict[str, List[Dict[str, Any]]]:
    """Parse batched cross-check JSON mapping claim ids to supporting source quotes."""
    cleaned = _clean_json_response(raw)
    sb = cleaned.find("{")
    eb = cleaned.rfind("}")
    if sb != -1 and eb != -1 and eb > sb:
        cleaned = cleaned[sb : eb + 1]

    try:
        data = json.loads(cleaned)
        if isinstance(data, dict):
            return data
        if isinstance(data, list):
            res = {}
            for item in data:
                if isinstance(item, dict):
                    cid = item.get("id") or item.get("claim_id")
                    if cid and "sources" in item and isinstance(item["sources"], list):
                        res[str(cid)] = item["sources"]
                    elif cid and "quotes" in item and isinstance(item["quotes"], list):
                        res[str(cid)] = item["quotes"]
            if res:
                return res
    except Exception:
        pass
    return {}


def _parse_fallback_json(raw: str) -> List[Dict[str, Any]]:
    """Parse JSON list of {source_index, quote} from targeted fallback search."""
    cleaned = _clean_json_response(raw)
    sb = cleaned.find("[")
    eb = cleaned.rfind("]")
    if sb != -1 and eb != -1 and eb > sb:
        cleaned = cleaned[sb : eb + 1]
    try:
        data = json.loads(cleaned)
        if isinstance(data, list):
            return [item for item in data if isinstance(item, dict)]
    except Exception:
        pass
    return []


def check_facts(topic: str, sources: List[Dict[str, str]]) -> List[Dict[str, Any]]:
    """
    Extract key claims from sources and verify their factual support through:
    1. Initial claim extraction
    2. Batched cross-check pass across all retrieved sources
    3. Strict quote-in-text validation and registrable domain deduplication
    4. Targeted search fallback for up to 3 single_source claims

    Statuses:
    - 'supported': corroborated by >= 2 distinct registrable domains
    - 'single_source': corroborated by exactly 1 domain
    - 'unsupported': 0 supporting domains or unsubstantiated

    Args:
        topic: The research topic.
        sources: List of source dictionaries containing 'title', 'url', and 'content'.
                 May be appended with new sources found during fallback search.

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

    # -------------------------------------------------------------
    # Step 1: Initial claim extraction pass
    # -------------------------------------------------------------
    sources_summary = "\n\n".join(
        f"Source URL: {s.get('url')}\nTitle: {s.get('title')}\nExcerpt: {(s.get('content') or '')[:800]}"
        for s in sources[:6]
    )

    extract_system_prompt = (
        "You are an impartial fact-checking agent. Analyze the provided research topic and source excerpts.\n"
        "Extract 3 to 5 key factual claims.\n"
        "For each claim:\n"
        "1. Identify supporting Source URLs from the provided excerpts that substantiate it.\n"
        "2. Extract a direct evidence excerpt (max 200 characters) from the source text.\n"
        "3. List all supporting Source URLs in 'source_urls' (empty list [] if unsupported).\n\n"
        "Return ONLY a valid JSON array of objects with keys: 'statement', 'evidence', 'source_urls'.\n"
        "Example:\n"
        '[{"statement": "Quantum computers use qubits.", "evidence": "qubits exhibit superposition...", '
        '"source_urls": ["https://example.com/a"]}]\n'
        "Do not include markdown code fences or conversational prose."
    )
    extract_user_prompt = f"Topic: {topic}\n\nRetrieved Sources:\n{sources_summary}"

    raw_extract = chat(system=extract_system_prompt, user=extract_user_prompt, temperature=0.1)
    cleaned_extract = _clean_json_response(raw_extract)

    start_b = cleaned_extract.find("[")
    end_b = cleaned_extract.rfind("]")
    if start_b != -1 and end_b != -1 and end_b > start_b:
        cleaned_extract = cleaned_extract[start_b : end_b + 1]

    claims: List[Dict[str, Any]] = []
    # Track initial validated URLs and quotes per claim index
    initial_validated_per_claim: List[Dict[str, str]] = []

    try:
        parsed = json.loads(cleaned_extract)
        if isinstance(parsed, list):
            for item in parsed:
                if isinstance(item, dict) and "statement" in item:
                    stmt = str(item["statement"]).strip()
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

                    matched_urls = [u.strip() for u in raw_urls if isinstance(u, str) and u.strip() in valid_urls]
                    raw_status = str(item.get("status", "")).strip().lower()
                    if raw_status == "unsupported":
                        matched_urls = []

                    evidence = str(item.get("evidence", "")).strip()[:200]
                    validated_map: Dict[str, str] = {}

                    if raw_status != "unsupported":
                        for u in matched_urls:
                            src = next((s for s in sources if s.get("url") == u), None)
                            if src:
                                src_content = src.get("content", "") or ""
                                if evidence and _is_quote_in_text(evidence, src_content):
                                    validated_map[u] = evidence
                                elif _is_quote_in_text(stmt, src_content):
                                    validated_map[u] = stmt
                                elif not evidence:
                                    validated_map[u] = src_content[:200].strip()

                    claims.append({
                        "statement": stmt,
                        "status": "unsupported",
                        "evidence": evidence if raw_status != "unsupported" else "",
                        "source_urls": list(validated_map.keys()),
                        "source_url": list(validated_map.keys())[0] if validated_map else None,
                    })
                    initial_validated_per_claim.append(validated_map)
    except (json.JSONDecodeError, TypeError):
        pass

    # Fallback if no claims extracted
    if not claims:
        first_url = next(iter(valid_urls), None)
        first_src = next((s for s in sources if s.get("url") == first_url), {}) if first_url else {}
        fallback_ev = (first_src.get("content", "") or "")[:200].strip() if first_url else ""
        init_map = {first_url: fallback_ev} if first_url else {}
        claims = [
            {
                "statement": f"Preliminary evidence gathered for {topic}.",
                "status": "single_source" if first_url else "unsupported",
                "evidence": fallback_ev,
                "source_urls": [first_url] if first_url else [],
                "source_url": first_url,
            }
        ]
        initial_validated_per_claim = [init_map]

    # -------------------------------------------------------------
    # Step 2: Cross-check pass (ONE batched LLM call, no extra search)
    # -------------------------------------------------------------
    if claims and sources:
        claims_input = [
            {"id": f"claim_{i}", "statement": c["statement"]}
            for i, c in enumerate(claims)
        ]
        numbered_sources_text = "\n\n".join(
            f"Source {idx} (domain: {_extract_registrable_domain(s.get('url', ''))}, url: {s.get('url')}):\n"
            f"{(s.get('content') or '')[:800]}"
            for idx, s in enumerate(sources)
        )

        cross_system_prompt = (
            "You are a rigorous factual verification agent. Cross-check the provided claims against the numbered sources.\n"
            "For each claim, determine which numbered sources directly corroborate it.\n"
            "Requirements:\n"
            "1. Only cite a source if it clearly states the same fact (same numbers, names, dates).\n"
            "2. For each supporting source, provide the source_index and a verbatim quote (<= 200 chars) copied directly from that source's content.\n"
            "3. If a source does not substantiate the claim, leave it out.\n"
            "4. Output JSON ONLY: a dictionary mapping each claim id to a list of {\"source_index\": int, \"quote\": str}.\n"
            "Example:\n"
            '{"claim_0": [{"source_index": 0, "quote": "..."}, {"source_index": 1, "quote": "..."}]}\n'
            "Do not include markdown code fences or conversational prose."
        )
        cross_user_prompt = (
            f"Claims to cross-check:\n{json.dumps(claims_input, indent=2)}\n\n"
            f"Numbered Sources:\n{numbered_sources_text}"
        )

        try:
            raw_cross = chat(system=cross_system_prompt, user=cross_user_prompt, temperature=0.1)
            cross_data = _parse_cross_check_json(raw_cross)
        except Exception:
            cross_data = {}

        for i, claim in enumerate(claims):
            cid = f"claim_{i}"
            validated_supporters: Dict[str, str] = dict(initial_validated_per_claim[i])

            # Process corroborating sources from cross-check
            items = cross_data.get(cid) or cross_data.get(str(i)) or []
            if isinstance(items, list):
                for item in items:
                    if isinstance(item, dict):
                        idx = item.get("source_index")
                        quote = str(item.get("quote", "")).strip()[:200]
                        if isinstance(idx, int) and 0 <= idx < len(sources):
                            src = sources[idx]
                            src_url = src.get("url", "").strip()
                            if src_url and _is_quote_in_text(quote, src.get("content", "")):
                                validated_supporters[src_url] = quote

            # Merge validated supporters into source_urls
            merged_urls = list(dict.fromkeys(validated_supporters.keys()))
            claim["source_urls"] = merged_urls

            # Pick best validated quote for evidence
            if validated_supporters:
                best_quote = max(validated_supporters.values(), key=len)
                claim["evidence"] = best_quote
            elif not claim.get("evidence"):
                claim["evidence"] = ""

            # Count distinct domains by registrable domain
            distinct_domains = {
                _extract_registrable_domain(u)
                for u in merged_urls
                if _extract_registrable_domain(u)
            }
            if len(distinct_domains) >= 2:
                claim["status"] = "supported"
            elif len(distinct_domains) == 1:
                claim["status"] = "single_source"
            else:
                claim["status"] = "unsupported"
                claim["source_urls"] = []
                claim["evidence"] = ""
            claim["source_url"] = claim["source_urls"][0] if claim["source_urls"] else None

    # -------------------------------------------------------------
    # Step 3: Targeted search fallback for up to 3 single_source claims
    # -------------------------------------------------------------
    single_source_claims = [c for c in claims if c.get("status") == "single_source"][:3]
    for claim in single_source_claims:
        try:
            new_results = search(query=claim["statement"], max_results=5)
            added_for_claim: List[Dict[str, str]] = []
            for nr in new_results:
                nr_url = nr.get("url", "").strip()
                if not nr_url:
                    continue
                # Add newly found sources to response sources list (de-duplicated by URL)
                if not any(s.get("url") == nr_url for s in sources):
                    sources.append(nr)
                added_for_claim.append(nr)

            if added_for_claim:
                fb_system = (
                    "You are a factual verification agent. For the given claim, determine which of the new sources directly support it.\n"
                    "Requirements:\n"
                    "1. Only cite a source if it clearly states the same fact (same numbers, names, dates).\n"
                    "2. For each supporting source, provide the source_index and a verbatim quote (max 200 chars) copied directly from that source.\n"
                    "3. Output JSON ONLY: a list of objects with 'source_index' and 'quote'. Example: [{\"source_index\": 0, \"quote\": \"...\"}]\n"
                    "If none support it, return []."
                )
                fb_sources_text = "\n\n".join(
                    f"Source {idx} (domain: {_extract_registrable_domain(s.get('url', ''))}, url: {s.get('url')}):\n"
                    f"{(s.get('content') or '')[:800]}"
                    for idx, s in enumerate(added_for_claim)
                )
                fb_user = f"Claim to verify: {claim['statement']}\n\nNew Sources:\n{fb_sources_text}"
                raw_fb = chat(system=fb_system, user=fb_user, temperature=0.1)
                fb_items = _parse_fallback_json(raw_fb)

                for item in fb_items:
                    idx = item.get("source_index")
                    quote = str(item.get("quote", "")).strip()[:200]
                    if isinstance(idx, int) and 0 <= idx < len(added_for_claim):
                        ns = added_for_claim[idx]
                        ns_url = ns.get("url", "").strip()
                        if ns_url and _is_quote_in_text(quote, ns.get("content", "")):
                            if ns_url not in claim["source_urls"]:
                                claim["source_urls"].append(ns_url)
                            if not claim.get("evidence"):
                                claim["evidence"] = quote

                # Re-evaluate status with distinct registrable domains
                domains = {
                    _extract_registrable_domain(u)
                    for u in claim["source_urls"]
                    if _extract_registrable_domain(u)
                }
                if len(domains) >= 2:
                    claim["status"] = "supported"
                elif len(domains) == 1:
                    claim["status"] = "single_source"
                else:
                    claim["status"] = "unsupported"
                claim["source_url"] = claim["source_urls"][0] if claim["source_urls"] else None
        except (SearchError, LLMError, Exception):
            # Swallow any search or LLM error; leaves claim as single_source
            pass

    # -------------------------------------------------------------
    # Step 4: Final status sanity check
    # -------------------------------------------------------------
    for claim in claims:
        domains = {
            _extract_registrable_domain(u)
            for u in claim.get("source_urls", [])
            if _extract_registrable_domain(u)
        }
        if len(domains) >= 2:
            claim["status"] = "supported"
            claim["source_url"] = claim["source_urls"][0]
        elif len(domains) == 1:
            claim["status"] = "single_source"
            claim["source_url"] = claim["source_urls"][0]
        else:
            claim["status"] = "unsupported"
            claim["source_urls"] = []
            claim["source_url"] = None
            claim["evidence"] = ""

    return claims
