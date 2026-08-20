# Prerequisites

Before setting up your local Rayls development environment, ensure your system meets the requirements and has all necessary software installed.

## System Requirements

### Hardware

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **RAM** | 16GB (2 participants) | 24GB+ (6 participants) |
| **CPU** | Quad-core | Quad-core or better |
| **Disk Space** | 10GB free | 20GB+ free |

!!! note "Participant Scaling"
    Each additional Privacy Node participant increases memory requirements by approximately 1-2GB. For development with 6 participants, ensure you have at least 24GB RAM available for Docker.

### Operating Systems

The local development environment is supported on:

- **macOS** 11+ (Big Sur or later)
- **Linux** (Ubuntu 20.04+, Debian 11+, Fedora 35+, or equivalent)
- **Windows** 10/11 with WSL2 (Windows Subsystem for Linux 2)

!!! warning "Windows Users"
    Native Windows is not supported. You must use WSL2 with a Linux distribution (Ubuntu recommended). All commands should be run inside WSL2.

## Required Software

### 1. Docker Desktop

**Version:** 4.0.0 or later

Docker is required to run the local development environment, which includes Privacy Node Ledgers, Private Network Hub, and all Rayls services.

!!! tip "macOS Users: OrbStack Recommended"
    For macOS, we recommend [OrbStack](https://orbstack.dev) as a faster, lighter alternative to Docker Desktop. OrbStack provides better performance with lower resource usage while maintaining full Docker compatibility.

**Installation:**

- **macOS:** [OrbStack](https://orbstack.dev/download) (recommended) or [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- **Windows:** Download [Docker Desktop](https://www.docker.com/products/docker-desktop/)
- **Linux:** Install Docker Engine and Docker Compose V2:

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Verify installation
docker --version
docker compose version
```

**Configuration:**

!!! note "Resource Configuration"
    - **OrbStack (macOS):** Automatically manages resources - no manual configuration needed
    - **Docker Desktop:** Allocate sufficient resources in Settings → Resources:
        - **Memory:** Minimum 16GB (2 participants), recommended 24GB (6 participants)
        - **CPUs:** Minimum 4, recommended 4 or more
        - **Disk:** Minimum 10GB

**Verification:**

```bash
docker --version
# Expected: Docker version 24.0.0 or later

docker compose version
# Expected: Docker Compose version v2.20.0 or later
```

### 2. Git

**Version:** 2.30.0 or later

Git is required to clone the Rayls repositories.

**Installation:**

```bash
# macOS (via Homebrew)
brew install git

# Ubuntu/Debian
sudo apt-get install git

# Windows WSL2
sudo apt-get install git
```

**Verification:**

```bash
git --version
# Expected: git version 2.30.0 or later
```

### 3. Node.js and npm

**Version:** Node.js 18.0.0 or later, npm 9.0.0 or later

Node.js is required for smart contract development, compilation, and deployment.

**Installation:**

We recommend using [nvm (Node Version Manager)](https://github.com/nvm-sh/nvm):

```bash
# Install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash

# Restart your terminal, then install Node.js 18
nvm install 18
nvm use 18
nvm alias default 18
```

**Verification:**

```bash
node --version
# Expected: v18.0.0 or later

npm --version
# Expected: 9.0.0 or later
```

### 4. Go

**Version:** 1.21.0 or later

Go is required for relayer and backend service development.

**Installation:**

```bash
# macOS (via Homebrew)
brew install go

# Linux - download from golang.org
wget https://go.dev/dl/go1.21.0.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.21.0.linux-amd64.tar.gz

# Add to PATH (add to ~/.bashrc or ~/.zshrc)
export PATH=$PATH:/usr/local/go/bin
export PATH=$PATH:$(go env GOPATH)/bin
```

**Verification:**

```bash
go version
# Expected: go version go1.21.0 or later
```

### 5. Git LFS

**Version:** Latest

Git LFS (Large File Storage) is required for the rayls-sovereign-gnark-api repository, which stores large cryptographic key files (~526MB).

**Installation:**

```bash
# macOS (via Homebrew)
brew install git-lfs

# Ubuntu/Debian
sudo apt-get install git-lfs

# Fedora/RHEL
sudo yum install git-lfs
# or
sudo dnf install git-lfs

# Arch Linux
sudo pacman -S git-lfs
```

**Initialize Git LFS:**

```bash
git lfs install
```

**Verification:**

```bash
git lfs version
# Expected: git-lfs/3.x.x or later
```

## Optional Tools

### Visual Studio Code

**Recommended for:** Debugging and development

VS Code with the Go extension provides excellent debugging support for Rayls services, including the ability to attach to running Docker containers.

**Installation:**

1. Download [VS Code](https://code.visualstudio.com/)
2. Install the [Go extension](https://marketplace.visualstudio.com/items?itemName=golang.Go)

The Rayls repositories include pre-configured `.vscode/launch.json` files for debugging.

### MongoDB Compass

**Recommended for:** Database inspection

MongoDB Compass provides a GUI for inspecting the MongoDB databases used by relayers and services.

**Installation:**

Download [MongoDB Compass](https://www.mongodb.com/products/compass)

**Connection:**

Once the Docker environment is running, connect to:
```
mongodb://admin:admin@localhost:27017
```

## Repository Access

You need access to the following Rayls repositories:

1. **rayls-sovereign-contracts** - Smart contract suite
2. **rayls-sovereign-relayer** - Cross-chain relayer services
3. **axyl** - axyl-based Privacy Node Ledger (Rust, reth-based EVM)
4. **rayls-sovereign-pnh-governance** - Governance and audit services
5. **rayls-sovereign-backend** - User-facing API gateway
6. **rayls-sovereign-gnark-api** - Zero-knowledge proof generation service (uses Git LFS)

!!! info "Repository Access"
    Ensure you have appropriate credentials to access these repositories. Contact your team administrator if you encounter authentication issues.

!!! warning "Git LFS Required"
    The rayls-sovereign-gnark-api repository requires Git LFS for managing large binary files (cryptographic keys and verifier contracts, ~526MB total). Ensure Git LFS is installed and initialized before cloning this repository.

## Directory Structure Setup

All Rayls repositories should be cloned into a common parent directory. We recommend `~/work/parfin/`:

### Create Base Directory

```bash
mkdir -p ~/work/parfin
cd ~/work/parfin
```

### Clone Repositories

Clone all required repositories:

```bash
# Clone contracts
git clone <REPOSITORY_URL>/rayls-sovereign-contracts.git

# Clone relayer
git clone <REPOSITORY_URL>/rayls-sovereign-relayer.git

# Clone Privacy Node Ledger
git clone <REPOSITORY_URL>/rayls-sovereign-node.git

# Clone governance API
git clone <REPOSITORY_URL>/rayls-sovereign-pnh-governance.git

# Clone backend
git clone <REPOSITORY_URL>/rayls-sovereign-backend.git

# Clone gnark API
git clone <REPOSITORY_URL>/rayls-sovereign-gnark-api.git
```

!!! warning "Directory Structure"
    The Docker development environment expects this exact directory structure:
    ```
    parfin/
    ├── rayls-sovereign-contracts/
    ├── rayls-sovereign-relayer/
    ├── rayls-sovereign-node/
    ├── rayls-sovereign-pnh-governance/
    ├── rayls-sovereign-backend/
    └── rayls-sovereign-gnark-api/
    ```

    Do not rename directories or use alternative structures - the Docker Compose configuration uses relative paths.

### Verify Structure

```bash
ls ~/work/parfin
# Expected output:
# rayls-sovereign-backend  rayls-sovereign-contracts  rayls-sovereign-gnark-api
# rayls-sovereign-node  rayls-sovereign-pnh-governance  rayls-sovereign-relayer
```

## Zero-Knowledge Proof Service Setup

The rayls-sovereign-gnark-api service generates zero-knowledge proofs for the Enygma privacy protocol. It requires additional setup beyond a simple clone.

### Clone rayls-sovereign-gnark-api

```bash
cd ~/work/parfin

# Clone the repository
git clone <REPOSITORY_URL>/rayls-sovereign-gnark-api.git

cd rayls-sovereign-gnark-api
```

### Pull LFS Files

After cloning, pull the large binary files managed by Git LFS:

```bash
# Ensure Git LFS is initialized
git lfs install

# Pull LFS files (cryptographic keys and verifier contracts)
git lfs pull
```

This downloads approximately 526MB of files including:
- Proving keys (36 files, ~160MB total)
- Verification keys (36 files)
- Solidity verifier contracts (36 files)

### Install Go Dependencies

```bash
go mod download
```

### Compile Circuits and Generate Executables

Run the compilation script to generate circuit files and build the server:

```bash
./compile_circuits_gen_executables.sh
```

**What this script does:**

1. **Verifies Git LFS** - Auto-installs if missing (macOS/Linux)
2. **Compiles circuits** - Generates R1CS (constraint system) files for 18+ circuit types:
   - Enygma Transfer (K=2 through K=6)
   - Dvp Withdraw (K=2 through K=6)
   - Dvp Deposit (K=2 through K=6)
   - Enygma JoinSplit, ERC-721 Ownership, ERC-1155 JoinSplit
3. **Builds server binary** - Compiles the Go server executable

**Expected time:** 2-6 minutes (depends on CPU)

**Output:**

- `last_build/circuits/*.r1cs` - 18 constraint system files
- `last_build/executables/server` - Server binary

### Verify Compilation

Check that the compilation succeeded:

```bash
# Verify circuits were generated
ls -l last_build/circuits/*.r1cs | wc -l
# Expected: 18 files

# Verify server binary exists
ls -lh last_build/executables/server
# Expected: Binary file (~30-50MB)
```

### Test the Server (Optional)

You can verify the server starts correctly:

```bash
./run_gnark_server.sh
```

The server should start on port 3003. Press Ctrl+C to stop it.

!!! note "Docker Environment"
    When using the Docker development environment (covered in the next section), the rayls-sovereign-gnark-api service will be started automatically as `proofs-api` on port 3003. You don't need to run it manually.

### Troubleshooting rayls-sovereign-gnark-api

**Issue: Git LFS files not downloaded**

```bash
# Check LFS status
git lfs ls-files

# If files are missing, pull them
git lfs pull
git lfs fetch --all
git lfs checkout
```

**Issue: Compilation fails with "CGO not enabled"**

Ensure CGO is enabled:
```bash
export CGO_ENABLED=1
./compile_circuits_gen_executables.sh
```

**Issue: "go: missing go.sum entry"**

Update Go dependencies:
```bash
go mod tidy
go mod download
./compile_circuits_gen_executables.sh
```

**Issue: Slow compilation**

Circuit compilation is CPU-intensive. Ensure your system has:

- Multi-core CPU (quad-core or better, uses all cores via GOMAXPROCS)
- At least 8GB RAM available
- No other CPU-intensive processes running

## Hosts File Configuration

The Docker development environment uses service hostnames for inter-service communication. You need to add these hostnames to your system's hosts file to enable proper DNS resolution.

### Why This Is Required

Docker services reference each other by hostname (e.g., `mongodb`, `pl-a`, `commit-chain`). Adding these to your hosts file allows services and local development tools to resolve these names to `127.0.0.1` (localhost).

### Add Hosts Entries

**macOS / Linux:**

Edit the hosts file with elevated permissions:

```bash
sudo nano /etc/hosts
```

Or using vim:

```bash
sudo vim /etc/hosts
```

**Windows (WSL2):**

Edit the Windows hosts file:

```powershell
# Run PowerShell as Administrator, then:
notepad C:\Windows\System32\drivers\etc\hosts
```

### Required Host Mappings

Add the following entries to your hosts file:

```bash
# Rayls Docker Development Environment
127.0.0.1 mongodb
127.0.0.1 pl-a
127.0.0.1 pl-b
127.0.0.1 pl-c
127.0.0.1 pl-d
127.0.0.1 pl-e
127.0.0.1 pl-f
127.0.0.1 commit-chain
127.0.0.1 contracts
127.0.0.1 proofs-api
127.0.0.1 kos-a
127.0.0.1 kos-b
127.0.0.1 kos-c
127.0.0.1 kos-d
127.0.0.1 kos-e
127.0.0.1 kos-f
127.0.0.1 relayer-a
127.0.0.1 relayer-b
127.0.0.1 relayer-c
127.0.0.1 relayer-d
127.0.0.1 relayer-e
127.0.0.1 relayer-f
127.0.0.1 atomic-a
127.0.0.1 atomic-b
127.0.0.1 atomic-c
127.0.0.1 atomic-d
127.0.0.1 atomic-e
127.0.0.1 atomic-f
127.0.0.1 governance-api
127.0.0.1 governance-flagger
127.0.0.1 governance-listener
127.0.0.1 governance-postgres
127.0.0.1 gnark-api
127.0.0.1 pubrelayer-a
127.0.0.1 pubrelayer-b
127.0.0.1 pubrelayer-c
127.0.0.1 pubrelayer-d
127.0.0.1 pubrelayer-e
127.0.0.1 pubrelayer-f
127.0.0.1 public-chain
127.0.0.1 backend-a
127.0.0.1 backend-b
127.0.0.1 backend-c
127.0.0.1 backend-d
127.0.0.1 backend-e
127.0.0.1 backend-f
```

!!! note "Participant Scaling"
    If you plan to run fewer than 6 participants (e.g., only 2), you still need all host entries. The Docker environment dynamically starts only the required services, but configuration files may reference all participants.

### Verify Hosts Configuration

Test that hostname resolution works:

```bash
# Should return 127.0.0.1
ping -c 1 mongodb
ping -c 1 pl-a
ping -c 1 commit-chain
```

On Windows:

```powershell
ping -n 1 mongodb
ping -n 1 pl-a
ping -n 1 commit-chain
```

### Troubleshooting Hosts File

**macOS: "Read-only file system" error:**

If you get permission errors:

```bash
# Disable System Integrity Protection temporarily (not recommended)
# Or use sudo with correct syntax:
sudo sh -c 'echo "127.0.0.1 mongodb" >> /etc/hosts'
```

**Windows: Cannot save hosts file:**

Ensure Notepad is running as Administrator. Right-click Notepad → "Run as administrator", then open the hosts file.

**Linux: Permission denied:**

```bash
# Ensure you're using sudo
sudo nano /etc/hosts

# Or change permissions temporarily (not recommended)
sudo chmod 666 /etc/hosts
# After editing:
sudo chmod 644 /etc/hosts
```

## Verification Checklist

Before proceeding to Docker setup, verify all prerequisites:

- [ ] Docker Desktop running with sufficient resources allocated
- [ ] Docker Compose V2 installed (`docker compose version` works)
- [ ] Git installed and configured
- [ ] Node.js 18+ and npm 9+ installed
- [ ] Go 1.21+ installed
- [ ] Git LFS installed and initialized (`git lfs version` works)
- [ ] All 6 repositories cloned into `~/work/parfin/`
- [ ] Repository directory structure matches expected layout
- [ ] rayls-sovereign-gnark-api LFS files pulled (`git lfs pull` completed)
- [ ] rayls-sovereign-gnark-api circuits compiled successfully
- [ ] rayls-sovereign-gnark-api server binary generated (`last_build/executables/server` exists)
- [ ] Hosts file configured with all Rayls service hostnames
- [ ] Hostname resolution verified (`ping mongodb` works)

## Troubleshooting

### Docker Permission Issues (Linux)

If you encounter permission errors running Docker commands:

```bash
# Add your user to the docker group
sudo usermod -aG docker $USER

# Log out and log back in for changes to take effect
# Or run: newgrp docker
```

### Node.js Version Conflicts

If you have multiple Node.js versions:

```bash
# Use nvm to manage versions
nvm list
nvm use 18
nvm alias default 18
```

### Go Module Issues

If Go cannot download modules:

```bash
# Configure Go proxy (especially in restrictive networks)
go env -w GOPROXY=https://proxy.golang.org,direct
```

## Next Steps

Once all prerequisites are installed and verified, proceed to:

**→ [Docker Setup](docker-setup.md)** - Set up your local development environment

## Related Documentation

- [Architecture Overview](architecture-overview.md) - Understand the system architecture
- [Glossary](../../resources/glossary.md) - Rayls terminology reference
