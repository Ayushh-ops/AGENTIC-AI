from crewai import Task, Agent

def create_research_task(agent: Agent, topic: str) -> Task:
    """Creates the deep-dive research gathering task."""
    return Task(
        description=(
            f"Conduct an in-depth web and literature investigation on: '{topic}'.\n"
            "Steps:\n"
            "1. Use search tools to find foundational concepts, technical architecture, and recent breakthroughs.\n"
            "2. Identify notable industry use cases, key players, frameworks, and benchmarks.\n"
            "3. Extract verified statistics, factual data, and preserve source URLs.\n"
            "Focus on depth, recency, and factual correctness."
        ),
        expected_output=(
            "A structured research dossier containing raw verified facts, technical specifications, "
            "recent developments, notable statistics, and source links for each finding."
        ),
        agent=agent,
    )


def create_analysis_task(agent: Agent, topic: str, research_task: Task) -> Task:
    """Creates the critical auditing and synthesis task."""
    return Task(
        description=(
            f"Critically audit and synthesize the research dossier compiled on: '{topic}'.\n"
            "Steps:\n"
            "1. Cross-validate facts and filter out any marketing hype or unverified claims.\n"
            "2. Identify core themes, technological trade-offs, advantages, and limitations.\n"
            "3. Structure the key findings into logical categories (Foundations, Innovations, Challenges, Roadmap).\n"
            "4. Verify that source citations and URLs are accurately tracked."
        ),
        expected_output=(
            "A comprehensive analytical briefing synthesizing verified insights, categorized themes, "
            "pros/cons, and curated references ready for executive report writing."
        ),
        agent=agent,
        context=[research_task],
    )


def create_reporting_task(agent: Agent, topic: str, analysis_task: Task, output_path: str = None) -> Task:
    """Creates the publication-grade Markdown report creation task."""
    return Task(
        description=(
            f"Write a publication-ready, executive-grade comprehensive Research Report on: '{topic}'.\n"
            "Using the audited analysis, format the report in clean GitHub Markdown.\n"
            "Structure requirements:\n"
            "# Title: [Compelling Topic Title]\n"
            "## 1. Executive Summary\n"
            "## 2. Background & Fundamentals\n"
            "## 3. Latest Breakthroughs & Industry Landscape\n"
            "## 4. Technical Architecture / Deep Dive\n"
            "## 5. Real-World Applications & Case Studies\n"
            "## 6. Challenges, Limitations & Security/Ethics\n"
            "## 7. Future Trends & Predictions\n"
            "## 8. Strategic Recommendations & Key Takeaways\n"
            "## 9. References & Sources (with URLs where available)\n\n"
            "Ensure the tone is authoritative, analytical, and engaging. Include Markdown tables or bullet lists where appropriate."
        ),
        expected_output=(
            "A comprehensive, complete, and professionally structured Markdown research report "
            "ready for distribution, containing all requested sections and citations."
        ),
        agent=agent,
        context=[analysis_task],
        output_file=output_path,
    )
