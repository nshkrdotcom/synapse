#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.
set -u  # Treat unset variables as an error.
set -o pipefail # Exit if any command in a pipeline fails.

# Get the path to the poetry environment
#POETRY_ENV_PATH=$(poetry --file apps/axon_python/pyproject.toml env info --path)
#echo "Poetry Environment Path: $POETRY_ENV_PATH"

# Construct the full path to the activate script
#ACTIVATE_SCRIPT="$POETRY_ENV_PATH/bin/activate"
#echo "Activate Script Path: $ACTIVATE_SCRIPT"


# Source the activate script

# Get the agent module from arguments
VENV_PATH="$1"
AGENT_MODULE="$2"
PORT="$3"
MODEL="$4"
AGENT_ID="$5"


source "$VENV_PATH/bin/activate"


# Print the received arguments
echo "Agent Module: $AGENT_MODULE"
echo "Port: $PORT"
echo "Model: $MODEL"
echo "Agent ID: $AGENT_ID"

# Set environment variables for the agent
export AXON_PYTHON_AGENT_PORT="$PORT"
export AXON_PYTHON_AGENT_MODEL="$MODEL"
export AXON_PYTHON_AGENT_ID="$AGENT_ID"

# Print the environment variables
echo "AXON_PYTHON_AGENT_PORT: $AXON_PYTHON_AGENT_PORT"
echo "AXON_PYTHON_AGENT_MODEL: $AXON_PYTHON_AGENT_MODEL"
echo "AXON_PYTHON_AGENT_ID: $AXON_PYTHON_AGENT_ID"

# Construct the poetry command and echo it
#POETRY_COMMAND="poetry --file apps/axon_python/pyproject.toml  run uvicorn \"axon_python.agent_wrapper:app\" --agent-module \"$AGENT_MODULE\" --host \"0.0.0.0\" --port \"$PORT\" --log-level debug"
#echo "Executing Poetry Command: $POETRY_COMMAND"

# Start the FastAPI server using uvicorn with verbose logging
#eval "$POETRY_COMMAND"



# # Start the FastAPI server using uvicorn with verbose logging
# poetry run uvicorn "axon_python.agent_wrapper:app" --agent-module "$AGENT_MODULE" --host "0.0.0.0" --port "$PORT" --log-level debug
