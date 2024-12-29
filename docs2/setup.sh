#!/bin/bash

# Fail on any error
set -e

echo "Setting up Axon development environment..."

# Check Elixir installation
if ! command -v elixir >/dev/null 2>&1; then
    echo "Error: Elixir is not installed"
    exit 1
fi

# Check minimum Elixir version
ELIXIR_VERSION=$(elixir --version | head -n 1 | cut -d ' ' -f 2)
MIN_ELIXIR_VERSION="1.14.0"
if ! printf '%s\n%s\n' "$MIN_ELIXIR_VERSION" "$ELIXIR_VERSION" | sort -V -C; then
    echo "Error: Elixir version must be >= $MIN_ELIXIR_VERSION"
    exit 1
fi

# Check Python3 installation
if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: Python3 is not installed"
    exit 1
fi

# Check minimum Python version
PYTHON_VERSION=$(python3 --version | cut -d ' ' -f 2)
MIN_PYTHON_VERSION="3.10.0"
if ! printf '%s\n%s\n' "$MIN_PYTHON_VERSION" "$PYTHON_VERSION" | sort -V -C; then
    echo "Error: Python version must be >= $MIN_PYTHON_VERSION"
    exit 1
fi

# Install Python venv if not present
if ! python3 -c "import venv" >/dev/null 2>&1; then
    echo "Installing Python venv..."
    sudo apt-get update
    sudo apt-get install -y python3-venv
fi

# Fetch Elixir dependencies
echo "Fetching Elixir dependencies..."
mix deps.get

# Compile Elixir project
echo "Compiling Elixir project..."
mix compile

echo "Setup completed successfully!"
echo "Run 'iex -S mix' to start the application."
