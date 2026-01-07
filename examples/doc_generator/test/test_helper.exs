ExUnit.start()

# Mock providers for testing
Mox.defmock(DocGenerator.Providers.MockClaude, for: DocGenerator.Providers.Behaviour)
Mox.defmock(DocGenerator.Providers.MockCodex, for: DocGenerator.Providers.Behaviour)
Mox.defmock(DocGenerator.Providers.MockGemini, for: DocGenerator.Providers.Behaviour)
