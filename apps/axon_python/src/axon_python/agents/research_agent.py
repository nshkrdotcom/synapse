"""
Example research agent implementation using pydantic-ai.
Demonstrates tool chaining, streaming responses, and complex structured output.
"""
from datetime import datetime
from typing import Dict, List, Optional, Union

from pydantic import BaseModel, Field
from pydantic_ai import Agent

# Models for structured output
class Source(BaseModel):
    """Information about a source."""
    title: str = Field(description="Title of the source")
    url: Optional[str] = Field(None, description="URL if available")
    date: Optional[datetime] = Field(None, description="Publication date if available")
    relevance_score: float = Field(
        description="How relevant this source is to the query",
        ge=0.0,
        le=1.0
    )

class Fact(BaseModel):
    """A single fact with its sources."""
    statement: str = Field(description="The factual statement")
    confidence: float = Field(
        description="Confidence in the fact's accuracy",
        ge=0.0,
        le=1.0
    )
    sources: List[Source] = Field(description="Sources supporting this fact")

class ResearchResult(BaseModel):
    """Complete research results."""
    summary: str = Field(description="Brief summary of findings")
    facts: List[Fact] = Field(description="List of discovered facts")
    sources: List[Source] = Field(description="All sources consulted")
    limitations: Optional[List[str]] = Field(
        None,
        description="Any limitations or caveats about the research"
    )

# Tool implementations
async def search_academic(query: str) -> List[Dict]:
    """
    Searches academic sources.
    In a real implementation, this would use an academic API like Semantic Scholar.
    """
    # Mock implementation
    return [{
        "title": f"Academic paper about {query}",
        "url": f"https://example.com/papers/{query.lower().replace(' ', '-')}",
        "date": "2024-01-01T00:00:00Z",
        "abstract": f"This paper discusses {query} in detail..."
    }]

async def search_news(query: str, days: int = 30) -> List[Dict]:
    """
    Searches recent news articles.
    In a real implementation, this would use a news API.
    """
    # Mock implementation
    return [{
        "title": f"Recent news about {query}",
        "url": f"https://example.com/news/{query.lower().replace(' ', '-')}",
        "date": "2024-01-01T00:00:00Z",
        "summary": f"Latest developments in {query}..."
    }]

async def fetch_webpage(url: str) -> str:
    """
    Fetches and extracts text from a webpage.
    In a real implementation, this would use proper web scraping.
    """
    # Mock implementation
    return f"Content from {url}..."

async def validate_fact(statement: str, context: str) -> Dict:
    """
    Validates a factual statement against provided context.
    In a real implementation, this would use more sophisticated fact checking.
    """
    # Mock implementation
    return {
        "is_supported": True,
        "confidence": 0.85,
        "evidence": f"Found supporting evidence in context: {context[:100]}..."
    }

# Create the agent
research_agent = Agent(
    "gemini-1.5-pro",
    system_prompt="""You are a thorough research assistant.
    Your task is to investigate topics deeply, finding and validating information
    from multiple sources. Always cite your sources and maintain academic rigor.
    Be transparent about limitations and uncertainties in your findings.""",
    tools=[
        {
            "name": "search_academic",
            "description": "Searches academic papers and publications",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string"}
                },
                "required": ["query"]
            },
            "handler": search_academic
        },
        {
            "name": "search_news",
            "description": "Searches recent news articles",
            "parameters": {
                "type": "object",
                "properties": {
                    "query": {"type": "string"},
                    "days": {"type": "integer", "default": 30}
                },
                "required": ["query"]
            },
            "handler": search_news
        },
        {
            "name": "fetch_webpage",
            "description": "Fetches and extracts text from a webpage",
            "parameters": {
                "type": "object",
                "properties": {
                    "url": {"type": "string"}
                },
                "required": ["url"]
            },
            "handler": fetch_webpage
        },
        {
            "name": "validate_fact",
            "description": "Validates a factual statement against provided context",
            "parameters": {
                "type": "object",
                "properties": {
                    "statement": {"type": "string"},
                    "context": {"type": "string"}
                },
                "required": ["statement", "context"]
            },
            "handler": validate_fact
        }
    ],
    result_type=ResearchResult
)

# Example usage:
"""
async def research_topic():
    # Start a streaming research session
    async with research_agent.run_stream(
        "What are the latest developments in quantum computing?"
    ) as stream:
        async for chunk in stream:
            print(chunk)  # Print each piece of research as it's found
            
    # Get the final structured results
    result = await stream.get_data()
    print(result)
"""
