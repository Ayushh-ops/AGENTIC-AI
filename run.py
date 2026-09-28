import os
import sys
from pathlib import Path
from dotenv import load_dotenv

# Ensure local packages are resolvable
ROOT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT_DIR))

load_dotenv(dotenv_path=ROOT_DIR / ".env")

from src.crew import ResearchCrew

def print_banner():
    print("""
========================================================================
   🤖 MULTI-AGENT RESEARCH ASSISTANT (CrewAI & Agentic AI) 🚀
========================================================================
   Agents:
     [1] Senior Research Analyst   - Live Web & Deep Intelligence
     [2] Critical Fact-Checker     - Auditing, Data Synthesis & Rigor
     [3] Executive Report Writer   - Publication-Ready Markdown
========================================================================
""")

def check_env():
    gemini_key = os.getenv("GEMINI_API_KEY")
    openai_key = os.getenv("OPENAI_API_KEY")
    groq_key = os.getenv("GROQ_API_KEY")

    if not any([gemini_key, openai_key, groq_key]):
        print("⚠️  No API Key detected in .env file!")
        print("Please configure at least one API key in the .env file:")
        print(f"   Location: {ROOT_DIR / '.env'}\n")
        print("Supported keys: GEMINI_API_KEY, OPENAI_API_KEY, GROQ_API_KEY")

        key_input = input("\n👉 Paste your Gemini/OpenAI/Groq API key right now (or press Enter to exit): ").strip()
        if not key_input:
            print("Exiting. Please add your API key in .env and run again.")
            sys.exit(1)

        # Detect or ask provider
        if key_input.startswith("AIzaSy"):
            os.environ["GEMINI_API_KEY"] = key_input
            os.environ["MODEL_NAME"] = "gemini/gemini-2.0-flash"
            print("✅ Detected Gemini API Key! Using gemini-2.0-flash.")
        elif key_input.startswith("sk-proj-") or key_input.startswith("sk-"):
            os.environ["OPENAI_API_KEY"] = key_input
            os.environ["MODEL_NAME"] = "gpt-4o-mini"
            print("✅ Detected OpenAI API Key! Using gpt-4o-mini.")
        elif key_input.startswith("gsk_"):
            os.environ["GROQ_API_KEY"] = key_input
            os.environ["MODEL_NAME"] = "groq/llama-3.3-70b-versatile"
            print("✅ Detected Groq API Key! Using llama-3.3-70b.")
        else:
            os.environ["GEMINI_API_KEY"] = key_input
            os.environ["MODEL_NAME"] = "gemini/gemini-2.0-flash"
            print("✅ Set as GEMINI_API_KEY.")

def main():
    print_banner()
    check_env()

    while True:
        print("\n" + "-" * 70)
        topic = input("🔍 Enter Research Topic (or 'exit' to quit): ").strip()
        if not topic:
            continue
        if topic.lower() in ["exit", "quit", "q"]:
            print("👋 Exiting Multi-Agent Research Assistant. Happy researching!")
            break

        try:
            crew_orchestrator = ResearchCrew()
            results = crew_orchestrator.run(topic=topic)

            print("\n" + "=" * 70)
            print("🎉 RESEARCH REPORT GENERATED SUCCESSFULLY!")
            print("=" * 70)
            print(f"📁 Report Saved To: {results['output_path']}\n")
            print("--- REPORT PREVIEW ---")
            lines = results["report"].splitlines()
            preview = "\n".join(lines[:35])
            print(preview)
            if len(lines) > 35:
                print(f"\n... [Full report containing {len(lines)} lines saved in: {results['output_path']}]")

        except Exception as e:
            print(f"\n❌ Error during crew execution: {str(e)}")

if __name__ == "__main__":
    main()
