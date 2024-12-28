import asyncio
import grpc
import logging
from concurrent import futures
from typing import AsyncIterable, Dict, Optional
from pydantic import BaseModel

import ai_pb2
import ai_pb2_grpc

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class PredictionRequest(BaseModel):
    text: str
    parameters: Dict[str, str] = {}

class PredictionResponse(BaseModel):
    output: str
    confidence: float

class AIService(ai_pb2_grpc.AIServiceServicer):
    """
    gRPC service implementation for AI predictions.
    Handles both unary and streaming predictions.
    """
    
    async def Predict(
        self, 
        request: ai_pb2.PredictRequest, 
        context: grpc.aio.ServicerContext
    ) -> ai_pb2.PredictResponse:
        """Handle unary prediction requests"""
        try:
            # Validate input with Pydantic
            pred_request = PredictionRequest(
                text=request.input,
                parameters=dict(request.parameters)
            )
            
            # Process prediction
            result = await self._process_prediction(pred_request)
            
            return ai_pb2.PredictResponse(
                output=result.output,
                confidence=result.confidence
            )
            
        except Exception as e:
            logger.error(f"Error in Predict: {str(e)}")
            await context.abort(grpc.StatusCode.INTERNAL, str(e))

    async def StreamPredict(
        self,
        request_iterator: AsyncIterable[ai_pb2.PredictRequest],
        context: grpc.aio.ServicerContext
    ) -> AsyncIterable[ai_pb2.PredictResponse]:
        """Handle streaming prediction requests"""
        try:
            async for request in request_iterator:
                # Validate each request
                pred_request = PredictionRequest(
                    text=request.input,
                    parameters=dict(request.parameters)
                )
                
                # Process each prediction
                result = await self._process_prediction(pred_request)
                
                yield ai_pb2.PredictResponse(
                    output=result.output,
                    confidence=result.confidence
                )
                
        except Exception as e:
            logger.error(f"Error in StreamPredict: {str(e)}")
            await context.abort(grpc.StatusCode.INTERNAL, str(e))

    async def _process_prediction(
        self, 
        request: PredictionRequest
    ) -> PredictionResponse:
        """
        Process a single prediction request.
        This is where you'd implement your actual AI/ML logic.
        """
        # Simulate some async processing
        await asyncio.sleep(0.1)
        
        # Example processing logic
        processed_text = f"Processed: {request.text}"
        if "uppercase" in request.parameters:
            processed_text = processed_text.upper()
            
        return PredictionResponse(
            output=processed_text,
            confidence=0.95
        )

# python/server/main.py
async def serve(port: int = 50051) -> None:
    """Start the gRPC server"""
    server = grpc.aio.server(
        futures.ThreadPoolExecutor(max_workers=10),
        options=[
            ('grpc.max_send_message_length', 50 * 1024 * 1024),
            ('grpc.max_receive_message_length', 50 * 1024 * 1024)
        ]
    )
    
    ai_pb2_grpc.add_AIServiceServicer_to_server(AIService(), server)
    
    listen_addr = f'[::]:{port}'
    server.add_insecure_port(listen_addr)
    
    logger.info(f"Starting gRPC server on {listen_addr}")
    await server.start()
    
    try:
        await server.wait_for_termination()
    except KeyboardInterrupt:
        logger.info("Shutting down gRPC server...")
        await server.stop(5)

if __name__ == "__main__":
    asyncio.run(serve())








    
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