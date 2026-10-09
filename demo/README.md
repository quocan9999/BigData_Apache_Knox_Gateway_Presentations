# Runbook demo Apache Knox

Demo dùng HDFS/WebHDFS thật, Apache Knox Gateway và Knox demo LDAP trong Docker Compose. Client Windows chỉ truy cập Gateway tại `https://127.0.0.1:8443`; NameNode WebHDFS `:9870` và LDAP không publish ra host.

## Điều kiện tiên quyết

- Windows với Windows PowerShell 5.1 trở lên; chạy lệnh bằng `curl.exe` (tránh alias `curl` của PowerShell).
- Docker Desktop đang chạy **Linux containers**. Xác nhận bằng `docker info --format '{{.OSType}}'`; kết quả cần là `linux`.
- Docker Compose hỗ trợ `up --wait`; phiên bản được kiểm thử trong repo là 5.3.1. `up --wait` chờ service healthy hoặc running theo healthcheck/dependency.
- Hãy cấp Docker Desktop đủ RAM để giữ Hadoop, LDAP và Knox chạy đồng thời. Môi trường đã kiểm thử có 8,128,749,568 bytes (~7.57 GiB) khả dụng cho Linux containers; đây là cấu hình quan sát, không phải minimum đã đo.
- Cần cổng host `127.0.0.1:8443` còn trống. HDFS volumes được tạo tự động bằng Compose; không cần chạy `chown` thủ công.

Phiên bản quan sát lúc kiểm thử: Windows 11 Home; PowerShell 5.1.26100.9444; Docker Engine Client/Server 29.6.2; Docker Compose 5.3.1; Hadoop `apache/hadoop:3.4.3`; Knox `apache/knox:3.0.0-release` với digest `sha256:058733ba7de9b6f7a37f850a50db343ebb8d0e72bc6bd5ecf668736906f2034c`.

## Khởi chạy lần đầu

Mở PowerShell tại thư mục gốc repository và chuyển vào `demo/`. Các lệnh ở phần còn lại chạy từ thư mục đó:

```powershell
Set-Location (Join-Path (git rev-parse --show-toplevel) 'demo')
$project = 'apache-knox-bigdata-demo'
$compose = @('-p', $project, '-f', 'docker-compose.yml', '-f', 'docker-compose.knox.yml')

docker compose @compose config --quiet
docker compose @compose up -d --wait --wait-timeout 180
.\scripts\Seed-HdfsDemo.ps1 -ProjectName $project -TimeoutSeconds 180 -IncludeKnoxOverlay
.\scripts\Wait-KnoxReady.ps1 -ProjectName $project -TimeoutSeconds 180
docker compose @compose ps -a
```

`hdfs-volume-init` ở trạng thái `Exited (0)` là bình thường: đây là one-shot service chuẩn bị quyền trên named volumes trước khi Hadoop khởi động. Readiness yêu cầu NameNode HTTP healthcheck với một live DataNode, LDAP listener và Knox HTTPS route trả Basic challenge HTTP 401 khi chưa gửi thông tin đăng nhập. `Seed-HdfsDemo.ps1` tạo `/demo/apache-knox.txt` và `/demo/bigdata.txt` nếu chưa có; file đã tồn tại được giữ nguyên.

Giữ cùng cửa sổ PowerShell để dùng lại biến `$project` và `$compose` trong các phần bên dưới. Nếu mở cửa sổ mới, chạy lại hai dòng khai báo biến ở trên.

## Kiểm tra truy cập WebHDFS

Fixture LDAP chứa `admin` / `admin-password` và `guest` / `guest-password`. Đây là credentials demo-only, được ghi trong cấu hình mẫu; không dùng ở hệ thống khác.

Admin được phép gọi WebHDFS thật qua Knox. JSON phải có `apache-knox.txt` và `bigdata.txt`:

```powershell
curl.exe --noproxy '*' --insecure --include --user 'admin:admin-password' 'https://127.0.0.1:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS'
```

Các kết quả đã quan sát và dùng trong năm màn demo:

| Ca | Lệnh/hành vi | Expected và observed | Nguồn kết quả |
|---|---|---|---|
| A | Gọi trực tiếp `http://127.0.0.1:9870` từ host | Kết nối thất bại; không có host mapping cho 9870. Lệnh qua Knox vẫn trả JSON HDFS. | Docker port/network mapping; không phải Knox ACL |
| B | `admin` với mật khẩu sai | HTTP 401; Knox ghi authentication failure cho principal/request. | Knox authentication qua LDAP |
| C | `guest` với mật khẩu đúng gọi WEBHDFS | HTTP 403; Knox audit ghi authorization failure và NameNode không nhận request listStatus đó. | Knox AclsAuthz |
| D | `admin` gọi WEBHDFS | HTTP 200; JSON liệt kê hai file HDFS thật. Knox dispatch và NameNode audit xác nhận backend được gọi. | Knox proxy + WebHDFS/HDFS |
| E | Đọc audit sau B/C/D | Có sự kiện xác thực thất bại, ACL từ chối và dispatch/access thành công. | Log runtime của Knox |

Lệnh kiểm tra A bằng tay (lỗi kết nối là expected khi stack đã bật):

```powershell
curl.exe --noproxy '*' --include --max-time 5 'http://127.0.0.1:9870/webhdfs/v1/demo?op=LISTSTATUS'
```

Sai mật khẩu và user bị ACL chặn:

```powershell
curl.exe --noproxy '*' --insecure --include --user 'admin:wrong-password' 'https://127.0.0.1:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS'
curl.exe --noproxy '*' --insecure --include --user 'guest:guest-password' 'https://127.0.0.1:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS'
```

Audit có thể xem trực tiếp trong container đang chạy:

```powershell
docker compose @compose exec -T knox-gateway bash -lc 'tail -n 100 /home/knox/knox/logs/gateway-audit.log'
```

Để đối chiếu request thật đã tới HDFS, Compose bật NameNode audit ra stdout bằng `HDFS_AUDIT_LOGGER=INFO,stdout`:

```powershell
docker compose @compose logs --no-color --since=10m namenode | Select-String 'cmd=listStatus\s+src=/demo'
```

NameNode audit là bằng chứng backend xử lý `listStatus`; quyết định authentication/authorization và dispatch vẫn được đối chiếu với Knox audit.

Khi trình bày nguồn lỗi, đối chiếu event mới sinh với `principal`, `action`, URI, `outcome`, HTTP status và request ID nếu field hiện diện. HTTP status đứng riêng không đủ chứng minh thành phần từ chối.

## Chạy test A–E và các ca lỗi

Runner dùng stack thật; trả exit code khác 0 nếu bất kỳ screen, suite hoặc nhóm regression nào thất bại:

```powershell
.\tests\Test-KnoxDemo.ps1 -ProjectName $project -TimeoutSeconds 180
```

Runner xác nhận A–E và các ca LDAP outage/recovery, đảo/khôi phục ACL, missing route, backend down/recovery, readiness timeout/recovery, restart và final stack recovery. Kết quả chi tiết được ghi trong thư mục `%TEMP%\knox-demo-v1-*` do runner in ra. Giữ log ở máy chạy; không commit log, transcript, credentials hoặc volume data. Có thể xem suite riêng bằng:

```powershell
.\tests\Test-KnoxBackendIsolation.ps1 -ProjectName $project -TimeoutSeconds 180
.\tests\Test-KnoxGateway.ps1 -ProjectName $project -TimeoutSeconds 180
.\tests\Test-KnoxAuthorization.ps1 -ProjectName $project -TimeoutSeconds 180
.\tests\Test-KnoxFailureInjection.ps1 -ProjectName $project -TimeoutSeconds 180
```

## Khởi tạo project/volumes sạch

Compose project name quyết định prefix cho named volumes. `-p` ghi đè top-level Compose `name`; chọn một tên mới để tạo bộ HDFS volumes độc lập. Không bỏ bước xem volume names trước khi `up`:

```powershell
$freshProject = "apache-knox-fresh-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$freshCompose = @('-p', $freshProject, '-f', 'docker-compose.yml', '-f', 'docker-compose.knox.yml')
$freshConfig = docker compose @freshCompose config --format json | ConvertFrom-Json
$freshVolumes = @($freshConfig.volumes.hdfs_namenode.name, $freshConfig.volumes.hdfs_datanode.name)
$freshVolumes
if ($freshVolumes | Where-Object { $_ -notlike "${freshProject}_*" }) { throw 'Fresh project volume prefix mismatch; stop before starting Compose.' }
$allVolumeNames = @(docker volume ls --format '{{.Name}}')
if ($LASTEXITCODE -ne 0) { throw 'Could not inspect Docker volumes; stop before starting Compose.' }
$existingVolumes = @($freshVolumes | Where-Object { $allVolumeNames -contains $_ })
if ($existingVolumes.Count -gt 0) { throw "Fresh project volumes already exist: $($existingVolumes -join ', '). Choose a new project name before starting Compose." }

docker compose @freshCompose up -d --wait --wait-timeout 180
.\scripts\Seed-HdfsDemo.ps1 -ProjectName $freshProject -TimeoutSeconds 180 -IncludeKnoxOverlay
.\scripts\Seed-HdfsDemo.ps1 -ProjectName $freshProject -TimeoutSeconds 180 -IncludeKnoxOverlay
.\tests\Test-KnoxDemo.ps1 -ProjectName $freshProject -TimeoutSeconds 180
```

Chạy seed hai lần để xác nhận lần sau giữ file đã có. Nếu muốn dừng stack kiểm tra sạch, chạy `docker compose @freshCompose down` **không thêm `-v`**. Named volumes của project mới vẫn nằm trên máy và sẽ được dùng lại nếu chạy lại cùng tên; hãy chọn tên project mới cho một lượt thử sạch tiếp theo. Hướng dẫn này xác nhận một bộ volume mới trên máy kiểm thử, không khẳng định đã chạy trên máy tính thứ hai.

## Phục hồi quyền volume

Nếu Hadoop báo không ghi được vào `/data/name` hoặc `/data/data`, dừng stack trước rồi chạy lại one-shot service đã cấu hình trong Compose. Service chạy root, so sánh owner của root volume với UID:GID `hadoop`; khi khác nhau, nó khôi phục owner đệ quy rồi mở quyền đọc/ghi/thực thi cho owner. Service không format volume và không xóa file:

```powershell
docker compose @compose stop
docker compose @compose run --rm --no-deps hdfs-volume-init
docker compose @compose up -d --wait --wait-timeout 180
.\scripts\Seed-HdfsDemo.ps1 -ProjectName $project -TimeoutSeconds 180 -IncludeKnoxOverlay
.\scripts\Wait-KnoxReady.ps1 -ProjectName $project -TimeoutSeconds 180
docker compose @compose exec -T namenode hdfs dfs -ls /demo
```

Nếu dữ liệu con có owner sai trong khi root volume đã sở hữu bởi user `hadoop`, helper hiện tại không phát hiện riêng từng file. Dừng lại, giữ nguyên volumes và xem log/owner trước khi chọn biện pháp sửa; không dùng lệnh xóa hoặc format HDFS.

## Dừng và khởi động lại

`stop` dừng containers nhưng giữ chúng và volumes; `up` khởi động lại. Có thể seed lại an toàn:

```powershell
docker compose @compose stop
docker compose @compose up -d --wait --wait-timeout 180
.\scripts\Seed-HdfsDemo.ps1 -ProjectName $project -TimeoutSeconds 180 -IncludeKnoxOverlay
docker compose @compose exec -T namenode hdfs dfs -ls /demo
```

Nếu muốn bỏ containers/network nhưng giữ HDFS data, chạy `docker compose @compose down`. **Không chạy `docker compose down -v`** vì tùy chọn đó xóa volumes.

## Khắc phục sự cố

| Triệu chứng | Kiểm tra/xử lý |
|---|---|
| Docker báo Windows containers hoặc không kết nối daemon | Kiểm tra Docker Desktop đang chạy Linux containers rồi xác nhận `docker info --format '{{.OSType}}'` trả `linux`. |
| Gateway không bind được cổng | `Get-NetTCPConnection -LocalPort 8443 -State Listen -ErrorAction SilentlyContinue`; xác định ứng dụng đang giữ cổng trước khi đổi cấu hình. |
| Compose chưa healthy hoặc `up --wait` hết timeout | `docker compose @compose ps -a` và `docker compose @compose logs --tail 100 namenode datanode hdfs-volume-init knox-ldap knox-gateway`; sửa nguyên nhân rồi chạy lại readiness. |
| `hdfs-volume-init` hiện `Exited (1)` | Đọc log service, xác nhận Docker mount hoạt động, rồi chạy quy trình [Phục hồi quyền volume](#phục-hồi-quyền-volume). `Exited (0)` là thành công bình thường. |
| Host gọi 9870 thất bại | Đây là expected của screen A. Nếu cổng mở, kiểm tra Compose không có `ports:` trên NameNode; không thêm publish backend để “sửa” Knox. |
| HTTP 401 | Không gửi credentials, credentials sai, hoặc LDAP outage. Đối chiếu Knox authentication audit; 401 tự nó chưa chỉ ra tình huống nào. |
| HTTP 403 với `guest` | Expected khi ACL mặc định từ chối WEBHDFS. Dùng audit Knox và test đối chứng để xác nhận nguồn là AclsAuthz. |
| HTTP 404 | Có thể là route/service không tồn tại; test fixture missing-route chủ động dùng 404. Không diễn giải là ACL denial. |
| HTTP 500 khi NameNode dừng | Expected trong backend-down test; kiểm tra Knox dispatch/gateway log và khôi phục NameNode. Đây không phải bằng chứng về ACL. |
| Không thấy hai file | Chạy HDFS readiness, seed idempotent rồi `hdfs dfs -ls /demo`. Không tạo response JSON giả. |

## Giới hạn an toàn và vận hành

- TLS của Knox là self-signed cho localhost; `--insecure`/`-k` chỉ dùng trong lab.
- Tài khoản LDAP chỉ là fixture demo. Runner không cần ghi credentials vào log.
- `dfs.permissions.enabled=false`: Knox ACL bảo vệ đường truy cập qua Gateway nhưng không thay thế quyền HDFS. Client khác trên Docker network có thể gọi backend.
- Cổng host `9870` không publish; Docker network isolation không phải ranh giới bảo mật production.
- Không commit capture, transcript, runtime log, `.env` cá nhân, volumes hay secrets. Quy tắc lưu evidence thật nằm tại [`demo-backup/README.md`](../demo-backup/README.md).

Tham khảo: [Docker Compose project name](https://docs.docker.com/compose/how-tos/project-name/), [`docker compose up`](https://docs.docker.com/reference/cli/docker/compose/up/) và [`docker compose down`](https://docs.docker.com/reference/cli/docker/compose/down/).
