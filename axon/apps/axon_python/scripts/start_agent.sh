#!/bin/bash

# Activate the virtual environment using Poetry
# shellcheck disable=SC1091
source $(poetry env info --path)/bin/activate

# Get the agent module from arguments
AGENT_MODULE="$1"
PORT="$2"
MODEL="$3"

# Set environment variables for the agent
export AXON_PYTHON_AGENT_PORT="$PORT"
export AXON_PYTHON_AGENT_MODEL="$MODEL"

# Start the FastAPI server using uvicorn
poetry run uvicorn "axon_python.agent_wrapper:app" --host 0.0.0.0 --port "$PORT"