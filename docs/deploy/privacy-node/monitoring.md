# Monitoring & Maintenance

This guide covers health monitoring, metrics collection, backup strategies, and log management for the Rayls Privacy Node.

## Health Check Endpoints

### Basic Health Checks

**Chain ID Check:**
```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}'
```
Expected: `{"jsonrpc":"2.0","id":1,"result":"0xc3500"}`

**Block Number:**
```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

**Peer Count:**
```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}'
```
Expected for standalone: `{"jsonrpc":"2.0","id":1,"result":"0x0"}`

**Syncing Status:**
```bash
curl -X POST http://localhost:8545 \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}'
```
Expected when synced: `{"jsonrpc":"2.0","id":1,"result":false}`

### Health Check Script

```bash title="healthcheck.sh"
#!/bin/bash

RPC_URL="${1:-http://localhost:8545}"
EXPECTED_CHAIN_ID="0xc3500"  # 800000 in hex

response=$(curl -s -X POST $RPC_URL \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}')

chain_id=$(echo $response | jq -r '.result')

if [ "$chain_id" == "$EXPECTED_CHAIN_ID" ]; then
  echo "OK: Node is healthy (chainId: $chain_id)"
  exit 0
else
  echo "FAIL: Unexpected chainId: $chain_id (expected: $EXPECTED_CHAIN_ID)"
  exit 1
fi
```

---

## Prometheus Metrics

### Enable Metrics

Add these flags when starting the node:

```bash
--metrics 0.0.0.0:6060        # consensus metrics
--reth-metrics 0.0.0.0:6061   # execution (reth) metrics
```

### Docker Compose Example

```yaml
services:
  privacy-node:
    image: rayls-stack-node-client:latest  # built from the axyl repo (etc/docker-network/Dockerfile)
    ports:
      - "8545:8545"
      - "6060:6060"  # Metrics port
    # The datadir must already be provisioned (validator keys + genesis bundle) — see the deployment guides.
    command: >
      /usr/local/bin/rayls node
      --datadir /data/pl
      --http
      --http.addr 0.0.0.0
      --http.port 8545
      --http.api all
      --network mainnet
      --metrics 0.0.0.0:6060
```

### Kubernetes ServiceMonitor

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rayls-sovereign-node
  namespace: rayls
spec:
  selector:
    matchLabels:
      app: rayls-sovereign-node
  endpoints:
  - port: metrics
    interval: 30s
    path: /debug/metrics/prometheus
```

### Key Metrics to Monitor

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `chain_head_block` | Current block number | Stalled for >5min |
| `txpool_pending` | Pending transactions | >1000 |
| `p2p_peers` | Connected peers | 0 (if expected >0) |
| `system_memory_used` | Memory usage | >90% of limit |
| `system_cpu_goroutines` | Active goroutines | Sudden spike |

---

## Backup Strategy

### Docker/VPS Backup

**Stop and Backup:**
```bash
# Stop the node
docker-compose down

# Create backup with timestamp
tar -czf rayls-backup-$(date +%Y%m%d-%H%M%S).tar.gz /opt/rayls/data

# Restart
docker-compose up -d
```

**Automated Backup Script:**
```bash title="backup.sh"
#!/bin/bash

BACKUP_DIR="/opt/backups/rayls"
DATA_DIR="/opt/rayls/data"
RETENTION_DAYS=7

mkdir -p $BACKUP_DIR

# Create backup
BACKUP_FILE="$BACKUP_DIR/rayls-$(date +%Y%m%d-%H%M%S).tar.gz"
tar -czf $BACKUP_FILE $DATA_DIR

# Remove old backups
find $BACKUP_DIR -name "rayls-*.tar.gz" -mtime +$RETENTION_DAYS -delete

echo "Backup created: $BACKUP_FILE"
```

**Cron Job (daily at 2 AM):**
```bash
0 2 * * * /opt/scripts/backup.sh >> /var/log/rayls-backup.log 2>&1
```

### Kubernetes Backup

**Using kubectl exec:**
```bash
kubectl exec -n rayls deployment/rayls-sovereign-node -- \
  tar czf - /data/pl > rayls-backup-$(date +%Y%m%d).tar.gz
```

**Using VolumeSnapshots (recommended):**
```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: rayls-snapshot-$(date +%Y%m%d)
  namespace: rayls
spec:
  source:
    persistentVolumeClaimName: rayls-data
```

Create snapshot:
```bash
kubectl apply -f - <<EOF
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: rayls-snapshot-$(date +%Y%m%d)
  namespace: rayls
spec:
  source:
    persistentVolumeClaimName: rayls-data
EOF
```

**Restore from Snapshot:**
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rayls-data-restored
  namespace: rayls
spec:
  dataSource:
    name: rayls-snapshot-20240115
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 500Gi
```

---

## Log Management

### Docker Logs

**View logs:**
```bash
docker logs -f rayls-sovereign-node
```

**With timestamps:**
```bash
docker logs -f --timestamps rayls-sovereign-node
```

**Last 100 lines:**
```bash
docker logs --tail 100 rayls-sovereign-node
```

**Docker Compose logging configuration:**
```yaml
services:
  privacy-node:
    logging:
      driver: "json-file"
      options:
        max-size: "100m"
        max-file: "10"
```

### Systemd Logs

```bash
# View logs
sudo journalctl -u rayls-pl -f

# Last 100 lines
sudo journalctl -u rayls-pl -n 100

# Logs since specific time
sudo journalctl -u rayls-pl --since "1 hour ago"

# Export logs
sudo journalctl -u rayls-pl --since today > rayls-logs-$(date +%Y%m%d).txt
```

### Kubernetes Logs

```bash
# Current logs
kubectl logs -f deployment/rayls-sovereign-node -n rayls

# Previous pod logs (after restart)
kubectl logs deployment/rayls-sovereign-node -n rayls --previous

# Last 100 lines
kubectl logs deployment/rayls-sovereign-node -n rayls --tail=100
```

### Log Aggregation

**Fluent Bit DaemonSet (example):**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluent-bit-config
  namespace: rayls
data:
  fluent-bit.conf: |
    [INPUT]
        Name              tail
        Path              /var/log/containers/rayls-*.log
        Parser            docker
        Tag               rayls.*
        Refresh_Interval  5

    [OUTPUT]
        Name  es
        Match rayls.*
        Host  elasticsearch.logging.svc
        Port  9200
        Index rayls-logs
```

---

## Alerting

### Example Alertmanager Rules

```yaml title="rayls-alerts.yaml"
groups:
- name: rayls
  rules:
  - alert: RaylsNodeDown
    expr: up{job="rayls-sovereign-node"} == 0
    for: 1m
    labels:
      severity: critical
    annotations:
      summary: "Rayls Privacy Node is down"

  - alert: RaylsBlockStalled
    expr: increase(chain_head_block[5m]) == 0
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Rayls node not producing blocks"

  - alert: RaylsHighMemory
    expr: container_memory_usage_bytes{container="privacy-node"} / container_spec_memory_limit_bytes > 0.9
    for: 5m
    labels:
      severity: warning
    annotations:
      summary: "Rayls node memory usage above 90%"
```

---

## Maintenance Windows

### Planned Maintenance Procedure

1. **Notify stakeholders** of maintenance window

2. **Create backup** before maintenance:
   ```bash
   docker-compose down
   tar -czf pre-maintenance-backup.tar.gz /opt/rayls/data
   ```

3. **Perform maintenance** (upgrade, config changes, etc.)

4. **Verify node health** after restart:
   ```bash
   ./healthcheck.sh
   ```

5. **Monitor logs** for any issues:
   ```bash
   docker-compose logs -f
   ```

---

## Related Pages

- [Configuration Reference](configuration.md) - Node configuration options
- [Troubleshooting](troubleshooting.md) - Common issues and solutions
- [Kubernetes](kubernetes.md) - K8s-specific operations
