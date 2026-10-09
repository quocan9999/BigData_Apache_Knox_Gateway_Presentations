# HANDOFF — PHASE 05: E2E 5 màn A–E, audit và thử lỗi có chủ đích

## 1. Metadata

- Phase: 05 — kiểm thử và audit demo Apache Knox
- Trạng thái: DONE
- Thời gian xác minh cuối: 2026-10-10 00:59–01:05, Asia/Ho_Chi_Minh
- Nhánh Git: `feat/demo-ver-1-knox-gateway`
- Base SHA lúc bắt đầu: `0384ba0c1f8ba90984fbd89f3c10d3039a8c9306`
- SHA commit implementation: `4b5f44ab9a6e7e907c5b0c0318f7f9cebcca5b86`
- Remote: implementation và handoff được push, xác minh trên `origin/feat/demo-ver-1-knox-gateway`.
- Người/thực thể thực hiện: Codex trên Windows PowerShell.

## 2. Tóm tắt đã làm

- Thêm `Test-KnoxDemo.ps1` làm runner cho các suite A–E. Runner kiểm tra Docker/Compose, chờ HDFS và Knox trước mỗi child, ghi log riêng vào thư mục `%TEMP%`, in trạng thái theo màn hình, suite và nhóm failure injection, rồi trả exit khác 0 nếu suite thất bại.
- Bổ sung audit assertion dựa trên bản ghi mới từ Knox đang chạy: sai mật khẩu phải là authentication failure; guest bị ACL từ chối phải là authorization failure; admin được phép phải có dispatch/access thành công. Screen E xác nhận đủ các sự kiện B/C/D.
- Thêm failure injection cho route thiếu, NameNode dừng, readiness timeout bằng healthcheck lỗi có chủ đích, và kiểm tra khôi phục sau từng ca. Có nhóm riêng xác nhận final stack recovery.
- Giữ kiểm tra đảo ACL và khôi phục mặc định, ngắt/khôi phục LDAP, cô lập backend và restart persistence. HDFS giữ nguyên hai file `apache-knox.txt` và `bigdata.txt`.
- README có lệnh chạy toàn bộ và từng suite. Log được ghi cục bộ, không đưa vào repository; lượt chạy cuối đã quét và không có chuỗi demo password.
- Không chạy `docker compose down -v`; không xóa named volume.

## 3. Files thay đổi

| Đường dẫn | Thay đổi | Lý do |
|---|---|---|
| `demo/tests/Test-KnoxDemo.ps1` | Tạo runner A–E, readiness gate, log cục bộ và summary PASS/FAIL/BLOCKED | Có một lệnh chạy suite đầy đủ và xác định kết quả theo marker cùng exit code child |
| `demo/tests/Test-KnoxGateway.ps1` | Xác nhận audit authentication failure cho mật khẩu sai; thêm marker Screen B và LDAP outage/recovery | Phân biệt xác thực LDAP thất bại với access audit mang HTTP 401 |
| `demo/tests/Test-KnoxAuthorization.ps1` | Xác nhận audit dispatch/access/authentication/authorization mới và marker C/D/E; giữ kiểm tra đảo/khôi phục ACL | Đo đúng nguồn 401/403 và bằng chứng forward đến NameNode |
| `demo/tests/Test-KnoxFailureInjection.ps1` | Tạo suite route thiếu, backend-down, readiness timeout và phục hồi | Kiểm tra lỗi thật từ Knox/Compose, không dùng phản hồi giả |
| `demo/tests/fixtures/docker-compose.knox-healthcheck-failure.yml` | Overlay healthcheck Gateway luôn lỗi để thử trạng thái unhealthy | Tạo lỗi readiness có thể tái hiện và đảo ngược |
| `demo/tests/Test-KnoxBackendIsolation.ps1` | Thêm marker Screen A | Cung cấp kết quả ổn định cho runner |
| `demo/README.md` | Thêm hướng dẫn full runner và các lệnh chạy riêng | Hướng dẫn thao tác và xem log cục bộ |
| `docs/superpowers/plans/2026-10-10-knox-e2e-audit-phase-05.md` | Ghi plan và checklist Phase 05 | Theo dõi yêu cầu và kết quả triển khai |

## 4. Bằng chứng kiểm thử THẬT

| Test ID | Lệnh/cách chạy | Exit code / HTTP thực | Bằng chứng output/log | Kết quả |
|---|---|---|---|---|
| P05-PARSER | `System.Management.Automation.Language.Parser` trên toàn bộ `demo/scripts` và `demo/tests` | Exit 0 | Parse thành công 12 file `.ps1` | PASS |
| P05-COMPOSE | `docker compose -f docker-compose.yml -f docker-compose.knox.yml config --quiet`; lặp với fixture healthcheck lỗi | Cả hai exit 0 | Compose model bình thường và overlay lỗi đều hợp lệ | PASS |
| P05-RUNNER | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-KnoxDemo.ps1 -TimeoutSeconds 180` | Exit 0 | Screen A–E, suite isolation/authentication/authorization/failure-injection, và sáu nhóm regression/injection đều PASS | PASS |
| P05-A | Runner gọi `Test-KnoxBackendIsolation.ps1`, kiểm tra trước/sau restart | Host curl exit 7, status `000`; Knox HTTP 200 | Không có Windows listener trên 9870; WebHDFS JSON chứa đúng hai file; trạng thái file giữ nguyên sau restart NameNode, DataNode, LDAP và Knox | PASS |
| P05-B | Runner gọi `Test-KnoxGateway.ps1` | Invalid password HTTP 401; LDAP outage HTTP 401 (curl exit 0); recovery HTTP 200 | Knox audit mới ghi `WEBHDFS`, `authentication`, `principal`, `admin`, `failure`; log có `INVALID_CREDENTIALS`; LDAP trở lại và WebHDFS JSON có đủ hai file | PASS |
| P05-C | Guest hợp lệ gọi WebHDFS với ACL mặc định | HTTP 403 | Knox audit mới ghi principal `guest`, action `authorization`, URI `/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS`, outcome `failure`; NameNode listStatus count không tăng | PASS |
| P05-D | Admin hợp lệ gọi WebHDFS với ACL mặc định | HTTP 200 | JSON thật có `apache-knox.txt`, `bigdata.txt`; Knox dispatch đến `http://namenode:9870/...` và gateway access ghi `success`/status 200 cùng request ID; NameNode audit listStatus tăng | PASS |
| P05-E | Screen E rà soát các sự kiện audit B/C/D vừa tạo | Dựa trên response và log runtime | Có authentication failure cho mật khẩu sai, authorization failure cho guest, và dispatch/access success cho admin; không suy diễn principal ở route không có principal | PASS |
| P05-ACL | Overlay đảo ACL tạm thời rồi khôi phục | Guest HTTP 200; admin HTTP 403; sau khôi phục admin HTTP 200 và guest HTTP 403 | Audit authorization failure khớp principal; suite xác nhận topology mặc định là admin allow/guest deny | PASS |
| P05-ROUTE | Gọi `/gateway/demo/missing-service/v1/demo?op=LISTSTATUS` | HTTP 404 | Không có JSON listing; Knox access audit mới ghi đúng URI và `Response status: 404` | PASS |
| P05-BACKEND | Dừng NameNode và gọi admin qua Knox | HTTP 500; không có `FileStatuses` hoặc tên file | Knox dispatch audit có principal admin và outcome `unavailable`; gateway log ghi `UnknownHostException` cho `namenode`; sau khi start lại, admin nhận HTTP 200 với hai file | PASS |
| P05-READINESS | Recreate Gateway với fixture healthcheck lỗi và `--wait --wait-timeout 5`, sau đó dùng Compose mặc định | Lệnh probe Compose exit 1, Gateway `unhealthy`; route chuẩn phục hồi HTTP 200 | Healthcheck lỗi là injection có chủ đích; Knox readiness thường và WebHDFS phục hồi sau khi recreate topology mặc định | PASS |
| P05-RESTORE | Cuối failure-injection suite | Exit 0; admin HTTP 200 | Compose services healthy, admin lại thấy đủ hai file; marker `FINAL_STACK_RECOVERY PASS` | PASS |
| P05-REVIEW | Review độc lập chỉ đọc | READY | Finding ban đầu về exit code child, status HTTP backend và BLOCKED/FAIL đã được xử lý; lượt review lại không còn finding cần xử lý | PASS |
| P05-GIT | `git diff --check`; quét key/token pattern và log cục bộ | Exit 0 | Không có whitespace error, key/token pattern hoặc demo password trong log. Log nằm ngoài repository. | PASS |

- Thư mục log của lượt chạy cuối: `C:\Users\trinh\AppData\Local\Temp\knox-demo-v1-20261010-005928-38074231794440cca05009482d796427` (Windows local time 2026-10-10 00:59:28–01:05:45). Không commit log.
- Môi trường: Windows PowerShell 5.1.26100.9444; Docker Client/Server 29.6.2; Docker Compose v5.3.1; Hadoop image `apache/hadoop:3.4.3`; Knox image `apache/knox:3.0.0-release`, digest `sha256:058733ba7de9b6f7a37f850a50db343ebb8d0e72bc6bd5ecf668736906f2034c`.
- Compose status cuối: NameNode healthy; DataNode running; Knox LDAP healthy; Knox Gateway healthy; `hdfs-volume-init` Exited (0). Host chỉ publish Knox tại `127.0.0.1:8443`; backend/LDAP không có host port mapping.
- Knox audit được đọc trực tiếp tại `/home/knox/knox/logs/gateway-audit.log`; gateway connectivity evidence tại `/home/knox/knox/logs/gateway.log`. Audit timestamp bên trong container hiển thị ngày `26/10/09`; thời gian handoff phía trên là giờ Windows `Asia/Ho_Chi_Minh`.
- Các response WebHDFS và audit đều đến từ stack thật. Route thiếu không có principal trong access audit nên kết luận chỉ dựa trên URI/status; backend DNS lỗi sau khi NameNode bị dừng được ghi đúng là `UnknownHostException`, không gán thành lỗi HTTP khác.

## 5. Quyết định kỹ thuật và giới hạn

- Test audit lấy offset trước request và chỉ khớp bản ghi mới trong file runtime. Với sai mật khẩu, assertion yêu cầu authentication/principal/failure; không dùng access event có outcome `success` và status 401 để nói xác thực thành công.
- Guest 403 được xác nhận tại Knox AclsAuthz bằng authorization audit và NameNode không nhận thêm listStatus. Admin 200 được xác nhận bằng cả listing JSON, Knox dispatch/access audit và NameNode audit.
- Readiness injection dùng healthcheck cố ý `exit 1` trong overlay riêng. Timeout 5 giây giúp Docker Compose quan sát trạng thái unhealthy một cách ổn định; đây là kiểm tra xử lý healthcheck lỗi có chủ đích, không phải đo cold-start tự nhiên.
- Runner giữ marker PASS của screen đã hoàn tất nếu lỗi xảy ra ở regression muộn hơn, nhưng suite exit khác 0 vẫn đặt suite FAIL và khiến runner trả nonzero. Screen/group chưa đến lượt được phân biệt FAIL/BLOCKED theo marker tiến trình.
- Tất cả checks giữ nguyên named HDFS volumes. Không chạy `down -v`, không dùng log audit giả, không fallback sang host port 9870.
- Blocker Phase 05: không có.

## 6. Blocker / việc tiếp theo

- Phase kế tiếp: 06 — chỉ mở spec sau khi handoff Phase 05 đã commit riêng và được push xác minh.
- Không tạo PR, không merge, không rebase hoặc force-push.

## 7. Checklist trước khi bàn giao

- [x] Screen A–E chạy trên stack thật; HTTP, audit, HDFS và origin denial được xác nhận.
- [x] LDAP/backend/readiness/route failure có injection và phục hồi; final stack healthy.
- [x] HDFS named volumes được giữ nguyên; không chạy `down -v`.
- [x] Implementation commit: `4b5f44ab9a6e7e907c5b0c0318f7f9cebcca5b86`.
- [x] Handoff được commit riêng bằng Conventional Commit tiếng Việt.
- [x] Implementation và handoff được push, remote branch đã xác minh.
- [x] Không tạo PR, không merge, không rebase/force-push.
