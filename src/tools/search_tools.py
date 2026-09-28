import os
import requests
from bs4 import BeautifulSoup
from crewai.tools import tool
from ddgs import DDGS
import wikipedia

@tool("DuckDuckGo Web Search")
def ddg_search(query: str) -> str:
    """
    Search the live web using DuckDuckGo for latest news, facts, papers, and information.
    Input should be a targeted search query string.
    Returns a formatted summary of top search results including title, snippet, and URL.
    """
    try:
        ddgs = DDGS()
        results = list(ddgs.text(query, max_results=5))
        if not results:
            return f"No results found for query: '{query}'."

        formatted_output = []
        for i, item in enumerate(results, 1):
            title = item.get("title", "No Title")
            snippet = item.get("body", "No description")
            url = item.get("href", "")
            formatted_output.append(f"Result {i}:\nTitle: {title}\nSnippet: {snippet}\nURL: {url}\n")

        return "\n".join(formatted_output)
    except Exception as e:
        return f"Error during web search: {str(e)}"


@tool("Wikipedia Search")
def wikipedia_search(query: str) -> str:
    """
    Search Wikipedia for comprehensive encyclopedia articles and background definitions.
    Input should be a topic or concept name.
    """
    try:
        wikipedia.set_lang("en")
        search_results = wikipedia.search(query, results=3)
        if not search_results:
            return f"No Wikipedia pages found for: '{query}'."

        page_title = search_results[0]
        page = wikipedia.page(page_title, auto_suggest=False)
        summary = wikipedia.summary(page_title, sentences=5, auto_suggest=False)

        return (
            f"Wikipedia Article: {page.title}\n"
            f"URL: {page.url}\n\n"
            f"Summary:\n{summary}"
        )
    except Exception as e:
        return f"Error retrieving Wikipedia article: {str(e)}"


@tool("Webpage Reader and Scraper")
def scrape_webpage(url: str) -> str:
    """
    Fetch and read readable textual content from a specific web URL.
    Useful when you need full article context from a search result link.
    """
    try:
        headers = {
            "User-Agent": (
                "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/118.0.0.0 Safari/537.36"
            )
        }
        resp = requests.get(url, headers=headers, timeout=10)
        resp.raise_for_status()

        soup = BeautifulSoup(resp.text, "html.parser")
        # Remove script and style elements
        for element in soup(["script", "style", "nav", "footer", "header", "aside"]):
            element.extract()

        text = soup.get_text(separator=" ", strip=True)
        # Limit to 3000 chars to avoid prompt bloat
        return text[:3000] if len(text) > 3000 else text
    except Exception as e:
        return f"Error reading webpage {url}: {str(e)}"


def get_research_tools():
    """
    Returns the list of enabled research tools.
    Includes SerperDevTool if SERPER_API_KEY is configured.
    """
    tools = [ddg_search, wikipedia_search, scrape_webpage]

    if os.getenv("SERPER_API_KEY"):
        try:
            from crewai_tools import SerperDevTool
            tools.append(SerperDevTool())
        except Exception:
            pass

    return tools
