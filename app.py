import os
import sys
from pathlib import Path
from datetime import datetime

# Prevent Windows charmap encoding crashes on emoji prints
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

import streamlit as st
from dotenv import load_dotenv

ROOT_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT_DIR))

load_dotenv(dotenv_path=ROOT_DIR / ".env")

from src.crew import ResearchCrew

# Page configuration
st.set_page_config(
    page_title="NexusAI | Multi-Agent Research Assistant",
    page_icon="🤖",
    layout="wide",
    initial_sidebar_state="expanded",
)

# Ultra-Modern Premium CSS (Glassmorphism, Neon Gradients, Polished Buttons & Cards)
st.markdown("""
<style>
    @import url('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@300;400;500;600;700;800&family=JetBrains+Mono:wght@400;500&display=swap');

    * {
        font-family: 'Plus Jakarta Sans', sans-serif;
    }

    /* Hero Gradient Title */
    .hero-badge {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        background: linear-gradient(135deg, rgba(99, 102, 241, 0.15), rgba(168, 85, 247, 0.15));
        border: 1px solid rgba(168, 85, 247, 0.35);
        color: #c084fc;
        padding: 5px 14px;
        border-radius: 9999px;
        font-size: 0.82rem;
        font-weight: 600;
        letter-spacing: 0.5px;
        text-transform: uppercase;
        margin-bottom: 12px;
    }

    .hero-title {
        font-size: 2.7rem;
        font-weight: 800;
        letter-spacing: -0.025em;
        background: linear-gradient(135deg, #60a5fa 0%, #a855f7 50%, #f43f5e 100%);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
        margin-bottom: 8px;
        line-height: 1.2;
    }

    .hero-subtitle {
        font-size: 1.05rem;
        color: #94a3b8;
        max-width: 800px;
        line-height: 1.6;
        margin-bottom: 24px;
    }

    /* Agent Cards Container */
    .agent-grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
        gap: 16px;
        margin-bottom: 28px;
    }

    .agent-card {
        background: rgba(22, 27, 34, 0.7);
        backdrop-filter: blur(12px);
        border: 1px solid rgba(255, 255, 255, 0.08);
        border-radius: 14px;
        padding: 18px 20px;
        transition: all 0.3s cubic-bezier(0.4, 0, 0.2, 1);
        position: relative;
        overflow: hidden;
    }

    .agent-card::before {
        content: '';
        position: absolute;
        top: 0;
        left: 0;
        right: 0;
        height: 3px;
    }

    .agent-card-1::before { background: linear-gradient(90deg, #38bdf8, #3b82f6); }
    .agent-card-2::before { background: linear-gradient(90deg, #f59e0b, #ef4444); }
    .agent-card-3::before { background: linear-gradient(90deg, #10b981, #06b6d4); }

    .agent-card:hover {
        transform: translateY(-3px);
        border-color: rgba(168, 85, 247, 0.4);
        box-shadow: 0 12px 24px -10px rgba(0, 0, 0, 0.5);
    }

    .agent-icon {
        font-size: 1.8rem;
        margin-bottom: 8px;
    }

    .agent-name {
        font-size: 1.02rem;
        font-weight: 700;
        color: #f1f5f9;
        margin-bottom: 4px;
    }

    .agent-role {
        font-size: 0.8rem;
        color: #a855f7;
        font-weight: 600;
        text-transform: uppercase;
        letter-spacing: 0.5px;
        margin-bottom: 8px;
    }

    .agent-desc {
        font-size: 0.85rem;
        color: #94a3b8;
        line-height: 1.45;
    }

    /* Premium Button Styling */
    div.stButton > button {
        background: linear-gradient(135deg, #6366f1 0%, #a855f7 50%, #ec4899 100%) !important;
        color: #ffffff !important;
        border: none !important;
        border-radius: 12px !important;
        font-weight: 700 !important;
        font-size: 1.02rem !important;
        padding: 0.65rem 1.6rem !important;
        box-shadow: 0 8px 20px -6px rgba(168, 85, 247, 0.5) !important;
        transition: all 0.25s ease-in-out !important;
        letter-spacing: 0.3px !important;
    }

    div.stButton > button:hover {
        transform: translateY(-2px) scale(1.02) !important;
        box-shadow: 0 12px 28px -6px rgba(236, 72, 153, 0.6) !important;
        color: #ffffff !important;
    }

    /* Download Button */
    div.stDownloadButton > button {
        background: linear-gradient(135deg, #059669 0%, #10b981 100%) !important;
        color: #ffffff !important;
        border: none !important;
        border-radius: 10px !important;
        font-weight: 600 !important;
        padding: 0.55rem 1.4rem !important;
        box-shadow: 0 6px 16px -4px rgba(16, 185, 129, 0.4) !important;
        transition: all 0.2s ease !important;
    }

    div.stDownloadButton > button:hover {
        transform: translateY(-1px) !important;
        box-shadow: 0 10px 22px -4px rgba(16, 185, 129, 0.6) !important;
    }

    /* Stat Badges */
    .stats-container {
        display: flex;
        gap: 14px;
        flex-wrap: wrap;
        margin: 18px 0;
        padding: 12px 18px;
        background: rgba(30, 41, 59, 0.5);
        border: 1px solid rgba(255, 255, 255, 0.06);
        border-radius: 10px;
    }

    .stat-badge {
        display: flex;
        align-items: center;
        gap: 6px;
        font-size: 0.85rem;
        color: #cbd5e1;
    }

    .stat-value {
        font-weight: 700;
        color: #38bdf8;
    }

    /* Report Content Container */
    .report-wrapper {
        background: rgba(15, 23, 42, 0.65);
        border: 1px solid rgba(255, 255, 255, 0.08);
        border-radius: 16px;
        padding: 32px 36px;
        margin-top: 20px;
        box-shadow: 0 20px 40px -15px rgba(0, 0, 0, 0.5);
    }

    /* Sidebar Clean styling */
    .sidebar-status {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 8px 12px;
        background: rgba(16, 185, 129, 0.12);
        border: 1px solid rgba(16, 185, 129, 0.25);
        border-radius: 8px;
        color: #34d399;
        font-size: 0.85rem;
        font-weight: 600;
        margin-bottom: 16px;
    }
</style>
""", unsafe_allow_html=True)

# ----------------- SIDEBAR CONFIGURATION -----------------
with st.sidebar:
    st.markdown("""
        <div style='display: flex; align-items: center; gap: 10px; margin-bottom: 10px;'>
            <span style='font-size: 2rem;'>🤖</span>
            <div>
                <h3 style='margin: 0; font-size: 1.25rem; font-weight: 700;'>Nexus AI</h3>
                <span style='font-size: 0.75rem; color: #94a3b8; text-transform: uppercase;'>Agentic Engine v2.0</span>
            </div>
        </div>
    """, unsafe_allow_html=True)

    st.markdown("<div class='sidebar-status'>🟢 Multi-Agent Crew Online</div>", unsafe_allow_html=True)
    st.markdown("### ⚙️ Engine Settings")

    provider = st.selectbox(
        "Select LLM Provider",
        ["Groq (Ultra-Fast ⚡)", "Google Gemini (Recommended 🌟)", "OpenAI", "DeepSeek", "Ollama (Local)"],
        index=0
    )

    if "Groq" in provider:
        env_key = os.getenv("GROQ_API_KEY", "")
        api_key = st.text_input("Groq API Key (gsk_...)", value=env_key, type="password", help="Get a free key from console.groq.com")
        st.caption("🔗 [Get Free Groq API Key](https://console.groq.com/keys)")
        model_selection = st.selectbox(
            "Model",
            [
                "groq/llama-3.3-70b-versatile (Smartest & Fast)",
                "groq/llama-3.1-8b-instant (Fastest & Free Limits)",
                "groq/gemma2-9b-it",
                "groq/mixtral-8x7b-32768",
                "Custom Model..."
            ],
            index=0
        )
        model_name = st.text_input("Enter Groq Model ID", value="groq/llama-3.3-70b-versatile") if "Custom" in model_selection else model_selection.split(" ")[0]

    elif "Gemini" in provider:
        env_key = os.getenv("GEMINI_API_KEY", "")
        api_key = st.text_input("Gemini API Key (AIzaSy...)", value=env_key, type="password", help="Get key from aistudio.google.com")
        st.caption("🔗 [Get Free Gemini API Key](https://aistudio.google.com/app/apikey)")
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
        model_name = st.text_input("Enter Gemini Model ID", value="gemini/gemini-2.0-flash") if "Custom" in model_selection else model_selection.split(" ")[0]

    elif "OpenAI" in provider:
        env_key = os.getenv("OPENAI_API_KEY", "")
        api_key = st.text_input("OpenAI API Key (sk-...)", value=env_key, type="password")
        model_selection = st.selectbox(
            "Model",
            ["gpt-4o-mini (Recommended)", "gpt-4o", "Custom Model..."],
            index=0
        )
        model_name = st.text_input("Enter OpenAI Model ID", value="gpt-4o-mini") if "Custom" in model_selection else model_selection.split(" ")[0]

    elif "DeepSeek" in provider:
        env_key = os.getenv("DEEPSEEK_API_KEY", "")
        api_key = st.text_input("DeepSeek API Key (sk-...)", value=env_key, type="password")
        model_selection = st.selectbox(
            "Model",
            ["deepseek/deepseek-chat", "deepseek/deepseek-reasoner", "Custom Model..."],
            index=0
        )
        model_name = st.text_input("Enter DeepSeek Model ID", value="deepseek/deepseek-chat") if "Custom" in model_selection else model_selection.split(" ")[0]

    else:  # Ollama Local
        api_key = "ollama"
        model_name = st.text_input("Ollama Model Name", value="ollama/llama3.2")

    st.markdown("---")
    st.markdown("### 🛠️ Active Toolchain")
    st.markdown("""
    - 🦆 **DuckDuckGo Live Search** *(Zero Config)*
    - 📚 **Wikipedia Intelligence Engine**
    - 🌐 **Web Content Scraper**
    - 📑 **Publication Markdown Formatter**
    """)


# ----------------- MAIN INTERFACE -----------------
st.markdown("<div class='hero-badge'>⚡ Next-Gen Agentic AI Architecture</div>", unsafe_allow_html=True)
st.markdown("<div class='hero-title'>Multi-Agent Research Assistant</div>", unsafe_allow_html=True)
st.markdown(
    "<div class='hero-subtitle'>Harness an autonomous collaborative crew of AI agents powered by <b>CrewAI</b>. "
    "From deep web intelligence to rigorous fact-auditing and publication-grade reports — completely automated.</div>",
    unsafe_allow_html=True
)

# Agent Cards Showcase
st.markdown("""
<div class='agent-grid'>
    <div class='agent-card agent-card-1'>
        <div class='agent-icon'>🔍</div>
        <div class='agent-name'>Senior Research Analyst</div>
        <div class='agent-role'>Agent 01 • Discovery</div>
        <div class='agent-desc'>Scours real-time web, Wikipedia, and whitepapers to extract core factual data, statistics, and sources.</div>
    </div>
    <div class='agent-card agent-card-2'>
        <div class='agent-icon'>⚖️</div>
        <div class='agent-name'>Critical Fact-Checker</div>
        <div class='agent-role'>Agent 02 • Audit & Synthesis</div>
        <div class='agent-desc'>Cross-validates claims, filters marketing hype & hallucinations, and verifies conflicting data.</div>
    </div>
    <div class='agent-card agent-card-3'>
        <div class='agent-icon'>📝</div>
        <div class='agent-name'>Executive Report Writer</div>
        <div class='agent-role'>Agent 03 • Authoring</div>
        <div class='agent-desc'>Transforms synthesized intelligence into an executive-level, structured Markdown research paper.</div>
    </div>
</div>
""", unsafe_allow_html=True)

tab1, tab2 = st.tabs(["🚀 Launch Research", "📂 Past Reports Archive"])

with tab1:
    st.markdown("#### 🎯 Enter Your Research Subject")
    
    # Topic Input
    topic_input = st.text_input(
        label="Research Topic",
        placeholder="e.g. Next-Generation Multimodal AI Agents in 2026, Agricultural Biotechnology of Potato, Quantum Computing...",
        label_visibility="collapsed",
        key="main_topic_input"
    )

    # Quick Suggestion Chips
    st.markdown("<span style='font-size: 0.85rem; color: #94a3b8;'>💡 Quick Suggestions:</span>", unsafe_allow_html=True)
    chip_col1, chip_col2, chip_col3, chip_col4 = st.columns(4)
    with chip_col1:
        if st.button("🥔 Potato Agritech & Genetics", use_container_width=True):
            st.session_state["topic_val"] = "Modern Agritech & Genetic Innovations in Potato Cultivation"
            st.rerun()
    with chip_col2:
        if st.button("🤖 Autonomous AI Agents 2026", use_container_width=True):
            st.session_state["topic_val"] = "Autonomous Multi-Agent AI Frameworks and Future Trends in 2026"
            st.rerun()
    with chip_col3:
        if st.button("⚛️ Quantum Computing", use_container_width=True):
            st.session_state["topic_val"] = "Quantum Computing Breakthroughs and Commercial Readiness"
            st.rerun()
    with chip_col4:
        if st.button("🧬 CRISPR Therapeutics", use_container_width=True):
            st.session_state["topic_val"] = "CRISPR-Cas9 Clinical Trials and Gene Editing Therapeutics"
            st.rerun()

    # If chip clicked, update
    if "topic_val" in st.session_state:
        topic_input = st.session_state.pop("topic_val")

    st.write("")
    run_btn = st.button("🚀 Start Autonomous Research", type="primary", use_container_width=True)

    if run_btn:
        active_topic = topic_input.strip()
        if not active_topic:
            st.warning("⚠️ Please provide a research topic to proceed.")
        elif provider != "Ollama (Local)" and not api_key.strip():
            st.error(f"⚠️ Please enter your {provider.split(' ')[0]} API key in the sidebar.")
        else:
            status_box = st.status(
                f"🤖 Initializing Crew with `{model_name}`...",
                expanded=True
            )
            with status_box:
                st.write("🔍 **Phase 1:** Senior Analyst is searching the web, Wikipedia, and extracting intelligence...")
                try:
                    crew = ResearchCrew(model_name=model_name, api_key=api_key)
                    result = crew.run(topic=active_topic)

                    st.write("⚖️ **Phase 2:** Critical Fact-Checker has audited claims and filtered hallucinations...")
                    st.write("📝 **Phase 3:** Executive Writer has formatted the comprehensive research report...")
                    status_box.update(label="✅ Research Mission Complete!", state="complete", expanded=False)

                    st.balloons()
                    
                    report_text = result["report"]
                    word_count = len(report_text.split())
                    char_count = len(report_text)
                    read_time = max(1, round(word_count / 200))

                    # Metrics Bar
                    st.markdown(f"""
                    <div class='stats-container'>
                        <div class='stat-badge'>📄 Words: <span class='stat-value'>{word_count:,}</span></div>
                        <div class='stat-badge'>⏱️ Reading Time: <span class='stat-value'>~{read_time} min</span></div>
                        <div class='stat-badge'>🧠 Model: <span class='stat-value'>{model_name}</span></div>
                        <div class='stat-badge'>📅 Generated: <span class='stat-value'>{datetime.now().strftime('%Y-%m-%d %H:%M')}</span></div>
                    </div>
                    """, unsafe_allow_html=True)

                    # Download Action
                    st.download_button(
                        label="📥 Download Full Research Report (.md)",
                        data=report_text,
                        file_name=Path(result["output_path"]).name,
                        mime="text/markdown",
                        use_container_width=True,
                    )

                    # Render Report
                    st.markdown("<div class='report-wrapper'>", unsafe_allow_html=True)
                    st.markdown(report_text)
                    st.markdown("</div>", unsafe_allow_html=True)

                except Exception as e:
                    status_box.update(label="❌ Research Failed", state="error", expanded=True)
                    st.error(f"Execution Error: {str(e)}")

with tab2:
    st.markdown("#### 📂 Generated Reports Archive")
    outputs_dir = ROOT_DIR / "outputs"
    if outputs_dir.exists():
        files = sorted(list(outputs_dir.glob("*.md")), key=os.path.getmtime, reverse=True)
        if files:
            selected_file = st.selectbox(
                "Select a report from the archive:",
                options=files,
                format_func=lambda x: f"📄 {x.name} ({round(x.stat().st_size/1024, 1)} KB)"
            )
            if selected_file:
                with open(selected_file, "r", encoding="utf-8", errors="replace") as f:
                    content = f.read()

                st.download_button(
                    label=f"📥 Download {selected_file.name}",
                    data=content,
                    file_name=selected_file.name,
                    mime="text/markdown"
                )
                st.markdown("<div class='report-wrapper'>", unsafe_allow_html=True)
                st.markdown(content)
                st.markdown("</div>", unsafe_allow_html=True)
        else:
            st.info("No research reports in archive yet. Run your first research topic in the tab above!")
    else:
        st.info("No archive found.")
