# AccessManager Audit — Operator Guide

Operational playbook for the hardhat audit tasks that gate every Rayls contracts deploy. The canonical task reference and code-level rationale live in [`docs/access-manager-migration.md`][repo-doc] and the entry-point [`README.md`][audit-readme] in the `rayls-sovereign-contracts` repo. This page focuses on operator concerns: what each task means in practice, how to triage findings, and how to wire the audits into CI/CD.

[repo-doc]: https://github.com/raylsnetwork/rayls-sovereign-contracts/blob/main/docs/access-manager-migration.md
[audit-readme]: https://github.com/raylsnetwork/rayls-sovereign-contracts/blob/main/hardhat/tasks/audit/README.md

## AccessManager access invariant — read this first

Every `restricted` function in any managed contract is **always callable by any account holding the `ADMIN` role** (`uint64 constant ADMIN = 0`). This access is **not granted via** `addFunctionAllowedRoles` **and cannot be revoked** through the role-mapping system — it's checked by `AccessManagerAuthLib.canCall` _before_ the selector map is consulted ([`AccessManagerAuthLib.sol:36-46`](https://github.com/raylsnetwork/rayls-sovereign-contracts/blob/main/src/privateHub/AccessControl/libraries/AccessManagerAuthLib.sol)).

Explicit `addFunctionAllowedRoles` mappings exist to **open** a function to _additional_ (non-admin) roles or scoped contracts — never to grant or remove admin access. A `restricted` function with no explicit mapping is the correct default: callable by every ADMIN-role holder, by no one else.

The audit's job is to detect drift between **explicit non-admin role mappings on chain** and the **current ABIs / deploy code's intent / CTS-advertised wallets** — not to enumerate admin-callable functions (by this invariant, every restricted function is admin-callable).

Two caveats to "ADMIN can always call everything":

- **Emergency pause** (`emergencyPaused`) blocks every call including ADMIN.
- **Execution delay** — an ADMIN grant can carry a non-zero `executionDelay`, requiring `schedule()` + `execute()`.

## Audit suite at a glance

The contracts repo ships chain-keyed audit tasks under three families. Most run automatically as part of `docker/dev/deploy_contracts.sh` and gate the contracts container's healthcheck; the migration generator is the one operator-driven task (it emits a reviewable cleanup script when drift is detected).

| Task family                                   | What it checks                                                                                                                                                                                                                                    | When it runs in the deploy                                                             |
| --------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `audit:deploy-selectors`                      | Every `iface.getFunction('NAME')` in deploy code resolves to a function on the just-compiled ABI                                                                                                                                                  | Once, immediately after `hardhat compile`, before any chain TX                         |
| `audit:{pnh,pn,pc}:onchain-selectors`         | Every on-chain `(target, selector, role)` mapping decodes to a real function on the target's current ABI                                                                                                                                          | Once per chain after its deploy + business-role activation                             |
| `audit:{pnh,pn,pc}:roles` (RELAYER mode)      | Every CTS-advertised relayer wallet holds the `RELAYER` role on the matching chain side, and no other holder exists                                                                                                                               | Per relayer / per chain side, after `add-authorized-relayers*` succeeds                |
| `audit:{pnh,pn,pc}:roles --include-own-roles` | Static deploy-time role grants (ENYGMA_CREATOR, MESSAGE_EXECUTOR, etc. — see [`expected-roles/<chain>.ts`](https://github.com/raylsnetwork/rayls-sovereign-contracts/tree/main/hardhat/tasks/audit/expected-roles)) match on-chain `getRoleMembers` | Operator-driven; included in `audit:all`                                               |
| `audit:{pnh,pn,pc}:generate-migration`        | Combines the static lint + on-chain selector audit, emits a reviewable `removeFunctionAllowedRoles` script                                                                                                                                        | Manual — operator runs when drift is found. Dry-run by design — emits no transactions. |
| `audit:{pnh,pn,pc}`                           | Parent tasks — chain `:onchain-selectors` then `:roles` via `hre.run()`. PN/PC iterate over `--pn A,B,C`.                                                                                                                                         | Drives the per-chain audit ordering in `deploy_contracts.sh`                           |
| `audit:all`                                   | Full CI entrypoint — runs `deploy-selectors --strict-unchecked`, then `audit:pnh`, then per-PN `audit:pn` / `audit:pc`, all with `--include-own-roles`                                                                                            | Recommended CI invocation                                                              |

**Healthcheck contract:** any audit failure → `set -e` → script exits → container never writes `1.0,Deployment complete` to `/tmp/deploy_status` → the healthcheck endpoint reports unhealthy. There's no separate "audit failed" status code; the absence of `1.0` is the signal.

## Environment variables the audit reads

The audit tasks pick up everything from `.env`. The deploy script writes these automatically; external operators populate them by hand.

```sh
# RPC URLs — chain-keyed
PNH_RPC_URL=http://...
PUBLIC_CHAIN_RPC_URL=http://...
PRIVACY_NODE_A_RPC_URL=http://...
PRIVACY_NODE_B_RPC_URL=http://...

# DeploymentProxyRegistry addresses
PNH_DEPLOYMENT_PROXY_REGISTRY=0x...
PRIVACY_NODE_A_DEPLOYMENT_PROXY_REGISTRY=0x...
PRIVACY_NODE_A_PUBLIC_CHAIN_DEPLOYMENT_PROXY_REGISTRY=0x...

# Optional — starting blocks skip the eth_getCode binary search on long-lived chains
PNH_STARTING_BLOCK=12345
PRIVACY_NODE_A_STARTING_BLOCK=67890

# Required for RELAYER audit — CTS endpoints per PN
CTS_SERVICE_A_URL=http://cts-a/...
CTS_SERVICE_B_URL=http://cts-b/...

# Required for audit:all and the default --privacy-nodes on audit:pnh:roles
PARTICIPANT_LIST=A,B,C,D
```

Any value can be overridden by a CLI flag: `--rpc <url>`, `--registry <addr>`, `--from-block <N>`. The audit task never reads from `--network` — chain identity is in the task name.

## One-time pre-flight for a new audit-gating environment

When enabling the audit gate against a long-lived chain that hasn't been audited before, the first run will surface every drift item accumulated since deploy day one. Walk this checklist for each long-lived environment (staging, dev cluster) before turning the gate on.

### Step 1 — Snapshot the current state

```sh
cd rayls-sovereign-contracts

# Prerequisite: .env populated for the target chain (see env-var list above).
# If env vars aren't set, every task takes --rpc and --registry as overrides:
#   npx hardhat audit:pnh:onchain-selectors --rpc http://... --registry 0x...

# Static lint — failures here are deploy-code bugs, not drift.
npx hardhat audit:deploy-selectors

# Onchain-selectors audit per chain side.
npx hardhat audit:pnh:onchain-selectors
npx hardhat audit:pn:onchain-selectors --pn A
npx hardhat audit:pc:onchain-selectors --pn A
# ... iterate per PN / PC ...

# Roles audit per chain side. --report-only suppresses exit-1 so you can
# survey every finding before deciding policy.
npx hardhat audit:pn:roles  --pn A     --report-only
npx hardhat audit:pc:roles  --pn A     --report-only
npx hardhat audit:pnh:roles --privacy-nodes A,B,C --report-only

# Own-roles audit (compares static deploy-time grants against on-chain state).
npx hardhat audit:pnh:roles --include-own-roles --skip-relayers
npx hardhat audit:pn:roles  --pn A --include-own-roles --skip-relayers
npx hardhat audit:pc:roles  --pn A --include-own-roles --skip-relayers
```

Capture each task's full output into a per-environment log. Don't mentally diff — bookkeeping matters for the next steps.

#### Sample output — clean state (no drift to triage)

When the chain is in sync with the deploy code, the audits look like this. Use these as the reference for what "no findings" looks like; anything else is a signal to investigate.

**`audit:deploy-selectors`** — the static lint runs in ~5 seconds:

```text
Deploy-selector lint: 102 references checked (102 OK, 0 MISSING, 0 UNCHECKED).

  ✅ LINT PASSED — all 102 getFunction(...) references resolve against the current ABIs.
```

**`audit:pnh:onchain-selectors`** — PNH has the largest selector surface (~29 contracts, ~84 live mappings):

```text
On-chain selector audit:
  AccessManager:        0xF99E319deB5bc8b108E5b87fA2cf1EEB5cbFA4D5
  Block range scanned:  24 → 29130  (source: auto-detect, block 24)
  Managed contracts:    29
  Live mappings:        84
  OK / STALE:           84 / 0
  Registry hygiene:     1 unregistered address, 6 name divergences (informational)

  REGISTRY HYGIENE — informational, not drift:
    NAME DIVERGES 0xe602…  registry='FungibleAssetGroup'    artifact='AssetGroup'
    NAME DIVERGES 0xd0b6…  registry='Endpoint'              artifact='EndpointV1'
    UNREGISTERED  0x0810…  (identified as RaylsMessageExecutorV1)  has on-chain role mappings but no entry in DeploymentProxyRegistry
    ...

  ✅ AUDIT PASSED — no selector drift; on-chain state matches current ABIs.
```

`UNREGISTERED` / `NAME DIVERGES` are registry-hygiene findings, **not** drift — they're informational. Drift produces `STALE`, which exits 1.

**`audit:pn:roles --pn A`** — RELAYER audit against CTS:

```text
Relayer-role audit (RELAYER):
  Scope:                PN (own chain)
  Privacy node:         A
  AccessManager:        0xF99E319deB5bc8b108E5b87fA2cf1EEB5cbFA4D5
  Block range scanned:  92 → 29229  (source: auto-detect, block 92)
  Role ID:              5
  Expected (CTS):       10
  On-chain holders:     10
  OK / MISSING / UNEXPECTED: 10 / 0 / 0

  ✅ AUDIT PASSED — every CTS-expected wallet holds RELAYER and no extras.
```

**`audit:pnh:roles --include-own-roles --skip-relayers`** — own-roles audit, no CTS calls:

```text
Own-roles audit:
  Scope:                Private Network Hub (shared)
  Expected role count:  8
  On-chain role count:  19
  OK / MISSING / UNEXPECTED: 15 / 0 / 0

  INFO — 11 roles not covered by expected-roles module:
    [#0] 1 holder                  ← ADMIN, deployer signer
    [PUBLIC#1] 0 holders
    [TOKEN_OWNER#2] 0 holders
    [ENYGMA_V1#8] 0 holders        ← dynamically granted by FACTORY_ADMIN
    [COIN_VAULT#9] 0 holders       ← dynamically granted by FACTORY_ADMIN
    [RELAYER#11] 36 holders        ← audited via CTS in RELAYER mode
    [MESSAGE_EXECUTOR#12] 1 holder
    [Private Network Operator#15] 0 holders
    ...

  ✅ OWN-ROLES AUDIT PASSED — every expected grant is on chain.
```

The INFO list is the operator's hint: ADMIN (always 1 holder = deployer wallet), the factory-managed roles (ENYGMA_V1, COIN_VAULT — granted at runtime by FACTORY_ADMIN to deployed contracts), business roles (granted via `grant-business-role`), and RELAYER (covered by the separate CTS-driven mode).

### Step 2 — Triage the findings

Each finding category and what to do about it:

#### `STALE` (onchain-selectors audit) — selector drift on chain

A `(target, selector, role)` mapping exists on chain but no function on the target's current ABI has that selector. Almost always a function rename or parameter-shape change that wasn't followed by a `removeFunctionAllowedRoles` in the deploy task.

1. Generate a migration:

   ```sh
   npx hardhat audit:pnh:generate-migration
   # or :pn:generate-migration --pn A, or :pc:generate-migration --pn A
   ```

   When drift is found, the output ends with:

   ```text
   📄 Wrote migration: audit/migrations/2026-05-19T04-12-00-access-manager-drift.ts
        STALE removals:   3 (active)

     ⚠️  Migration GENERATED but NOT applied. Review the file, then run:
        npx hardhat run audit/migrations/2026-05-19T04-12-00-access-manager-drift.ts --network <name>
   ```

   When the chain is already clean, no file is written and the output ends with:

   ```text
   ✅ Nothing to migrate — on-chain state matches current ABIs. No migration file emitted.
   ```

2. Review the emitted file under `audit/migrations/<timestamp>-...ts`. Each STALE entry becomes an active `removeFunctionAllowedRoles` call. **No transactions are sent yet — the generator is dry-run by design.**
3. Apply: `npx hardhat run audit/migrations/<timestamp>-...ts --network <name>`.
4. Re-run the audit — expect zero STALE.
5. **Archive the migration** alongside the deploy artifacts (S3, deploy registry, or the PR record). Six months from now this is the audit trail for "why does the chain look this way?".

#### `UNCHECKED` (static lint) — non-literal `getFunction` argument

The lint's three argument-resolution passes (string literal → `.map(literal-array)` arrow param → lexically-scoped `const` binding to string literal or array literal) couldn't reduce the call's first argument. Common causes: template-string interpolation, ternary, dynamic property access, or a `.map` chained on something deeper than a single `const` binding.

1. **Try to refactor the call site** so it reduces via one of the three passes. Often as simple as replacing a template string with a literal or pulling an inline array into a top-level `const`.
2. **Otherwise accept the blind spot** with a code comment explaining why the dynamic lookup is intentional, and use `--strict-unchecked` in CI so any _new_ UNCHECKED finding forces a decision (refactor vs. accept).

UNCHECKED is informational by default. `--strict-unchecked` escalates it to fatal.

#### `MISSING` (roles audit, RELAYER mode) — CTS advertises but on-chain absent

CTS lists a wallet but the on-chain `RoleGranted` history shows no grant. Usually a partially-applied authorization, or a manual `revokeRole` that wasn't followed by a re-grant.

1. Verify the wallet address is correct in CTS — confirm it's a current live signing key, not a stale advertisement.
2. If correct: re-run `add-authorized-relayers` (or `-pnh`) for that PN. It's idempotent — addresses already granted get re-attempted but the on-chain `grantRole` call is a no-op for existing holders.
3. Re-audit.

#### `UNEXPECTED` (roles audit, RELAYER mode) — on-chain holder not in CTS

An address holds RELAYER on chain but CTS doesn't advertise it. Most common cause: **rotated CTS keys** — new keys got granted by a recent deploy, old keys were never revoked.

1. Confirm with the team that the address really is a rotated/decommissioned key (not a stray test wallet, not a legitimate operator wallet you'd missed). If you can't account for the address, **stop and investigate** — an unaccounted RELAYER holder is a security finding.
2. For each confirmed-stale address, call `revokeRole(roleId, account)` from an admin signer. There's no helper task; use `hardhat console` or write a one-off script.
3. Re-audit. UNEXPECTED count should drop to zero.

#### `MISSING` / `UNEXPECTED` (roles audit, own-roles mode) — static-grant drift

The own-roles audit compares the chain's per-chain expected-roles module against `getRoleMembers(roleId)`.

- **MISSING**: an expected grantee (resolved by registry name) doesn't hold the role on chain. Either the deploy missed the grant or the expected-roles module is wrong.
  1. Confirm the expected grantee is correct by checking the deploy code: `git blame hardhat/tasks/deploy/<chain>.ts` for the `grantRole` call with that role.
  2. If the grant should be there but isn't: re-run the deploy or grant it manually as ADMIN.
  3. If the expected-roles module is wrong: update [`hardhat/tasks/audit/expected-roles/<chain>.ts`](https://github.com/raylsnetwork/rayls-sovereign-contracts/tree/main/hardhat/tasks/audit/expected-roles) to match the deploy code.

- **UNEXPECTED**: an on-chain holder isn't in the expected list. Either the deploy granted something not in the expected-roles module (update the module), or a manual grant happened (investigate). For roles that grow at runtime (ENDPOINT_SENDER, AUTHORIZED_SENDER), the expected-roles module should set `allowUnexpected: true`.

#### What "drift" looks like in practice

The most common operator mistake is passing an **incomplete PN list** to `audit:pnh:roles`. The hub's RELAYER set unions every PN's CTS-advertised hub addresses; omitting PNs makes the other PNs' relayers look UNEXPECTED:

```text
$ npx hardhat audit:pnh:roles --privacy-nodes A,B

Relayer-role audit (RELAYER):
  Scope:                Private Network Hub (shared)
  Privacy nodes:        A,B
  AccessManager:        0xF99E319deB5bc8b108E5b87fA2cf1EEB5cbFA4D5
  Role ID:              11
  Expected (CTS):       12
  On-chain holders:     36
  OK / MISSING / UNEXPECTED: 12 / 0 / 24

  UNEXPECTED — on-chain holder not advertised by CTS (likely rotated key or stray grant):
    0xab95…
    0xae6d…
    ...

  ❌ AUDIT FAILED — 24 UNEXPECTED holders.
```

**Triage**: confirm the listed addresses are CTS-advertised hub addresses for PNs C, D, E, F (not actual rotated keys) by re-running with the full list. Set `PARTICIPANT_LIST=A,B,C,D,E,F` in `.env` or pass `--privacy-nodes` with every active PN.

`--report-only` suppresses the exit code but keeps the finding visible — useful during pre-flight surveying:

```text
  ℹ️  REPORT-ONLY — 24 UNEXPECTED holders (would have failed without --report-only).
```

#### `MISSING` (static lint) — different from roles MISSING

The static lint's MISSING means a deploy script references a function (`iface.getFunction('NAME')`) that doesn't exist on the current ABI. Always a code bug.

**Action:** fix the deploy task. Either restore the function or update the deploy string. Don't enable the audit gate until `audit:deploy-selectors` is clean.

### Step 3 — Verify clean

After applying all remediations, every command below should exit 0 against the target environment:

```sh
npx hardhat audit:deploy-selectors --strict-unchecked
npx hardhat audit:pnh --include-own-roles
npx hardhat audit:pn  --pn A,B,C --include-own-roles
npx hardhat audit:pc  --pn A,B,C --include-own-roles
# Or, all at once:
npx hardhat audit:all
```

**Sample `audit:all` output** (full CI entrypoint, against a clean 6-PN deployment):

```text
══════ audit:all (PNs: A,B,C,D,E,F) ════════════════════════
[1/4] audit:deploy-selectors --strict-unchecked
  ✅ LINT PASSED — all 102 getFunction(...) references resolve against the current ABIs.

[2/4] audit:pnh (includes own-roles)
  ✅ AUDIT PASSED — no selector drift; on-chain state matches current ABIs.
  ✅ OWN-ROLES AUDIT PASSED — every expected grant is on chain.
  ✅ AUDIT PASSED — every CTS-expected wallet holds RELAYER and no extras.
  ══════ audit:pnh ✅ PASSED ══════

[3/4] audit:pn --pn A,B,C,D,E,F (includes own-roles)
  ... (six per-PN passes) ...
  ══════ audit:pn (6 PNs) ✅ PASSED ══════

[4/4] audit:pc --pn A,B,C,D,E,F (includes own-roles)
  ... (six per-PN passes) ...
  ══════ audit:pc (6 PNs) ✅ PASSED ══════

══════ audit:all ✅ PASSED ══════
```

Parent tasks (`audit:pnh`, `audit:pn`, `audit:pc`) do **not** halt on the first failed child — every child runs and `process.exitCode` aggregates the worst result. So a single `audit:all` invocation produces a full picture of every finding across every chain, which is the right shape for triage.

Once clean, enable the audit gate for that environment (already wired into `docker/dev/deploy_contracts.sh` for local dev; for staging / prod CI, add `audit:all` to the relevant CI step). The next deploy starts from a clean baseline; any future audit failure is real drift on a recent change, not historical accumulation.

## Manual-edit + regenerate workflow

The migration generator is **idempotent for STALE entries** — re-running against the same chain state produces the same `removeFunctionAllowedRoles` calls. Side-effects: `fs.writeFileSync` (writing the migration file) + read-only RPC calls for the audit's event replay. The `manager.removeFunctionAllowedRoles(...)` lines in the generated file are _source code being written to disk_, not calls the generator executes. The actual on-chain step is the separate, manual `npx hardhat run audit/migrations/<file>.ts --network <name>`.

Operators sometimes need to hand-edit a generated file (add a one-off `revokeRole` for a stale relayer wallet, add a comment, etc.) and then re-generate later. The expected behavior:

### What the generator does on re-run

- **Always writes a new file** with a fresh ISO timestamp: `audit/migrations/<new-timestamp>-access-manager-drift.ts`. **Never overwrites** an existing file. The directory is an append-only candidate area.
- **Always reflects the chain's current state** at the moment of generation.
- **Does not know** about your hand edits in previous files. Each file is an independent snapshot.

### Best practices

1. **Don't keep stale generated files lying around.** After applying, move the file to a long-term archive location (S3 bucket, the PR record, `audit/migrations/applied/`) so `audit/migrations/` only ever contains **candidate** scripts.
2. **Treat each generated file as ephemeral.** The state-of-truth is the chain. If you're unsure what `<file>.ts` will do, run the audit again and regenerate.
3. **Hand-edited files lose idempotency.** Once you add a `revokeRole` or similar manual call, re-running the generator won't reproduce your edit — your hand-edited version is the source of truth until applied.
4. **To open a function to a non-admin role**, the change goes in the deploy task in `hardhat/tasks/deploy/*.ts` and gets re-deployed. The migration generator deliberately doesn't auto-emit `addFunctionAllowedRoles` — choosing which non-admin role should hold a function isn't derivable from the ABI, and granting `ADMIN` would be a no-op against the access invariant above.

## CI/CD guidance

### Recommended invocations per environment

| Environment                                  | Tasks                                                                                               |
| -------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Local dev (`docker/dev/deploy_contracts.sh`) | `audit:deploy-selectors` + per-chain `:onchain-selectors` and `:roles` (RELAYER) — already wired in |
| PR CI (lint only — no chain available)       | `npx hardhat audit:deploy-selectors --strict-unchecked`                                             |
| Release branch CI (against staging chain)    | `npx hardhat audit:all` (includes `--include-own-roles` automatically)                              |
| Production deploy                            | `npx hardhat audit:all` mandatory before promotion                                                  |

`audit:all` is the recommended CI entrypoint for any environment with a chain. It chains:

1. `audit:deploy-selectors --strict-unchecked`
2. `audit:pnh --include-own-roles`
3. For each PN in `PARTICIPANT_LIST`: `audit:pn --pn <X> --include-own-roles`
4. For each PN in `PARTICIPANT_LIST`: `audit:pc --pn <X> --include-own-roles`

Each child sets `process.exitCode` on findings without throwing, so all phases run and a single failed phase causes the CI step to exit 1.

### What `--strict-unchecked` does

`audit:deploy-selectors` reports three statuses per `iface.getFunction(arg)` call site:

| Status        | Meaning                                                                                                                                                                                                  |
| ------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **OK**        | First argument resolves to a string literal (directly, via `.map(['...']) → fn`, or via a `const name = 'literal'` binding) and the literal exists in the matching factory's current ABI.                |
| **MISSING**   | First argument resolves to a literal but does NOT exist in the current ABI. **Always exit 1** — the deploy will throw at runtime.                                                                        |
| **UNCHECKED** | First argument cannot be resolved (template string, ternary, dynamic property access, `.map` over a non-literal receiver chain > 1 deep). Informational by default. `--strict-unchecked` makes it fatal. |

Use `--strict-unchecked` in CI to gate against any future contributor introducing a pattern the resolvers can't handle without an explicit "I know this is dynamic, accept the blind spot" decision (with an inline code comment).

### Why local dev deliberately runs without `--strict-unchecked`

A dev mid-refactor may temporarily introduce a non-literal `getFunction` call. The lint's UNCHECKED finding is the right signal — but failing the local deploy on it would gate every dev iteration. CI is where it matters.

### `--from-block` and event-replay performance

The selectors and roles audits replay events from the AccessManager. On long-lived chains, scanning from block 0 is slow because most blocks before the AccessManager's deployment are empty.

Resolution ladder (`resolveStartingBlock` in `utils.ts`):

1. **Explicit `--from-block <N>`** — operator-supplied; always wins. Any non-empty value (including `0`) short-circuits the ladder. Only an omitted flag (empty string) walks the fallback steps below.
2. **Env-var fallback** — `PNH_STARTING_BLOCK` / `PRIVACY_NODE_<X>_STARTING_BLOCK` / `PRIVACY_NODE_<X>_PUBLIC_CHAIN_STARTING_BLOCK`. The deploy script writes these to `.env` automatically.
3. **Auto-detect** — `eth_getCode(<manager-addr>)` binary search. O(log chainHead) RPC calls.
4. **Default to 0** with a loud warning. To opt into this deliberately and silence the warning, pass `--from-block 0`.

The audit's verdict line reports the resolution source: `Block range scanned: 12345 → 67890  (source: env, PNH_STARTING_BLOCK)`.

### Surfacing audit failures in CI/CD pipelines

Exit codes alone aren't enough for prod operators. Recommended wiring:

- **Healthcheck** — the deploy script's `contracts_deploy_healthcheck.js` polls `/tmp/deploy_status`. The file's last written line follows the format `<progress>,<stage-name>`. Read the stage name, not the progress number.
- **Per-stage timing log lines** (`⏱  audit:<task> took Ns`) are already emitted. Plumb them through to your log aggregator to alert on per-audit-stage duration regressions.
- **Capture audit stdout** in the contracts container's logs. The STALE / MISSING / UNEXPECTED detail tables are essential for triage; raw `exit=1` is not.
- **Block deploy promotion on container health.** A passing audit at staging that fails at prod is exactly the signal you want — promote on healthcheck, not on container-started.

## CTS dependency

The RELAYER-mode role audit depends on the CTS HTTP endpoint (`CTS_SERVICE_<PN>_URL/public/addresses?service=<service>`) being reachable. If CTS is down or `CTS_SERVICE_<PN>_URL` is unset, the audit hard-fails with the attempted URL in the error message.

**Mitigation in `deploy_contracts.sh`:** the role audits run _after_ `authorize_relayer_async`, which has already gated on `wait_for_cts_keys`. So CTS has produced keys at least once by the time the audit fires.

**Recovery if CTS goes down mid-deploy:** the audit is read-only — no on-chain state cleanup is needed. Fix CTS and re-run the deploy. The container's healthcheck stays unhealthy until the audit passes.

**Don't disable the audit to "ship through."** If the alternative is silently mis-attributing relayer-role grants, taking the deploy outage and fixing CTS is the correct trade.

**Caveat: CTS can be wrong too.** CTS is the source of truth for "expected relayer wallets", but it could itself be advertising stale keys or missing fresh ones. The audit's value is the _diff_ between CTS and on-chain; the operator decides which side is right when they disagree. Periodically run the role audit in `--report-only` mode against the live chain to catch CTS drift that the per-deploy gate doesn't surface.

**Skip the CTS dependency entirely** with `--skip-relayers` — combine with `--include-own-roles` to audit only the static deploy-time grants when CTS is unavailable.

**Testability:** the `CtsFetcher` type in `utils.ts` is a DI hook — tests inject canned responses without standing up an HTTP server. The default fetcher (`defaultCtsFetcher`) uses axios against the env-var URL.

## External operators (Rayls users without docker/dev/deploy_contracts.sh)

The audit suite needs only the contracts repo + a populated `.env`:

1. Clone the contracts repo and run `npx hardhat compile`.
2. Populate `.env` with the env-vars listed above for the chain(s) you're auditing.
3. Run any task: `npx hardhat audit:pnh`, `npx hardhat audit:pn --pn A`, `npx hardhat audit:all`, etc.

Pass `--rpc <url>` and `--registry <addr>` directly to bypass env-var lookup entirely (one-off audits against arbitrary chains).

## Where to go next

- For the full task reference, status tables, and AccessManager invariant in detail: [`rayls-sovereign-contracts/docs/access-manager-migration.md`][repo-doc] and [`rayls-sovereign-contracts/hardhat/tasks/audit/README.md`][audit-readme].
- For the underlying AccessManager architecture: [Smart Contracts → Architecture](../../learn/components/smart-contracts/architecture.md).
- For role definitions and the business-role hierarchy: [Authorization Operations](authorization-operations.md).
