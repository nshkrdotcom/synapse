import Config

# Configure providers (set via environment variables in production)
config :data_pipeline,
  gemini_api_key: System.get_env("GEMINI_API_KEY"),
  gemini_available: !is_nil(System.get_env("GEMINI_API_KEY"))

# Configure batch processing
config :data_pipeline, DataPipeline.Batch,
  default_batch_size: 100,
  max_parallel_batches: 10
