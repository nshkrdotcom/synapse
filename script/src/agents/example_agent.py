from typing import Dict, Any
from pydantic import BaseModel

class ExampleAgent(BaseModel):
    model: str = "default"

    async def run_sync(self, message: str, **kwargs) -> Dict[str, Any]:
        return {"response": f"Echo: {message}"}

agent = ExampleAgent()
