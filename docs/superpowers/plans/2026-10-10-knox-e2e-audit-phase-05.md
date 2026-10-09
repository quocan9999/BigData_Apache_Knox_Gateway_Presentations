# Knox E2E Audit Phase 05 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Run the five demo screens against the real Docker stack, prove audit outcomes for authentication, authorization, and dispatch, and exercise recoverable failure cases.

**Architecture:** Keep the existing scripts as the executable checks for host isolation, authentication, and AclsAuthz. Extend them to assert fresh audit records for screens B–D, add a failure-injection script for missing route/backend/readiness timeout, then add a PowerShell runner that records local logs and summarizes A–E.

**Tech Stack:** Windows PowerShell 5.1, Docker CLI/Compose, Apache Knox 3.0.0-release, Hadoop 3.4.3, WebHDFS.

**Spec:** docs/demo-ver-1/spec/phase-05-kiem-thu-va-audit.md

## Global Constraints

- Use the real Knox and Hadoop containers; do not mock WebHDFS or fabricate audit output.
- Host access goes through Knox at 127.0.0.1:8443; NameNode port 9870 stays unpublished.
- Use PowerShell Windows and curl.exe for the main run path.
- Keep the named HDFS volumes; do not run docker compose down -v.
- Measure HTTP status and audit outcome from the running stack; do not infer the source of a 401 or 403 from status alone.
- Demo credentials are lab-only and must not be printed into runner logs or committed as personal secrets.
- Restore LDAP, Knox, and HDFS after each failure injection; report failed restoration explicitly.
- Commit implementation and Phase 05 handoff separately with Vietnamese Conventional Commit messages; push both to the feature branch without creating a PR.

## Review Focus

- Invalid credentials can create an access audit record with response status 401 while authentication itself fails; assert the authentication/principal/failure record.
- An ACL denial must identify guest, WEBHDFS, authorization, the inbound URI, and failure, and must not reach NameNode.
- An allowed admin request must contain a real WebHDFS JSON listing both seeded files and a successful NameNode dispatch audit event.
- Stopping NameNode must not produce a fake HTTP 200 or FileStatuses body; restore readiness before later checks.
- A missing service route and a deliberately short readiness timeout must fail for the expected reason, then the normal route must recover.

---

### Task 1: Authentication audit and Screen B

**Files:**
- Modify: demo/tests/Test-KnoxGateway.ps1

**Interfaces:**
- Keep the current ProjectName and TimeoutSeconds parameters.
- Use the existing Compose prefix, curl.exe request helper, and Gateway log path.
- Add audit helpers that read the line offset and fresh records from /home/knox/knox/logs/gateway-audit.log.

- [x] Add a fresh audit assertion around the invalid-password request. Require HTTP 401, the Knox INVALID_CREDENTIALS diagnostic, and an authentication event with principal admin and outcome failure; do not treat the access event’s response-status outcome as authentication success.
- [x] Emit a stable SCREEN B PASS line only after all three assertions pass.
- [x] Run the focused authentication script and inspect the fresh Knox audit excerpt; confirm that no password is printed.

    Set-Location demo
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/Test-KnoxGateway.ps1 -TimeoutSeconds 180

### Task 2: Authorization, dispatch audit, and Screens C–E

**Files:**
- Modify: demo/tests/Test-KnoxAuthorization.ps1

**Interfaces:**
- Keep the current ProjectName and TimeoutSeconds parameters.
- Reuse Get-GatewayLogLineCount and Get-GatewayLogSince for the gateway audit path.
- Preserve the current default-policy restoration behavior and guest-allow overlay test.

- [x] Capture a fresh audit offset before the allowed admin request. Require an admin WEBHDFS dispatch record for the NameNode URI with outcome success and HTTP response 200.
- [x] Capture a fresh audit offset before the invalid-password request. Require an authentication/principal/guest/failure record as well as INVALID_CREDENTIALS.
- [x] Keep the existing guest ACL denial proof and add a SCREEN C PASS line only after the Knox authorization failure and unchanged NameNode audit count are both confirmed.
- [x] Emit SCREEN D PASS after the allowed response and NameNode forwarding evidence pass.
- [x] Emit SCREEN E PASS only after the test has checked fresh audit evidence for admin dispatch success, guest authorization failure, and invalid-password authentication failure.
- [x] Run the focused authorization script and verify each event against the current runtime record structure.

    Set-Location demo
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/Test-KnoxAuthorization.ps1 -TimeoutSeconds 180

### Task 3: Recoverable failure injection

**Files:**
- Create: demo/tests/Test-KnoxFailureInjection.ps1
- Create: demo/tests/fixtures/docker-compose.knox-healthcheck-failure.yml

**Interfaces:**
- Parameters: ProjectName defaults to apache-knox-bigdata-demo; TimeoutSeconds uses the existing 30–600 second range.
- Compose files: docker-compose.yml and docker-compose.knox.yml.
- Log directory: use the OS temporary directory for request bodies and diagnostics; delete only this test’s temporary files.
- Restoration: in finally, start the full project with the normal timeout, then call Wait-HdfsReady.ps1 and Wait-KnoxReady.ps1. Never remove named volumes.

- [x] Validate resolved Compose config, start/wait for the stack, seed the two files idempotently, and capture the normal admin HTTP 200 response.
- [x] Call the authenticated missing-service URL /gateway/demo/missing-service/v1/demo?op=LISTSTATUS. Require measured HTTP 404, reject FileStatuses JSON, and require a fresh Knox access audit event for that exact URI and response status.
- [x] Stop NameNode, make the normal authenticated WebHDFS request, require a non-200 response without the two-file JSON, and capture fresh Knox dispatch or gateway connectivity evidence. Start NameNode and wait for HDFS before continuing.
- [x] Stop Knox Gateway, force-recreate it using the failing-healthcheck Compose fixture with --wait --wait-timeout 5, require nonzero Compose exit plus a timeout/unhealthy diagnostic, then recreate it with the default topology and wait for normal Knox recovery.
- [x] In finally, restore all services and assert that the normal admin request again returns both files. Fail the script if recovery cannot be confirmed.
- [x] Run the failure-injection script on the real stack and record the measured status for route-missing and backend-down cases.

    Set-Location demo
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/Test-KnoxFailureInjection.ps1 -TimeoutSeconds 180

### Task 4: Five-screen runner and operator instructions

**Files:**
- Create: demo/tests/Test-KnoxDemo.ps1
- Modify: demo/README.md
- Modify: demo/tests/Test-KnoxBackendIsolation.ps1

**Interfaces:**
- Runner parameters: ProjectName defaults to apache-knox-bigdata-demo; TimeoutSeconds defaults to 180.
- Child suites: Test-KnoxBackendIsolation.ps1 maps to A; Test-KnoxGateway.ps1 maps to B and LDAP outage; Test-KnoxAuthorization.ps1 maps to C/D/E; Test-KnoxFailureInjection.ps1 covers missing route, backend-down, timeout, and recovery.
- Logs: one new directory under the OS temporary directory per run; write one full output log per child suite; print its absolute path.
- Summary: print PASS, FAIL, or BLOCKED per screen plus PASS/FAIL for each failure-injection group; exit 0 only when A–E and all required injections pass.

- [x] Add a Docker preflight. If Docker Engine is unavailable, print BLOCKED for A–E with the diagnostic log path and exit nonzero without pretending a screen passed.
- [x] Invoke child scripts in order and capture stdout/stderr into separate local logs. Before each child, require the normal HDFS and Knox readiness checks; if recovery failed, mark dependent later screens BLOCKED.
- [x] Add SCREEN A PASS after the direct-host check, allowed Knox response, and restart checks all pass. Read stable SCREEN A–E markers from child logs; a missing marker means that screen did not pass.
- [x] Keep each completed screen’s marker distinct from later regression checks in the same child. A nonzero child exit must fail the relevant regression group and the whole runner, even when an earlier screen marker is present.
- [x] Update README with the one-command full run, summary meanings, temp log location, individual commands, and the rule that logs stay local and contain no credentials.
- [x] Run Test-KnoxDemo.ps1 and require every screen and failure-injection group to report PASS.

    Set-Location demo
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/Test-KnoxDemo.ps1 -TimeoutSeconds 180

### Task 5: Final verification and handoff

**Files:**
- Create: docs/demo-ver-1/handoff/phase-05-handoff.md

- [x] Parse every PowerShell script in demo/scripts and demo/tests with System.Management.Automation.Language.Parser.
- [x] Run Compose config validation and the full Test-KnoxDemo.ps1 once more; capture actual exit codes, HTTP results, audit records, service states, versions, and timestamp.
- [x] Run git diff --check; scan tracked changes for secrets and ensure temporary logs are outside the repository.
- [x] Request one independent read-only review. Resolve any Critical or Important finding and rerun the affected check.
- [ ] Commit implementation/tests/docs, record the full implementation SHA in the Phase 05 handoff, commit the handoff separately, push both commits, and verify the remote branch and clean worktree.
- [ ] Open Phase 06 only after the Phase 05 handoff is DONE and pushed.
