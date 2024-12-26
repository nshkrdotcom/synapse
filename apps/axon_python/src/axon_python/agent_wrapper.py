from typing import Any, Callable, Dict, List, Optional
import json
import os
import sys
from datetime import datetime
from json import JSONDecodeError






from axon_python.agents.example_agent import agent as example_agent
 




import uvicorn
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse, PlainTextResponse, StreamingResponse
from pydantic import BaseModel, ValidationError, create_model
from pydantic_core import to_jsonable_python

from pydantic_ai import Agent
from pydantic_ai.exceptions import UnexpectedModelBehavior
from pydantic_ai.result import RunResult, Usage

from .agents.example_agent import agent as example_agent



import asyncio
from typing import AsyncIterator
from .agents.example_agent import agent as example_agent # , chat_agent



app = FastAPI(title='Axon Python Agent Wrapper')

# Global dictionary to hold agent instances
# Agent Registry (In a real app, consider using a more robust solution)
agent_instances: Dict[str, Agent] = {"example_agent": example_agent}

# Helper functions
def _resolve_model_name(model_name: str) -> str:
    return f"openai:{model_name}"

# TODO: Add this to the agent creation endpoint
# def _resolve_tools(tool_configs: List[Dict[str, Any]]) -> List[Callable]:
#     """
#     Simplified tool resolution. In a real implementation,
#     you'd likely want a more robust mechanism to map tool names
#     to Python functions, potentially using a registry or
#     dynamically loading modules.
#     """
#     tools = []
#     for config in tool_configs:
#         if config["name"] == "some_tool":
#             tools.append(some_tool)
#         # Add more tool mappings as needed
#     return tools

def _resolve_result_type(result_type_config: Dict[str, Any]) -> BaseModel:
    """
    Dynamically creates a Pydantic model from a JSON schema-like definition.
    This is a placeholder for a more complete schema translation mechanism.
    """
    fields = {}
    for field_name, field_info in result_type_config.items():
        # Assuming a simple type mapping for now
        field_type = {
            "string": str,
            "integer": int,
            "boolean": bool,
            "number": float,
            "array": list,
            "object": dict,
            "null": type(None),
        }[field_info["type"]]

        # Handle nested objects/arrays if necessary
        # ...

        fields[field_name] = (field_type, ...)  # Use ellipsis for required fields

    return create_model("ResultModel", **fields)

# Placeholder for a tool function
def some_tool(arg1: str, arg2: int) -> str:
    return f"Tool executed with {arg1} and {arg2}"

@app.post("/agents")
async def create_agent(request: Request):
    """
    Creates a new agent instance.

    Expects a JSON payload like:
    {
        "agent_id": "my_agent",
        "model": "gpt-4o",
        "system_prompt": "You are a helpful assistant.",
        "tools": [
            {"name": "some_tool", "description": "Does something", "parameters": {
                "type": "object",
                "properties": {
                    "arg1": {"type": "string"},
                    "arg2": {"type": "integer"}
                }
            }}
        ],
        "result_type": {
            "type": "object",
            "properties": {
                "field1": {"type": "string"},
                "field2": {"type": "integer"}
            }
        },
        "retries": 3,
        "result_retries": 5,
        "end_strategy": "early"
    }
    """
    try:
        data = await request.json()
        agent_id = data["agent_id"]

        if agent_id in agent_instances:
            raise HTTPException(status_code=400, detail="Agent with this ID already exists")

        model = _resolve_model_name(data["model"])
        system_prompt = data["system_prompt"]
        tools = _resolve_tools(data.get("tools", []))
        result_type = _resolve_result_type(data.get("result_type", {}))

        agent = Agent(
            model=model,
            system_prompt=system_prompt,
            tools=tools,
            result_type=result_type,
            # Add other agent parameters as needed
        )

        agent_instances[agent_id] = agent

        return JSONResponse({"status": "success", "agent_id": agent_id})

    except ValidationError as e:
        raise HTTPException(status_code=400, detail=e.errors())
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/agents/{agent_id}/run_sync")
async def run_agent_sync(agent_id: str, request_data: dict):
    """
    Executes an agent synchronously.

    Expects a JSON payload like:
    {
        "prompt": "What's the weather like?",
        "message_history": [],  # Optional
        "model_settings": {},  # Optional
        "usage_limits": {}  # Optional
    }
    """
    if agent_id not in agent_instances:
        raise HTTPException(status_code=404, detail="Agent not found")

    agent = agent_instances[agent_id]

    try:
        result = agent.run_sync(
            request_data["prompt"],
            message_history=request_data.get("message_history"),
            model_settings=request_data.get("model_settings"),
            usage_limits=request_data.get("usage_limits"),
            infer_name=False
        )

        # Log the successful run
        logger.info(f"Agent {agent_id} completed run_sync successfully")

        return JSONResponse(content={
            "result": to_jsonable_python(result.data),
            "usage": to_jsonable_python(result.usage)
        })
    except ValidationError as e:
        raise HTTPException(status_code=400, detail=e.errors())
    except UnexpectedModelBehavior as e:
        raise HTTPException(status_code=500, detail=f"Unexpected model behavior: {e}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

class LogEntry(BaseModel):
    timestamp: datetime
    level: str
    message: str

@app.post("/agents/{agent_id}/log")
async def log_message(agent_id: str, log_entry: LogEntry):
    # In a real implementation, you might want to use a more robust logging mechanism
    print(f"[{log_entry.timestamp}] {agent_id} - {log_entry.level}: {log_entry.message}")
    return JSONResponse({"status": "success"})

# Error handler for generic exceptions
@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception):
    logger.exception(f"An unexpected error occurred: {exc}")
    return JSONResponse(
        status_code=500,
        content={
            "status": "error",
            "error_type": exc.__class__.__name__,
            "message": str(exc),
        },
    )
    
 
async def event_stream(result: AsyncIterator):
    try:
        async for event in result:
            yield f"data: {json.dumps(to_jsonable_python(event))}\n\n"
    except Exception as e:
        yield f"data: {json.dumps({'error': str(e)})}\n\n"

@app.post("/agents/{agent_id}/run_sync")
async def run_agent_sync(agent_id: str, request_data: dict):
    if agent_id not in agent_instances:
        raise HTTPException(status_code=404, detail="Agent not found")

    agent = agent_instances[agent_id]

    try:
        result = agent.run_sync(
            request_data["prompt"],
            message_history=request_data.get("message_history"),
            model_settings=request_data.get("model_settings"),
            usage_limits=request_data.get("usage_limits"),
            infer_name=False
        )
        return JSONResponse(content={
            "result": to_jsonable_python(result.data),
            "usage": to_jsonable_python(result.usage)
        })
    except ValidationError as e:
        logger.error(f"Agent {agent_id} encountered a validation error: {e.errors()}")
        raise HTTPException(status_code=400, detail=e.errors())
    except UnexpectedModelBehavior as e:
        logger.error(f"Agent {agent_id} encountered an unexpected model behavior: {e}")
        raise HTTPException(status_code=500, detail=f"Unexpected model behavior: {e}")
    except Exception as e:
        logger.exception(f"Agent {agent_id} encountered an unexpected error: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/agents/{agent_id}/run_stream")
async def run_agent_stream(agent_id: str, request_data: dict):
    if agent_id not in agent_instances:
        return PlainTextResponse("Agent not found", status_code=404)

    agent = agent_instances[agent_id]

    try:
        result = agent.run_stream(
            request_data["prompt"],
            message_history=request_data.get("message_history"),
            model_settings=request_data.get("model_settings"),
            usage_limits=request_data.get("usage_limits"),
            infer_name=False
        )

        return StreamingResponse(event_stream(result), media_type="text/event-stream")

    except Exception as e:
        logger.exception(f"Agent {agent_id} encountered an error during streaming: {e}")
        return PlainTextResponse(f"Error during streaming: {e}", status_code=500)
 


def start_fastapi(port: int):
    uvicorn.run(app, host="0.0.0.0", port=port)

if __name__ == "__main__":
     # Get port from environment variable or default to 8000
    port = int(os.environ.get("AXON_PYTHON_AGENT_PORT", 8000))
    start_fastapi(port=port)
