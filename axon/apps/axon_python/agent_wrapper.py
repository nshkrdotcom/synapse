from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, ValidationError

# Import your pydantic-ai agent code here

app = FastAPI()
agent = MyAgent(model="openai:gpt-4o")  # Instantiate your agent

# Load the appropriate agent based on configuration
# You might need a way to select different agents based on the agent's name or other identifiers
# ...

class Input(BaseModel):
    prompt: str

class Output(BaseModel):
    response: str

@app.post("/run")
async def run_agent(input_data: Input):
    try:
        result = agent.run_sync(input_data.prompt)
        return Output(response=result.data)
    except ValidationError as e:
        raise HTTPException(status_code=400, detail=e.errors())
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/run")
async def run_agent_2(request_data: dict):
    result = agent.run_sync(request_data["prompt"], **request_data)
    return {"data": result.data}