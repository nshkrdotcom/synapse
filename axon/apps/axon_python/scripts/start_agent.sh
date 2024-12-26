#!/bin/bash

# Activate the virtual environment
# shellcheck disable=SC1091
source ../../.venv/bin/activate

# Get the agent module from arguments
AGENT_MODULE="$1"
PORT="$2"
MODEL="$3"

# Set environment variables for the agent
export AXON_PYTHON_AGENT_PORT="$PORT"
export AXON_PYTHON_AGENT_MODEL="$MODEL"

# Start the FastAPI server
python -m uvicorn "axon_python.agent_wrapper:app" --host 0.0.0.0 --port "$PORT"