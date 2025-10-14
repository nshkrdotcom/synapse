"""
FastAPI wrapper for pydantic-ai agents that provides a clean HTTP interface
for agent management and execution.
"""
import asyncio
import logging
from typing import Any, AsyncIterator, Dict, List, Optional

from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse, StreamingResponse
from pydantic import BaseModel, ValidationError
from pydantic_ai import Agent
from pydantic_ai.exceptions import UnexpectedModelBehavior
from pydantic_ai.message import ModelMessage

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title='Synapse Pydantic Agent Wrapper')

# Global registry for agent instances
agent_instances: Dict[str, Agent] = {}

# Request/Response Models
class AgentConfig(BaseModel):
    """Configuration for creating a new agent."""
    agent_id: str
    model: str
    system_prompt: str
    tools: Optional[List[Dict[str, Any]]] = None
    result_type: Optional[Dict[str, Any]] = None

class RunRequest(BaseModel):
    """Request for running an agent."""
    prompt: str
    message_history: Optional[List[ModelMessage]] = None
    model_settings: Optional[Dict[str, Any]] = None
    system_prompt: Optional[str] = None
    tools: Optional[List[Dict[str, Any]]] = None
    result_type: Optional[Dict[str, Any]] = None

class ToolCallRequest(BaseModel):
    """Request for calling a specific tool."""
    tool_name: str
    args: Dict[str, Any]

# Error Handling
class AgentError(Exception):
    """Base class for agent-related errors."""
    pass

class AgentNotFoundError(AgentError):
    """Raised when an agent is not found in the registry."""
    pass

@app.exception_handler(AgentError)
async def agent_error_handler(request, exc):
    return JSONResponse(
        status_code=404 if isinstance(exc, AgentNotFoundError) else 500,
        content={"error": str(exc)}
    )

@app.exception_handler(ValidationError)
async def validation_error_handler(request, exc):
    return JSONResponse(
        status_code=422,
        content={"error": str(exc)}
    )

@app.exception_handler(UnexpectedModelBehavior)
async def model_error_handler(request, exc):
    return JSONResponse(
        status_code=500,
        content={"error": str(exc)}
    )

# Agent Management Endpoints
@app.post("/agents")
async def create_agent(config: AgentConfig):
    """Create and register a new agent instance."""
    try:
        agent = Agent(
            config.model,
            system_prompt=config.system_prompt,
            tools=config.tools,
            result_type=config.result_type
        )
        agent_instances[config.agent_id] = agent
        return {"status": "success", "message": f"Agent {config.agent_id} created"}
    except Exception as e:
        logger.error(f"Error creating agent: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.delete("/agents/{agent_id}")
async def delete_agent(agent_id: str):
    """Remove an agent from the registry."""
    if agent_id in agent_instances:
        del agent_instances[agent_id]
        return {"status": "success", "message": f"Agent {agent_id} deleted"}
    raise AgentNotFoundError(f"Agent {agent_id} not found")

# Agent Execution Endpoints
@app.post("/run")
async def run_agent(agent_id: str, request: RunRequest):
    """Run an agent synchronously."""
    agent = _get_agent(agent_id)
    try:
        result = await agent.run(
            request.prompt,
            message_history=request.message_history,
            model_settings=request.model_settings
        )
        return {
            "result": result.data,
            "messages": result.all_messages(),
            "usage": result.usage
        }
    except Exception as e:
        logger.error(f"Error running agent: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/run/stream")
async def run_agent_stream(agent_id: str, request: RunRequest):
    """Run an agent and stream the response."""
    agent = _get_agent(agent_id)
    try:
        result = await agent.run_stream(
            request.prompt,
            message_history=request.message_history,
            model_settings=request.model_settings
        )
        return StreamingResponse(
            _stream_response(result),
            media_type="text/event-stream"
        )
    except Exception as e:
        logger.error(f"Error streaming agent response: {e}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/tool_call")
async def call_tool(agent_id: str, request: ToolCallRequest):
    """Call a specific tool on an agent."""
    agent = _get_agent(agent_id)
    try:
        result = await agent.call_tool(request.tool_name, request.args)
        return {"result": result}
    except Exception as e:
        logger.error(f"Error calling tool: {e}")
        raise HTTPException(status_code=500, detail=str(e))

# Helper Functions
def _get_agent(agent_id: str) -> Agent:
    """Get an agent from the registry or raise an error."""
    agent = agent_instances.get(agent_id)
    if not agent:
        raise AgentNotFoundError(f"Agent {agent_id} not found")
    return agent

async def _stream_response(result: AsyncIterator[str]) -> AsyncIterator[str]:
    """Stream agent responses in SSE format."""
    try:
        async for chunk in result:
            yield f"data: {chunk}\n\n"
    except Exception as e:
        logger.error(f"Error in stream: {e}")
        yield f"error: {str(e)}\n\n"
    finally:
        yield "data: [DONE]\n\n"

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
