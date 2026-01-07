ExUnit.start()

# Define mocks for testing
Mox.defmock(TestWriter.Providers.Mock, for: TestWriter.Providers.Behaviour)
