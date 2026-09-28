import os
import sys
import requests
from pathlib import Path
from datetime import datetime

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

# Configure LiteLLM and CrewAI to drop unsupported params (like cache_breakpoint) for Groq
try:
    import litellm
    litellm.drop_params = True
except Exception:
    pass

try:
    import crewai.llms.cache
    crewai.llms.cache.mark_cache_breakpoint = lambda msg: msg
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

# Ultra-Modern CSS Styling
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
        max-width: 850px;
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

    /* Suggestion Chips Button Styling */
    div[data-testid="column"] div.stButton > button {
        background: rgba(30, 41, 59, 0.7) !important;
        border: 1px solid rgba(168, 85, 247, 0.3) !important;
        color: #e2e8f0 !important;
        font-size: 0.84rem !important;
        font-weight: 500 !important;
        padding: 0.45rem 0.8rem !important;
        border-radius: 10px !important;
        box-shadow: none !important;
    }

    div[data-testid="column"] div.stButton > button:hover {
        background: linear-gradient(135deg, rgba(99, 102, 241, 0.3), rgba(168, 85, 247, 0.3)) !important;
        border-color: #a855f7 !important;
        color: #ffffff !important;
        transform: translateY(-1px) !important;
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

    .model-info-box {
        background: rgba(99, 102, 241, 0.1);
        border: 1px solid rgba(99, 102, 241, 0.25);
        border-radius: 8px;
        padding: 8px 12px;
        margin-top: 8px;
        font-size: 0.8rem;
        color: #c7d2fe;
    }
</style>
""", unsafe_allow_html=True)

# ----------------- LIVE MODEL DETECTORS -----------------
def get_live_groq_models(api_key: str):
    """Fetch live list of models authorized for this Groq API Key."""
    if not api_key.strip():
        return False, "Please enter your Groq API key first."
    try:
        r = requests.get(
            "https://api.groq.com/openai/v1/models",
            headers={"Authorization": f"Bearer {api_key.strip()}"},
            timeout=6
        )
        if r.status_code == 200:
            data = r.json().get("data", [])
            ids = [m["id"] for m in data if "whisper" not in m["id"].lower()]
            return True, ids
        else:
            err = r.json().get("error", {}).get("message", f"HTTP {r.status_code}")
            return False, err
    except Exception as e:
        return False, str(e)


def get_live_gemini_models(api_key: str):
    """Fetch live list of models authorized for this Gemini API Key."""
    if not api_key.strip():
        return False, "Please enter your Gemini API key first."
    try:
        url = f"https://generativelanguage.googleapis.com/v1beta/models?key={api_key.strip()}"
        r = requests.get(url, timeout=6)
        if r.status_code == 200:
            data = r.json().get("models", [])
            ids = [m["name"].replace("models/", "") for m in data if "generateContent" in m.get("supportedGenerationMethods", [])]
            return True, ids
        else:
            err = r.json().get("error", {}).get("message", f"HTTP {r.status_code}")
            return False, err
    except Exception as e:
        return False, str(e)


# Default Fallback Catalog
MODELS_CATALOG = {
    "Groq": [
        {"id": "groq/llama-3.1-8b-instant", "name": "Llama 3.1 8B Instant", "tag": "100% Free Tier Active", "desc": "Fast execution, verified active on free Groq tier."},
        {"id": "groq/llama-3.3-70b-versatile", "name": "Llama 3.3 70B Versatile", "tag": "General Intelligence", "desc": "Research summaries, structured writing."},
        {"id": "groq/openai/gpt-oss-20b", "name": "GPT-OSS 20B", "tag": "Fast inference (~1,000 tok/s)", "desc": "High-volume research extraction."},
        {"id": "groq/openai/gpt-oss-120b", "name": "GPT-OSS 120B", "tag": "Fast + Strong reasoning", "desc": "Tool-using research, fact-checker."},
    ],
    "Google Gemini": [
        {"id": "gemini/gemini-2.0-flash", "name": "Gemini 2.0 Flash", "tag": "Fast & Reliable (Recommended)", "desc": "Fast production responses, robust general research."},
        {"id": "gemini/gemini-1.5-flash", "name": "Gemini 1.5 Flash", "tag": "High Rate Limits", "desc": "Generous free tier token allowance."},
        {"id": "gemini/gemini-3.8-flash", "name": "Gemini 3.8 Flash", "tag": "Agentic Engineering", "desc": "Autonomous workflows, long-horizon coding."},
        {"id": "gemini/gemini-2.5-pro", "name": "Gemini 2.5 Pro", "tag": "Deep reasoning", "desc": "Complex multimodal reasoning."},
    ],
    "OpenAI": [
        {"id": "openai/gpt-4o-mini", "name": "GPT-4o mini", "tag": "Everyday Efficient", "desc": "Balanced cost and quality."},
        {"id": "openai/gpt-5-mini", "name": "GPT-5 mini", "tag": "Fast reasoning", "desc": "Structured outputs, cost-efficient worker."},
        {"id": "openai/gpt-5", "name": "GPT-5", "tag": "Deep reasoning", "desc": "Planner, fact-checker, technical writer."},
    ],
    "DeepSeek": [
        {"id": "deepseek/deepseek-chat", "name": "DeepSeek Chat", "tag": "Conversational Agent", "desc": "Standard balanced reasoning."},
        {"id": "deepseek/deepseek-flash", "name": "DeepSeek V4.1 Flash", "tag": "Economical Long-Context", "desc": "Web-research workers, extraction."},
    ],
}

# ----------------- SIDEBAR -----------------
with st.sidebar:
    st.markdown("""
        <div style='display: flex; align-items: center; gap: 10px; margin-bottom: 10px;'>
            <span style='font-size: 2rem;'>🤖</span>
            <div>
                <h3 style='margin: 0; font-size: 1.25rem; font-weight: 700;'>Nexus AI</h3>
                <span style='font-size: 0.75rem; color: #94a3b8; text-transform: uppercase;'>Multi-Agent Engine</span>
            </div>
        </div>
    """, unsafe_allow_html=True)

    st.markdown("<div class='sidebar-status'>🟢 Multi-Agent Crew Online</div>", unsafe_allow_html=True)
    st.markdown("### ⚙️ Engine Settings")

    provider = st.selectbox(
        "Select Provider",
        ["Groq", "Google Gemini", "OpenAI", "DeepSeek", "Ollama (Local)"],
        index=0
    )

    if provider == "Groq":
        env_key = os.getenv("GROQ_API_KEY", "")
        api_key = st.text_input("Groq API Key (gsk_...)", value=env_key, type="password")
        st.caption("🔗 [Get Free Groq API Key](https://console.groq.com/keys)")

        # Verify Key Button
        if st.button("🔍 Check Key & Load My Account Models", use_container_width=True):
            with st.spinner("Connecting to Groq API..."):
                ok, res = get_live_groq_models(api_key)
                if ok:
                    st.session_state["groq_live_models"] = res
                    st.success(f"✅ Key Verified! Found {len(res)} models authorized for your account.")
                else:
                    st.error(f"❌ Key Verification Failed: {res}")

        # Populate model dropdown
        if "groq_live_models" in st.session_state and st.session_state["groq_live_models"]:
            live_models = st.session_state["groq_live_models"]
            selected_live = st.selectbox("Active Models on Your Account", live_models, index=0)
            model_name = f"groq/{selected_live}"
            model_desc = f"Verified active on your Groq key."
        else:
            catalog = MODELS_CATALOG["Groq"]
            options = [f"{m['name']} ({m['tag']})" for m in catalog] + ["Custom Model ID..."]
            selected_opt = st.selectbox("Select Model", options, index=0)
            if "Custom Model" in selected_opt:
                model_name = st.text_input("Enter exact Groq Model ID", value="groq/llama-3.1-8b-instant")
                model_desc = "Custom user-specified model identifier."
            else:
                idx = options.index(selected_opt)
                model_name = catalog[idx]["id"]
                model_desc = catalog[idx]["desc"]

        st.markdown(f"<div class='model-info-box'>💡 <b>Selected Model:</b> <code>{model_name}</code><br>{model_desc}</div>", unsafe_allow_html=True)

    elif provider == "Google Gemini":
        env_key = os.getenv("GEMINI_API_KEY", "")
        api_key = st.text_input("Gemini API Key (AIzaSy...)", value=env_key, type="password")
        st.caption("🔗 [Get Free Gemini API Key](https://aistudio.google.com/app/apikey)")

        if st.button("🔍 Check Key & Load Gemini Models", use_container_width=True):
            with st.spinner("Connecting to Gemini API..."):
                ok, res = get_live_gemini_models(api_key)
                if ok:
                    st.session_state["gemini_live_models"] = res
                    st.success(f"✅ Connected! Found {len(res)} Gemini models.")
                else:
                    st.error(f"❌ Verification Failed: {res}")

        if "gemini_live_models" in st.session_state and st.session_state["gemini_live_models"]:
            live_models = st.session_state["gemini_live_models"]
            selected_live = st.selectbox("Active Models on Your Key", live_models, index=0)
            model_name = f"gemini/{selected_live}"
            model_desc = "Verified active on your Gemini key."
        else:
            catalog = MODELS_CATALOG["Google Gemini"]
            options = [f"{m['name']} ({m['tag']})" for m in catalog] + ["Custom Model ID..."]
            selected_opt = st.selectbox("Select Model", options, index=0)
            if "Custom Model" in selected_opt:
                model_name = st.text_input("Enter exact Gemini Model ID", value="gemini/gemini-2.0-flash")
                model_desc = "Custom user-specified model identifier."
            else:
                idx = options.index(selected_opt)
                model_name = catalog[idx]["id"]
                model_desc = catalog[idx]["desc"]

        st.markdown(f"<div class='model-info-box'>💡 <b>Selected Model:</b> <code>{model_name}</code><br>{model_desc}</div>", unsafe_allow_html=True)

    elif provider == "OpenAI":
        env_key = os.getenv("OPENAI_API_KEY", "")
        api_key = st.text_input("OpenAI API Key (sk-...)", value=env_key, type="password")
        catalog = MODELS_CATALOG["OpenAI"]
        options = [f"{m['name']} ({m['tag']})" for m in catalog] + ["Custom Model ID..."]
        selected_opt = st.selectbox("Select Model", options, index=0)
        idx = options.index(selected_opt)
        model_name = st.text_input("Enter Model ID", value="openai/gpt-4o-mini") if "Custom" in selected_opt else catalog[idx]["id"]
        model_desc = catalog[idx]["desc"] if "Custom" not in selected_opt else "Custom model."
        st.markdown(f"<div class='model-info-box'>💡 <code>{model_name}</code><br>{model_desc}</div>", unsafe_allow_html=True)

    elif provider == "DeepSeek":
        env_key = os.getenv("DEEPSEEK_API_KEY", "")
        api_key = st.text_input("DeepSeek API Key (sk-...)", value=env_key, type="password")
        catalog = MODELS_CATALOG["DeepSeek"]
        options = [f"{m['name']} ({m['tag']})" for m in catalog] + ["Custom Model ID..."]
        selected_opt = st.selectbox("Select Model", options, index=0)
        idx = options.index(selected_opt)
        model_name = st.text_input("Enter Model ID", value="deepseek/deepseek-chat") if "Custom" in selected_opt else catalog[idx]["id"]
        model_desc = catalog[idx]["desc"] if "Custom" not in selected_opt else "Custom model."
        st.markdown(f"<div class='model-info-box'>💡 <code>{model_name}</code><br>{model_desc}</div>", unsafe_allow_html=True)

    else:  # Ollama Local
        api_key = "ollama"
        model_name = st.text_input("Ollama Model Name", value="ollama/llama3.2")
        st.markdown("<div class='model-info-box'>💡 Running on local Ollama server (http://localhost:11434).</div>", unsafe_allow_html=True)

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

# State callback for the 4 suggestion chips
def set_topic_callback(topic_text: str):
    st.session_state["main_topic_input"] = topic_text

with tab1:
    st.markdown("#### 🎯 Enter Your Research Subject")

    # Initialize session state for topic if not present
    if "main_topic_input" not in st.session_state:
        st.session_state["main_topic_input"] = "Modern Agritech & Genetic Innovations in Potato Cultivation"

    # Main text input bound to session state
    topic_input = st.text_input(
        label="Research Topic",
        key="main_topic_input",
        placeholder="e.g. Modern Agritech & Genetic Innovations in Potato, Autonomous Multi-Agent AI Frameworks in 2026...",
        label_visibility="collapsed",
    )

    # Quick Suggestion Chips with working callbacks
    st.markdown("<span style='font-size: 0.85rem; color: #94a3b8;'>💡 Quick Suggestions (Click any button to fill):</span>", unsafe_allow_html=True)
    chip_col1, chip_col2, chip_col3, chip_col4 = st.columns(4)
    with chip_col1:
        st.button(
            "🥔 Potato Agritech & Genetics",
            key="chip_potato_btn",
            on_click=set_topic_callback,
            args=("Modern Agritech & Genetic Innovations in Potato Cultivation",),
            use_container_width=True
        )
    with chip_col2:
        st.button(
            "🤖 Autonomous AI Agents 2026",
            key="chip_agents_btn",
            on_click=set_topic_callback,
            args=("Autonomous Multi-Agent AI Frameworks and Future Trends in 2026",),
            use_container_width=True
        )
    with chip_col3:
        st.button(
            "⚛️ Quantum Computing",
            key="chip_quantum_btn",
            on_click=set_topic_callback,
            args=("Quantum Computing Breakthroughs and Commercial Readiness",),
            use_container_width=True
        )
    with chip_col4:
        st.button(
            "🧬 CRISPR Therapeutics",
            key="chip_crispr_btn",
            on_click=set_topic_callback,
            args=("CRISPR-Cas9 Clinical Trials and Gene Editing Therapeutics",),
            use_container_width=True
        )

    st.write("")
    run_btn = st.button("🚀 Start Autonomous Research", type="primary", use_container_width=True)

    if run_btn:
        active_topic = topic_input.strip()
        if not active_topic:
            st.warning("⚠️ Please provide a research topic to proceed.")
        elif provider != "Ollama (Local)" and not api_key.strip():
            st.error(f"⚠️ Please enter your {provider} API key in the sidebar.")
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
