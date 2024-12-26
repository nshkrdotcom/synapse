# axon_python/src/axon_python/agents/example_agent.py
from pydantic import BaseModel

from pydantic_ai import Agent

class Output(BaseModel):
    response: str

agent = Agent(
    model="openai:gpt-4o",
    result_type=Output,
    system_prompt="You are a helpful assistant that answers in JSON format.",
)