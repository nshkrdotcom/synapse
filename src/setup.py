from setuptools import setup, find_packages

setup(
    name="axon-core",
    version="0.1.0",
    packages=find_packages(),
    install_requires=[
        "fastapi>=0.104.1",
        "uvicorn>=0.24.0",
        "python-dotenv>=1.0.1",
        "pydantic>=2.10.4"
    ],
)
