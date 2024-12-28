import asyncio
import grpc
import ai_pb2
import ai_pb2_grpc

async def test_unary():
    async with grpc.aio.insecure_channel('localhost:50051') as channel:
        stub = ai_pb2_grpc.AIServiceStub(channel)
        
        request = ai_pb2.PredictRequest(
            input="Hello, World!",
            parameters={"uppercase": "true"}
        )
        
        response = await stub.Predict(request)
        print(f"Unary response: {response.output} (confidence: {response.confidence})")

async def test_streaming():
    async with grpc.aio.insecure_channel('localhost:50051') as channel:
        stub = ai_pb2_grpc.AIServiceStub(channel)
        
        async def request_generator():
            messages = ["Hello", "World", "Test", "Stream"]
            for msg in messages:
                yield ai_pb2.PredictRequest(
                    input=msg,
                    parameters={"uppercase": "true"}
                )
        
        async for response in stub.StreamPredict(request_generator()):
            print(f"Stream response: {response.output} (confidence: {response.confidence})")

if __name__ == "__main__":
    asyncio.run(test_unary())
    asyncio.run(test_streaming())



    
# ```

# File structure:
# ```
# python/
# ├── server/
# │   ├── __init__.py
# │   ├── service.py
# │   └── main.py
# ├── client/
# │   ├── __init__.py
# │   └── test_client.py
# └── proto/
#     ├── ai_pb2.py       # Generated
#     └── ai_pb2_grpc.py  # Generated
# ```

# Key features:

# 1. **Async Implementation**:
#    - Uses `asyncio` and `grpc.aio` for async handling
#    - Non-blocking request processing
#    - Proper error handling with context aborts

# 2. **Type Safety**:
#    - Pydantic models for request/response validation
#    - Clear typing with Python type hints
#    - Structured error handling

# 3. **Streaming Support**:
#    - Handles both unary and streaming requests
#    - Proper async iteration over stream
#    - Generator-based stream handling

# 4. **Production Features**:
#    - Configurable message sizes
#    - Multi-worker thread pool
#    - Graceful shutdown
#    - Comprehensive logging

# 5. **Testing**:
#    - Included test client
#    - Examples for both unary and streaming calls

# To generate the proto files:
# ```bash
# python -m grpc_tools.protoc -I./proto --python_out=./python --grpc_python_out=./python ./proto/ai.proto
# ```

# Dependencies (requirements.txt):
# ```
# grpcio==1.59.0
# grpcio-tools==1.59.0
# pydantic==2.4.2
# ```

# This Python implementation pairs with the Elixir code we discussed earlier, providing a complete system for both unary and streaming gRPC communication. Let me know if you need any clarification or have questions about specific parts!