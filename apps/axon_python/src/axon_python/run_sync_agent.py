import argparse
import asyncio
import grpc
from pydantic import BaseModel
from pydantic_ai import Agent
import json

# Import generated gRPC code
from .generated import axon_pb2, axon_pb2_grpc

# Example pydantic-ai agent
class Input(BaseModel):
    prompt: str

class Output(BaseModel):
    response: str

async def run_sync_agent(agent_config: dict, request_data: dict) -> dict:
    """Runs a pydantic-ai agent synchronously."""
    agent = Agent(
        model=agent_config["model"],
        system_prompt=agent_config["system_prompt"],
        result_type=Output,
        # ... other agent parameters ...
    )

    result = agent.run_sync(request_data["prompt"])

    return {
        "result": result.data.json(),
        "usage": result.usage.dict() if result.usage else None,
    }

class AgentService(axon_pb2_grpc.AgentServiceServicer):
    def __init__(self, agent_config):
        self.agent_config = agent_config

    async def RunSync(self, request, context):
        # Deserialize the request data
        request_data = {
            "prompt": request.prompt,
            "message_history": list(request.message_history),
            "model_settings": dict(request.model_settings),
        }

        # Run the agent synchronously
        result = await run_sync_agent(self.agent_config, request_data)

        # Convert the result to the appropriate gRPC response message
        return axon_pb2.RunResponse(
            result=result["result"],
            usage=axon_pb2.Usage(**result["usage"]) if result["usage"] else axon_pb2.Usage()
        )

async def serve(port: int, agent_config: dict):
    server = grpc.aio.server()
    axon_pb2_grpc.add_AgentServiceServicer_to_server(
        AgentService(agent_config), server
    )
    server.add_insecure_port(f"[::]:{port}")
    await server.start()
    await server.wait_for_termination()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Run a gRPC agent server.")
    parser.add_argument("--port", type=int, required=True, help="The port to run the server on.")
    parser.add_argument("--agent_config", type=str, required=True, help="JSON string of agent configuration.")
    args = parser.parse_args()

    # Load agent configuration from JSON string
    agent_config = json.loads(args.agent_config)

    asyncio.run(serve(args.port, agent_config))
