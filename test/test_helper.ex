# test/test_helper.exs
ExUnit.start()
# Setup Mox
Mox.defmock(SynapseCore.HTTPClientMock, for: SynapseCore.HTTPClient)

# Ensure the application is started
Application.ensure_all_started(:synapse)

# Ensure agents are started
# Agent.start_link(
#  python_module: "agents.example_agent",
#  model: "openai:gpt-4o",
#  name: "python_agent_1"
# )

# Agent.start_link(
#  python_module: "agents.bank_support_agent",
#  model: "openai:gpt-4o",
#  name: "python_agent_2"
# )
