ExUnit.start()

# Define mocks for the SDKs
Mox.defmock(CodingAgent.Mocks.ClaudeSDK, for: CodingAgent.Providers.Behaviour)
Mox.defmock(CodingAgent.Mocks.CodexSDK, for: CodingAgent.Providers.Behaviour)
Mox.defmock(CodingAgent.Mocks.GeminiSDK, for: CodingAgent.Providers.Behaviour)
