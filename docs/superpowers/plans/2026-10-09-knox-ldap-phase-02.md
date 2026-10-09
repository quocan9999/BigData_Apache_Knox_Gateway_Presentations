# Apache Knox + LDAP Phase 02 Implementation Plan

> For agentic workers: use superpowers:executing-plans to run these tasks task by task. Keep the work on feat/demo-ver-1-knox-gateway.

**Goal:** Run the official Apache Knox gateway with its real demo LDAP and proxy authenticated HTTPS requests to the existing HDFS WebHDFS service.

**Architecture:** Keep the existing HDFS stack in docker-compose.yml and add a consistently used Compose overlay for Knox Gateway and Knox Demo LDAP. Mount a dedicated demo topology into the official Knox image; use Shiro Basic LDAP authentication, Default identity assertion, the real namenode:9870 WebHDFS backend, and loopback-only HTTPS on port 8443.

**Tech Stack:** Docker Compose; apache/knox:3.0.0-release pinned to manifest digest sha256:058733ba7de9b6f7a37f850a50db343ebb8d0e72bc6bd5ecf668736906f2034c; Apache Knox 3.0.0 release; bundled Knox Demo LDAP; PowerShell 5.1; real Hadoop HDFS 3.4.3.

**Spec:** docs/demo-ver-1/spec/phase-02-knox-ldap.md

## Global Constraints

- Keep the existing feature branch and named HDFS volumes; never use down -v.
- Keep NameNode/WebHDFS reachable to Knox on the private Docker backend network.
- Publish only Knox HTTPS as 127.0.0.1:8443 during this phase; Phase 04 closes the host NameNode port.
- Require four real services: NameNode, DataNode, Knox Gateway and Knox Demo LDAP.
- A valid demo LDAP account must reach real WebHDFS JSON; an invalid password must be rejected at Knox.
- The Phase 02 test and operator flow seed the expected HDFS files idempotently before checking the Knox route, including on fresh volumes.
- Pin a release tag and image digest; do not use latest.
- Document demo credentials as lab-only; do not commit personal keys or production credentials.
- If an overlay is used, all Phase 02 scripts and README commands use both docker-compose.yml and docker-compose.knox.yml.
- Keep Ranger, Kerberos, Spark, Hive, Kubernetes and production HA outside this demo.

## Preflight Verified

- Docker Hub identifies apache/knox as published by The Apache Software Foundation. Tag 3.0.0-release is available for linux/amd64 and linux/arm64. The pulled multi-architecture manifest digest is sha256:058733ba7de9b6f7a37f850a50db343ebb8d0e72bc6bd5ecf668736906f2034c; its linux/amd64 image digest is sha256:d67102356ab9190a8f8701e7e3d681b8b405b2a8508990f3e74957fed1c85d2c.
- Local Docker reports linux/x86_64. The pulled image runs as UID:GID 8000:0, sets JAVA_HOME=/opt/java/openjdk/17 and Temurin 17.0.20.1, uses ./entrypoint.sh from /home/knox/knox, and exposes 8443/tcp.
- The same release image includes bin/ldap.sh, bin/ldap.jar, conf/users.ldif and conf/topologies. Its guest and admin demo fixtures are guest/guest-password and admin/admin-password. The gateway entrypoint starts the Gateway; the LDAP service must explicitly run bin/ldap.sh start with KNOX_LDAP_RUNNING_IN_FOREGROUND=true.
- The release tag v3.0.0-release has hadoop.version 3.4.1 in its POM. This is a Hadoop 3 line; interoperability with the project's Hadoop 3.4.3 will be established by the live end-to-end test.
- Primary configuration references: Apache Knox 2.1 user guide for Shiro LDAP provider keys, Default identity assertion and WebHDFS URL mapping; Apache Knox 2.1 developer guide for Docker image entrypoint model; Apache Knox v3.0.0-release source POM; ASF Docker Hub image tags.
## Review Focus

1. Wrong passwords must be rejected at Knox with an authentication response, not mistaken for a backend connectivity failure. Test the challenge/status and gateway log.
2. An unavailable LDAP server must not allow the request; stop the LDAP service, verify valid credentials fail, then restart and verify recovery.
3. Topology paths must map the client URL to the correct Hadoop 3 WebHDFS URL and return live JSON for both seed files.
4. Compose startup ordering must wait for an LDAP listener, an HTTPS Knox listener, and the existing HDFS readiness check before the end-to-end test runs.
5. Image architecture, user, Java version, entrypoint, configuration paths, and bundled LDAP users must match the pulled official image, not assumptions.

---

### Task 1: Write the Knox end-to-end acceptance test first

**Files:**
- Create: demo/tests/Test-KnoxGateway.ps1
- Test: demo/tests/Test-KnoxGateway.ps1

**Interfaces:**
- Consumes: the Compose project name apache-knox-bigdata-demo and the overlay path docker-compose.knox.yml.
- Produces: one script that starts the four-service stack, checks readiness, validates TLS and unauthenticated challenge, parses authenticated WebHDFS JSON, rejects a wrong password, and proves LDAP-down failure plus recovery.

- [ ] Step 1: Write the PowerShell script to use one Compose prefix for every call: compose -p apache-knox-bigdata-demo -f docker-compose.yml -f docker-compose.knox.yml. Capture native exit codes and stderr without letting PowerShell 5.1 convert Docker progress output into a false failure.
- [ ] Step 2: Implement checks in this order: compose config --quiet; up -d --wait --wait-timeout 180; idempotent HDFS seed using the same base-plus-overlay Compose prefix; unauthenticated HTTPS request to /gateway/demo/webhdfs/v1/demo?op=LISTSTATUS; valid guest request and JSON parse; invalid password status check; stop knox-ldap and retry with valid credentials; start knox-ldap and verify recovery.
- [ ] Step 3: Before any Compose files are added, run the test and confirm it exits nonzero because docker-compose.knox.yml is missing. Preserve that RED output in the local SDD ledger.
- [ ] Step 4: Keep cleanup in finally limited to restoring knox-ldap if it was stopped; do not stop HDFS or remove volumes.

### Task 2: Add the pinned Knox and LDAP services plus the demo topology

**Files:**
- Create: demo/docker-compose.knox.yml
- Create: demo/knox/topologies/demo.xml
- Modify: none in the base HDFS Compose file

**Interfaces:**
- Consumes: phase 01 HDFS services and the tested E2E command prefix.
- Produces: services named knox-gateway and knox-ldap on the existing backend network; both use the pinned official image; demo.xml is mounted at /home/knox/knox/conf/topologies/demo.xml.

- [ ] Step 1: Add knox-ldap using image apache/knox:3.0.0-release@sha256:058733ba7de9b6f7a37f850a50db343ebb8d0e72bc6bd5ecf668736906f2034c, entrypoint /home/knox/knox/bin/ldap.sh, command start, and KNOX_LDAP_RUNNING_IN_FOREGROUND=true. Add a TCP healthcheck for port 33389 and do not publish that port to the host.
- [ ] Step 2: Add knox-gateway using the same pinned image and default entrypoint. Mount only the demo topology read-only; set IMPORT_LETS_ENCRYPT_STAGING_CERTS=false; bind 8443 to 127.0.0.1; depend on healthy LDAP and healthy NameNode.
- [ ] Step 3: Put a ShiroProvider in demo.xml with KnoxLdapRealm, LDAP URL ldap://knox-ldap:33389, user DN template uid={0},ou=people,dc=hadoop,dc=apache,dc=org and urls./**=authcBasic. Add the enabled Default identity assertion provider; add NAMENODE at hdfs://namenode:8020 and WEBHDFS at http://namenode:9870/webhdfs.
- [ ] Step 4: Add a gateway healthcheck that requests the demo WebHDFS route without credentials and requires HTTP 401; this proves TLS, topology deployment and the auth challenge are active.
- [ ] Step 5: Run docker compose -f demo/docker-compose.yml -f demo/docker-compose.knox.yml config --quiet, inspect the merged service list, then run the focused end-to-end test through its startup and valid-user JSON assertions.

### Task 3: Add a reusable Knox readiness wait and finish negative-path assertions

**Files:**
- Create: demo/scripts/Wait-KnoxReady.ps1
- Modify: demo/tests/Test-KnoxGateway.ps1
- Modify: demo/scripts/Seed-HdfsDemo.ps1 and demo/scripts/Wait-HdfsReady.ps1 to accept the Knox overlay while preserving their base-only defaults

**Interfaces:**
- Consumes: the Compose overlay healthchecks and HTTPS listener.
- Produces: Wait-KnoxReady.ps1 -TimeoutSeconds N, which exits nonzero on timeout; the test script uses that helper before each request and after LDAP recovery.

- [ ] Step 1: Run Compose up -d --wait --wait-timeout N so readiness depends on the LDAP TCP healthcheck and the Gateway HTTPS healthcheck, which requires a 401 from the demo WebHDFS route. Include the last service states and logs on failure; the end-to-end script separately checks the loopback-published HTTPS route.
- [ ] Step 2: Assert valid guest:guest-password returns HTTP 200 and JSON with pathSuffix values apache-knox.txt and bigdata.txt. Assert guest:wrong-password returns the actual Knox authentication rejection and capture response headers plus gateway log evidence.
- [ ] Step 3: Stop knox-ldap, verify a valid-credential request is not HTTP 200 and capture the LDAP-connect/authentication error; restart LDAP, wait for readiness and verify the valid request returns HTTP 200 again.
- [ ] Step 4: Run Test-KnoxGateway.ps1 on the live HDFS stack and verify a nonzero exit for every intentionally failed assertion in a safe isolated test attempt. Never call down -v.

### Task 4: Add repeatable operator commands and record Phase 02 evidence

**Files:**
- Create: demo/README.md
- Create: docs/demo-ver-1/handoff/phase-02-handoff.md after the implementation commit
- Include: this implementation plan in the Phase 02 implementation commit

**Interfaces:**
- README commands use the same Compose overlay prefix and the tested demo credentials.
- Handoff records the full implementation SHA, real HTTP status/body, image digest/runtime, four service states, wrong-password and LDAP-down evidence, and the separate handoff commit workflow.

- [ ] Step 1: Document the demo-only account fixture, loopback HTTPS URL, curl.exe -k example, startup/readiness/seed/test commands, and non-destructive cleanup without -v.
- [ ] Step 2: Run config, startup/readiness, valid login, bad password, LDAP failure/recovery, direct HDFS/WebHDFS persistence, and PowerShell parser checks. Record commands, exit codes, output excerpts, timestamp and timezone.
- [ ] Step 3: Review the handoff against docs/demo-ver-1/handoff/HANDOFF-TEMPLATE.md; commit implementation/test/plan first, write the full implementation SHA in the handoff, then commit handoff separately and push both commits.
