import os
import sys
from pathlib import Path
import streamlit as st
from dotenv import load_dotenv

ROOT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT_DIR))

load_dotenv(dotenv_path=ROOT_DIR / ".env")

from src.crew import ResearchCrew

# Page configuration
st.set_page_config(
    page_title="Multi-Agent Research Assistant (CrewAI)",
    page_icon="🤖",
    layout="wide",
    initial_sidebar_state="expanded",
)

# Custom CSS for modern styling
st.markdown("""
<style>
    .main-header {
        font-size: 2.2rem;
        font-weight: 700;
        color: #1E88E5;
        margin-bottom: 0.2rem;
    }
    .sub-header {
        font-size: 1.05rem;
        color: #616161;
        margin-bottom: 1.5rem;
    }
    .stAlert {
        border-radius: 8px;
    }
</style>
""", unsafe_allow_html=True)

# Sidebar
with st.sidebar:
    st.image("https://img.icons8.com/color/96/artificial-intelligence.png", width=64)
    st.title("Settings & Models")

    provider = st.selectbox(
        "LLM Provider",
        ["Groq (Ultra-Fast)", "Google Gemini", "OpenAI", "DeepSeek", "Ollama (Local)"],
        index=0
    )

    if provider == "Groq (Ultra-Fast)":
        env_key = os.getenv("GROQ_API_KEY", "")
        api_key = st.text_input("Groq API Key (gsk_...)", value=env_key, type="password")
        model_selection = st.selectbox(
            "Model",
            [
                "groq/llama-3.3-70b-versatile (Recommended)",
                "groq/llama-3.1-8b-instant (Fastest / High Rate Limit)",
                "groq/gemma2-9b-it",
                "groq/mixtral-8x7b-32768",
                "Custom Model..."
            ],
            index=0
        )
        if "Custom Model" in model_selection:
            model_name = st.text_input("Enter Groq Model ID", value="groq/llama-3.3-70b-versatile")
        else:
            model_name = model_selection.split(" ")[0]

    elif provider == "Google Gemini":
        env_key = os.getenv("GEMINI_API_KEY", "")
        api_key = st.text_input("Gemini API Key (AIzaSy...)", value=env_key, type="password")
        model_selection = st.selectbox(
            "Model",
            [
                "gemini/gemini-2.0-flash (Recommended)",
                "gemini/gemini-1.5-flash",
                "gemini/gemini-1.5-pro",
                "Custom Model..."
            ],
            index=0
        )
        if "Custom Model" in model_selection:
            model_name = st.text_input("Enter Gemini Model ID", value="gemini/gemini-2.0-flash")
        else:
            model_name = model_selection.split(" ")[0]

    elif provider == "OpenAI":
        env_key = os.getenv("OPENAI_API_KEY", "")
        api_key = st.text_input("OpenAI API Key (sk-...)", value=env_key, type="password")
        model_selection = st.selectbox(
            "Model",
            ["gpt-4o-mini (Recommended)", "gpt-4o", "Custom Model..."],
            index=0
        )
        if "Custom Model" in model_selection:
            model_name = st.text_input("Enter OpenAI Model ID", value="gpt-4o-mini")
        else:
            model_name = model_selection.split(" ")[0]

    elif provider == "DeepSeek":
        env_key = os.getenv("DEEPSEEK_API_KEY", "")
        api_key = st.text_input("DeepSeek API Key (sk-...)", value=env_key, type="password")
        model_selection = st.selectbox(
            "Model",
            ["deepseek/deepseek-chat", "deepseek/deepseek-reasoner", "Custom Model..."],
            index=0
        )
        if "Custom Model" in model_selection:
            model_name = st.text_input("Enter DeepSeek Model ID", value="deepseek/deepseek-chat")
        else:
            model_name = model_selection.split(" ")[0]

    else:  # Ollama Local
        api_key = "ollama"
        model_name = st.text_input("Ollama Model Name", value="ollama/llama3.2")

    st.markdown("---")
    st.subheader("👥 Active Crew Agents")
    st.markdown("""
    - **🔍 Senior Research Analyst**  
      *Web intelligence, DuckDuckGo & Wikipedia search.*
    - **⚖️ Critical Fact-Checker**  
      *Audits data, eliminates hallucinations & synthesizes insights.*
    - **📝 Executive Report Writer**  
      *Composes structured, publication-grade Markdown reports.*
    """)

# Main Content
st.markdown("<div class='main-header'>🤖 Multi-Agent Research Assistant</div>", unsafe_allow_html=True)
st.markdown(
    "<div class='sub-header'>Powered by <b>CrewAI</b> & <b>Agentic AI</b>. "
    "Autonomous agents collaborate to gather intelligence, verify facts, and produce in-depth research reports.</div>",
    unsafe_allow_html=True
)

tab1, tab2 = st.tabs(["🚀 New Research", "📂 Past Reports Archive"])

with tab1:
    col1, col2 = st.columns([3, 1])
    with col1:
        topic_input = st.text_input(
            "What topic do you want to research?",
            placeholder="e.g. Next-Generation Multimodal AI Agents in 2026, Quantum Computing breakthroughs, Autonomous Drones...",
        )
    with col2:
        st.write("")
        st.write("")
        start_btn = st.button("🚀 Start Autonomous Research", type="primary", use_container_width=True)

    if start_btn:
        if not topic_input.strip():
            st.warning("⚠️ Please enter a research topic to proceed.")
        elif provider != "Ollama (Local)" and not api_key.strip():
            st.error(f"⚠️ Please enter your {provider} API key in the sidebar.")
        else:
            with st.spinner(f"🤖 Autonomous Crew running using `{model_name}`! Agents are searching the web, auditing data, and composing your report..."):
                try:
                    crew = ResearchCrew(model_name=model_name, api_key=api_key)
                    result = crew.run(topic=topic_input)

                    st.success("✅ Research Report successfully generated!")
                    
                    st.download_button(
                        label="📥 Download Full Report (Markdown)",
                        data=result["report"],
                        file_name=Path(result["output_path"]).name,
                        mime="text/markdown",
                    )

                    st.markdown("---")
                    st.markdown(result["report"])

                except Exception as e:
                    st.error(f"❌ Execution failed: {str(e)}")

with tab2:
    st.subheader("Saved Research Reports")
    outputs_dir = ROOT_DIR / "outputs"
    if outputs_dir.exists():
        files = sorted(list(outputs_dir.glob("*.md")), key=os.path.getmtime, reverse=True)
        if files:
            selected_file = st.selectbox(
                "Select a report to view:",
                options=files,
                format_func=lambda x: x.name
            )
            if selected_file:
                with open(selected_file, "r", encoding="utf-8") as f:
                    content = f.read()

                st.download_button(
                    label=f"📥 Download {selected_file.name}",
                    data=content,
                    file_name=selected_file.name,
                    mime="text/markdown"
                )
                st.markdown("---")
                st.markdown(content)
        else:
            st.info("No research reports generated yet. Run your first research topic in the tab above!")
    else:
        st.info("Outputs directory will be created once your first report is generated.")
