# HANDOFF — PHASE 04: Cô lập backend khỏi Windows host

## 1. Metadata

- Phase: 04 — Cô lập NameNode WebHDFS khỏi Windows host
- Trạng thái: DONE
- Ngày giờ + múi giờ: 2026-10-10 00:15, Asia/Ho_Chi_Minh
- Nhánh Git: feat/demo-ver-1-knox-gateway
- Base SHA lúc bắt đầu: fababece631c9e913a70f4908a6f7aa4209f2c41
- SHA commit implementation: 550f14fdcb376241dc51798669770aef92747394
- Remote: implementation commit đã được xác minh trên origin/feat/demo-ver-1-knox-gateway; handoff commit được đẩy riêng ngay sau đó.
- Người/thực thể thực hiện: Codex trên Windows PowerShell

## 2. Tóm tắt đã làm

- Bỏ publish NameNode WebHDFS 9870 khỏi host và xóa chú thích phase 01 đã lỗi thời. Compose chỉ còn publish Knox HTTPS tại 127.0.0.1:8443.
- Thêm Test-KnoxBackendIsolation.ps1 để kiểm tra Compose model, binding thực từ Docker Engine, listener/curl từ Windows, DNS nội bộ, WebHDFS qua Knox, audit NameNode và khả năng giữ dữ liệu sau restart.
- Cập nhật README về ranh giới network: Knox gọi namenode:9870 trên backend network; container khác cùng network vẫn có thể gọi backend.
- Test seed nhận diện và giữ nguyên hai file hiện có; restart NameNode, DataNode, LDAP và Knox không xóa named volumes, không chạy down -v, và không thay ACL Phase 03.
- Kết quả: host không kết nối được 9870 khi NameNode vẫn healthy; admin gọi Knox HTTPS nhận HTTP 200 với apache-knox.txt và bigdata.txt trước và sau restart.
- Chưa làm: các ca audit/failure matrix đầy đủ thuộc Phase 05; không thay đổi hay mở rộng chính sách ACL.

## 3. Files thay đổi

| Đường dẫn | Thay đổi | Lý do |
|---|---|---|
| demo/docker-compose.yml | Bỏ ports 127.0.0.1:9870:9870 khỏi namenode | Backend không còn được publish trên Windows host |
| demo/tests/Test-KnoxBackendIsolation.ps1 | Tạo kiểm thử E2E cô lập backend và restart | Đo đồng thời điều kiện âm ở host, đường đi dương qua Knox và persistence |
| demo/README.md | Bổ sung giải thích isolation và lệnh chạy test | Làm rõ port mapping/network, hướng dẫn kiểm tra và cảnh báo phạm vi |

## 4. Bằng chứng kiểm thử THẬT

| Test ID | Lệnh/cách chạy | Exit code / HTTP thực | Bằng chứng output/log | Kết quả |
|---|---|---|---|---|
| P04-RED | Chạy Test-KnoxBackendIsolation.ps1 trước khi sửa Compose | Exit 1 dự kiến | Test phát hiện 2 host mappings: Knox 127.0.0.1:8443->8443/tcp và NameNode 127.0.0.1:9870->9870/tcp | RED đúng |
| P04-COMPOSE | docker compose -p apache-knox-bigdata-demo -f docker-compose.yml -f docker-compose.knox.yml config --quiet | Exit 0 | Không có lỗi cấu hình hoặc cảnh báo biến | PASS |
| P04-PS-PARSER | PowerShell Parser trên demo/scripts và demo/tests | Exit 0 | Parse thành công 10 file .ps1 | PASS |
| P04-E2E | powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./tests/Test-KnoxBackendIsolation.ps1 -TimeoutSeconds 180, chạy hai lần | Cả hai lần exit 0 | Compose chỉ có mapping Knox; Docker Engine inspect xác nhận backend/LDAP không có host binding; toàn bộ gate lặp lại sau restart | PASS |
| P04-HOST | Trong E2E, kiểm tra Get-NetTCPConnection rồi gọi curl.exe --noproxy '*' --connect-timeout 3 --max-time 5 --include --silent --write-out ' CURL_HTTP_STATUS=%{http_code}' 'http://localhost:9870/' | Không có listener; curl exit 7, HTTP status 000; quan sát hai lần | curl báo không kết nối được localhost:9870 sau khoảng 2.2 giây, cả trước và sau restart | PASS |
| P04-KNOX | Trong E2E, admin gọi HTTPS 127.0.0.1:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS | HTTP 200 | JSON WebHDFS chứa đúng apache-knox.txt và bigdata.txt; kiểm tra Getent trong Knox giải quyết namenode thành IP nội bộ Docker; NameNode listStatus audit tăng 4->5 và 6->7 ở lượt chạy cuối | PASS |
| P04-RESTART | Test restart namenode+datanode, chờ HDFS ready, restart knox-ldap+knox-gateway, chờ Knox/HDFS ready | Exit 0 | Port bindings và curl âm tính vẫn đạt; Knox tiếp tục trả hai file; WebHDFS FileStatus của hai file trước/sau restart giống hệt; container NameNode healthy | PASS |
| P04-STATUS | docker compose -p apache-knox-bigdata-demo -f docker-compose.yml -f docker-compose.knox.yml ps -a, được ghi ở cuối E2E | Exit 0 | NameNode healthy; DataNode running; Knox LDAP và Gateway healthy; volume-init Exited (0); PORTS chỉ publish 127.0.0.1:8443 cho Gateway | PASS |

- Môi trường: Windows PowerShell 5.1.26100.9444; Docker Client/Server 29.6.2; Docker Compose v5.3.1; Hadoop apache/hadoop:3.4.3; Knox 3.0.0-release, image digest sha256:058733ba7de9b6f7a37f850a50db343ebb8d0e72bc6bd5ecf668736906f2034c.
- Trạng thái cuối: NameNode Up (healthy), DataNode Up, Knox LDAP Up (healthy), Knox Gateway Up (healthy), hdfs-volume-init Exited (0). Không có host mapping cho NameNode, DataNode hoặc LDAP.
- Nguồn lỗi được phân biệt: Get-NetTCPConnection xác nhận không có listener Windows trên 9870 trước khi dùng curl; curl exit 7/status 000 chứng minh host không nhận HTTP. Ngược lại, DNS nội bộ từ Knox và NameNode listStatus audit tăng cùng JSON WebHDFS 200 chứng minh backend sống và request được forward qua gateway.
- Negative/failure injection đã chạy: truy cập trực tiếp từ host tới NameNode 9870 bị từ chối sau khi xác nhận không có listener.
- Restart/persistence: đã restart HDFS, LDAP và Knox, chờ readiness, so sánh FileStatus của hai file qua Knox; không dùng down -v và không xóa volume.
- Ca Phase 05 chưa chạy: ma trận authentication/authorization/audit và failure injection mở rộng; đây là ngoài gate của Phase 04.

## 5. Quyết định kỹ thuật và giới hạn

- Chỉ gỡ ports khỏi NameNode; không cần expose WebHDFS để Knox gọi service nội bộ qua cùng Docker bridge network. Gateway tiếp tục bind loopback host 127.0.0.1:8443.
- Kết luận isolation giới hạn ở Windows host. Những container cùng backend network vẫn có thể truy cập namenode:9870; đây là hành vi Docker networking/Compose port mapping, không phải Knox tự chặn cổng.
- HDFS vẫn là lab với dfs.permissions.enabled=false; Knox TLS dùng chứng thư demo tự ký; tài khoản mẫu chỉ dành cho demo.
- Không có khác biệt với Master hoặc Phase 04 spec. Các port mapping được kiểm tra cả từ Compose config và Docker Engine inspect.
- Reviewer độc lập: READY; không có Critical, Important hoặc Minor findings. Review chỉ đọc; E2E do Codex chạy hai lần.

## 6. Blocker / việc tiếp theo

- Blocker: không có cho Phase 04.
- Phase kế tiếp: 05 — kiểm thử và audit.
- Spec tiếp theo được phép đọc sau khi bàn giao phase này: docs/demo-ver-1/spec/phase-05-kiem-thu-va-audit.md.
- Khi resume: kiểm tra git status --short --branch; đọc MASTER-SPEC.md và handoff phase 04; chỉ đọc spec Phase 05. Không tạo PR nếu chưa có yêu cầu mới.

## 7. Checklist trước khi bàn giao

- [x] Có Compose config, kiểm thử E2E và hướng dẫn vận hành thực.
- [x] Host negative check và Knox positive check cùng đạt khi backend healthy.
- [x] Đã inspect Docker Engine port bindings trước và sau restart.
- [x] HDFS named volumes được giữ nguyên; không chạy down -v.
- [x] Implementation commit: 550f14fdcb376241dc51798669770aef92747394.
- [x] Handoff nằm trong commit riêng, dùng Conventional Commit tiếng Việt.
- [x] Implementation đã push lên origin/feat/demo-ver-1-knox-gateway; handoff được push riêng.
- [x] Không tạo PR, không merge, không rebase/force push.
