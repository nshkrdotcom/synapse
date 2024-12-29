"""Tests for the pydantic-ai agent wrapper."""
import asyncio
import json
from typing import AsyncIterator, Dict

import pytest
from fastapi.testclient import TestClient
from pydantic_ai import Agent
from pydantic_ai.message import SystemPromptPart, TextPart, UserPromptPart

from axon_python.pydantic_agent_wrapper import (
    AgentConfig,
    AgentError,
    AgentNotFoundError,
    RunRequest,
    ToolCallRequest,
    app,
)

@pytest.fixture
def test_client():
    """Create a test client for the FastAPI app."""
    return TestClient(app)

@pytest.fixture
def agent_config():
    """Create a test agent configuration."""
    return AgentConfig(
        agent_id="test_agent",
        model="gemini-1.5-flash",  # Fast model for testing
        system_prompt="You are a test assistant.",
        tools=[{
            "name": "test_tool",
            "description": "A test tool",
            "parameters": {
                "type": "object",
                "properties": {
                    "input": {"type": "string"}
                },
                "required": ["input"]
            }
        }],
        result_type={
            "type": "object",
            "properties": {
                "output": {"type": "string"}
            }
        }
    )

@pytest.fixture
def run_request():
    """Create a test run request."""
    return RunRequest(
        prompt="Hello",
        message_history=[
            SystemPromptPart(content="You are a test assistant."),
            UserPromptPart(content="Hello"),
            TextPart(content="Hi there!")
        ],
        model_settings={},
        system_prompt="You are a test assistant.",
        tools=[],
        result_type=None
    )

@pytest.fixture
def tool_request():
    """Create a test tool call request."""
    return ToolCallRequest(
        tool_name="test_tool",
        args={"input": "test"}
    )

class TestAgentManagement:
    """Test agent management endpoints."""

    def test_create_agent(self, test_client, agent_config):
        """Test creating a new agent."""
        response = test_client.post("/agents", json=agent_config.model_dump())
        assert response.status_code == 200
        assert response.json()["status"] == "success"

    def test_create_duplicate_agent(self, test_client, agent_config):
        """Test creating a duplicate agent."""
        # Create first agent
        test_client.post("/agents", json=agent_config.model_dump())
        
        # Try to create duplicate
        response = test_client.post("/agents", json=agent_config.model_dump())
        assert response.status_code == 500

    def test_delete_agent(self, test_client, agent_config):
        """Test deleting an agent."""
        # Create agent first
        test_client.post("/agents", json=agent_config.model_dump())
        
        # Delete agent
        response = test_client.delete(f"/agents/{agent_config.agent_id}")
        assert response.status_code == 200
        assert response.json()["status"] == "success"

    def test_delete_nonexistent_agent(self, test_client):
        """Test deleting a nonexistent agent."""
        response = test_client.delete("/agents/nonexistent")
        assert response.status_code == 404

class TestAgentExecution:
    """Test agent execution endpoints."""

    def test_run_agent(self, test_client, agent_config, run_request):
        """Test running an agent synchronously."""
        # Create agent first
        test_client.post("/agents", json=agent_config.model_dump())
        
        # Run agent
        response = test_client.post(
            f"/run?agent_id={agent_config.agent_id}",
            json=run_request.model_dump()
        )
        assert response.status_code == 200
        data = response.json()
        assert "result" in data
        assert "messages" in data
        assert "usage" in data

    def test_run_nonexistent_agent(self, test_client, run_request):
        """Test running a nonexistent agent."""
        response = test_client.post(
            "/run?agent_id=nonexistent",
            json=run_request.model_dump()
        )
        assert response.status_code == 404

    def test_stream_agent(self, test_client, agent_config, run_request):
        """Test streaming agent responses."""
        # Create agent first
        test_client.post("/agents", json=agent_config.model_dump())
        
        # Stream responses
        with test_client.stream(
            "POST",
            f"/run/stream?agent_id={agent_config.agent_id}",
            json=run_request.model_dump()
        ) as response:
            assert response.status_code == 200
            chunks = []
            for line in response.iter_lines():
                if line:
                    # Parse SSE format
                    if line.startswith(b"data: "):
                        chunk = line[6:].decode()
                        if chunk == "[DONE]":
                            break
                        chunks.append(chunk)
            assert len(chunks) > 0

    def test_call_tool(self, test_client, agent_config, tool_request):
        """Test calling a tool."""
        # Create agent first
        test_client.post("/agents", json=agent_config.model_dump())
        
        # Call tool
        response = test_client.post(
            f"/tool_call?agent_id={agent_config.agent_id}",
            json=tool_request.model_dump()
        )
        assert response.status_code == 200
        assert "result" in response.json()

class TestErrorHandling:
    """Test error handling."""

    def test_validation_error(self, test_client):
        """Test handling of validation errors."""
        response = test_client.post("/agents", json={})
        assert response.status_code == 422

    def test_model_error(self, test_client, agent_config):
        """Test handling of model errors."""
        # Create agent with invalid model
        config = agent_config.model_dump()
        config["model"] = "invalid-model"
        response = test_client.post("/agents", json=config)
        assert response.status_code == 500

    def test_tool_error(self, test_client, agent_config, tool_request):
        """Test handling of tool errors."""
        # Create agent first
        test_client.post("/agents", json=agent_config.model_dump())
        
        # Call nonexistent tool
        request = tool_request.model_dump()
        request["tool_name"] = "nonexistent"
        response = test_client.post(
            f"/tool_call?agent_id={agent_config.agent_id}",
            json=request
        )
        assert response.status_code == 500
