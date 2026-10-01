"""
Fact Checker Agent: Audits sources, extracts key factual claims, and evaluates
corroboration across multiple distinct sources with strict quote validation,
domain deduplication, and targeted search fallback.
"""

import json
import re
from typing import Any, Dict, List, Optional, Set, Tuple
import urllib.parse
from backend.app.services.llm_service import chat, LLMError
from backend.app.services.search_service import search, SearchError

STOP_WORDS = {
    "a", "about", "above", "after", "again", "against", "all", "am", "an", "and", "any", "are",
    "aren't", "as", "at", "be", "because", "been", "before", "being", "below", "between", "both",
    "but", "by", "can", "can't", "cannot", "could", "couldn't", "did", "didn't", "do", "does",
    "doesn't", "doing", "don't", "down", "during", "each", "few", "for", "from", "further", "had",
    "hadn't", "has", "hasn't", "have", "haven't", "having", "he", "he'd", "he'll", "he's", "her",
    "here", "here's", "hers", "herself", "him", "himself", "his", "how", "how's", "i", "i'd", "i'll",
    "i'm", "i've", "if", "in", "into", "is", "isn't", "it", "it's", "its", "itself", "let's", "me",
    "more", "most", "mustn't", "my", "myself", "no", "nor", "not", "of", "off", "on", "once", "only",
    "or", "other", "ought", "our", "ours", "ourselves", "out", "over", "own", "same", "shan't", "she",
    "she'd", "she'll", "she's", "should", "shouldn't", "so", "some", "such", "than", "that", "that's",
    "the", "their", "theirs", "them", "themselves", "then", "there", "there's", "these", "they", "they'd",
    "they'll", "they're", "they've", "this", "those", "through", "to", "too", "under", "until", "up",
    "very", "was", "wasn't", "we", "we'd", "we'll", "we're", "we've", "were", "weren't", "what", "what's",
    "when", "when's", "where", "where's", "which", "while", "who", "who's", "whom", "why", "why's", "with",
    "won't", "would", "wouldn't", "you", "you'd", "you'll", "you're", "you've", "your", "yours", "yourself",
    "yourselves", "also", "including", "across", "using", "use", "used", "new", "many", "well", "one",
    "two", "first", "such", "than", "may", "can", "could", "will", "would", "which", "whose", "where",
}


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


def _extract_meaningful_terms(text: str) -> Set[str]:
    """Extract meaningful terms (nouns, numbers, names; ignoring stop words)."""
    words = re.findall(r"\b[a-zA-Z0-9_\-\.]{2,}\b", text.lower())
    terms: Set[str] = set()
    for w in words:
        w_clean = w.strip(".-_")
        if len(w_clean) >= 2 and w_clean not in STOP_WORDS:
            terms.add(w_clean)
    return terms


def _validate_quote_for_claim(
    quote: str,
    source_text: str,
    claim_statement: str,
) -> Tuple[bool, float, Set[str]]:
    """
    Validate that a quote genuinely supports a claim from source_text:
    (a) Quote must be at least 6 words.
    (b) Match ratio >= 80% against source_text.
    (c) Quote must share at least 2 meaningful terms with claim_statement.
    (d) Source text must contain those shared terms.

    Returns:
        (is_valid, match_ratio, shared_terms)
    """
    if not quote or not source_text or not claim_statement:
        return False, 0.0, set()

    quote_words = re.findall(r"\b\w+\b", quote)
    # (a) Quote must be at least 6 words
    if len(quote_words) < 6:
        return False, 0.0, set()

    # (b) Match ratio >= 80% against source text
    norm_quote = " ".join(quote.lower().split())
    norm_text = " ".join(source_text.lower().split())

    if norm_quote in norm_text:
        match_ratio = 1.0
    else:
        source_words_set = set(re.findall(r"\b\w+\b", norm_text))
        matched_count = sum(1 for w in quote_words if w.lower() in source_words_set)
        match_ratio = matched_count / len(quote_words)

    if match_ratio < 0.8:
        return False, match_ratio, set()

    # (c) Share at least 2 meaningful terms with claim statement
    claim_terms = _extract_meaningful_terms(claim_statement)
    quote_terms = _extract_meaningful_terms(quote)
    shared_terms = quote_terms.intersection(claim_terms)

    if len(shared_terms) < 2:
        return False, match_ratio, shared_terms

    # (d) Source text must contain those shared terms
    source_terms = _extract_meaningful_terms(source_text)
    if not shared_terms.issubset(source_terms):
        return False, match_ratio, shared_terms

    return True, match_ratio, shared_terms


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


def _cap_sources(sources: List[Dict[str, str]], claims: List[Dict[str, Any]], max_sources: int = 12) -> List[Dict[str, str]]:
    """
    Cap total returned sources at 12:
    - Keep every source that supports a claim
    - Fill the rest with the first-retrieved sources
    """
    supporting_urls: Set[str] = set()
    for c in claims:
        for u in c.get("source_urls", []):
            if u:
                supporting_urls.add(u)
        if c.get("source_url"):
            supporting_urls.add(c["source_url"])

    supporters = [s for s in sources if s.get("url") in supporting_urls]
    remaining_slots = max(0, max_sources - len(supporters))
    others = [s for s in sources if s.get("url") not in supporting_urls][:remaining_slots]

    kept_urls = {s.get("url") for s in supporters + others if s.get("url")}
    capped = [s for s in sources if s.get("url") in kept_urls]
    return capped[:max_sources] if len(capped) > max_sources else capped


def check_facts(topic: str, sources: List[Dict[str, str]]) -> List[Dict[str, Any]]:
    """
    Extract key claims from sources and verify their factual support:
    1. Initial claim extraction
    2. Batched cross-check pass across all retrieved sources
    3. Strict quote-in-text validation and registrable domain deduplication
    4. Targeted search fallback for up to 3 single_source claims
    5. Capping total returned sources at 12

    Statuses:
    - 'supported': corroborated by >= 2 distinct registrable domains
    - 'single_source': corroborated by exactly 1 domain
    - 'unsupported': 0 supporting domains or unsubstantiated
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
        "2. Extract a direct evidence excerpt (at least 6 words, max 200 characters) from the source text.\n"
        "3. List all supporting Source URLs in 'source_urls' (empty list [] if unsupported).\n\n"
        "Return ONLY a valid JSON array of objects with keys: 'statement', 'evidence', 'source_urls'.\n"
        "Example:\n"
        '[{"statement": "Quantum computers use qubits that exist in superposition.", "evidence": "qubits exist in superposition allowing both zero and one states simultaneously", '
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
                                is_valid, _, _ = _validate_quote_for_claim(evidence, src_content, stmt)
                                if is_valid:
                                    validated_map[u] = evidence
                                else:
                                    is_valid_stmt, _, _ = _validate_quote_for_claim(stmt, src_content, stmt)
                                    if is_valid_stmt:
                                        validated_map[u] = stmt

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
            "2. For each supporting source, provide the source_index and a verbatim quote (at least 6 words, max 200 chars) copied directly from that source's content.\n"
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
                            if src_url:
                                is_valid, _, _ = _validate_quote_for_claim(
                                    quote, src.get("content", "") or "", claim["statement"]
                                )
                                if is_valid:
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
            if not new_results:
                continue

            fb_system = (
                "You are a factual verification agent. For the given claim, determine which of the new sources directly support it.\n"
                "Requirements:\n"
                "1. Only cite a source if it clearly states the same fact (same numbers, names, dates).\n"
                "2. For each supporting source, provide the source_index and a verbatim quote (at least 6 words, max 200 chars) copied directly from that source.\n"
                "3. Output JSON ONLY: a list of objects with 'source_index' and 'quote'. Example: [{\"source_index\": 0, \"quote\": \"...\"}]\n"
                "If none support it, return []."
            )
            fb_sources_text = "\n\n".join(
                f"Source {idx} (domain: {_extract_registrable_domain(s.get('url', ''))}, url: {s.get('url')}):\n"
                f"{(s.get('content') or '')[:800]}"
                for idx, s in enumerate(new_results)
            )
            fb_user = f"Claim to verify: {claim['statement']}\n\nNew Sources:\n{fb_sources_text}"
            raw_fb = chat(system=fb_system, user=fb_user, temperature=0.1)
            fb_items = _parse_fallback_json(raw_fb)

            for item in fb_items:
                idx = item.get("source_index")
                quote = str(item.get("quote", "")).strip()[:200]
                if isinstance(idx, int) and 0 <= idx < len(new_results):
                    ns = new_results[idx]
                    ns_url = ns.get("url", "").strip()
                    if ns_url:
                        is_valid, _, _ = _validate_quote_for_claim(
                            quote, ns.get("content", "") or "", claim["statement"]
                        )
                        if is_valid:
                            # Only add newly found source if it actually validated as a supporter
                            if not any(s.get("url") == ns_url for s in sources):
                                sources.append(ns)
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

    # -------------------------------------------------------------
    # Step 5: Cap total returned sources at 12
    # -------------------------------------------------------------
    capped = _cap_sources(sources, claims, max_sources=12)
    sources.clear()
    sources.extend(capped)

    return claims
