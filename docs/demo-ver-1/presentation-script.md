# Kịch bản thuyết trình demo Apache Knox (khoảng 4 phút)

Kịch bản này dùng stack đang chạy thật trên Windows PowerShell. Trước khi bắt đầu, chạy runbook trong [`demo/README.md`](../../demo/README.md), chờ readiness và mở PowerShell tại `demo/`. Các credentials dưới đây là fixture demo-only. Không dùng ảnh/video dựng sẵn để thay cho phản hồi của phiên đang trình diễn.

## Chuẩn bị trước khi bấm giờ

```powershell
$project = 'apache-knox-bigdata-demo'
$compose = @('-p', $project, '-f', 'docker-compose.yml', '-f', 'docker-compose.knox.yml')
docker compose @compose ps -a
.\scripts\Wait-KnoxReady.ps1 -ProjectName $project -TimeoutSeconds 180
```

Xác nhận LDAP, Gateway, NameNode và DataNode sẵn sàng. `hdfs-volume-init` `Exited (0)` là trạng thái bình thường.

## Lời thoại theo thời gian

| Thời gian | Màn / thao tác | Lời thoại | Expected / observed và nguồn lỗi |
|---|---|---|---|
| 0:00–0:25 | Dẫn nhập | «Trong Hadoop có nhiều REST endpoint. Knox đưa client qua một địa chỉ Gateway để xác thực, kiểm tra ACL, proxy request và ghi audit. HDFS phía sau đây là thật; Knox không phải engine lưu trữ hay xử lý Big Data.» | Kiến trúc: `127.0.0.1:8443` → Knox → `namenode:9870` trên Docker network; LDAP cũng chỉ nội bộ. |
| 0:25–0:55 | **A —** gọi NameNode trực tiếp | «Trước hết thử gọi thẳng WebHDFS từ Windows. Cổng 9870 không được publish ra host, nên request này phải thất bại. Việc đó do Docker port mapping, không phải một ACL của Knox.» | Chạy lệnh bên dưới. Expected: lỗi kết nối (đã quan sát `curl.exe` exit 7, không có HTTP status); sau đó màn D chứng minh route qua Knox vẫn hoạt động. |
| 0:55–1:30 | **B —** sai mật khẩu | «Bây giờ Gateway nhận request nhưng thông tin LDAP không hợp lệ. Knox trả 401; audit mới phải ghi authentication failure cho request này.» | Expected/observed: HTTP 401 và event authentication failure trong Knox audit. Response 401 một mình không chứng minh được nguồn; đối chiếu event mới. |
| 1:30–2:05 | **C —** user hợp lệ nhưng không có ACL | «Guest đăng nhập đúng nên authentication qua được. Chính sách AclsAuthz không cho guest gọi WEBHDFS, vì vậy Knox từ chối trước khi chuyển tiếp tới NameNode.» | Expected/observed: HTTP 403, Knox audit action `authorization` outcome `failure`; NameNode không tăng listStatus tương ứng. Nguồn là Knox ACL, không phải mật khẩu sai hay backend. |
| 2:05–2:50 | **D —** user được phép | «Admin được ACL cho phép. Knox chuyển request tới WebHDFS thật, và JSON trả về hai file đã seed trong HDFS.» | Expected/observed: HTTP 200; body có `apache-knox.txt` và `bigdata.txt`; Knox dispatch/access và NameNode audit cùng xác nhận backend được gọi. |
| 2:50–3:35 | **E —** đọc audit | «Audit giúp phân biệt ba việc vừa xem: xác thực thất bại, authorization bị từ chối, và request được dispatch thành công. Ta chỉ kết luận từ các event runtime mới của lần chạy này.» | Đọc `gateway-audit.log`; đối chiếu principal, action, URI, outcome, status và request ID nếu field có mặt. Không suy từ status code đơn lẻ. |
| 3:35–4:00 | Kết luận | «Demo cho thấy Knox là cửa vào thống nhất với authn, ACL, proxy và audit. Cấu hình này dùng TLS tự ký cho local lab; HDFS đang tắt permission enforcement nên chưa phải bảo mật production.» | Không gọi `curl -k` hay credentials demo là cấu hình production. |

## Lệnh cho các màn A–E

**A — backend không mở trên host**

```powershell
curl.exe --noproxy '*' --include --max-time 5 'http://127.0.0.1:9870/webhdfs/v1/demo?op=LISTSTATUS'
```

Giữ lại lỗi kết nối thật trên terminal. Không thêm port mapping 9870 để làm lệnh này trả lời.

**B — mật khẩu sai qua Knox**

```powershell
curl.exe --noproxy '*' --insecure --include --user 'admin:wrong-password' 'https://127.0.0.1:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS'
```

**C — guest đúng mật khẩu nhưng bị Knox ACL chặn**

```powershell
curl.exe --noproxy '*' --insecure --include --user 'guest:guest-password' 'https://127.0.0.1:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS'
```

**D — admin nhận JSON từ HDFS thật**

```powershell
curl.exe --noproxy '*' --insecure --include --user 'admin:admin-password' 'https://127.0.0.1:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS'
```

Body cần hiển thị cả `apache-knox.txt` và `bigdata.txt`.

**E — audit runtime**

```powershell
docker compose @compose exec -T knox-gateway bash -lc 'tail -n 100 /home/knox/knox/logs/gateway-audit.log'
```

Nếu event chưa xuất hiện ngay, chờ một chút rồi đọc lại log; không thêm dòng log giả. Đối chiếu với thời điểm request vừa gửi và các test trong `%TEMP%\knox-demo-v1-*`.

## Bằng chứng đã quan sát

P06 đã lặp full runner trên volumes mới sau khi seed ban đầu và sau khi khôi phục owner sai; cả hai lượt exit 0 với A–E, bốn suite và sáu nhóm regression/injection PASS. `docker compose stop` rồi `up --wait` trên project mới cũng giữ nguyên hai file. Log cục bộ được ghi trong Phase 06 handoff. Trước buổi trình bày, chạy `.\tests\Test-KnoxDemo.ps1 -ProjectName $project -TimeoutSeconds 180` để tạo một lượt kiểm tra mới và chỉ trình bày trạng thái vừa đo được.
