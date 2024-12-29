import importlib
import logging
import os
import sys
from typing import Dict, Any

import uvicorn
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[logging.StreamHandler()]
)
logger = logging.getLogger(__name__)

app = FastAPI()

# Global dictionary to hold agent instances
agent_instances: Dict[str, Any] = {}

class MessageRequest(BaseModel):
    message: str

@app.post("/agents/{agent_id}/run_sync")
async def run_agent_sync(agent_id: str, request: MessageRequest):
    logger.info(f"Received request for agent {agent_id}: {request.message}")
    
    if agent_id not in agent_instances:
        logger.error(f"Agent {agent_id} not found in instances: {list(agent_instances.keys())}")
        raise HTTPException(status_code=404, detail=f"Agent {agent_id} not found")
    
    agent = agent_instances[agent_id]
    try:
        logger.info(f"Running agent {agent_id}")
        result = await agent.run_sync(request.message)
        logger.info(f"Agent {agent_id} response: {result}")
        return result
    except Exception as e:
        logger.exception(f"Error running agent {agent_id}")
        raise HTTPException(status_code=500, detail=str(e))

def start_fastapi(port: int):
    # Log all environment variables to help debug
    logger.info("Environment variables:")
    for key, value in os.environ.items():
        if "AXON" in key:
            logger.info(f"  {key}={value}")
            
    logger.info(f"Starting FastAPI server on port {port}")
    uvicorn.run(app, host="0.0.0.0", port=port, log_level="info")

if __name__ == "__main__":
    logger.info(f"Starting agent wrapper with args: {sys.argv}")
    logger.info(f"Current working directory: {os.getcwd()}")
    logger.info(f"Python path: {sys.path}")
    
    if len(sys.argv) < 2:
        logger.error("Usage: python -m axon_python.agent_wrapper <module_name>")
        sys.exit(1)

    module_name = sys.argv[1]
    try:
        # Import the module and get the agent instance
        logger.info(f"Attempting to import module: axon_python.{module_name}")
        module = importlib.import_module(f"axon_python.{module_name}")
        agent_instances["example_agent"] = module.agent
        logger.info(f"Successfully loaded agent from module {module_name}")
    except Exception as e:
        logger.exception(f"Failed to load agent module: {e}")
        sys.exit(1)

    port = int(os.environ.get("AXON_PYTHON_AGENT_PORT", 8000))
    start_fastapi(port=port)


# import os
# from typing import Dict, Any

# import uvicorn
# from fastapi import FastAPI, HTTPException
# from pydantic import BaseModel

# from axon_python.agents.example_agent import agent as example_agent

# app = FastAPI()

# # Global dictionary to hold agent instances
# agent_instances: Dict[str, Any] = {"example_agent": example_agent}

# class MessageRequest(BaseModel):
#     message: str

# @app.post("/agents/{agent_id}/run_sync")
# async def run_agent_sync(agent_id: str, request: MessageRequest):
#     if agent_id not in agent_instances:
#         raise HTTPException(status_code=404, detail=f"Agent {agent_id} not found")
    
#     agent = agent_instances[agent_id]
#     try:
#         result = await agent.run_sync(request.message)
#         return result
#     except Exception as e:
#         raise HTTPException(status_code=500, detail=str(e))

# def start_fastapi(port: int):
#     uvicorn.run(app, host="0.0.0.0", port=port)

# if __name__ == "__main__":
#     port = int(os.environ.get("AXON_PYTHON_AGENT_PORT", 8000))
#     start_fastapi(port=port)

    
# # import asyncio

# # import importlib
# # import inspect
# # import json
# # import logging
# # import os
# # from platform import python_branch
# # import sys
# # from datetime import datetime
# # from json import JSONDecodeError






# # from axon_python.agents.example_agent import agent as example_agent
 



# # from typing import Any, AsyncIterator, Callable, Dict, List, Optional, Union
# # import uvicorn
# # import grpc
# # from fastapi import FastAPI, HTTPException, Request
# # from fastapi.responses import JSONResponse, PlainTextResponse, StreamingResponse
# # from pydantic import BaseModel, ValidationError, create_model
# # from pydantic_core import to_jsonable_python

# # from pydantic_ai import Agent
# # from pydantic_ai.exceptions import UnexpectedModelBehavior
# # from pydantic_ai.message import (
# #     ModelMessage,
# #     ModelRequest,
# #     ModelResponse,
# #     RetryPromptPart,
# #     SystemPromptPart,
# #     TextPart,
# #     ToolCallPart,
# #     ToolReturnPart,
# #     UserPromptPart,
# # )
# # from pydantic_ai.result import RunResult, Usage

 


# # # Assuming all agents are defined in the .agents module.
# # # This could be adapted to load agents from other modules.
# # from .agents import example_agent
# # from .agents.bank_support_agent import support_agent


# # from .agents.example_agent import agent as example_agent
# # from .agents.example_agent import agent as example_agent # , chat_agent


# # # Import generated gRPC stubs
# # from .protos import axon_pb2, axon_pb2_grpc


# # app = FastAPI(title='Axon Python Agent Wrapper')

# # # Configure logging
# # logging.basicConfig(level=logging.INFO)
# # logger = logging.getLogger(__name__)

# # # Global dictionary to hold agent instances
# # #agent_instances: dict[str, Agent] = {"example_agent": example_agent, "bank_support_agent": support_agent}
# # agent_instances: Dict[str, Agent] = {}
# # agent_configs: Dict[str, Dict[str, Any]] = {}

# # # Helper functions
# # def _resolve_model_name(model_name: str) -> str:
# #     # Basic model name resolution.
# #     # You could add more sophisticated logic here if needed.
# #     return f"openai:{model_name}"


# # # # Global dictionary to hold agent instances
# # # # Agent Registry (In a real app, consider using a more robust solution)
# # # agent_instances: Dict[str, Agent] = {"example_agent": example_agent}

# # # # Helper functions
# # # def _resolve_model_name(model_name: str) -> str:
# # #     return f"openai:{model_name}"

# # # TODO: Add this to the agent creation endpoint
# # # def _resolve_tools(tool_configs: List[Dict[str, Any]]) -> List[Callable]:
# # #     """
# # #     Simplified tool resolution. In a real implementation,
# # #     you'd likely want a more robust mechanism to map tool names
# # #     to Python functions, potentially using a registry or
# # #     dynamically loading modules.
# # #     """
# # #     tools = []
# # #     for config in tool_configs:
# # #         if config["name"] == "some_tool":
# # #             tools.append(some_tool)
# # #         # Add more tool mappings as needed
# # #     return tools

# # def _resolve_result_type(result_type_config: Dict[str, Any]) -> BaseModel:
# #     """
# #     Dynamically creates a Pydantic model from a JSON schema-like definition.
# #     This is a placeholder for a more complete schema translation mechanism.
# #     """
# #     fields = {}
# #     for field_name, field_info in result_type_config.items():
# #         # Assuming a simple type mapping for now
# #         field_type = {
# #             "string": str,
# #             "integer": int,
# #             "boolean": bool,
# #             "number": float,
# #             "array": list,
# #             "object": dict,
# #             "null": type(None),
# #         }[field_info["type"]]

# #         # Handle nested objects/arrays if necessary
# #         # ...

# #         fields[field_name] = (field_type, ...)  # Use ellipsis for required fields

# #     return create_model("ResultModel", **fields)

# # # Placeholder for a tool function
# # def some_tool(arg1: str, arg2: int) -> str:
# #     return f"Tool executed with {arg1} and {arg2}"




# # # Here's a more concise example to illustrate the concept:
# # # 
# # # from pydantic_ai import Agent
# # # from pydantic import BaseModel
# # # 
# # # # Define your tool function
# # # def my_tool(x: int, y: str) -> str:
# # #     """This tool takes an integer 'x' and a string 'y' and returns a string 
# # #     indicating the received values."""
# # #     return f"Received: x={x}, y={y}"
# # # 
# # # # Create an agent, passing the tool function in the `tools` list
# # # agent = Agent(
# # #     model="openai:gpt-4o",
# # #     system_prompt="You are a helpful assistant.",
# # #     tools=[my_tool],  # Register the tool here
# # #     result_type=BaseModel,  # You need to define a result type, even if simple
# # # ) 
# # # 
# # # # In essence, you register tools with pydantic-ai by passing the actual 
# # # # Python function objects (not just their names as strings) to the 
# # # # Agent constructor's tools argument.





    

# # @app.post("/agents")
# # async def create_agent(request: Request):
# #     """
# #     Creates a new agent instance.

# #     Expects a JSON payload like:
# #     {
# #         "agent_id": "my_agent",
# #         "model": "gpt-4o",
# #         "system_prompt": "You are a helpful assistant.",
# #         "tools": [
# #             {"name": "some_tool", "description": "Does something", "parameters": {
# #                 "type": "object",
# #                 "properties": {
# #                     "arg1": {"type": "string"},
# #                     "arg2": {"type": "integer"}
# #                 }
# #             }}
# #         ],
# #         "result_type": {
# #             "type": "object",
# #             "properties": {
# #                 "field1": {"type": "string"},
# #                 "field2": {"type": "integer"}
# #             }
# #         },
# #         "retries": 3,
# #         "result_retries": 5,
# #         "end_strategy": "early"
# #     }
# #     """
# #     try:
# #         data = await request.json()
# #         agent_id = data["agent_id"]
# #         print(f"DATA: {data}")
# #         if agent_id in agent_instances:
# #             raise HTTPException(status_code=400, detail="Agent with this ID already exists")

# #         model = _resolve_model_name(data["model"])
# #         system_prompt = data["system_prompt"]
# #         tools = _resolve_tools(data.get("tools", []))
# #         result_type = _resolve_result_type(data.get("result_type", {}))



# #         # agent = Agent(
# #         #     model=model,
# #         #     system_prompt=system_prompt,
# #         #     tools=tools,
# #         #     result_type=result_type,
# #         #     # Add other agent parameters as needed
# #         # )
# #         agent = Agent(
# #             model=model,
# #             system_prompt=system_prompt,
# #             tools=[some_tool],  # Pass the tool function here
# #             result_type=result_type,
# #             # ... other agent parameters
# #         )

# #         # Dynamically import the agent module based on the provided name
# #         module_name = f"axon_python.agents.{data['agent_module']}"
# #         agent_module = importlib.import_module(module_name)

# #         # Assuming each agent module has an 'agent' attribute which is an instance of pydantic_ai.Agent
# #         agent = agent_module.agent

# #         agent_instances[agent_id] = agent

# #         return JSONResponse({"status": "success", "agent_id": agent_id})

# #     except ValidationError as e:
# #         raise HTTPException(status_code=400, detail=e.errors())
# #     except Exception as e:
# #         raise HTTPException(status_code=500, detail=str(e))

# # @app.post("/agents/{agent_id}/run_sync")
# # async def run_agent_sync(agent_id: str, request_data: dict):
# #     """
# #     Executes an agent synchronously.

# #     Expects a JSON payload like:
# #     {
# #         "prompt": "What's the weather like?",
# #         "message_history": [],  # Optional
# #         "model_settings": {},  # Optional
# #         "usage_limits": {}  # Optional
# #     }
# #     """
# #     if agent_id not in agent_instances:
# #         raise HTTPException(status_code=404, detail="Agent not found")

# #     agent = agent_instances[agent_id]

# #     try:
# #         result = agent.run_sync(
# #             request_data["prompt"],
# #             message_history=request_data.get("message_history"),
# #             model_settings=request_data.get("model_settings"),
# #             usage_limits=request_data.get("usage_limits"),
# #             infer_name=False
# #         )

# #         # Log the successful run
# #         logger.info(f"Agent {agent_id} completed run_sync successfully")

# #         return JSONResponse(content={
# #             "result": to_jsonable_python(result.data),
# #             "usage": to_jsonable_python(result.usage),
# #             "messages": result.messages
# #         })
# #     except ValidationError as e:
# #         logger.error(f"Agent {agent_id} encountered a validation error: {e.errors()}")
# #         raise HTTPException(status_code=400, detail=e.errors())
# #     except UnexpectedModelBehavior as e:
# #         logger.error(f"Agent {agent_id} encountered an unexpected model behavior: {e}")
# #         raise HTTPException(status_code=500, detail=f"Unexpected model behavior: {e}")
# #     except Exception as e:
# #         logger.exception(f"Agent {agent_id} encountered an unexpected error: {e}")
# #         raise HTTPException(status_code=500, detail=str(e))



# # @app.post("/agents/{agent_id}/tool_call")
# # async def call_tool(agent_id: str, tool_name: str, request_data: dict):
# #     if agent_id not in agent_instances:
# #         raise HTTPException(status_code=404, detail="Agent not found")

# #     agent = agent_instances[agent_id]

# #     # Access the agent's tools
# #     agent_tools = {tool.name: tool for tool in agent.tools}

# #     if tool_name not in agent_tools:
# #         raise HTTPException(status_code=404, detail=f"Tool '{tool_name}' not found for agent '{agent_id}'")

# #     tool = agent_tools[tool_name]

# #     # Prepare the arguments for the tool function
# #     # Assuming the tool function expects keyword arguments
# #     tool_args = request_data.get("args", {})

# #     # Call the tool function
# #     try:
# #         # If the tool function expects a context, you need to pass it here
# #         # For example, if your tool function is defined like `def my_tool(ctx, **kwargs)`
# #         # result = tool.function(None, **tool_args)
# #         # Assuming no context for this example:
# #         result = tool.function(**tool_args)

# #         # Convert the result to a JSON-serializable format
# #         result_json = json.dumps(result)

# #         # Return the result as a JSON response
# #         return JSONResponse(content={"result": result_json})

# #     except Exception as e:
# #         logger.exception(f"Error calling tool '{tool_name}' for agent '{agent_id}': {e}")
# #         raise HTTPException(status_code=500, detail=f"Error calling tool: {e}")

# # # # Tool registry
# # # tool_registry: Dict[str, Callable] = {}

# # # def register_tool(name: str, func: Callable):
# # #     tool_registry[name] = func

# # def _resolve_tools(tool_configs: List[Dict[str, Any]]) -> List[Callable]:
# #     """
# #     Resolves tool names to their corresponding functions using a registry.
# #     """
# #     tools = []
# #     for config in tool_configs:
# #         tool_name = config["name"]
# #         if tool_name in tool_registry:
# #             tools.append(tool_registry[tool_name])
# #         else:
# #             logger.warning(f"Tool '{tool_name}' not found in registry.")
# #     return tools

# # def _resolve_result_type(result_type_config: Dict[str, Any]) -> BaseModel:
# #     """
# #     Dynamically creates a Pydantic model from a JSON schema-like definition.
# #     This is a placeholder for a more complete schema translation mechanism.
# #     """
# #     fields = {}
# #     for field_name, field_info in result_type_config.items():
# #         field_type = {
# #             "string": str,
# #             "integer": int,
# #             "boolean": bool,
# #             "number": float,
# #             "array": list,
# #             "object": dict,
# #             "null": type(None),
# #         }[field_info["type"]]

# #         fields[field_name] = (field_type, ...)

# #     return create_model("ResultModel", **fields)

# # # Example tool functions
# # def some_tool(arg1: str, arg2: int) -> str:
# #     return f"Tool executed with {arg1} and {arg2}"

# # def another_tool(data: dict) -> list:
# #     return list(data.values())

# # # # Register tools
# # # register_tool("some_tool", some_tool)
# # # register_tool("another_tool", another_tool)

# # # Register tools
# # tool_registry: Dict[str, Callable] = {}
# # tool_registry["some_tool"] = some_tool
# # tool_registry["another_tool"] = another_tool



































# # class LogEntry(BaseModel):
# #     timestamp: datetime
# #     level: str
# #     message: str

# # @app.post("/agents/{agent_id}/log")
# # async def log_message(agent_id: str, log_entry: LogEntry):
# #     # In a real implementation, you might want to use a more robust logging mechanism
# #     print(f"[{log_entry.timestamp}] {agent_id} - {log_entry.level}: {log_entry.message}")
# #     return JSONResponse({"status": "success"})

# # # Error handler for generic exceptions
# # @app.exception_handler(Exception)
# # async def generic_exception_handler(request: Request, exc: Exception):
# #     logger.exception(f"An unexpected error occurred: {exc}")
# #     return JSONResponse(
# #         status_code=500,
# #         content={
# #             "status": "error",
# #             "error_type": exc.__class__.__name__,
# #             "message": str(exc),
# #         },
# #     )
    
 
# # async def event_stream(result: AsyncIterator):
# #     try:
# #         async for event in result:
# #             yield f"data: {json.dumps(to_jsonable_python(event))}\n\n"
# #     except Exception as e:
# #         yield f"data: {json.dumps({'error': str(e)})}\n\n"

# # @app.post("/agents/{agent_id}/run_sync")
# # async def run_agent_sync(agent_id: str, request_data: dict):
# #     if agent_id not in agent_instances:
# #         raise HTTPException(status_code=404, detail="Agent not found")

# #     agent = agent_instances[agent_id]

# #     try:
# #         result = agent.run_sync(
# #             request_data["prompt"],
# #             message_history=request_data.get("message_history"),
# #             model_settings=request_data.get("model_settings"),
# #             usage_limits=request_data.get("usage_limits"),
# #             infer_name=False
# #         )
# #         return JSONResponse(content={
# #             "result": to_jsonable_python(result.data),
# #             "usage": to_jsonable_python(result.usage),
# #             "messages": to_jsonable_python(result.messages) # Assuming result.messages is a list of messages
# #         })
# #     except ValidationError as e:
# #         logger.error(f"Agent {agent_id} encountered a validation error: {e.errors()}")
# #         raise HTTPException(status_code=400, detail=e.errors())
# #     except UnexpectedModelBehavior as e:
# #         logger.error(f"Agent {agent_id} encountered an unexpected model behavior: {e}")
# #         raise HTTPException(status_code=500, detail=f"Unexpected model behavior: {e}")
# #     except Exception as e:
# #         logger.exception(f"Agent {agent_id} encountered an unexpected error: {e}")
# #         raise HTTPException(status_code=500, detail=str(e))

# # async def run_and_stream(agent: Agent, request_data: dict) -> AsyncIterator[str]:
# #     """Run an agent and stream the response."""
# #     async with agent.run_stream(
# #         request_data["prompt"],
# #         message_history=request_data.get("message_history"),
# #         model_settings=request_data.get("model_settings"),
# #         usage_limits=request_data.get("usage_limits"),
# #         infer_name=False
# #     ) as result:
# #         try:
# #             async for text in result.stream_text():
# #                 yield json.dumps(to_jsonable_python({"data": text})) # Stream text chunks
# #         except Exception as e:
# #             logger.exception(f"Error during streaming: {e}")
# #             yield json.dumps({"error": str(e)})

            

# # # async def run_and_stream(agent: Agent, request_data: dict) -> AsyncIterator[str]:
# # #     """Run an agent and stream the response."""
# # #     async with agent.run_stream(
# # #         request_data["prompt"],
# # #         message_history=request_data.get("message_history"),
# # #         model_settings=request_data.get("model_settings"),
# # #         usage_limits=request_data.get("usage_limits"),
# # #         infer_name=False
# # #     ) as result:
# # #         try:
# # #             async for response_part in result.stream_text():
# # #                 # Use a structured format for sending chunks
# # #                 chunk = {
# # #                     "status": "chunk",
# # #                     "data": response_part
# # #                 }
# # #                 yield json.dumps(to_jsonable_python(chunk))

# # #             # Send a completion message with usage info
# # #             final_result = {
# # #                 "status": "complete",
# # #                 "result": result.data,
# # #                 "usage": result.usage()
# # #             }
# # #             yield json.dumps(to_jsonable_python(final_result))
# # #         except Exception as e:
# # #             # Handle any errors that occur during streaming
# # #             error_message = {
# # #                 "status": "error",
# # #                 "error_type": e.__class__.__name__,
# # #                 "message": str(e)
# # #             }
# # #             yield json.dumps(error_message)

# # @app.post("/agents/{agent_id}/run_stream")
# # async def run_agent_stream(agent_id: str, request_data: dict):
# #     if agent_id not in agent_instances:
# #         return PlainTextResponse("Agent not found", status_code=404)

# #     agent = agent_instances[agent_id]
    
# #     return StreamingResponse(run_and_stream(agent, request_data), media_type="application/json")

# #     # try:
# #     #     result = agent.run_stream(
# #     #         request_data["prompt"],
# #     #         message_history=request_data.get("message_history"),
# #     #         model_settings=request_data.get("model_settings"),
# #     #         usage_limits=request_data.get("usage_limits"),
# #     #         infer_name=False
# #     #     )

# #     #     return StreamingResponse(event_stream(result), media_type="text/event-stream")

# #     # except Exception as e:
# #     #     logger.exception(f"Agent {agent_id} encountered an error during streaming: {e}")
# #     #     return PlainTextResponse(f"Error during streaming: {e}", status_code=500)
 


# # # endpoint to simulate a crash
# # @app.post("/agents/{agent_id}/crash")
# # async def crash_agent(agent_id: str):
# #     if agent_id not in agent_instances:
# #         raise HTTPException(status_code=404, detail="Agent not found")

# #     # Forcefully exit the process
# #     # You might want to make this more sophisticated (e.g., raise an exception)
# #     # depending on how you want to simulate the crash
# #     os._exit(1)










# # # class AgentServicer(axon_pb2_grpc.AgentServiceServicer):
# # #     def __init__(self, agent_instances: dict[str, Agent]):
# # #         self.agent_instances = agent_instances

# # #     def RunSync(self, request, context):
# # #         agent_id = request.agent_id
# # #         if agent_id not in self.agent_instances:
# # #             context.abort(grpc.StatusCode.NOT_FOUND, f"Agent '{agent_id}' not found")

# # #         agent = self.agent_instances[agent_id]
# # #         prompt = request.prompt
# # #         message_history = [self._convert_message_to_pydantic_ai(msg) for msg in request.message_history]

# # #         # Execute the agent synchronously and get the result
# # #         try:
# # #             result = agent.run_sync(prompt, message_history=message_history)
# # #             # Convert the result to a protobuf message
# # #             return axon_pb2.RunSyncResponse(
# # #                 result=json.dumps(result.data),
# # #                 usage=axon_pb2.Usage(
# # #                     requests=result.usage.requests,
# # #                     request_tokens=result.usage.request_tokens,
# # #                     response_tokens=result.usage.response_tokens,
# # #                     total_tokens=result.usage.total_tokens
# # #                     # Convert details as needed
# # #                 ),
# # #                 messages=[_convert_pydantic_ai_message_to_protobuf(msg) for msg in result.messages]
# # #             )
# # #         except Exception as e:
# # #             context.abort(grpc.StatusCode.UNKNOWN, f"Error during agent execution: {e}")

# # #     def RunStream(self, request, context):
# # #         agent_id = request.agent_id
# # #         if agent_id not in self.agent_instances:
# # #             context.abort(grpc.StatusCode.NOT_FOUND, f"Agent '{agent_id}' not found")
# # #             return

# # #         agent = self.agent_instances[agent_id]
# # #         prompt = request.prompt
# # #         message_history = [self._convert_message_to_pydantic_ai(msg) for msg in request.message_history]

# # #         try:
# # #             async for chunk in agent.run_stream(prompt, message_history=message_history):
# # #                 # Convert each chunk to a RunResponseChunk message
# # #                 yield axon_pb2.RunResponseChunk(data=json.dumps(chunk).encode('utf-8'))
# # #         except Exception as e:
# # #             logger.exception(f"Error during streaming for agent {agent_id}: {e}")
# # #             context.abort(grpc.StatusCode.UNKNOWN, f"Error during streaming: {e}")
# # #             return

# # #     def _convert_message_to_pydantic_ai(self, msg):
# # #         # Convert a gRPC ModelMessage to a pydantic-ai ModelMessage
# # #         # Convert a gRPC ModelMessage to a pydantic-ai ModelMessage or a compatible format
# # #         parts = []
# # #         for part in msg.parts:
# # #             if part.HasField('system_prompt_part'):
# # #                 parts.append(
# # #                     SystemPromptPart(content=part.system_prompt_part.content, part_kind='system-prompt')
# # #                 )
# # #             elif part.HasField('user_prompt_part'):
# # #                 parts.append(
# # #                     UserPromptPart(
# # #                         content=part.user_prompt_part.content,
# # #                         timestamp=Timestamp(seconds=part.user_prompt_part.timestamp),
# # #                         part_kind='user-prompt'
# # #                     )
# # #                 )
# # #             elif part.HasField('tool_return_part'):
# # #                 parts.append(
# # #                     ToolReturnPart(
# # #                         tool_name=part.tool_return_part.tool_name,
# # #                         content=part.tool_return_part.content,
# # #                         tool_call_id=part.tool_return_part.tool_call_id,
# # #                         part_kind='tool-return'
# # #                     )
# # #                 )
# # #             elif part.HasField('retry_prompt_part'):
# # #                 parts.append(
# # #                     RetryPromptPart(
# # #                         content=part.retry_prompt_part.content,
# # #                         tool_name=part.retry_prompt_part.tool_name,
# # #                         tool_call_id=part.retry_prompt_part.tool_call_id,
# # #                         part_kind='retry-prompt'
# # #                     )
# # #                 )
# # #             elif part.HasField('text_part'):
# # #                 parts.append(
# # #                     TextPart(content=part.text_part.content, part_kind='text')
# # #                 )
# # #             elif part.HasField('tool_call_part'):
# # #                 parts.append(
# # #                     ToolCallPart(
# # #                         tool_name=part.tool_call_part.tool_name,
# # #                         args=part.tool_call_part.args,  # Assuming this is already a JSON string
# # #                         tool_call_id=part.tool_call_part.tool_call_id,
# # #                         part_kind='tool-call'
# # #                     )
# # #                 )

# # #         # Determine the kind of message
# # #         kind = 'request' if msg.kind == axon_pb2.ModelMessage.REQUEST else 'response'

# # #         # Create and return the appropriate ModelMessage
# # #         if kind == 'request':
# # #             return ModelRequest(parts=parts, kind=kind)
# # #         else:  # kind == 'response'
# # #             return ModelResponse(parts=parts, timestamp=Timestamp(seconds=msg.timestamp), kind=kind)

# # # def serve():
# # #     server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
# # #     axon_pb2_grpc.add_AgentServiceServicer_to_server(AgentServicer(agent_instances), server)
# # #     server.add_insecure_port('[::]:50051')  # Specify the port your agent should listen on
# # #     server.start()
# # #     server.wait_for_termination()



# # # ... (other imports and helper functions)












# # class AgentServicer(axon_pb2_grpc.AgentServiceServicer):
# #     def __init__(self, agent_instances: dict[str, Agent]):
# #         self.agent_instances = agent_instances

# #     async def RunSync(self, request: axon_pb2.RunSyncRequest, context) -> axon_pb2.RunSyncResponse:
# #         agent_id = request.agent_id
# #         if agent_id not in self.agent_instances:
# #             raise Exception(f"Agent not found: {agent_id}")

# #         agent = self.agent_instances[agent_id]
# #         prompt = request.prompt
# #         message_history = [self._convert_message_to_pydantic_ai(msg) for msg in request.message_history]

# #         try:
# #             result = agent.run_sync(
# #                 prompt,
# #                 message_history=message_history,
# #                 # model_settings=request.model_settings,
# #                 # usage_limits=request.usage_limits,
# #                 infer_name=False
# #             )

# #             return axon_pb2.RunSyncResponse(
# #                 result=json.dumps(result.data).encode("utf-8"),
# #                 usage=axon_pb2.Usage(
# #                     requests=result.usage.requests,
# #                     request_tokens=result.usage.request_tokens,
# #                     response_tokens=result.usage.response_tokens,
# #                     total_tokens=result.usage.total_tokens,
# #                 ),
# #                 messages=[_convert_pydantic_ai_message_to_protobuf(msg) for msg in result.messages],
# #             )

# #         except Exception as e:
# #             logger.exception(f"Error during RunSync for agent {agent_id}: {e}")
# #             raise

# #     async def RunStream(self, request: axon_pb2.RunRequest, context):
# #         agent_id = request.agent_id
# #         if agent_id not in self.agent_instances:
# #             raise Exception(f"Agent not found: {agent_id}")

# #         agent = self.agent_instances[agent_id]
# #         prompt = request.prompt
# #         message_history = [self._convert_message_to_pydantic_ai(msg) for msg in request.message_history]

# #         try:
# #             async for chunk in agent.run_stream(
# #                 prompt,
# #                 message_history=message_history,
# #                 # model_settings=request.model_settings,
# #                 # usage_limits=request.usage_limits,
# #                 infer_name=False
# #             ):
# #                 yield axon_pb2.RunResponseChunk(data=json.dumps(chunk).encode("utf-8"))

# #         except Exception as e:
# #             logger.exception(f"Error during RunStream for agent {agent_id}: {e}")
# #             raise

# #     def _convert_message_to_pydantic_ai(self, msg: axon_pb2.ModelMessage) -> ModelMessage:
# #         """Convert a gRPC ModelMessage to a pydantic-ai ModelMessage."""
# #         parts = []
# #         for part in msg.parts:
# #             if part.HasField("system_prompt_part"):
# #                 parts.append(
# #                     SystemPromptPart(
# #                         content=part.system_prompt_part.content,
# #                         part_kind="system-prompt",
# #                     )
# #                 )
# #             elif part.HasField("user_prompt_part"):
# #                 parts.append(
# #                     UserPromptPart(
# #                         content=part.user_prompt_part.content,
# #                         timestamp=datetime.fromtimestamp(part.user_prompt_part.timestamp),
# #                         part_kind="user-prompt",
# #                     )
# #                 )
# #             elif part.HasField("tool_return_part"):
# #                 parts.append(
# #                     ToolReturnPart(
# #                         tool_name=part.tool_return_part.tool_name,
# #                         content=json.loads(part.tool_return_part.content),
# #                         tool_call_id=part.tool_return_part.tool_call_id,
# #                         part_kind="tool-return",
# #                     )
# #                 )
# #             elif part.HasField("retry_prompt_part"):
# #                 parts.append(
# #                     RetryPromptPart(
# #                         content=part.retry_prompt_part.content,
# #                         tool_name=part.retry_prompt_part.tool_name,
# #                         tool_call_id=part.retry_prompt_part.tool_call_id,
# #                         part_kind="retry-prompt",
# #                     )
# #                 )
# #             elif part.HasField("text_part"):
# #                 parts.append(TextPart(content=part.text_part.content, part_kind="text"))
# #             elif part.HasField("tool_call_part"):
# #                 parts.append(
# #                     ToolCallPart(
# #                         tool_name=part.tool_call_part.tool_name,
# #                         args=part.tool_call_part.args,  # Assuming this is already a JSON string
# #                         tool_call_id=part.tool_call_part.tool_call_id,
# #                         part_kind="tool-call",
# #                     )
# #                 )

# #         kind = "request" if msg.kind == axon_pb2.ModelMessage.REQUEST else "response"

# #         if kind == "request":
# #             return ModelRequest(parts=parts, kind=kind)
# #         else:  # kind == 'response'
# #             return ModelResponse(parts=parts, timestamp=datetime.now(), kind=kind)

# #     def _convert_pydantic_ai_message_to_protobuf(self, msg: ModelMessage) -> axon_pb2.ModelMessage:
# #         """Convert a pydantic-ai ModelMessage to a gRPC ModelMessage."""
# #         parts = []
# #         for part in msg.parts:
# #             if isinstance(part, SystemPromptPart):
# #                 parts.append(axon_pb2.ModelMessagePart(system_prompt_part=axon_pb2.SystemPromptPart(content=part.content)))
# #             elif isinstance(part, UserPromptPart):
# #                 parts.append(
# #                     axon_pb2.ModelMessagePart(
# #                         user_prompt_part=axon_pb2.UserPromptPart(
# #                             content=part.content, timestamp=int(part.timestamp.timestamp())
# #                         )
# #                     )
# #                 )
# #             elif isinstance(part, ToolReturnPart):
# #                 parts.append(
# #                     axon_pb2.ModelMessagePart(
# #                         tool_return_part=axon_pb2.ToolReturnPart(
# #                             tool_name=part.tool_name,
# #                             content=json.dumps(part.content).encode("utf-8"),
# #                             tool_call_id=part.tool_call_id,
# #                         )
# #                     )
# #                 )
# #             elif isinstance(part, RetryPromptPart):
# #                 parts.append(
# #                     axon_pb2.ModelMessagePart(
# #                         retry_prompt_part=axon_pb2.RetryPromptPart(
# #                             content=part.content, tool_name=part.tool_name, tool_call_id=part.tool_call_id
# #                         )
# #                     )
# #                 )
# #             elif isinstance(part, TextPart):
# #                 parts.append(axon_pb2.ModelMessagePart(text_part=axon_pb2.TextPart(content=part.content)))
# #             elif isinstance(part, ToolCallPart):
# #                 parts.append(
# #                     axon_pb2.ModelMessagePart(
# #                         tool_call_part=axon_pb2.ToolCallPart(
# #                             tool_name=part.tool_name,
# #                             args=part.args.encode("utf-8"),  # Assuming args is a JSON string
# #                             tool_call_id=part.tool_call_id,
# #                         )
# #                     )
# #                 )

# #         kind = axon_pb2.ModelMessage.REQUEST if msg.kind == "request" else axon_pb2.ModelMessage.RESPONSE

# #         return axon_pb2.ModelMessage(kind=kind, parts=parts, timestamp=int(msg.timestamp.timestamp()))

# # ## FOR gRPC:
# # # def serve():
# # #     server = grpc.server(futures.ThreadPoolExecutor(max_workers=10))
# # #     axon_pb2_grpc.add_AgentServiceServicer_to_server(AgentServicer(agent_instances), server)
# # #     server.add_insecure_port(f"[::]:{os.environ.get('AXON_PYTHON_AGENT_PORT', '50051')}")
# # #     server.start()
# # #     server.wait_for_termination()

# # # if __name__ == "__main__":
# # #     serve()


# # # #### TODO: Generate Python gRPC Code:
# # # ```python
# # # python -m grpc_tools.protoc -I=./apps/axon_python/src/axon_python/protos --python_out=./apps/axon_python/src/axon_python/generated --pyi_out=./apps/axon_python/src/axon_python/generated --grpc_python_out=./apps/axon_python/src/axon_python/generated axon.proto
# # # ````







    

# # def start_fastapi(port: int):
# #     uvicorn.run(app, host="0.0.0.0", port=port)

# # if __name__ == "__main__":
# #      # Get port from environment variable or default to 8000
# #     port = int(os.environ.get("AXON_PYTHON_AGENT_PORT", 8000))
# #     start_fastapi(port=port)



























##################################### LATEST FOR GRPC

# import asyncio
# import grpc
# from concurrent import futures
# import ai_pb2
# import ai_pb2_grpc
# from pydantic import BaseModel
# from typing import List

# class PredictInput(BaseModel):
#     text: str
#     parameters: dict = {}

# class PredictOutput(BaseModel):
#     result: str
#     confidence: float

# class AIServicer(ai_pb2_grpc.AIServiceServicer):
#     async def Predict(self, request, context):
#         input_data = PredictInput(
#             text=request.input,
#             parameters=request.parameters
#         )
        
#         # Your AI logic here
#         result = await self.process_prediction(input_data)
        
#         return ai_pb2.PredictResponse(
#             output=result.result,
#             confidence=result.confidence
#         )

#     async def StreamPredict(self, request_iterator, context):
#         async for request in request_iterator:
#             input_data = PredictInput(
#                 text=request.input,
#                 parameters=request.parameters
#             )
            
#             result = await self.process_prediction(input_data)
            
#             yield ai_pb2.PredictResponse(
#                 output=result.result,
#                 confidence=result.confidence
#             )

#     async def process_prediction(self, input_data: PredictInput) -> PredictOutput:
#         # Simulate AI processing
#         await asyncio.sleep(0.1)
#         return PredictOutput(
#             result=f"Processed: {input_data.text}",
#             confidence=0.95
#         )

# async def serve():
#     server = grpc.aio.server(futures.ThreadPoolExecutor(max_workers=10))
#     ai_pb2_grpc.add_AIServiceServicer_to_server(AIServicer(), server)
#     server.add_insecure_port('[::]:50051')
#     await server.start()
#     await server.wait_for_termination()

# if __name__ == '__main__':
#     asyncio.run(serve())


