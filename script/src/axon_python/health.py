# python/server/health.py
from typing import Optional
import asyncio
import logging
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)

class HealthManager:
    def __init__(self):
        self.last_request: Optional[datetime] = None
        self.request_count: int = 0
        self.error_count: int = 0
        self._reset_time = datetime.now()

    async def record_request(self):
        """Record a successful request"""
        self.last_request = datetime.now()
        self.request_count += 1

    async def record_error(self):
        """Record an error"""
        self.error_count += 1

    async def get_health_metrics(self):
        """Get current health metrics"""
        now = datetime.now()
        uptime = now - self._reset_time
        
        return {
            "status": "healthy" if self.error_count < 5 else "degraded",
            "uptime_seconds": uptime.total_seconds(),
            "last_request": self.last_request.isoformat() if self.last_request else None,
            "request_count": self.request_count,
            "error_count": self.error_count,
            "error_rate": self.error_count / self.request_count if self.request_count > 0 else 0
        }

    async def reset_metrics(self):
        """Reset all metrics"""
        self.last_request = None
        self.request_count = 0
        self.error_count = 0
        self._reset_time = datetime.now()

# Modify service.py to include health checks
class AIService(ai_pb2_grpc.AIServiceServicer):
    def __init__(self):
        super().__init__()
        self.health_manager = HealthManager()

    async def Predict(self, request, context):
        try:
            if request.input == "ping":
                return ai_pb2.PredictResponse(output="pong", confidence=1.0)

            await self.health_manager.record_request()
            result = await super().Predict(request, context)
            return result
        except Exception as e:
            await self.health_manager.record_error()
            raise

    async def GetHealth(self, request, context):
        metrics = await self.health_manager.get_health_metrics()
        return ai_pb2.HealthResponse(**metrics)

# Add to proto/ai.proto
"""
message HealthResponse {
    string status = 1;
    double uptime_seconds = 2;
    string last_request = 3;
    int32 request_count = 4;
    int32 error_count = 5;
    double error_rate = 6;
}

service AIService {
    // ... existing methods ...
    rpc GetHealth(google.protobuf.Empty) returns (HealthResponse);
}
"""