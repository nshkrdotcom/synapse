# # Simplified example
# from openai import OpenAI

# def get_completion(model: str, messages: list, tools: list | None = None) -> str:
#     client = OpenAI() # Or get from env, etc.
#     response = client.chat.completions.create(
#         model=model,
#         messages=messages,
#         tools=tools,
#     )
#     return response.choices[0].message.content




from openai import AsyncOpenAI

async def get_completion(model: str, messages: list, tools: list | None = None):
    client = AsyncOpenAI()  # Or configure based on environment variables
    response = await client.chat.completions.create(
        model=model,
        messages=messages,
        tools=tools,
    )
    return response.choices[0].message.content

async def get_streamed_completion(model: str, messages: list, tools: list | None = None):
    client = AsyncOpenAI()
    stream = await client.chat.completions.create(
        model=model,
        messages=messages,
        tools=tools,
        stream=True,
    )
    async for chunk in stream:
        yield chunk.choices[0].delta.content or ""