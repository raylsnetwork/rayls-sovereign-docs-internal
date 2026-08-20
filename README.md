<div align="center">

# Rayls Documentation

**The official documentation for Rayls — privacy-preserving cross-chain infrastructure. Built with [Material for MkDocs](https://squidfunk.github.io/mkdocs-material/).**

[![License: Apache 2.0][license-badge]][license-url]
[![Docs][docs-badge]][docs-url]

[![Discord][discord-badge]][discord-url]
[![X][x-badge]][x-url]
[![LinkedIn][linkedin-badge]][linkedin-url]
[![YouTube][youtube-badge]][youtube-url]

[Read the docs](https://docs.rayls.io) | [Build & serve](#building-the-documentation) | [Versioning](#documentation-versioning)

</div>

## Overview

This repository contains the complete documentation for:
- **Rayls Privacy Node** - Private blockchain infrastructure for financial institutions
- **Private Network Hub** - Hub architecture for connecting privacy nodes
- **Relayer** - Cross-chain communication and message relay
- **Governance** - Auditing and oversight system

## Documentation Structure

- **Learn** - Conceptual and educational content about Rayls architecture and protocols
- **Build** - Practical guides, tutorials, and API references
- **Resources** - Glossary, FAQ, and additional resources

## Building the Documentation

### Quick Start (Recommended)

The easiest way to run the documentation locally is using the provided script:

```bash
# Make the script executable (first time only)
chmod +x run.sh

# Run the documentation server
./run.sh
```

The script will:
- ✅ Check if Python 3.8+ is installed
- ✅ Check if pip is installed
- ✅ Create a virtual environment (if needed)
- ✅ Install all required dependencies
- ✅ Start the MkDocs development server

The documentation will be available at `http://127.0.0.1:8000`

Press `Ctrl+C` to stop the server.

### Manual Setup

If you prefer to set up manually:

#### Prerequisites

```bash
# Install Python 3.8 or higher
# macOS: brew install python3
# Ubuntu/Debian: sudo apt-get install python3 python3-pip python3-venv
# CentOS/RHEL: sudo yum install python3 python3-pip
```

#### Installation

```bash
# Create virtual environment
python3 -m venv venv

# Activate virtual environment
source venv/bin/activate  # On macOS/Linux
# OR
venv\Scripts\activate     # On Windows

# Install dependencies
pip install -r requirements.txt
```

#### Running

```bash
# Serve documentation locally
mkdocs serve

# Build static site
mkdocs build
```

The documentation will be available at `http://127.0.0.1:8000`

## Documentation Versioning

This project uses [mike](https://github.com/jimporter/mike) for documentation versioning. Mike allows maintaining multiple versions of documentation with a version selector dropdown.

### How It Works

- Each version branch (e.g., `version/2.6.0`, `version/2.6.1`) contains docs for that release
- `mike deploy` builds and stores docs in a local `gh-pages` branch
- `mike serve` serves all versions with a version dropdown
- You never edit the `gh-pages` branch directly - mike manages it

### Deploying a New Version

```bash
# 1. Checkout the version branch
git checkout version/2.6.1

# 2. Deploy that version's docs
source venv/bin/activate
mike deploy 2.6.1

# 3. (Optional) Set as latest/default
mike deploy 2.6.1 latest
mike set-default latest
```

### Viewing Versioned Docs Locally

```bash
# Using run.sh with --versioned flag
./run.sh --versioned

# Or directly with mike
source venv/bin/activate
mike serve
```

### Managing Versions

```bash
# List all versions
mike list

# Delete a version
mike delete 2.6.0

# Set default version (shown at root URL)
mike set-default 2.6.1
```

### Development vs Versioned Mode

| Mode | Command | Use Case |
|------|---------|----------|
| Development | `./run.sh` | Writing docs (live reload) |
| Versioned | `./run.sh --versioned` | Testing version dropdown |

## Contributing

We are not accepting external contributions at this time — see [CONTRIBUTING.md](./CONTRIBUTING.md). Please also read our [Code of Conduct](./CODE_OF_CONDUCT.md). When editing docs, use the official terminology from the [Glossary](docs/resources/glossary.md).

## Security

To report a security issue in the documentation, see [SECURITY.md](./SECURITY.md) — please do not open a public issue.

## License

Licensed under the Apache License, Version 2.0 — see [LICENSE](./LICENSE).

Copyright 2026 Rayls Core Ltd.

[license-badge]: https://img.shields.io/badge/License-Apache_2.0-blue.svg
[license-url]: ./LICENSE
[docs-badge]: https://img.shields.io/badge/docs-docs.rayls.io-blue
[docs-url]: https://docs.rayls.io
[discord-badge]: https://img.shields.io/badge/Discord-join%20chat-5865F2?logo=discord&logoColor=white
[discord-url]: https://discord.gg/6THZ96357r
[x-badge]: https://img.shields.io/badge/X-%40RaylsLabs-000000?logo=x&logoColor=white
[x-url]: https://x.com/RaylsLabs
[linkedin-badge]: https://img.shields.io/badge/LinkedIn-Rayls-0A66C2?logo=linkedin&logoColor=white
[linkedin-url]: https://www.linkedin.com/company/rayls/
[youtube-badge]: https://img.shields.io/badge/YouTube-Rayls-FF0000?logo=youtube&logoColor=white
[youtube-url]: https://www.youtube.com/@Rayls_blockchain
