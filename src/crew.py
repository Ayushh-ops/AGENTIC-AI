import os
import sys
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Optional

# Enforce UTF-8 encoding on Windows to prevent charmap emoji crashes
os.environ["PYTHONIOENCODING"] = "utf-8"
if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
if hasattr(sys.stderr, "reconfigure"):
    try:
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass

from crewai import Crew, Process, LLM
from .config import get_configured_llm, ROOT_DIR
from .agents import (
    create_researcher_agent,
    create_fact_checker_agent,
    create_writer_agent,
)
from .tasks import (
    create_research_task,
    create_analysis_task,
    create_reporting_task,
)

def _sanitize_filename(text: str) -> str:
    """Sanitizes topic string for safe filesystem filename."""
    clean = re.sub(r'[^a-zA-Z0-9_\- ]+', '', text)
    clean = clean.strip().replace(' ', '_').lower()
    return clean[:40] if clean else "research"


class ResearchCrew:
    """Orchestrates the Multi-Agent Research Assistant Crew."""

    def __init__(
        self,
        model_name: Optional[str] = None,
        api_key: Optional[str] = None,
        llm: Optional[LLM] = None,
    ):
        self.llm = llm or get_configured_llm(model_override=model_name, api_key_override=api_key)

    def run(self, topic: str) -> Dict[str, Any]:
        """
        Executes the multi-agent research workflow on the given topic.
        Returns the final report text and metadata.
        """
        outputs_dir = ROOT_DIR / "outputs"
        outputs_dir.mkdir(parents=True, exist_ok=True)

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        safe_title = _sanitize_filename(topic)
        output_file = outputs_dir / f"report_{safe_title}_{timestamp}.md"

        # 1. Initialize Agents
        researcher = create_researcher_agent(self.llm)
        analyst = create_fact_checker_agent(self.llm)
        writer = create_writer_agent(self.llm)

        # 2. Initialize Tasks
        task1 = create_research_task(researcher, topic)
        task2 = create_analysis_task(analyst, topic, task1)
        task3 = create_reporting_task(writer, topic, task2, output_path=str(output_file))

        # 3. Assemble Crew
        crew = Crew(
            agents=[researcher, analyst, writer],
            tasks=[task1, task2, task3],
            process=Process.sequential,
            verbose=True,
        )

        try:
            print(f"\n[CrewAI] Initiating Multi-Agent Research on: '{topic}'...")
            print("=" * 60)
        except Exception:
            pass

        # 4. Kickoff
        crew_output = crew.kickoff(inputs={"topic": topic})

        # Read output from file or crew_output raw
        report_content = str(crew_output.raw if hasattr(crew_output, "raw") else crew_output)

        # Ensure output is safely saved to disk
        try:
            with open(output_file, "w", encoding="utf-8", errors="replace") as f:
                f.write(report_content)
        except Exception as e:
            print(f"Warning: could not write to file: {e}")

        return {
            "topic": topic,
            "report": report_content,
            "output_path": str(output_file),
            "timestamp": timestamp,
        }
