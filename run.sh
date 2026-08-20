#!/bin/bash

# run.sh - Script to run Rayls documentation locally
# Works on macOS and Linux

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Parse command line arguments
USE_VERSIONED=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --versioned|-v)
            USE_VERSIONED=true
            shift
            ;;
        *)
            shift
            ;;
    esac
done

print_info "Starting Rayls documentation server..."
echo ""

# Check if Python is installed
print_info "Checking for Python installation..."
if command -v python3 &> /dev/null; then
    PYTHON_CMD="python3"
    PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
    print_success "Python found: $PYTHON_VERSION"
elif command -v python &> /dev/null; then
    PYTHON_CMD="python"
    PYTHON_VERSION=$(python --version 2>&1 | awk '{print $2}')
    # Check if it's Python 3
    if [[ $PYTHON_VERSION == 3.* ]]; then
        print_success "Python found: $PYTHON_VERSION"
    else
        print_error "Python 3 is required, but found Python $PYTHON_VERSION"
        echo "Please install Python 3.8 or higher"
        exit 1
    fi
else
    print_error "Python is not installed!"
    echo ""
    echo "Please install Python 3.8 or higher:"
    echo "  macOS: brew install python3"
    echo "  Ubuntu/Debian: sudo apt-get install python3 python3-pip python3-venv"
    echo "  CentOS/RHEL: sudo yum install python3 python3-pip"
    exit 1
fi

# Check Python version is 3.8+
PYTHON_MAJOR=$($PYTHON_CMD -c 'import sys; print(sys.version_info.major)')
PYTHON_MINOR=$($PYTHON_CMD -c 'import sys; print(sys.version_info.minor)')

if [ "$PYTHON_MAJOR" -lt 3 ] || ([ "$PYTHON_MAJOR" -eq 3 ] && [ "$PYTHON_MINOR" -lt 8 ]); then
    print_error "Python 3.8 or higher is required (found $PYTHON_VERSION)"
    exit 1
fi

# Check if pip is installed
print_info "Checking for pip installation..."
if command -v pip3 &> /dev/null; then
    PIP_CMD="pip3"
    print_success "pip3 found"
elif command -v pip &> /dev/null; then
    PIP_CMD="pip"
    print_success "pip found"
else
    print_error "pip is not installed!"
    echo ""
    echo "Please install pip:"
    echo "  macOS: python3 -m ensurepip --upgrade"
    echo "  Ubuntu/Debian: sudo apt-get install python3-pip"
    echo "  CentOS/RHEL: sudo yum install python3-pip"
    exit 1
fi

# Check if virtual environment exists
VENV_DIR="venv"
if [ ! -d "$VENV_DIR" ]; then
    print_info "Virtual environment not found. Creating..."

    # Check if venv module is available
    if ! $PYTHON_CMD -m venv --help &> /dev/null; then
        print_error "Python venv module is not available!"
        echo ""
        echo "Please install python3-venv:"
        echo "  Ubuntu/Debian: sudo apt-get install python3-venv"
        echo "  CentOS/RHEL: sudo yum install python3-venv"
        exit 1
    fi

    $PYTHON_CMD -m venv "$VENV_DIR"
    print_success "Virtual environment created"
else
    print_info "Virtual environment already exists"
fi

# Activate virtual environment
print_info "Activating virtual environment..."
if [ -f "$VENV_DIR/bin/activate" ]; then
    source "$VENV_DIR/bin/activate"
    print_success "Virtual environment activated"
elif [ -f "$VENV_DIR/Scripts/activate" ]; then
    # Windows Git Bash
    source "$VENV_DIR/Scripts/activate"
    print_success "Virtual environment activated"
else
    print_error "Could not find activation script!"
    exit 1
fi

# Upgrade pip in virtual environment
print_info "Upgrading pip..."
$PYTHON_CMD -m pip install --upgrade pip --quiet
print_success "pip upgraded"

# Install/upgrade required packages
print_info "Installing/upgrading required packages..."
echo ""

if [ -f "requirements.txt" ]; then
    $PYTHON_CMD -m pip install --upgrade -r requirements.txt --quiet
else
    print_error "requirements.txt not found!"
    exit 1
fi

print_success "All packages installed"
echo ""

# Check if mkdocs.yml exists
if [ ! -f "mkdocs.yml" ]; then
    print_error "mkdocs.yml not found in current directory!"
    print_error "Please run this script from the rayls-docs directory"
    exit 1
fi

# Display system info
print_info "System Information:"
echo "  OS: $(uname -s)"
echo "  Python: $PYTHON_VERSION"
echo "  MkDocs: $(mkdocs --version | head -n 1)"
echo ""

# Run mkdocs serve
print_success "Starting MkDocs development server..."
echo ""
print_info "Documentation will be available at: ${GREEN}http://127.0.0.1:8000${NC}"
print_info "Press ${YELLOW}Ctrl+C${NC} to stop the server"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Run server based on mode
if [ "$USE_VERSIONED" = true ]; then
    print_info "Running with versioning enabled (mike serve)"
    print_warning "Note: Live reload not available in versioned mode"
    echo ""
    mike serve --dev-addr=127.0.0.1:8000
else
    # Run mkdocs serve with auto-reload
    mkdocs serve --dev-addr=127.0.0.1:8000 --livereload --watch-theme
fi

# This will only run if mkdocs serve is stopped
echo ""
print_info "Documentation server stopped"

# Deactivate virtual environment
deactivate 2>/dev/null || true
