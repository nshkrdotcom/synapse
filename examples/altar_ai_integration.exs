# Synapse integration with Altar.AI (mocked).
#
# Run:
#   mix run examples/altar_ai_integration.exs

alias Altar.AI.Adapters.Mock
alias Altar.AI.Config
alias Altar.AI.Integrations.Synapse

config =
  Config.new()
  |> Config.add_profile(:mock, adapter: Mock.new())
  |> Map.put(:default_profile, :mock)

{:ok, response} = Synapse.chat_completion(%{prompt: "Say hello"}, config: config, profile: :mock)
IO.inspect(response, label: "Chat completion response")
