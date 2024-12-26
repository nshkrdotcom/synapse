# Simplified example
from openai import OpenAI

def get_completion(model: str, messages: list, tools: list | None = None) -> str:
    client = OpenAI() # Or get from env, etc.
    response = client.chat.completions.create(
        model=model,
        messages=messages,
        tools=tools,
    )
    return response.choices[0].message.content
