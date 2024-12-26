#!/bin/bash

# Start the Elixir application
(cd apps/axon && iex -S mix phx.server) &

# Start a Python agent in the background, passing the agent module as an argument
(cd apps/axon_python && poetry run python ./scripts/start_agent.sh example_agent 8000 "openai:gpt-4o") &

# You can start more agents here if needed
# ...

# Keep the script running (optional, depends on your setup)
wait