# synapse_python/src/synapse_python/agents/simple_agent.py
from pydantic import BaseModel

from pydantic_ai import Agent

class Input(BaseModel):
    prompt: str

class Output(BaseModel):
    response: str

# agent = Agent(
#     model="gpt-4o",
#     result_type=Output,
#     system_prompt="You are a helpful assistant that responds in JSON.",
# )
agent = Agent(
    model_name,
    result_type=Output,
    system_prompt="You are a helpful assistant that responds in JSON format.",
    tools=[some_tool]
)