# # axon_python/src/axon_python/agents/example_agent.py
# from pydantic import BaseModel

# from pydantic_ai import Agent

# class Output(BaseModel):
#     response: str

# agent = Agent(
#     model="openai:gpt-4o",
#     result_type=Output,
#     system_prompt="You are a helpful assistant that answers in JSON format.",
# )
 
# def some_tool(arg1: str, arg2: int) -> str:
#     return f"Tool executed with arg1: {arg1}, arg2: {arg2}"

# agent.tools = [some_tool]



import json
import os
from typing import Union, AsyncIterator
from datetime import datetime

import uvicorn
from fastapi import FastAPI
from fastapi.responses import HTMLResponse, JSONResponse, PlainTextResponse, StreamingResponse
from pydantic import BaseModel, Field

from pydantic_ai import Agent

# agent which constrained to only return text
chat_agent = Agent(
    'gemini-1.5-flash', 
    # result_type=Output,
    system_prompt="""
"You are a helpful assistant that responds in JSON format. You are running within an agent process in the Axon framework.",
""",
    temperature=0.0
)

app = FastAPI(title='pydantic-ai chat app example')
# dictionary to store chat histories, in a real application this would be a database
chat_histories: dict[int, ChatHistory] = {}
# for demo simplicity we use a simple incrementing integer, in a real application this would be a UUID
next_chat_id = 1

@app.get('/', response_class=HTMLResponse)
async def index():
    """Serve the index page."""
    return """
<!DOCTYPE html>
<html>
<head>
    <title>Chat</title>
    <script src="https://cdn.tailwindcss.com"></script>
</head>
<body class="bg-gray-100">
    <div class="container mx-auto p-4">
        <h1 class="text-2xl mb-4">Chat</h1>
        <div id="chat-history" class="mb-4 overflow-y-auto h-64 border border-gray-300 p-4 bg-white rounded">
            <!-- Chat messages will be appended here -->
        </div>
        <div class="mb-4">
            <label for="chat-id" class="block mb-2">Chat ID:</label>
            <select id="chat-id" class="w-full border border-gray-300 p-2 rounded">
                <!-- Existing chat IDs will be loaded here -->
            </select>
            <button id="new-chat" class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded">
                New Chat
            </button>
        </div>
        <div class="mb-4">
            <label for="message" class="block mb-2">Message:</label>
            <input type="text" id="message" class="w-full border border-gray-300 p-2 rounded" />
        </div>
        <button id="send" class="bg-blue-500 hover:bg-blue-700 text-white font-bold py-2 px-4 rounded">
            Send
        </button>
    </div>
    <script>
        const chatHistoryDiv = document.getElementById('chat-history');
        const chatIdSelect = document.getElementById('chat-id');
        const messageInput = document.getElementById('message');
        const sendButton = document.getElementById('send');
        const newChatButton = document.getElementById('new-chat');

        function addMessageToChatHistory(message, role) {
            const messageDiv = document.createElement('div');
            messageDiv.classList.add('mb-2');
            messageDiv.textContent = `${role}: ${message}`;
            chatHistoryDiv.appendChild(messageDiv);
            chatHistoryDiv.scrollTop = chatHistoryDiv.scrollHeight;
        }

        async function loadChatIds() {
            const response = await fetch('/chats');
            const data = await response.json();
            data.forEach(chatId => {
                const option = document.createElement('option');
                option.value = chatId;
                option.textContent = chatId;
                chatIdSelect.appendChild(option);
            });
        }

        async function sendMessage() {
            const chatId = chatIdSelect.value;
            const message = messageInput.value;
            addMessageToChatHistory(message, 'User');
            messageInput.value = '';

            const response = await fetch(`/chat/${chatId}`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ prompt: message })
            });

            if (response.ok) {
                const reader = response.body.getReader();
                const decoder = new TextDecoder();
                let done = false;
                while (!done) {
                    const { value, done: readerDone } = await reader.read();
                    done = readerDone;
                    if (value) {
                        const chunk = decoder.decode(value);
                        addMessageToChatHistory(chunk, 'Assistant');
                    }
                }
            } else {
                console.error('Failed to send message');
            }
        }

        sendButton.addEventListener('click', sendMessage);
        messageInput.addEventListener('keydown', (event) => {
            if (event.key === 'Enter') {
                sendMessage();
            }
        });

        newChatButton.addEventListener('click', async () => {
            const response = await fetch('/new_chat', { method: 'POST' });
            const data = await response.json();
            const option = document.createElement('option');
            option.value = data.chat_id;
            option.textContent = data.chat_id;
            chatIdSelect.appendChild(option);
            chatIdSelect.value = data.chat_id;
            chatHistoryDiv.innerHTML = '';
        });

        loadChatIds();
    </script>
</body>
</html>
    """

@app.get('/chats')
async def get_chats() -> JSONResponse:
    """Get all chat IDs."""
    return JSONResponse(content=list(chat_histories.keys()))

@app.post('/new_chat')
async def new_chat() -> JSONResponse:
    """Create a new chat."""
    global next_chat_id
    chat_id = next_chat_id
    next_chat_id += 1
    chat_histories[chat_id] = ChatHistory()
    return JSONResponse(content={'chat_id': chat_id})

@app.post('/chat/{chat_id}')
async def chat(chat_id: int, request: Union[dict, list]) -> StreamingResponse:
    """
    Run a chat with the given chat ID.

    The request body can either be the prompt (for a new message), or a list of messages (to set the chat history).
    """
    chat_history = chat_histories.get(chat_id)
    if chat_history is None:
        return PlainTextResponse('Chat not found', status_code=404)

    # check if request is a list of messages and set the chat history if so
    if isinstance(request, list):
        chat_history.messages = [ChatMessage.model_validate(m) for m in request]
        return PlainTextResponse('Chat history set')

    prompt: str = request.get('prompt')

    async def run_and_stream() -> AsyncIterator[str]:
        async for message in run_chat_stream(chat_history, prompt):
            yield message

    return StreamingResponse(run_and_stream(), media_type='text/plain')

async def run_chat_stream(chat_history: ChatHistory, prompt: str) -> AsyncIterator[str]:
    """Run a chat and stream the response."""
    async with chat_agent.run_stream(
        prompt, message_history=[m.model_dump(mode='json') for m in chat_history.messages]
    ) as result:
        async for text in result.stream_text():
            yield text
        final_result = await result.get_data()

    print(f'history: {result.all_messages_json(indent=2)}')
    chat_history.messages.append(ChatMessage(role='user', content=prompt))
    chat_history.messages.append(ChatMessage(role='assistant', content=final_result))




def some_tool(arg1: str, arg2: int) -> str:
    return f"Tool executed with arg1: {arg1}, arg2: {arg2}"




if __name__ == '__main__':
    uvicorn.run(app, host='0.0.0.0', port=8000)