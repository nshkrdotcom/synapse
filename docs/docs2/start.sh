#!/bin/bash

# # Start the Elixir application
# (cd apps/synapse && iex -S mix phx.server) &

# # Start a Python agent in the background, passing the agent module as an argument
# (cd apps/synapse_python && poetry run python ./scripts/start_agent.sh example_agent 8000 "openai:gpt-4o") &

# # You can start more agents here if needed
# # ...

# # Keep the script running (optional, depends on your setup)
# wait



#!/bin/bash

# Start the Elixir application in interactive mode
# (cd apps/synapse && iex -S mix phx.server) & # remove this line from old start.sh

# Start the Elixir application in the background
(cd apps/synapse && mix phx.server) &

# Wait for the Elixir application to fully start
# This can be improved by checking if the server is actually listening on the expected port
sleep 5

# Now we will change the directory to where our Python project is
cd apps/synapse_python || exit

# It's a good practice to ensure that the virtual environment is activated
# shellcheck disable=SC1091
source ../../.venv/bin/activate

# Assuming the Python project has a setup.py or requirements.txt, install the dependencies
python -m pip install -e .

# Start a Python agent in the background, passing the agent module, port, and model as arguments
# Here we are assuming that start_agent.sh is executable and in the current directory
# Note: Removed the background execution (&) to keep the script simple for demonstration
# Adjust the python command and the module path as necessary for your project structure
python -u -m synapse_python.agent_wrapper example_agent 8000 "openai:gpt-4o"

# If you need to start more agents, you can add more lines similar to the above

# Keep the script running (optional, depends on your setup)
# You can use 'wait' to wait for all background processes, but since we removed '&', this is not necessary