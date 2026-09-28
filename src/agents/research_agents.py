from crewai import Agent, LLM
from typing import List
from ..tools.search_tools import get_research_tools

def create_researcher_agent(llm: LLM) -> Agent:
    """Creates the Senior Research Analyst agent."""
    return Agent(
        role="Senior Research Analyst",
        goal="Perform in-depth research, discover latest developments, and gather factual data on {topic}",
        backstory=(
            "You are a world-class investigative researcher and intelligence analyst. "
            "You have an extraordinary talent for searching the web, discovering verified facts, "
            "tracking recent breakthroughs, and synthesizing academic and market insights."
        ),
        tools=get_research_tools(),
        llm=llm,
        verbose=True,
        allow_delegation=False,
    )


def create_fact_checker_agent(llm: LLM) -> Agent:
    """Creates the Critical Fact-Checker & Data Synthesizer agent."""
    return Agent(
        role="Critical Fact-Checker & Data Synthesizer",
        goal="Audit gathered research on {topic}, cross-validate sources, resolve contradictions, and identify key insights",
        backstory=(
            "You are a meticulous investigative auditor and data specialist. "
            "You do not accept claims at face value. You double-check dates, verify statistics, "
            "filter out hype, and synthesize complex findings into logical, objective pillars of truth."
        ),
        tools=get_research_tools(),
        llm=llm,
        verbose=True,
        allow_delegation=False,
    )


def create_writer_agent(llm: LLM) -> Agent:
    """Creates the Executive Report Specialist & Technical Writer agent."""
    return Agent(
        role="Executive Report Specialist",
        goal="Craft a comprehensive, engaging, and publication-ready Markdown research report on {topic}",
        backstory=(
            "You are an acclaimed technical author and executive briefing specialist. "
            "You transform dense technical findings and data into beautifully structured, "
            "insightful, and highly readable reports with executive summaries, clear sections, "
            "key takeaways, and source citations."
        ),
        tools=[],  # Writer focuses on writing and synthesis without tool distractions
        llm=llm,
        verbose=True,
        allow_delegation=False,
    )
