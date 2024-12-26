defp deps do
  [
    {:jason, "~> 1.2"},
    {:req, "~> 0.4"},
    {:gen_stage, "~> 1.2"},
    {:protobuf, "~> 0.11"},
    {:grpc, "~> 0.9.0"},
    {:protobuf_generate, "~> 0.4", only: :dev},
    {:mox, "~> 1.2.0", only: :dev},
    # Add other dependencies as needed
  ]
end
