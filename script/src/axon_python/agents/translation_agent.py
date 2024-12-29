"""
Example translation agent implementation using pydantic-ai.
Demonstrates basic agent setup, tool usage, and structured output.
"""
from typing import Dict, List, Optional

from pydantic import BaseModel, Field
from pydantic_ai import Agent

# Models for structured output
class TranslationResult(BaseModel):
    """Result from translation agent."""
    translated_text: str = Field(description="The translated text")
    source_language: str = Field(description="Detected or specified source language")
    target_language: str = Field(description="The target language")
    confidence: float = Field(
        description="Confidence score of the translation",
        ge=0.0,
        le=1.0
    )
    alternatives: Optional[List[str]] = Field(
        default=None,
        description="Alternative translations if available"
    )

# Tool implementations
async def detect_language(text: str) -> Dict[str, str]:
    """
    Detects the language of the input text.
    In a real implementation, this would use a language detection service.
    """
    # Mock implementation
    return {"detected_language": "en"}

async def get_language_name(code: str) -> str:
    """
    Gets the full name of a language from its code.
    """
    # Mock implementation - would use a proper language code mapping
    language_names = {
        "en": "English",
        "es": "Spanish",
        "fr": "French",
        "de": "German",
        "it": "Italian",
        "pt": "Portuguese",
        "ru": "Russian",
        "ja": "Japanese",
        "ko": "Korean",
        "zh": "Chinese"
    }
    return language_names.get(code.lower(), code)

# Create the agent
translation_agent = Agent(
    "gemini-1.5-pro",  # Using Gemini for better multilingual support
    system_prompt="""You are a professional translator. 
    Your task is to translate text between different languages accurately and naturally.
    Consider cultural context and idiomatic expressions in your translations.
    If unsure about any part of the translation, provide alternatives.""",
    tools=[
        {
            "name": "detect_language",
            "description": "Detects the language of the input text",
            "parameters": {
                "type": "object",
                "properties": {
                    "text": {"type": "string"}
                },
                "required": ["text"]
            },
            "handler": detect_language
        },
        {
            "name": "get_language_name",
            "description": "Gets the full name of a language from its code",
            "parameters": {
                "type": "object",
                "properties": {
                    "code": {"type": "string"}
                },
                "required": ["code"]
            },
            "handler": get_language_name
        }
    ],
    result_type=TranslationResult
)

# Example usage:
"""
result = await translation_agent.run(
    "Translate this to Spanish: Hello, how are you?"
)
print(result.data)
# TranslationResult(
#     translated_text="¡Hola, ¿cómo estás?",
#     source_language="English",
#     target_language="Spanish",
#     confidence=0.95,
#     alternatives=["¡Hola, ¿cómo está usted?"]
# )
"""
