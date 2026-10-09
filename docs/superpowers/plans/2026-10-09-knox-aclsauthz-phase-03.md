# Apache Knox AclsAuthz Phase 03 Implementation Plan

> Work on `feat/demo-ver-1-knox-gateway`. Read only Master, the latest completed handoff, and Phase 03 spec until its gate passes.

**Goal:** Demonstrate that a correct LDAP login can still be denied at Knox by a real WebHDFS service ACL, while an authorized identity reaches real HDFS.

**Architecture:** Keep the normal `demo` topology restricted to `admin;*;*` for `webhdfs.acl`. Use a separate test-only Compose override and topology fixture to reverse the ACL to `guest;*;*` during the acceptance test, then restore the normal topology in `finally`. This proves that the observed allow/deny direction follows AclsAuthz policy rather than a fixed test expectation.

**Evidence design:** Distinguish invalid credentials (HTTP 401 plus Shiro `INVALID_CREDENTIALS`) from a valid-but-denied user (the actual observed Knox response plus fresh authorization-failure audit event). Confirm the allowed admin request returns WebHDFS JSON. Compare NameNode audit-log `listStatus` evidence around admin and denied guest requests to determine whether the denied request reached the backend.

**Version-checked references:** The official Knox user guide documents `AclsAuthz` and `{serviceName}.acl` as `user;group;IP`, with AND semantics by default. Apache Knox 3.0.0 source shows `AclsAuthorizationFilter` calls the chain only when allowed; when denied it audits `Action.AUTHORIZATION` / `FAILURE` and sends HTTP 403. Docker Compose documents later files overriding a duplicate volume target. Context7 found only an unrelated Knox VS Code extension, so use Apache's own user guide and v3.0.0 source for Knox behavior.

## Constraints

- Keep the existing branch and named HDFS volumes; never use `docker compose down -v`.
- Keep LDAP and HDFS inside the private backend network. Use Knox HTTPS `127.0.0.1:8443`.
- Preserve Phase 02 authentication tests by changing their valid principal to the ACL-allowed `admin`; wrong credentials must still fail at authentication.
- Do not treat a 403 alone as proof. Require a fresh Knox authorization failure audit and check for a corresponding backend audit request.
- The expected policy is admin allow / guest deny. If live Knox returns a status other than 403, capture status, headers, audit and gateway logs; stop and report a blocker without changing the screen C requirement.
- Test the reversed policy (guest allow / admin deny) on the real Knox Gateway, then restore the default policy even after failures.

## Task 1: Write the authorization acceptance test first

Files:
- Create `demo/tests/Test-KnoxAuthorization.ps1`.
- Test against the current Phase 02 topology before adding AclsAuthz; the valid guest request should expose the missing deny and exit nonzero.

Checks:
1. Compose config and start/readiness using base + Knox overlay.
2. Seed HDFS idempotently with `-IncludeKnoxOverlay`.
3. Assert admin credentials return HTTP 200 with both seeded `pathSuffix` values.
4. Assert guest valid credentials are denied with the measured authorization status and no Basic challenge; capture fresh `gateway-audit.log` authorization failure.
5. Assert guest invalid credentials remain HTTP 401 and `INVALID_CREDENTIALS` is present.
6. Enable the guest-allow test topology using an additional Compose file; assert guest returns 200 and admin is denied.
7. In `finally`, restore the default topology and assert readiness; never remove volumes.

## Task 2: Configure the real service ACL and an isolated policy-reversal fixture

Files:
- Modify `demo/knox/topologies/demo.xml` with `AclsAuthz` and `webhdfs.acl=admin;*;*`.
- Create `demo/knox/topologies/demo-guest-allow.xml` as a test-only variant with `webhdfs.acl=guest;*;*`.
- Create `demo/docker-compose.knox-acl-test.yml` to override the topology bind source at the same container target during reversal.

Keep the standard Compose overlay and HDFS base file unchanged. Verify the effective mount source with `docker compose config` before using the test override.

## Task 3: Preserve authentication coverage and add origin evidence

Files:
- Modify `demo/tests/Test-KnoxGateway.ps1` to use `admin` as its valid account and `admin` with a wrong password for its authentication-negative case.
- Modify `demo/README.md` to explain the difference between authentication and authorization; show admin allow and guest deny commands.
- Add `demo/tests/Test-KnoxAuthorization.ps1` checks for Knox audit failure and NameNode audit behavior around the denied request.

Do not attribute an HDFS/Ranger denial to Knox. Validate the HDFS audit counter using the successful admin request as control, then check whether the guest denial generated another `listStatus` backend event.

## Task 4: Verify and hand off

- Run the ACL test on the existing project and a fresh project/volume if the runtime budget permits; retain volumes.
- Confirm normal topology is restored, Compose reports healthy services, admin returns HTTP 200, guest gets the observed Knox denial, and invalid credentials remain HTTP 401.
- Re-run the Phase 02 Gateway test with admin as the allowed user, Compose config, XML parsing and PowerShell parsing.
- Record exact status, response headers, authorization audit event, backend audit observations, test output, version, timestamp and timezone.
- Commit implementation/config/tests first, then a separate Phase 03 handoff commit containing the implementation SHA; push both to the feature branch. No PR.
