# Kubernetes Deployment

This guide provides production-oriented Kubernetes manifests for deploying a Rayls Privacy Node with the **axyl** client.

A Privacy Node is a **multi-validator BFT cluster** (4 validators by default), so it maps naturally onto a **StatefulSet**: each pod is one validator with its own stable identity, persistent data directory, and persistent network multiaddr. Bringing the cluster up has three phases:

1. **Key generation** — an init container per validator runs `rayls keytool generate validator`.
2. **Genesis ceremony** — a Job collects every validator's `node-info.yaml`, runs `rayls genesis`, and writes the genesis bundle to shared/per-pod storage.
3. **Run** — the StatefulSet runs `rayls node`.

!!! note "Image"
    These manifests reference `rayls-stack-node-client:<tag>`. Pull it from Rayls' private registry, or build from the axyl repository's `etc/docker-network/Dockerfile`. Replace the placeholder with your registry path and tag.

## Prerequisites

- Kubernetes cluster 1.20+ (1.25+ recommended)
- `kubectl` configured with cluster access
- A storage class for PersistentVolumes
- A Secret containing the BLS passphrase
- (Optional) Ingress controller for external RPC access

## Step 1: Namespace and Secret

```yaml title="namespace.yaml"
apiVersion: v1
kind: Namespace
metadata:
  name: rayls
```

Create a Secret for the BLS passphrase (consumed via `RL_BLS_PASSPHRASE`):

```yaml title="secret.yaml"
apiVersion: v1
kind: Secret
metadata:
  name: rayls-secrets
  namespace: rayls
type: Opaque
stringData:
  RL_BLS_PASSPHRASE: "change-me"
```

Apply:

```bash
kubectl apply -f namespace.yaml
kubectl apply -f secret.yaml
```

## Step 2: Headless Service

A StatefulSet needs a headless Service to give each validator pod a stable DNS name, which is also used to build its consensus multiaddr.

```yaml title="service-headless.yaml"
apiVersion: v1
kind: Service
metadata:
  name: rayls-validators
  namespace: rayls
  labels:
    app: rayls-sovereign-node
spec:
  clusterIP: None      # headless
  selector:
    app: rayls-sovereign-node
  ports:
    - name: rpc
      port: 8545
      targetPort: 8545
      protocol: TCP
    - name: primary
      port: 49590
      targetPort: 49590
      protocol: UDP
    - name: worker
      port: 49595
      targetPort: 49595
      protocol: UDP
```

Apply:

```bash
kubectl apply -f service-headless.yaml
```

## Step 3: Per-Validator Key Generation and Genesis

Each validator needs its own keys, and the cluster needs one shared genesis bundle. The cleanest pattern is:

- An **init container** in each StatefulSet pod that runs `rayls keytool generate validator` into the pod's PersistentVolume if `node-keys/` does not yet exist (idempotent — see `setup_validator.sh` in [Local Development](local.md)).
- A **one-shot Job** that, once all validators have generated keys, collects every `node-info.yaml`, runs `rayls genesis`, and distributes `genesis.yaml` / `committee.yaml` / `parameters.yaml`.

```yaml title="genesis-job.yaml"
apiVersion: batch/v1
kind: Job
metadata:
  name: rayls-genesis
  namespace: rayls
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
      - name: genesis
        image: rayls-stack-node-client:<tag>
        env:
        - name: RL_BLS_PASSPHRASE
          valueFrom:
            secretKeyRef:
              name: rayls-secrets
              key: RL_BLS_PASSPHRASE
        command: ["bash", "/genesis.sh"]
        volumeMounts:
        - name: genesis-work
          mountPath: /home/nonroot/data
        - name: genesis-script
          mountPath: /genesis.sh
          subPath: genesis.sh
      volumes:
      - name: genesis-work
        persistentVolumeClaim:
          claimName: rayls-genesis-work
      - name: genesis-script
        configMap:
          name: rayls-genesis-script
```

The `genesis.sh` here is the same script shown in [Local Development](local.md): it copies each validator's `node-info.yaml` into `genesis/validators/`, runs `rayls genesis --chain-id ... --epoch-duration-in-secs ... --consensus-registry-owner ... --network-admin ... --fee-aggregator-admin ...`, and distributes the resulting bundle.

> NOTE: How `node-info.yaml` files are gathered and the genesis bundle is handed back to the validators depends on your storage topology (a shared ReadWriteMany volume, an object-store sync step, or an operator). Choose whichever fits your cluster; the axyl commands themselves are unchanged.

Apply and wait:

```bash
kubectl apply -f genesis-job.yaml
kubectl wait --for=condition=complete --timeout=600s job/rayls-genesis -n rayls
```

## Step 4: StatefulSet (the validators)

```yaml title="statefulset.yaml"
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: rayls-sovereign-node
  namespace: rayls
  labels:
    app: rayls-sovereign-node
spec:
  serviceName: rayls-validators
  replicas: 4                 # 4-validator committee by default
  podManagementPolicy: Parallel
  selector:
    matchLabels:
      app: rayls-sovereign-node
  template:
    metadata:
      labels:
        app: rayls-sovereign-node
    spec:
      initContainers:
      # Generate this validator's keys on first start (idempotent).
      - name: keygen
        image: rayls-stack-node-client:<tag>
        env:
        - name: RL_BLS_PASSPHRASE
          valueFrom:
            secretKeyRef:
              name: rayls-secrets
              key: RL_BLS_PASSPHRASE
        - name: EXECUTION_ADDRESS
          value: "0x1111111111111111111111111111111111111111"
        command: ["bash", "/setup_validator.sh"]
        volumeMounts:
        - name: data
          mountPath: /home/nonroot/data
        - name: setup-script
          mountPath: /setup_validator.sh
          subPath: setup_validator.sh
      containers:
      - name: validator
        image: rayls-stack-node-client:<tag>
        env:
        - name: RUST_LOG
          value: "info"
        - name: RAYLS_NETWORK
          value: "mainnet"
        - name: RL_BLS_PASSPHRASE
          valueFrom:
            secretKeyRef:
              name: rayls-secrets
              key: RL_BLS_PASSPHRASE
        - name: PRIMARY_LISTENER_MULTIADDR
          value: "/ip4/0.0.0.0/udp/49590/quic-v1"
        - name: WORKER_LISTENER_MULTIADDR
          value: "/ip4/0.0.0.0/udp/49595/quic-v1"
        command: ["rayls"]
        args:
          - "node"
          - "--datadir=/home/nonroot/data"
          - "--metrics=0.0.0.0:9101"
          - "--full"
          - "--storage.v2"
          - "--txpool.minimal-protocol-fee=0"
          - "--gpo.default-suggested-fee=0"
          - "--http"
          - "--http.addr=0.0.0.0"
          - "--http.port=8545"
          - "--http.api=all"
        ports:
        - name: rpc
          containerPort: 8545
          protocol: TCP
        - name: primary
          containerPort: 49590
          protocol: UDP
        - name: worker
          containerPort: 49595
          protocol: UDP
        - name: metrics
          containerPort: 9101
          protocol: TCP
        resources:
          requests:
            memory: "4Gi"
            cpu: "2000m"
          limits:
            memory: "16Gi"
            cpu: "4000m"
        volumeMounts:
        - name: data
          mountPath: /home/nonroot/data
        readinessProbe:
          exec:
            command:
            - sh
            - -c
            - |
              wget -q -O - http://localhost:8545 \
                --post-data='{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
                --header='Content-Type: application/json' | grep -q '"result"'
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
      volumes:
      - name: setup-script
        configMap:
          name: rayls-setup-script
          defaultMode: 0755
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 500Gi
      storageClassName: gp3   # Adjust based on your cluster
```

Apply:

```bash
kubectl apply -f statefulset.yaml
```

!!! note "Storage Class"
    Replace `gp3` with your cluster's storage class. Common options:

    - AWS: `gp3`, `gp2`
    - GCP: `standard`, `premium-rwo`
    - Azure: `managed-premium`
    - On-premise: Check your provisioner

    The data directory holds both MDBX databases (`db/` for execution, `consensus-db/` for consensus), the encrypted `node-keys/`, and the genesis bundle. Use a fast SSD-backed class.

!!! warning "Validator identity must be stable"
    The QUIC multiaddr baked into each validator's keys must remain reachable for the life of the network. With a StatefulSet, give each pod a stable address (headless Service DNS or a per-pod LoadBalancer/NodePort for the UDP ports) and generate the keys with that address as `--external-primary-addr` / `--external-worker-addr`.

## Step 5: Client-facing Service

Expose RPC to in-cluster consumers (and optionally externally). This is separate from the headless Service used for validator identity.

```yaml title="service-rpc.yaml"
apiVersion: v1
kind: Service
metadata:
  name: rayls-sovereign-node
  namespace: rayls
  labels:
    app: rayls-sovereign-node
spec:
  type: ClusterIP
  ports:
  - name: rpc
    port: 8545
    targetPort: 8545
    protocol: TCP
  selector:
    app: rayls-sovereign-node
```

Apply:

```bash
kubectl apply -f service-rpc.yaml
```

## Step 6: Ingress (Optional)

For external RPC access with TLS:

```yaml title="ingress.yaml"
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rayls-sovereign-node
  namespace: rayls
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"  # If using cert-manager
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - rayls-rpc.yourdomain.com
    secretName: rayls-tls
  rules:
  - host: rayls-rpc.yourdomain.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: rayls-sovereign-node
            port:
              number: 8545
```

Apply:

```bash
kubectl apply -f ingress.yaml
```

## Validation

### Check Pod Status

```bash
kubectl get pods -n rayls
```

You should see `rayls-sovereign-node-0` through `rayls-sovereign-node-3` (for a 4-validator cluster) in `Running`.

### View Logs

```bash
kubectl logs -f rayls-sovereign-node-0 -n rayls
```

### Port Forward for Local Testing

```bash
kubectl port-forward -n rayls svc/rayls-sovereign-node 8545:8545
```

### Test RPC

```bash
curl http://localhost:8545 \
  -X POST \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
```

A steadily increasing block number confirms the committee is producing blocks.

---

## High Availability Considerations

The multi-validator BFT model **is** the high-availability mechanism: a committee of `n` validators tolerates up to `f` Byzantine/failed validators where `n >= 3f + 1` (so a 4-validator cluster tolerates 1 failure). Best practices:

1. **Spread validators across failure domains** — use pod anti-affinity and a topology spread so no two validators share a node or availability zone.
2. **Back up each validator's `node-keys/`** — these are irreplaceable. Losing a validator's BLS keys means re-registering a new validator on-chain.
3. **VolumeSnapshots** of the data PVCs let a replaced validator restart from a recent checkpoint and catch up via state-sync rather than from genesis.

```yaml
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: rayls-snapshot-0
  namespace: rayls
spec:
  source:
    persistentVolumeClaimName: data-rayls-sovereign-node-0
```

---

## On-chain Validator Registration

A validator pod must be registered on-chain before it joins the committee (observers skip this): fund the operator key, `ConsensusRegistry.allowlistValidator(...)` (admin), `ConsensusRegistry.stake(...)` (calldata from `rayls keytool stake-calldata`), then `ConsensusRegistry.activate()`. See [Configuration Reference](configuration.md#on-chain-validator-registration).

---

## Connecting Applications

For services in the same cluster:

```bash
BLOCKCHAIN_CHAINID=487
BLOCKCHAIN_CHAINURL=http://rayls-sovereign-node.rayls.svc.cluster.local:8545
```

For external access (with Ingress):

```bash
BLOCKCHAIN_CHAINURL=https://rayls-rpc.yourdomain.com
```

---

## Next Steps

- Configure node options: [Configuration Reference](configuration.md)
- Set up monitoring: [Monitoring Guide](monitoring.md)
- Troubleshoot issues: [Troubleshooting](troubleshooting.md)
