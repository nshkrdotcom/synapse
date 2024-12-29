"""Example agent for testing."""
from typing import Dict, List, Optional

from fastapi import FastAPI
from pydantic import BaseModel

app = FastAPI()

class Message(BaseModel):
    prompt: str
    message_history: List[Dict[str, str]] = []

class AgentResponse(BaseModel):
    result: str
    messages: List[Dict[str, str]]
    usage: Dict[str, int]

@app.post("/agents/{agent_id}/run_sync")
async def run_sync(agent_id: str, message: Message) -> AgentResponse:
    """Handle synchronous agent execution."""
    return AgentResponse(
        result="Hello from the test agent!",
        messages=[{"role": "agent", "content": "Test response"}],
        usage={"total_tokens": 10}
    )
