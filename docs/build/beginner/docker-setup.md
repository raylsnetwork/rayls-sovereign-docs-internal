# Docker Setup

Set up a complete local Rayls development environment using Docker. This guide walks you through deploying a full Privacy Node network with up to 6 participants on your local machine.

## Overview

The Rayls Docker development environment provides a complete, production-like stack running locally:

- **6 Privacy Node Ledgers** (axyl-based private blockchains)
- **Private Network Hub** (Besu-based coordinator chain)
- **Cross-chain relayers** with encryption (Key Operation Service)
- **Atomic swap services** for trustless exchanges
- **Backend APIs** for user interactions
- **Governance services** for audit and compliance
- **Zero-knowledge proof generation**
- **Observability stack** (Grafana, Prometheus, Loki)

**Total Services:** 40+ Docker containers
**Startup Time:** 4-6 minutes for full deployment
**Memory Required:** 16GB minimum (2 participants), 24GB recommended (6 participants)

## Quick Start

If you've completed the [prerequisites](prerequisites.md), you can start the environment with a single command:

```bash
cd ~/work/parfin/rayls-sovereign-relayer
./start_dev.sh
```

This will:

1. Generate configuration for 2 participants (default)
2. Start all infrastructure services
3. Deploy smart contracts (~4 minutes)
4. Launch relayers and services
5. Set up observability stack

**What to expect:**
- Initial Docker image builds: 1-2 minutes
- Privacy Node Ledger startup: 30 seconds
- Contract deployment: 3-4 minutes
- Service initialization: 30 seconds

Once complete, you'll have a fully functional 2-participant Privacy Node network ready for development and testing.

## Detailed Setup Guide

### Step 1: Navigate to Relayer Directory

The orchestration script lives in the `rayls-sovereign-relayer` repository:

```bash
cd ~/work/parfin/rayls-sovereign-relayer
```

### Step 2: Understand Configuration Options

The `start_dev.sh` script supports several options:

| Option | Description | Default |
|--------|-------------|---------|
| `[N]` | Number of participants (2-6) | 2 |
| `-c` or `--clean` | Clean state (remove all data) | Keep data |
| `-l` or `--local` | Local mode (all services in Docker) | Local |
| `--no-governance` | Disable governance services | Enabled |
| `--no-otel` | Disable observability | Enabled |
| `--no-public-chain` | Disable public chain bridge | Enabled |

**Examples:**

```bash
# Start with 2 participants (default)
./start_dev.sh

# Start with 6 participants
./start_dev.sh 6

# Clean restart (wipes all data)
./start_dev.sh --clean

# 4 participants without governance
./start_dev.sh 4 --no-governance
```

!!! tip "Participant Count"
    Start with 2 participants for initial development. Increase to 4 or 6 when testing complex multi-party scenarios. Each participant adds approximately 1-2GB RAM usage.

### Step 3: Start the Environment

For first-time setup with default configuration:

```bash
./start_dev.sh
```

**Startup Phases:**

1. **Validation** - Checks directory structure and Docker installation
2. **Configuration** - Generates `.env` files for each participant
3. **Base Services** - Starts MongoDB, blockchains, and proof API
4. **Contract Deployment** - Deploys and configures smart contracts
5. **Service Launch** - Starts relayers, backends, and governance

**Progress Indicators:**

Watch for these log messages:

```
✓ MongoDB healthy
✓ Privacy Node Ledger A healthy
✓ Privacy Node Ledger B healthy
✓ Private Network Hub healthy
✓ ZK Proofs API healthy
⏳ Deploying contracts... (this takes ~4 minutes)
✓ Contracts deployed successfully
✓ KOS-A healthy
✓ KOS-B healthy
✓ Relayer-A healthy
✓ Relayer-B healthy
```

!!! note "First Run"
    The first run takes longer (6-8 minutes) because Docker needs to build images. Subsequent runs are faster (4-5 minutes).

### Step 4: Verify Deployment

Once the startup script completes, verify all services are running:

```bash
# Check all services are running
docker compose ps

# Expected: All services should show "running" or "healthy" state
```

**Key Services to Verify:**

| Service | Health Check URL | Expected Response |
|---------|-----------------|-------------------|
| **MongoDB** | `http://localhost:9999` | Mongo Express UI |
| **Privacy Node Ledger A** | `http://localhost:8545` | JSON-RPC endpoint |
| **Private Network Hub** | `http://localhost:3445` | JSON-RPC endpoint |
| **Relayer A** | `http://localhost:9000/healthcheck` | `{"status":"healthy"}` |
| **Backend A** | `http://localhost:3500/healthcheck` | `{"status":"ok"}` |
| **Contract Deployment** | `http://localhost:7000` | HTTP 200 OK |
| **Grafana** | `http://localhost:3300` | Grafana login page |

**Quick Health Check:**

```bash
# Check relayer A is healthy
curl http://localhost:9000/healthcheck

# Check blockchain is producing blocks
curl -X POST -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  http://localhost:8545
```

## Accessing Services

### Port Reference

All services are accessible on `localhost` (127.0.0.1):

#### Privacy Node Ledgers

| Participant | HTTP RPC | Chain ID |
|-------------|----------|----------|
| **A** | :8545 | 12345 |
| **B** | :8546 | 12346 |
| **C** | :8547 | 12347 |
| **D** | :8548 | 12348 |
| **E** | :8549 | 12349 |
| **F** | :8550 | 12350 |

#### Core Infrastructure

| Service | Port | Description |
|---------|------|-------------|
| **Private Network Hub** | :3445 | Besu-based coordinator chain |
| **Public Chain** | :8845 | Reth-based test chain (optional) |
| **ZK Proofs API** | :3003 | Groth16 proof generation |
| **MongoDB** | :27017 | Database server |
| **Mongo Express** | :9999 | Database UI (admin/admin) |
| **Contract Status** | :7000 | Deployment health check |

#### Per-Participant Services

**Participant A:**
- KOS (Key Operation): :8080
- Relayer: :9000
- Backend API: :3500
- Public Relayer: :9006

**Participant B:**
- KOS: :8081
- Relayer: :9001
- Backend API: :3501
- Public Relayer: :9007

**Pattern continues for C (:8082, :9002, :3502, :9008) through F (:8085, :9005, :3505, :9011)**

#### Governance Services

| Service | Port | Description |
|---------|------|-------------|
| **API** | :9100 | REST API |
| **Listener** | :9101 | Event monitoring |
| **Flagger** | :9102 | Transaction flagging |
| **PostgreSQL** | :5432 | Database |

#### Observability Stack

| Service | Port | Description |
|---------|------|-------------|
| **Grafana** | :3300 | Dashboards and visualization |
| **Prometheus** | :3090 | Metrics collection |
| **Pyroscope** | :3040 | Profiling |
| **Loki** | :3100 | Log aggregation |
| **OTLP gRPC** | :4317 | OpenTelemetry collector |
| **OTLP HTTP** | :4318 | OpenTelemetry collector |

### Service URLs

**MongoDB UI:**
```
http://localhost:9999
Username: admin
Password: admin
```

**Grafana:**
```
http://localhost:3300
Default credentials: admin/admin
```

**Example API Call:**
```bash
# Get Privacy Node Ledger A block number
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'

# Get Backend A health
curl http://localhost:3500/healthcheck

# Get Relayer A health
curl http://localhost:9000/healthcheck
```

## VS Code Debugging

All Rayls Go services include pre-configured VS Code debugging support. You can attach debuggers to running Docker containers or launch services locally with debugging enabled.

### Prerequisites

1. **VS Code** with Go extension installed
2. **Delve debugger** (installed automatically by Go extension)
3. **Docker environment running** (for attach mode)

### Available Debug Configurations

Each repository includes `.vscode/launch.json` with configurations:

#### rayls-sovereign-relayer Repository

**Docker Attach Mode** - Debug running containers:
- KOS-A through KOS-F (ports 4000-4005)
- Relayer-A through Relayer-F (ports 4010-4015)
- Atomic-A through Atomic-F (ports 4020-4025)
- PubRelayer-A through PubRelayer-F (ports 4035-4040)

**Local Launch Mode** - Run services locally with debugging:
- KOS-A through KOS-F (local)
- Relayer-A through Relayer-F (local)
- Atomic-A through Atomic-F (local)
- PubRelayer-A through PubRelayer-F (local)

**Compound Configurations** - Launch multiple services:
- "Run Relayer and Atomic A" - Both services for participant A
- "Run First two Relayers" - Relayer-A and Relayer-B
- "Run Six Relayers" - All relayers simultaneously

#### rayls-sovereign-backend Repository

- Backend A-F (Docker attach: ports 4040-4045)
- Backend A-F (Local launch)

#### rayls-sovereign-pnh-governance Repository

- API (Docker attach: port 4030 / Local launch)
- Listener (Docker attach: port 4031 / Local launch)
- Flagger (Docker attach: port 4032 / Local launch)

### Debug Port Reference

| Service Type | Participant | Debug Port |
|--------------|-------------|------------|
| **KOS** | A-F | 4000-4005 |
| **Relayer** | A-F | 4010-4015 |
| **Atomic** | A-F | 4020-4025 |
| **PubRelayer** | A-F | 4035-4040 |
| **Backend** | A-F | 4040-4045 |
| **Governance API** | - | 4030 |
| **Governance Listener** | - | 4031 |
| **Governance Flagger** | - | 4032 |

### Debugging Workflow: Docker Attach Mode

This is the recommended approach for most development work.

**Step 1: Start Docker Environment**

```bash
cd ~/work/parfin/rayls-sovereign-relayer
./start_dev.sh
```

Wait for all services to be healthy.

**Step 2: Open Repository in VS Code**

```bash
# For debugging relayer services
code ~/work/parfin/rayls-sovereign-relayer

# For debugging backend
code ~/work/parfin/rayls-sovereign-backend

# For debugging governance
code ~/work/parfin/rayls-sovereign-pnh-governance
```

**Step 3: Attach Debugger**

1. In VS Code, click **Run and Debug** (Ctrl/Cmd+Shift+D)
2. Select configuration from dropdown:

   - For relayer: Choose "Relayer-A (docker)"
   - For backend: Choose "Backend A (docker)"
   - For KOS: Choose "KOS-A (docker)"

3. Press **F5** or click **Start Debugging**

**Step 4: Set Breakpoints**

1. Open the source file you want to debug
2. Click in the gutter next to line numbers to set breakpoints
3. Trigger the code path (e.g., make an API call, send a transaction)
4. Execution will pause at your breakpoints

**Step 5: Debug Controls**

- **Continue (F5)**: Resume execution
- **Step Over (F10)**: Execute next line
- **Step Into (F11)**: Enter function calls
- **Step Out (Shift+F11)**: Exit current function
- **Restart (Ctrl/Cmd+Shift+F5)**: Restart debugger
- **Stop (Shift+F5)**: Detach debugger

### Debugging Workflow: Local Launch Mode

For faster iteration without Docker overhead.

**Step 1: Ensure Infrastructure Running**

```bash
# Start only base services
cd ~/work/parfin/rayls-sovereign-relayer
./start_dev.sh

# Stop the service you want to debug locally
docker compose stop relayer-a
```

**Step 2: Open Repository in VS Code**

```bash
code ~/work/parfin/rayls-sovereign-relayer
```

**Step 3: Launch Service with Debugger**

1. Select "Relayer-A (local)" from debug dropdown
2. Press **F5**
3. Service starts with debugger attached

**Benefits:**

- Faster restarts (no Docker overhead)
- Direct console output
- Easier hot-reload during development

### Multi-Service Debugging

Debug complex cross-chain flows by attaching to multiple services simultaneously.

**Example: Debug Cross-Chain Transfer**

1. Open `rayls-sovereign-relayer` in VS Code
2. Start debugging "Relayer-A (docker)"
3. Set breakpoint in `relayer/listener/listener.go` when message detected
4. In **separate VS Code window**, debug "Relayer-B (docker)"
5. Set breakpoint in `relayer/executor/executor.go` when executing message
6. Trigger transfer from Backend A to Participant B
7. Watch execution flow through both relayers

**Using Compound Configurations:**

1. Select "Run Relayer and Atomic A" from dropdown
2. Press F5
3. Both services start with debuggers attached
4. Set breakpoints in both
5. Debug atomic swap flow end-to-end

### Debugging Tips

**View Logs:**
```bash
# View specific service logs
docker compose logs -f relayer-a

# View all relayer logs
docker compose logs -f relayer-a relayer-b

# View with timestamps
docker compose logs -f --timestamps relayer-a
```

**Inspect Variables:**

- Hover over variables to see values
- Use **Debug Console** to evaluate expressions
- Watch panel to monitor specific variables

**Hot Reload:**

- Code changes trigger automatic rebuild in Docker
- Debugger reattaches within 1-2 seconds
- Near-instant feedback loop

**Path Mapping:**
Docker configurations include `substitutePath` for correct source mapping between host and container.

## Common Operations

### Viewing Logs

**Individual Service:**
```bash
# Follow logs for specific service
docker compose logs -f relayer-a

# View last 50 lines
docker compose logs --tail=50 relayer-a

# View logs with timestamps
docker compose logs -f --timestamps relayer-a
```

**Multiple Services:**
```bash
# All relayers
docker compose logs -f relayer-a relayer-b relayer-c relayer-d relayer-e relayer-f

# All KOS services
docker compose logs -f kos-a kos-b kos-c kos-d kos-e kos-f

# Infrastructure
docker compose logs -f mongodb pl-a pl-b commit-chain
```

**Centralized Logging:**

Access Grafana at `http://localhost:3300`:

- Navigate to Explore → Loki
- Query logs across all services
- Filter by service, log level, or content

### Stopping Services

**Stop All (Preserve Data):**
```bash
cd ~/work/parfin/rayls-sovereign-relayer
docker compose down
```

Data in MongoDB and blockchain state is preserved. Next startup resumes from current state.

**Clean Stop (Remove All Data):**
```bash
cd ~/work/parfin/rayls-sovereign-relayer
docker compose down --volumes
```

!!! warning "Data Loss"
    `--volumes` flag removes all data including databases and blockchain state. Use for fresh starts only.

**Stop Individual Service:**
```bash
# Stop specific service
docker compose stop relayer-a

# Start it again
docker compose start relayer-a
```

### Restarting Services

**After Code Changes:**

Code changes in Go services trigger automatic rebuild and restart via hot-reload (Docker Compose `watch` feature). Wait 1-2 seconds after saving.

**Manual Restart:**
```bash
# Restart specific service
docker compose restart relayer-a

# Restart all relayers
docker compose restart relayer-a relayer-b relayer-c relayer-d relayer-e relayer-f
```

**Clean Restart:**
```bash
./start_dev.sh --clean
```

This wipes all state and starts fresh.

### Configuration Changes

**Update Environment Variables:**

1. Edit `.env` file:
```bash
cd ~/work/parfin/rayls-sovereign-relayer
nano .A.env  # Or .B.env, .C.env, etc.
```

2. Restart affected service:
```bash
docker compose restart relayer-a kos-a
```

**Hot-reload** detects `.env` changes and restarts automatically.

### Scaling Participants

**Change Participant Count:**

```bash
# Start with 4 participants
./start_dev.sh 4

# Or 6 participants
./start_dev.sh 6
```

**Memory Considerations:**

| Participants | RAM Required | Services Running |
|-------------|--------------|-----------------|
| 2 | 16GB | ~25 containers |
| 4 | 20GB | ~35 containers |
| 6 | 24GB | ~45 containers |

### Accessing Container Shell

**Execute Commands in Container:**
```bash
# Open shell in relayer-a container
docker compose exec relayer-a bash

# Run specific command
docker compose exec relayer-a ls -la

# Check Go environment
docker compose exec relayer-a go version
```

### Monitoring Resources

**Docker Stats:**
```bash
docker stats

# Shows CPU, memory, network usage for all containers
```

**Specific Services:**
```bash
docker stats relayer-a relayer-b kos-a kos-b
```

## Troubleshooting

### Port Conflicts

**Symptom:** Service fails to start with "port already in use" error

**Solution:**
```bash
# Find process using port
lsof -i :8545  # Replace with conflicting port

# Kill process
kill -9 <PID>

# Or use different ports by modifying docker-compose.yml
```

### Docker Memory/CPU Limits

**Symptom:** Services crash with OOM (Out of Memory) errors

**Solution:**

1. Open Docker Desktop → Settings → Resources
2. Increase memory allocation to 16GB (2 participants) or 24GB (6 participants)
3. Ensure CPU is set to at least 4 cores
4. Click "Apply & Restart"

### Contract Deployment Failures

**Symptom:** Contracts service shows unhealthy status

**Check logs:**
```bash
docker compose logs contracts
```

**Common issues:**

- Blockchain not producing blocks → Check `pl-a` logs
- Compilation errors → Check Node.js version (need 18+)
- Network issues → Verify Docker network: `docker network ls`

**Solution:**
```bash
# Clean restart
./start_dev.sh --clean
```

### Service Health Check Timeouts

**Symptom:** Services remain in "starting" state indefinitely

**Check service logs:**
```bash
docker compose logs <service-name>
```

**Common causes:**

- MongoDB not ready → Check MongoDB logs
- Previous service in dependency chain unhealthy
- Port conflicts
- Insufficient resources

**Solution:**
```bash
# Check all services status
docker compose ps

# Restart specific service
docker compose restart <service-name>

# Or clean restart
./start_dev.sh --clean
```

### Blockchain Not Producing Blocks

**Check block number:**
```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

**If stuck at block 0:**
```bash
# Check Privacy Node Ledger logs
docker compose logs pl-a

# Common issue: Genesis file mismatch
# Solution: Clean restart
./start_dev.sh --clean
```

### MongoDB Connection Issues

**Test connection:**
```bash
# Try to connect via mongo shell in container
docker compose exec mongodb mongosh -u admin -p admin
```

**If connection fails:**
```bash
# Check MongoDB logs
docker compose logs mongodb

# Restart MongoDB
docker compose restart mongodb

# Or clean restart with volumes
docker compose down --volumes
./start_dev.sh
```

### File Permission Errors

**Symptom:** "Permission denied" errors in logs

**Linux Solution:**
```bash
# Set correct ownership
sudo chown -R $USER:$USER ~/work/parfin

# Or run with user mapping
export CUSTOM_UID=$(id -u)
export CUSTOM_GID=$(id -g)
./start_dev.sh
```

### Out of Disk Space

**Check disk usage:**
```bash
docker system df
```

**Clean up:**
```bash
# Remove unused images
docker image prune -a

# Remove unused volumes
docker volume prune

# Clean everything (CAREFUL!)
docker system prune -a --volumes
```

### Hot-Reload Not Working

**Symptom:** Code changes don't trigger rebuild

**Solution:**
```bash
# Check if using `--watch` flag
docker compose ps

# Manually restart with watch
docker compose up --watch relayer-a

# Or restart environment
./start_dev.sh
```

### Getting Help

If you encounter issues not covered here:

1. **Check service logs:** `docker compose logs <service>`
2. **Verify health checks:** Visit health endpoints listed above
3. **Check Grafana:** `http://localhost:3300` for centralized logs
4. **Review configuration:** Ensure `.env` files are properly generated
5. **Clean restart:** `./start_dev.sh --clean` often resolves issues

**Log Locations:**

- Container logs: `docker compose logs <service>`
- MongoDB: Access via Mongo Express at `:9999`
- Grafana: Loki logs at `:3300`
- Contract deployment: Check `:7000/healthcheck`

## What's Next

Now that your local development environment is running:

**→ [First Transaction](first-transaction.md)** - Send your first cross-chain transaction

**→ [Deployment Workflow](../intermediate/deployment-workflow.md)** - Deploy your own smart contracts

**→ [Developer Tools](../reference/developer-tools.md)** - Development tools and utilities

## Related Documentation

- [Prerequisites](prerequisites.md) - System requirements
- [Architecture Overview](architecture-overview.md) - System architecture
- [Glossary](../../resources/glossary.md) - Rayls terminology
