# Testing initiall

Before running the test, ensure that the Python environment is set up correctly, and the AXON_PYTHON_AGENT_PORT environment variable is set if needed. You can then run the test using:

```
mix test test/axon_core/agent_process_test.exs
```



Running the Test:

Make sure your pydantic-ai environment is set up and your example_agent.py is in the correct directory.

Ensure that the start_agent.sh script is executable (chmod +x start_agent.sh).

Run mix test in the axon directory.

This test will:

Start an AgentProcess.

Mock HTTPClient.post to simulate a successful response from a Python agent.

Send a run_sync request to the agent.

Verify that the agent process correctly sends the request, receives the response, and replies with the result and usage.