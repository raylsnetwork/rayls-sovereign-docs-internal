# Fault Injection

A controlled-failure testing facility built into the Rayls relayer. Tests can force the
relayer to crash, sleep, panic, or return a specific error at a *named line of code*,
then assert that the system recovers without violating any invariant (no token loss,
no double-spend, no inflation, no stuck state).

!!! danger "Test builds only"
    Fault injection is gated behind a Go build tag (`-tags faultinjection`) **and** a
    runtime flag (`FAULT_INJECTION_ENABLED`). Production binaries are built without the
    tag — every fault-point call compiles to a no-op and the HTTP control surface does
    not exist. A production binary is provably free of fault-injection machinery.

---

## Why it exists

The relayer connects systems with very different failure modes: Postgres, NATS
JetStream, the Private Network Hub, Privacy Nodes, KOS, the Proofs API, public chains.
Any of them can fail at any moment — between a database write and a NATS ack, midway
through a multi-leg atomic teleport, while a proof is being computed. The relayer must
survive every one of those failures without ever losing or duplicating an asset.

Reproducing those failures with unit tests is impractical: the timing windows are tiny,
the dependencies are external, and the failure paths are inherently asynchronous.
Fault injection solves this by letting a test say: *"crash the relayer the instant it
finishes inserting this row but before it acknowledges the message"* and then assert
that the post-restart state is correct.

**Business outcome.** Every recovery scenario that matters — relayer crashes mid-batch,
KOS times out, NATS redelivers a message we already processed — becomes a deterministic,
scripted test that runs on every CI build. We stop discovering these failure modes in
production.

---

## When to use it

Reach for fault injection when a test needs to verify *behaviour under failure*:

- **Crash-recovery and idempotency.** Crash the relayer at a specific cutpoint and
  assert that restart + redelivery never produces inflation, token loss, or
  double-spends.
- **Transient-error handling.** Return a `"timeout"` error from a downstream call and
  assert that the relayer retries, backs off, or escalates to revert — whichever branch
  production is supposed to take.
- **Slow-downstream / race windows.** Inject a `sleep` at one cutpoint to widen the
  window for a concurrent operation to interleave and confirm that the resulting race
  is benign.
- **Panic-recovery.** Force a panic at a cutpoint and assert that the supervisor /
  goroutine pool restores the service correctly.

If a test would be a no-op without injecting failure, it belongs here.

---

## Mental model

```
┌──────────────────────────────────────────────────────────────────────────┐
│  TEST  (TypeScript)                                                      │
│    1. POST /sessions       → server-assigned session UUID                │
│    2. POST /faults         → arm a rule at a cutpoint inside that session│
│    3. trigger production flow                                            │
│    4. GET /sessions/<id>   → read trigger log, assert invariants         │
│    5. DELETE /sessions/<id>→ teardown                                    │
└──────────────────────────────────────────────────────────────────────────┘
                                  │ HTTP, port 6660..6665 per relayer
                                  ▼
┌──────────────────────────────────────────────────────────────────────────┐
│  RELAYER  (Go, -tags faultinjection)                                     │
│                                                                          │
│    faultinjector.Check("enygma.handler.after_insert_history")            │
│           ↓                                                              │
│    Registry picks winning arm across all sessions                        │
│    (priority: crash > panic > error; sleep adds latency)                 │
│           ↓                                                              │
│    crash → os.Exit(1)                                                    │
│    panic → goroutine panic                                               │
│    sleep → time.Sleep(d)                                                 │
│    error → return *faultinjector.Error{Code, Message}                    │
└──────────────────────────────────────────────────────────────────────────┘
```

**Sessions** isolate tests from each other. Two parallel tests on the same relayer can
arm the same cutpoint without colliding. Each session owns its own rules and its own
trigger log.

**Cutpoints** are named lines of code in the relayer (e.g.
`enygma.handler.Receiver.HandleEnygmaCrossTransfer.after_insert_history`). Production
code calls `faultinjector.Check(name)`. When no rule is armed at that name, the call
returns immediately at near-zero cost.

**Rules** combine a cutpoint name with an action and optional payload. A rule armed in
session A doesn't affect session B's view of the same cutpoint.

**Equivalence classes** decide what happens when several sessions arm the same
cutpoint. Identical arms group; distinct arms fire FIFO across consecutive cutpoint
hits. The full rules — including the `error_code` discriminator covered below — are in
[`faultinjector/README.md`](https://github.com/raylsnetwork/rayls-sovereign-relayer/blob/main/faultinjector/README.md)
in the relayer repo.

---

## The four actions

| Action  | What happens at the cutpoint                                                   | Use case                                                  |
|---------|--------------------------------------------------------------------------------|-----------------------------------------------------------|
| `crash` | Process calls `os.Exit(1)` after flushing logs and persisting the consumed rule | NATS redelivery, restart-driven recovery paths             |
| `panic` | Goroutine panics with the rule's `message`                                     | Panic-recovery middleware, supervisor restart logic        |
| `sleep` | Cutpoint blocks for `duration_ms` milliseconds                                 | Timeouts, race windows, concurrent ordering tests          |
| `error` | Cutpoint's `Check()` returns a typed `*faultinjector.Error`                    | Retry / revert paths, transient-failure handling           |

### Discriminating error *types* — `error_code`

Real production code often handles different *kinds* of errors at the same line with
different behaviour: retry on a transient timeout, revert on a permanent failure, back
off on a rate-limit. Rather than instrumenting three cutpoints, arm the same cutpoint
with three `error_code` values:

```ts
import { FaultInjector, FAULT_POINTS } from '.../fault-injector';

const fi = FaultInjector.forRelayer('A');
const sA = await fi.newSession();
const sB = await fi.newSession();
const sC = await fi.newSession();

await sA.arm({ point: FAULT_POINTS.EXECUTOR_BEFORE_EXECUTE, action: 'error', error_code: 'timeout',           one_shot: true });
await sB.arm({ point: FAULT_POINTS.EXECUTOR_BEFORE_EXECUTE, action: 'error', error_code: 'db_locked',         one_shot: true });
await sC.arm({ point: FAULT_POINTS.EXECUTOR_BEFORE_EXECUTE, action: 'error', error_code: 'permanent_failure', one_shot: true });
```

Production reads the code via `CodeOf(err)` and branches:

```go
if err := faultinjector.Check(point); err != nil {
    switch faultinjector.CodeOf(err) {
    case "timeout":           // retry with backoff
    case "db_locked":         // yield this batch, take the next
    case "permanent_failure": // surface upstream so the orchestrator reverts
    default:                  // no FI / unknown: bubble up
    }
    return err
}
```

Three consecutive cutpoint hits return the three codes in arm order (FIFO across
sessions, oldest first). The test reads the trigger log to confirm *which* arm fired:

```ts
const events = await sA.triggerEvents(FAULT_POINTS.EXECUTOR_BEFORE_EXECUTE);
expect(events[0].code).to.equal('timeout');
```

---

## End-to-end example

A complete resilience test that drives the relayer's retry branch by injecting a
`timeout`-class error, then confirms the system reached the expected end state.

```ts
import { FaultInjector, FAULT_POINTS } from '.../fault-injector';
import { compose } from '.../docker-compose';
import { expect } from 'chai';

describe('Enygma retry on transient executor failure', () => {
  let fi, session;

  before(async () => {
    // '127.0.0.1' is required when tests run on the host (outside Docker) —
    // the FI control surface for each relayer is exposed on a localhost port
    // (6660..6665 for relayer-a..relayer-f). Omit the host override only when
    // the test process runs inside the same compose network as the relayer.
    fi = FaultInjector.forRelayer('A', '127.0.0.1');
    session = await fi.newSession();
  });

  after(async () => {
    // Belt and suspenders: ensure relayer-A is up before dropping the session.
    // A neighbour test may have armed `crash`/`panic` and taken it down even
    // though our `error` arm fired cleanly.
    if (!(await fi.isAlive())) {
      compose.start('relayer-a');
      await fi.waitUntilAlive(180_000);
    }
    await session.clear();
  });

  it('retries cross-transfer on timeout-class error from the executor', async () => {
    // Arm: next time the executor is invoked, return a typed timeout error.
    await session.arm({
      point: FAULT_POINTS.EXECUTOR_BEFORE_EXECUTE,
      action: 'error',
      error_code: 'timeout',
      message: 'simulated executor timeout',
      one_shot: true,            // consume after one fire
    });

    // Trigger the relayer flow that hits the cutpoint (test-domain helper).
    await driveEnygmaCrossTransfer({ from: 'A', to: 'B', amount: 100n });

    // MANDATORY under the parallel-test contract: wait for our fault to fire
    // AND verify the relayer is healthy. A neighbour test may have armed
    // `crash` or `panic` at the same cutpoint — assertLiveAfter polls both
    // conditions (relayer alive + this session's log contains the point)
    // before returning, and throws on timeout.
    await session.assertLiveAfter(FAULT_POINTS.EXECUTOR_BEFORE_EXECUTE, 60_000);

    // Confirm: our error_code fired (not a neighbour's at the same cutpoint).
    // Sessions are isolated, so status().log only contains events from this
    // session's arms — under multi-arm FIFO a neighbour's different
    // error_code lands in their log, not ours.
    const { log } = await session.status();
    const fired = log.find(e => e.point === FAULT_POINTS.EXECUTOR_BEFORE_EXECUTE);
    expect(fired?.code).to.equal('timeout');

    // Confirm: the eventual end state is correct (transfer landed after the
    // retry, not lost in the failed first attempt).
    await assertBalances({ A: 900n, B: 100n });
  });
});
```

---

## Crash recovery, panic, and offline patterns

The example above uses `action: 'error'`, which the relayer surfaces as a typed
return value — the process keeps running. Tests that exercise `crash`, `panic`,
or a hard outage need a different lifecycle. Two contracts to internalise:

- **Restart is manual.** `fi.assertLiveAfter(point, ...)` only *polls* — it waits
  for the relayer to be healthy and for `point` to appear in this session's log,
  but it never starts a container. After a crash, the test code must call
  `compose.restart(...)` itself.
- **Docker Compose does not auto-restart the relayer services.** The
  `docker-compose.dev-local.yml` deliberately omits `restart: unless-stopped` on
  relayers so a crashed process stays crashed until the test brings it back —
  this is what makes "did the redelivery path mint twice?" testable.

### Crash test lifecycle

```ts
import { compose } from '.../docker-compose';
import { FaultInjector, FAULT_POINTS } from '.../fault-injector';

const fi = FaultInjector.forRelayer('A', '127.0.0.1');
const session = await fi.newSession();

// 1. Arm the crash at a named cutpoint.
await session.arm({
  point: FAULT_POINTS.AFTER_CROSS_TRANSFER,
  action: 'crash',
  one_shot: true,
});

// 2. Trigger the production flow that should reach the cutpoint.
await driveEnygmaCrossTransfer({ from: 'A', to: 'B', amount: 100n });

// 3. Block until the relayer is observed to be down.
//    Throws on timeout — that means production never hit the cutpoint.
await fi.waitForCrash();

// 4. Restart the container yourself. assertLiveAfter would not do this.
compose.restart('relayer-a');
await fi.waitUntilAlive(180_000);

// 5. Grace period for async redelivery / restart-driven recovery (varies by
//    flow; 30–60s is typical for NATS-driven Enygma paths).
await new Promise(r => setTimeout(r, 45_000));

// 6. Assert the post-recovery invariant (no inflation / no token loss /
//    correct end state).
await assertNoInflation({ token: tokenB, expectedSupply });
```

`waitForCrash()` and `waitUntilAlive()` are methods on `FaultInjector` — use
those rather than re-implementing polling loops. The cleanup section below
covers the `after()` hook.

### Panic action

`action: 'panic'` is implemented in the framework and unit-tested in
[`faultinjector_test.go`](https://github.com/raylsnetwork/rayls-sovereign-relayer/blob/story/75/faultinjector/faultinjector_test.go)
(multi-arm FIFO across sessions, equivalence classes, `crash > panic > error`
priority, persistence). The TypeScript API surface — arming a panic rule,
round-tripping through `status()`, multi-session isolation — is covered by
[`FaultInjector_Panic.ts`](https://github.com/raylsnetwork/rayls-sovereign-tests-automation/blob/story/75/test/e2e/security/resilience/FaultInjector_Panic.ts).

**What's not specified by the framework:** whether firing a panic at a
specific cutpoint *takes the relayer down* depends on the calling goroutine's
recover()-handler chain in the production code. Net/http handlers typically
recover and return 500; background workers vary. Treat panic-firing the same
way you'd treat crash-firing: arm it, trigger, then `waitForCrash()`-then-
restart if the cutpoint's goroutine has no upstream recover, or use
`assertLiveAfter()` if it does. Verify experimentally for your chosen cutpoint
before relying on the behaviour.

### Offline-period pattern (no fault injection)

When the goal is to test "what happens while a service is unreachable" rather
than "what happens after a specific cutpoint fires", skip the FI machinery
entirely and drive the container directly:

```ts
import { compose } from '.../docker-compose';

// 1. Stop the service.
compose.stop('relayer-b');

// 2. Exercise state during the outage (e.g. attempt double-release on a
//    lock contract; the relayer can't process the event).
await tokenBAsAttacker.unlock(victim.address, AMOUNT);

// 3. Wait long enough for the system's internal timeout to elapse —
//    typical atomic-flow timeout in dev-local is 60s, so 70s is a safe minimum.
await new Promise(r => setTimeout(r, 70_000));

// 4. Bring the service back. Once `start` returns the container is up, but
//    async catch-up work (NATS redelivery, recovery loops) may take longer.
compose.start('relayer-b');

// 5. Poll for the post-recovery state.
await waitForExpectedSupply({ token: tokenA, expected: expectedSupplyAfter });
```

`compose.stop` sends SIGTERM (graceful, ~10s); `compose.kill` sends SIGKILL
(immediate); `compose.restart` is equivalent to `stop` + `start`. Use `kill`
only when testing ungraceful-termination paths.

### Cleanup — belt and suspenders

Every fault-injection test must restore relayer state in `after()`. A
neighbour test running in parallel may have armed `crash`/`panic` on the same
relayer and taken it down even if your test arm fired cleanly — so don't
assume the relayer is alive at cleanup time:

```ts
after(async () => {
  try {
    // 1. If a fault (ours or a neighbour's) took the relayer down, restart it.
    if (!(await fi.isAlive())) {
      compose.start('relayer-a');
      await fi.waitUntilAlive(180_000);
    }
    // 2. Drop the session. clear() swallows 404 — idempotent.
    if (session) await session.clear();
  } catch { /* best-effort */ }
});
```

If your test stopped any container directly (e.g. `compose.stop('relayer-b')`
in an offline-period test), also restart it explicitly in `after()` — even if
no FaultSession is involved. Best practice: every service the test
shuts down, kills, or crashes must be brought back in cleanup.

---

## Reference tests — read these in order

The synthetic example above is illustrative. To see how real resilience tests are
structured against the live relayer set, read these three files in order. They're
maintained in the tests-automation repo and exercise the same framework the example
sketches.

1. **Framework tour — [`FaultInjector_Sessions.ts`](https://github.com/raylsnetwork/rayls-sovereign-tests-automation/blob/story/75/test/e2e/security/resilience/FaultInjector_Sessions.ts)** (~330 lines)
    *Teaches:* the full `FaultInjector` / `FaultSession` API in isolation — sessions, arms, trigger logs, multi-session isolation, persistence across restart.
    *Look for:* `FaultInjector.forRelayer('A')` + `await fi.newSession()` as the canonical setup.

2. **Error-code steering — [`FaultInjector_ErrorCodes.ts`](https://github.com/raylsnetwork/rayls-sovereign-tests-automation/blob/story/75/test/e2e/security/resilience/FaultInjector_ErrorCodes.ts)** (~130 lines)
    *Teaches:* how to drive a specific production branch (retry vs revert vs back-off) by arming the same cutpoint with different `error_code` values across sessions.
    *Look for:* the FIFO-across-sessions assertion against `session.triggerEvents(point)[0].code`.

3. **Crash-recovery against real blockchain state — [`Enygma_ReferenceId_Idempotency.ts`](https://github.com/raylsnetwork/rayls-sovereign-tests-automation/blob/story/75/test/e2e/security/resilience/Enygma_ReferenceId_Idempotency.ts)** (~330 lines)
    *Teaches:* the canonical crash → restart → assert-invariant cycle (`AFTER_CROSS_TRANSFER` crash → NATS redelivery → assert no token inflation).
    *Look for:* the post-trigger liveness gate (`fi.waitUntilAlive(180_000)`) and the state-rich `expect(...)` failure message naming the specific invariant.

!!! tip "Writing your own?"
    The [resilience README](https://github.com/raylsnetwork/rayls-sovereign-tests-automation/blob/story/75/test/e2e/security/resilience/README.md) has the full test-design contract and a copy-paste authoring template.

---

## Production safety

How we know production binaries can't fault-inject:

1. **Build-tag gating.** `faultinjector/faultinjector.go` starts with
   `//go:build faultinjection`. Without the tag, this file is not compiled. A sibling
   `noop.go` (built only **without** the tag) provides empty stubs: `Check()` returns
   `nil`, `Enable()` is a no-op, `NewHTTPServer()` returns `nil`.
2. **Runtime flag gating.** Even with the tag, the HTTP control server only starts
   when `FAULT_INJECTION_ENABLED=true`. Production `.env` files do not set the flag.
3. **Two independent locks.** A misbuilt binary still requires an explicit env-var
   flip to expose the control surface. Neither alone is sufficient.

The dev-local environment intentionally compiles with the tag and sets the flag — every
relayer exposes its FI control surface on a distinct localhost port (6660 through
6665, one per `relayer-a..relayer-f`).

### Enabling FI in your build — the `BUILD_TAGS` mechanism

`Dockerfile.relayer-dev`, `Dockerfile.kos-dev`, and `Dockerfile.public-relayer-dev` all
honour a `BUILD_TAGS` build-arg / env-var that is threaded through both the initial
image build and `air`'s in-container hot-reload rebuild. To opt a dev container into
fault injection, set `BUILD_TAGS=faultinjection` in two places: the compose service's
`build.args` (used by the initial image build) and the same service's `environment`
(used by air on rebuild). The `docker-compose.dev-local.yml` shipped with the repo is
already wired this way for the services that need FI.

The production Dockerfiles (`Dockerfile.relayer`, `Dockerfile.kos`,
`Dockerfile.public-relayer`) deliberately do **not** expose `BUILD_TAGS` — they always
build with the empty tag set, so the `noop.go` path is the only one that can be
deployed.

For framework-local Go testing:

```bash
go test -tags faultinjection ./faultinjector/...   # exercises the full FI tree
go build ./...                                     # production path — noop.go
```

---

## References

- **Framework deep dive (relayer-side semantics, full HTTP API, persistence model):**
  [`faultinjector/README.md`](https://github.com/raylsnetwork/rayls-sovereign-relayer/blob/story/75/faultinjector/README.md)
- **Test-authoring guide (TS client, neighbour-tolerance contract, examples):**
  [`test/e2e/security/resilience/README.md`](https://github.com/raylsnetwork/rayls-sovereign-tests-automation/blob/story/75/test/e2e/security/resilience/README.md)
