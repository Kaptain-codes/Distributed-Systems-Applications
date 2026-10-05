# Merge Plan: Remote `dev` and Local Assignment 2 Changes

## 1. Current repository state

Captured on 2026-10-05:

- Current branch: `dev`
- Remote: `origin` (`https://github.com/Kaptain-codes/Distributed-Systems-Applications.git`)
- Local `HEAD`: `961cc22`
- Remote `origin/dev`: `961cc22`
- Result: there is currently **no committed branch divergence**. The local and remote branch tips are identical after fetching.
- The worktree is dirty and contains local Assignment 2 changes that are not committed.
- The worktree also contains untracked files; these must be preserved during the integration.
- Git reports CRLF-to-LF normalization warnings for several Ballerina files. Review the resulting diff for accidental line-ending-only changes.
- Do not inspect, stage, or commit secrets from `Assignment-2\infra\docker\.env`. Use `.env.example` for configuration review.

The current remote baseline includes the admin/notification service refactor from commit `0c5a952`, incorporated by merge commit `961cc22`. The local uncommitted work is primarily in delivery/order services, Docker development tooling, database initialization, tests, and debug documentation.

## 2. Local work that must be preserved

### Modified tracked files

- `Assignment-2\README.md`
- `Assignment-2\debug-session-1.md`
- `Assignment-2\debug-session-4.md`
- `Assignment-2\infra\docker\README.md`
- `Assignment-2\infra\docker\initdb\delivery-db\01-schema.sql`
- `Assignment-2\infra\docker\scripts\reset-dev-data.ps1`
- `Assignment-2\infra\docker\scripts\start-dev.ps1`
- `Assignment-2\services\deliveryService\db.bal`
- `Assignment-2\services\deliveryService\kafka_runtime.bal`
- `Assignment-2\services\orderService\kafka.bal`
- `Assignment-2\services\orderService\kafka_consumer.bal`
- `Assignment-2\services\orderService\mongo_persistence.bal`
- `Assignment-2\services\orderService\service.bal`
- `Assignment-2\services\orderService\tests\service_test.bal`

### Untracked files

- `Assignment-2\debug-session-2.md`
- `Assignment-2\debug-session-5.md`
- `Assignment-2\docs\debug-index.md`
- `Assignment-2\infra\docker\docker-compose.scale.yml`
- `Assignment-2\infra\docker\initdb\delivery-db\tests\driver-claim-concurrency.ps1`
- `Assignment-2\infra\docker\scripts\check-consumers.ps1`

## 3. Safe integration procedure

Run these commands from the repository root in PowerShell. Stop if any command reports an unexpected result.

### 3.1 Reconfirm the baseline

```powershell
git status --short --branch
git fetch --prune origin
git rev-parse HEAD
git rev-parse origin/dev
git log --left-right --oneline HEAD...origin/dev
```

Expected result: `HEAD` and `origin/dev` remain equal, and the left/right log is empty.

### 3.2 Preserve the local worktree before any merge operation

Because the worktree contains both modified and untracked files, create a reversible WIP snapshot before changing branches or applying remote work:

```powershell
git stash push --include-untracked --message "pre-merge Assignment 2 local changes"
git stash list -1
git status --short --branch
```

Confirm that the worktree is clean and that the stash exists. If the stash command reports a problem, do not continue; preserve the files manually and investigate before merging.

### 3.3 Align the branch with remote

Since the branch tips currently match, this should be a no-op:

```powershell
git merge --ff-only origin/dev
```

If `origin/dev` advances between the fetch and this command, use the newly fetched tip as the baseline and record the new commit ID. Do not use `reset --hard`, and do not discard the stash.

### 3.4 Reapply the local changes

```powershell
git stash apply --index
git status --short
git diff --check
```

Use `apply` rather than `pop` until validation succeeds. If conflicts occur, keep the stash in place and resolve deliberately. The highest-risk files are:

- `Assignment-2\README.md`
- `Assignment-2\infra\docker\README.md`
- `Assignment-2\infra\docker\initdb\delivery-db\01-schema.sql`
- `Assignment-2\services\deliveryService\db.bal`
- `Assignment-2\services\deliveryService\kafka_runtime.bal`
- `Assignment-2\services\orderService\service.bal`
- `Assignment-2\services\orderService\kafka_consumer.bal`
- `Assignment-2\services\orderService\tests\service_test.bal`

The current remote refactor is in admin/notification services, so no direct conflict is expected with the listed local files. Still, resolve by behavior and current documentation rather than accepting one side wholesale.

## 4. Review and commit strategy

Before committing, inspect the complete staged candidate and ensure `.env` is not included:

```powershell
git status --short
git diff -- Assignment-2
git diff --name-only --cached
git diff --cached --check
```

Stage only the intended Assignment 2 files. Keep the changes logically grouped where practical:

1. Delivery/order service and test changes.
2. Docker scripts, scale compose file, schema, and database concurrency test.
3. Documentation and debug-session/index files.

Use descriptive commits, for example:

```text
Implement delivery concurrency and consumer diagnostics
Update local Docker development workflow
Document Assignment 2 debugging and validation
```

Each commit should include the repository-required co-author trailer:

```text
Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>
```

After the commits, verify:

```powershell
git status --short --branch
git log --oneline --decorate -5
git diff origin/dev...HEAD --stat
```

Do not delete the pre-merge stash until the commits and validation are complete. Once the working tree is verified and the commits contain all intended files, remove only the named stash:

```powershell
git stash drop stash@{0}
```

## 5. Validation gates

Run validation from `Assignment-2` after the merge/reapply step and again after resolving any conflicts.

### Ballerina checks

```powershell
Set-Location Assignment-2\shared\contracts
bal test

Set-Location ..\services\orderService
bal test

Set-Location ..\..\gateway
bal build
```

Also run `bal test` or `bal build` for `deliveryService` if its local changes are included in the final commit.

### Docker and Compose checks

```powershell
Set-Location Assignment-2\infra\docker
docker compose --env-file .env.example -f docker-compose.yml config --quiet
docker compose -f docker-compose.yml -f docker-compose.scale.yml --profile delivery config --quiet
```

If Docker is available, start the relevant profile and verify service health before running the ordered acceptance scripts:

```powershell
.\scripts\start-dev.ps1
.\scripts\check-consumers.ps1
.\scripts\test-at-1.ps1
.\scripts\test-at-2.ps1
.\scripts\test-at-3.ps1
.\scripts\test-at-4.ps1
.\scripts\test-at-5.ps1
.\scripts\test-at-duplicate-ready.ps1
```

For the delivery concurrency change, additionally run:

```powershell
.\initdb\delivery-db\tests\driver-claim-concurrency.ps1
```

Record any environment-dependent failures separately from merge conflicts. Do not weaken tests or silently skip a failing service.

## 6. Final acceptance criteria

- `HEAD` contains the current `origin/dev` baseline plus the intended local Assignment 2 changes.
- No local changes or untracked files were lost.
- `.env` contents were not exposed, staged, or committed.
- `git diff --check` is clean, aside from any deliberately documented line-ending normalization.
- Ballerina tests/builds and Docker Compose configuration checks pass, or failures are documented with their cause.
- The final worktree is clean.
- Push only after reviewing the commit list and confirming the target branch is `dev`:

```powershell
git push origin dev
```

## 7. Plan: merge `origin/customer-service-impl` into `dev`

### Current state

Checked on 2026-10-05:

- `dev` and `origin/dev` are both at `961cc22`.
- `origin/customer-service-impl` is at `a23d516`.
- The feature branch has three commits not reachable from `dev`:
  - `f5cbc3e` — customer-service MySQL client, schema initialization, endpoints, and Compose environment wiring.
  - `f768dda` — order-service state machine, Kafka producer, customer validation, and Mongo persistence.
  - `a23d516` — customer table-name fix and seeded test customers.
- The local worktree is dirty and contains both tracked and untracked Assignment 2 changes. Do not merge until those changes are safely checkpointed.

### Scope of the incoming branch

The branch changes these nine paths:

- `Assignment-2\infra\docker\docker-compose.yml`
- `Assignment-2\infra\docker\initdb\customer-db\01-schema.sql`
- `Assignment-2\services\customerService\Ballerina.toml`
- `Assignment-2\services\customerService\Dependencies.toml`
- `Assignment-2\services\customerService\db.bal`
- `Assignment-2\services\customerService\service.bal`
- `Assignment-2\services\orderService\Dependencies.toml`
- `Assignment-2\services\orderService\db.bal`
- `Assignment-2\services\orderService\service.bal`

### Recommended sequence

1. **Freeze and record the current state**
   ```powershell
   git fetch --prune origin
   git status --short --branch
   git rev-parse dev
   git rev-parse origin/dev
   git rev-parse origin/customer-service-impl
   git diff --check
   ```
   Do not read or stage `Assignment-2\infra\docker\.env`.

2. **Create a reversible checkpoint for all local work**
   ```powershell
   git stash push --include-untracked --message "pre-customer-service-impl merge local Assignment 2 work"
   git stash list -1
   git status --short --branch
   ```
   Confirm the worktree is clean and the stash exists before merging. Use `apply` rather than `pop` later so recovery remains possible.

3. **Merge the remote feature branch into `dev`**
   ```powershell
   git switch dev
   git merge --no-ff origin/customer-service-impl
   ```
   The merge is expected to require conflict resolution because the incoming branch is based on the older `3bda383` line while `dev` contains the later admin/notification refactor at `0c5a952` and merge commit `961cc22`.

4. **Resolve conflicts by behavior, not by choosing one side wholesale**
   Prioritize:
   - `Assignment-2\infra\docker\docker-compose.yml`: combine customer database wiring with the current service profiles, ports, health checks, and local development changes.
   - `Assignment-2\services\orderService\service.bal`: reconcile incoming customer validation/state-machine behavior with the local Kafka, persistence, and delivery changes.
   - `Assignment-2\services\orderService\Dependencies.toml`: retain compatible dependency versions and avoid duplicate or stale entries.
   - `Assignment-2\services\customerService\service.bal` and `db.bal`: verify the new endpoints and MySQL client do not conflict with current service conventions.
   - `Assignment-2\services\customerService\Ballerina.toml` and both `Dependencies.toml` files: regenerate or validate lock/dependency metadata only after the intended versions are settled.
   - `Assignment-2\infra\docker\initdb\customer-db\01-schema.sql`: preserve the corrected table name and test seed data while matching database initialization conventions.

5. **Reapply local uncommitted work after the merge**
   ```powershell
   git stash apply --index
   git status --short
   git diff --check
   ```
   Expect possible additional conflicts in `docker-compose.yml` and `orderService\service.bal`. Resolve these against the merged feature behavior and retain the local diagnostics, tests, and UI/client files unless they are intentionally superseded.

6. **Validate the merged result**
   ```powershell
   Set-Location Assignment-2\shared\contracts
   bal test

   Set-Location ..\services\customerService
   bal test

   Set-Location ..\orderService
   bal test

   Set-Location ..\..\gateway
   bal build

   Set-Location ..\infra\docker
   docker compose --env-file .env.example -f docker-compose.yml config --quiet
   docker compose -f docker-compose.yml -f docker-compose.scale.yml --profile all config --quiet
   ```
   If Docker is available, start the customer/order dependencies and verify health endpoints, customer validation, order creation, Kafka events, and persistence before running the existing acceptance scripts.

7. **Review and commit**
   ```powershell
   git diff --name-only --diff-filter=U
   git diff --check
   git status --short
   ```
   Confirm there are no unmerged paths, `.env` is not staged, and all intended local files are present. Commit the merge and local work in logically grouped commits with the required co-author trailer. Drop the pre-merge stash only after the final validation succeeds.

### Pros

- Adds the missing customer-service persistence and API implementation.
- Connects order creation to customer validation, state transitions, Kafka publication, and Mongo persistence.
- Adds customer database initialization and seed data, improving reproducibility of local integration tests.
- Keeps the feature history available in `dev` as an explicit merge, which makes the integration auditable.
- Brings customer/order behavior into the same branch used by the current delivery and notification work.

### Cons and risks

- The branch is based on an older `main` commit, so it may overwrite or conflict with current `dev` conventions and later service changes.
- `docker-compose.yml` and `orderService\service.bal` overlap with uncommitted local work, creating a high risk of losing local Kafka/concurrency fixes during conflict resolution.
- Dependency manifest changes can introduce version drift, generated lockfile churn, or incompatible Ballerina libraries.
- Customer validation adds a runtime dependency on MySQL availability and correct schema initialization; existing tests may become environment-sensitive.
- The order-service state machine and persistence changes can alter existing acceptance-test behavior, especially around duplicate events, cancellation, and delivery transitions.
- A merge commit will make rollback more involved than a fast-forward or isolated cherry-pick.

### Current blockers

1. **Dirty worktree:** tracked and untracked local Assignment 2 changes must be checkpointed before merging.
2. **Direct file overlap:** local edits and incoming changes both affect `docker-compose.yml` and `orderService\service.bal`.
3. **Branch age/divergence:** the feature branch is based on `3bda383`, while `dev` includes later service refactors and merge history.
4. **Unverified compatibility:** Ballerina tests/builds and Compose configuration have not yet been run against the combined result.
5. **Environment dependency:** end-to-end validation requires Docker, Kafka, MySQL, MongoDB, and the configured local environment; `.env` must remain private.
6. **Behavioral uncertainty:** customer validation and order state-machine changes need explicit regression checks against the existing acceptance scripts before push.

### Merge decision gate

Proceed only if the local work is checkpointed and the team accepts resolving the two high-overlap files manually. If preserving the current local work is more important than integrating the feature immediately, first commit the local changes on a separate WIP branch, then perform the merge on `dev`. Do not push until all conflicts are resolved and the targeted Ballerina and Compose checks pass.
