[
  # Ignore warnings from Jido dependency (macro-generated functions)
  ~r/deps\/jido\/lib\/jido\/agent\.ex:.*:unused_fun/,
  ~r/deps\/jido\/lib\/jido\/agent\.ex:.*:call/,

  # Our Jido.Agent-based modules: known spec mismatches due to upstream types
  {"lib/synapse/agents/critic_agent.ex", :callback_spec_arg_type_mismatch},
  {"lib/synapse/agents/critic_agent.ex", :invalid_contract},
  {"lib/synapse/agents/simple_executor.ex", :callback_spec_arg_type_mismatch},
  {"lib/synapse/agents/simple_executor.ex", :invalid_contract},
  {"lib/synapse/orchestrator/generic_agent.ex", :callback_spec_arg_type_mismatch},
  {"lib/synapse/orchestrator/generic_agent.ex", :invalid_contract}
]
