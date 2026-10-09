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

## Request WebHDFS through Knox

`curl.exe -k` accepts the demo's self-signed TLS certificate. Use the guest fixture to list the seeded HDFS files through the Gateway:

```powershell
curl.exe -k --user 'guest:guest-password' 'https://127.0.0.1:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS'
```

The response is WebHDFS JSON and includes `apache-knox.txt` and `bigdata.txt`. To check authentication rejection, use a wrong password; Knox responds with HTTP 401:

```powershell
curl.exe -k --include --user 'guest:wrong-password' 'https://127.0.0.1:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS'
```

## Run the end-to-end check

The script starts or waits for the Compose stack, seeds the expected HDFS files idempotently, verifies the unauthenticated challenge, checks valid and invalid LDAP credentials, stops LDAP to verify authentication failure, then restores LDAP and checks recovery:

```powershell
.\tests\Test-KnoxGateway.ps1 -TimeoutSeconds 180
```

## Stop the demo

Run from the `demo` directory:

```powershell
docker compose -p apache-knox-bigdata-demo -f docker-compose.yml -f docker-compose.knox.yml down
```

This removes the demo containers and network while retaining the named HDFS data volumes. Do not add `-v` when stopping the demo.
