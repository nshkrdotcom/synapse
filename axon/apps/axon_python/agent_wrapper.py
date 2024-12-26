# from fastapi import FastAPI, HTTPException
# from pydantic import BaseModel, ValidationError

# # Import your pydantic-ai agent code here

# app = FastAPI()
# agent = MyAgent(model="openai:gpt-4o")  # Instantiate your agent

# # Load the appropriate agent based on configuration
# # You might need a way to select different agents based on the agent's name or other identifiers
# # ...

# class Input(BaseModel):
#     prompt: str

# class Output(BaseModel):
#     response: str

# @app.post("/run")
# async def run_agent(input_data: Input):
#     try:
#         result = agent.run_sync(input_data.prompt)
#         return Output(response=result.data)
#     except ValidationError as e:
#         raise HTTPException(status_code=400, detail=e.errors())
#     except Exception as e:
#         raise HTTPException(status_code=500, detail=str(e))

# @app.post("/run")
# async def run_agent_2(request_data: dict):
#     result = agent.run_sync(request_data["prompt"], **request_data)
#     return {"data": result.data}




    # axon_python/src/axon_python/agent_wrapper.py
import os

import uvicorn
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel, ValidationError

from axon_python.agents.example_agent import agent as example_agent
from pydantic_ai.agent import Agent

app = FastAPI()

# Agent Registry (In a real app, consider using a more robust solution)
agent_instances: dict[str, Agent] = {"example_agent": example_agent}

class RunSyncInput(BaseModel):
    prompt: str
    message_history: list | None = None
    model_settings: dict | None = None
    usage_limits: dict | None = None

class RunSyncOutput(BaseModel):
    result: str | dict  # Depends on your agent's result_type
    usage: dict

@app.post("/agents/{agent_id}/run_sync")
async def run_agent_sync(agent_id: str, request: Request, input_data: RunSyncInput):
    if agent_id not in agent_instances:
        raise HTTPException(status_code=404, detail="Agent not found")

    agent = agent_instances[agent_id]

    try:
        # Extract model and usage_limits if they exist in the input
        model = input_data.model_settings.get("model") if input_data.model_settings else None
        usage_limits = input_data.usage_limits

        result = agent.run_sync(
            input_data.prompt,
            message_history=input_data.message_history,
            model=model,
            usage_limits=usage_limits,
            infer_name=False
        )
        return RunSyncOutput(result=result.data, usage=result.usage())
    except ValidationError as e:
        raise HTTPException(status_code=400, detail=e.errors())
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

def start_fastapi(port: int):
    uvicorn.run(app, host="0.0.0.0", port=port)

if __name__ == "__main__":
    # Get port from environment variable or default to 8000
    port = int(os.environ.get("AXON_PYTHON_AGENT_PORT", 8000))
    start_fastapi(port=port)