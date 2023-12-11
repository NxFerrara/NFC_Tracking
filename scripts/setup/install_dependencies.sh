#!/bin/bash

assert_conditions() {
    # Root check
    if [ "$(id -u)" -ne 0 ]; then
        echo "This script must be run as root. Please use sudo."
        exit 1
    fi

    if [ -z "$PROJECT_PATH" ]; then
        echo "Required environment variable PROJECT_PATH is not set."
        exit 1
    fi

    if [ ! -d "$PROJECT_PATH/venv" ]; then
        echo "Virtual environment not found at $PROJECT_PATH/venv. Please create it before running this script."
        exit 1
    fi
}

install_python_packages() {
    local py_req_file="$PROJECT_PATH/requirements.txt"
    if [ -f "$py_req_file" ]; then
        echo "Installing Python packages..."
        "$PROJECT_PATH/venv/bin/pip3" install -r "$py_req_file" || { echo "Failed to install Python packages"; return 1; }
    else
        echo "Python requirements file not found: $py_req_file"
        return 1
    fi
}

main() {
    assert_conditions
    install_python_packages || exit 1
    echo "All packages installed successfully."
}

main
