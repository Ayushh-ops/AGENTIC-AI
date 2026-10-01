"""
Synthesizer Agent: Generates a well-structured Markdown research report
with verified claims, key findings, and auditable references.
"""

from typing import Any, Dict, List
from backend.app.services.llm_service import chat


def synthesize_report(
    topic: str,
    claims: List[Dict[str, Any]],
    sources: List[Dict[str, str]],
) -> str:
    """
    Synthesize research findings into a structured Markdown document.

    Args:
        topic: The research topic investigated.
        claims: Verified claims list from the Fact Checker agent.
        sources: De-duplicated sources list from the Researcher agent.

    Returns:
        A complete Markdown formatted research report.
    """
    valid_sources = [s for s in sources if s.get("url")]
    valid_urls = {s["url"] for s in valid_sources}

    claims_text = "\n".join(
        f"- [{c.get('status', 'unverified').upper()}] {c.get('statement')}"
        for c in claims
    )
    sources_summary = "\n".join(
        f"- {s.get('title') or s.get('url')}: {s.get('content')[:250]}..."
        for s in valid_sources[:5]
    )

    system_prompt = (
        "You are a lead technical research writer. Your task is to synthesize the provided "
        "verified claims and source excerpts into a rigorous, objective research report.\n"
        "Guidelines:\n"
        "1. Write an Executive Summary and In-Depth Analysis.\n"
        "2. Do NOT invent new facts or external URLs.\n"
        "3. Maintain an academic, professional tone."
    )
    user_prompt = (
        f"Research Topic: {topic}\n\n"
        f"Verified Claims:\n{claims_text}\n\n"
        f"Source Contexts:\n{sources_summary}\n\n"
        "Compose an Executive Summary and Key Findings based solely on this evidence."
    )

    narrative = chat(system=system_prompt, user=user_prompt, temperature=0.2)

    # Format the definitive Markdown report
    lines: List[str] = [
        f"# Research Report: {topic}",
        "",
        "## Executive Summary & Findings",
        "",
        narrative.strip(),
        "",
        "## Evaluated Claims & Verification Audit",
        "",
    ]

    if claims:
        for c in claims:
            status = c.get("status")
            if status == "supported":
                status_tag = "✓ Verified"
            elif status == "single_source":
                status_tag = "⚠ Single source"
            else:
                status_tag = "✗ Unsupported"

            # Resolve citation URLs
            urls = [u for u in c.get("source_urls", []) if u in valid_urls]
            if not urls and c.get("source_url") and c.get("source_url") in valid_urls:
                urls = [c["source_url"]]

            if urls:
                if len(urls) == 1:
                    citation = f"([Source]({urls[0]}))"
                else:
                    links = ", ".join(f"[Source {i+1}]({u})" for i, u in enumerate(urls))
                    citation = f"({links})"
            else:
                citation = "(No direct citation)"

            lines.append(f"- **{status_tag}**: {c.get('statement')} {citation}")
    else:
        lines.append("- No specific claims evaluated.")

    lines.extend([
        "",
        "## References",
        "",
    ])

    if valid_sources:
        for idx, s in enumerate(valid_sources, 1):
            title = s.get("title") or s["url"]
            lines.append(f"{idx}. [{title}]({s['url']})")
    else:
        lines.append("- No external sources available.")

    return "\n".join(lines)
