# Apache Knox local demo

This demo runs HDFS, the Apache Knox Gateway, and the Knox demo LDAP server with Docker Compose. Knox listens on HTTPS at `https://127.0.0.1:8443`; the TLS certificate is self-signed for this local lab.

The bundled demo LDAP fixture includes `guest` / `guest-password` and `admin` / `admin-password`. These credentials are for this demo only and must not be used for production systems.

## Start and wait for readiness

Run these commands from the `demo` directory in PowerShell:

```powershell
docker compose -p apache-knox-bigdata-demo -f docker-compose.yml -f docker-compose.knox.yml config --quiet
docker compose -p apache-knox-bigdata-demo -f docker-compose.yml -f docker-compose.knox.yml up -d --wait --wait-timeout 180
.\scripts\Seed-HdfsDemo.ps1 -TimeoutSeconds 180 -IncludeKnoxOverlay
.\scripts\Wait-KnoxReady.ps1 -TimeoutSeconds 180
```

The readiness check waits for the NameNode, LDAP listener, and Knox HTTPS route. Knox's health check requests the demo WebHDFS route without credentials and requires its HTTP 401 Basic challenge.

## Authentication and authorization

Authentication checks whether the LDAP credentials are valid. Authorization then checks whether the authenticated identity may call the `WEBHDFS` service. The default `webhdfs.acl` allows `admin` and denies `guest`; both accounts exist in the demo LDAP fixture.

`curl.exe -k` accepts the demo's self-signed TLS certificate. Use the authorized admin fixture to list the seeded HDFS files through the Gateway:

```powershell
curl.exe -k --user 'admin:admin-password' 'https://127.0.0.1:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS'
```

The response is WebHDFS JSON and includes `apache-knox.txt` and `bigdata.txt`. A wrong password fails authentication with HTTP 401. A valid guest password passes authentication, then Knox AclsAuthz denies the WebHDFS request with HTTP 403:

```powershell
curl.exe -k --include --user 'admin:wrong-password' 'https://127.0.0.1:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS'
curl.exe -k --include --user 'guest:guest-password' 'https://127.0.0.1:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS'
```

## Backend network isolation

The Windows host publishes only Knox HTTPS on 127.0.0.1:8443. NameNode WebHDFS (namenode:9870), DataNode, HDFS RPC, and demo LDAP have no host port mappings. Knox reaches WebHDFS over the Compose backend network using the internal service name namenode; other containers attached to that network can also reach the backend, so this is Docker network and port configuration rather than a Knox rule that blocks the NameNode port.

Check the resolved Compose mappings and run the isolation/restart check from PowerShell:

    docker compose -p apache-knox-bigdata-demo -f docker-compose.yml -f docker-compose.knox.yml config --format json
    & 'tests/Test-KnoxBackendIsolation.ps1' -TimeoutSeconds 180

The test inspects Docker Engine port bindings, confirms Windows has no listener on 9870, expects a direct host curl.exe connection to fail, then confirms the admin route through Knox still returns both HDFS files. It restarts HDFS, LDAP, and Knox services and repeats the checks without deleting the named volumes.

## Run the full five-screen demo

Run the complete real-stack suite from the `demo` directory in PowerShell:

```powershell
.\tests\Test-KnoxDemo.ps1 -TimeoutSeconds 180
```

The runner checks Docker and Compose, waits for HDFS and Knox before each suite, and prints `PASS`, `FAIL`, or `BLOCKED` for screens A–E and each child suite. It also reports LDAP outage/recovery, ACL reversal/restoration, missing-route, backend-down/recovery, readiness-timeout/recovery, and final stack recovery. The command exits zero only when every screen, suite, and regression group passes. Each child suite has a full log under the printed `%TEMP%\knox-demo-v1-*` directory; the logs stay on this machine and the checks do not print passwords.

To run individual suites instead, use these commands:

The authentication test starts or waits for the Compose stack, seeds the expected HDFS files idempotently, verifies the unauthenticated challenge, checks admin and invalid credentials, stops LDAP to verify authentication failure, then restores LDAP and checks recovery:

```powershell
.\tests\Test-KnoxGateway.ps1 -TimeoutSeconds 180
```

The authorization test verifies the real default policy (admin allowed, guest denied), checks Knox audit and NameNode evidence for the denial origin, confirms an invalid password still fails during authentication, reverses the ACL to prove the result changes with policy, then restores the default topology:

```powershell
.\tests\Test-KnoxAuthorization.ps1 -TimeoutSeconds 180
```

The failure-injection test checks a missing service route, a stopped NameNode, and a deliberately failing Gateway health check. It restores the normal stack and verifies the admin WebHDFS listing after each injection:

```powershell
.\tests\Test-KnoxFailureInjection.ps1 -TimeoutSeconds 180
```

## Stop the demo

Run from the `demo` directory:

```powershell
docker compose -p apache-knox-bigdata-demo -f docker-compose.yml -f docker-compose.knox.yml down
```

This removes the demo containers and network while retaining the named HDFS data volumes. Do not add `-v` when stopping the demo.
