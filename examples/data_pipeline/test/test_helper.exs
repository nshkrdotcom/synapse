# Start application to ensure all supervisors are running
{:ok, _} = Application.ensure_all_started(:data_pipeline)

# Set test mode
Application.put_env(:data_pipeline, :use_mocks, true)
Application.put_env(:data_pipeline, :gemini_available, true)

ExUnit.start()
