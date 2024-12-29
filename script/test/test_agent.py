# test_agent.py
from pydantic import BaseModel

from pydantic_ai import Agent

class TestResult(BaseModel):
    message: str

test_agent = Agent(
    model="openai:gpt-4o",
    system_prompt="You are a test agent.",
    result_type=TestResult,
)