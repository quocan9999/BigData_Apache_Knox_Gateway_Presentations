# HANDOFF — PHASE 06: Đóng gói, runbook và trình diễn

## 1. Metadata

- Phase: 06 — đóng gói demo Apache Knox v1
- Trạng thái: **DONE**
- Thời gian kiểm chứng: 2026-10-10 01:22–02:49, Asia/Ho_Chi_Minh (UTC+07:00)
- Nhánh: `feat/demo-ver-1-knox-gateway`
- Base SHA: `be7454a1228d59faef65fb7e9a79d76c9ea77965`
- SHA commit implementation: `e27226abab7260c3d147fbbaebcc14d31113e4f8`
- Môi trường: Windows 11 Home, Windows PowerShell 5.1.26100.9444, Docker Desktop Linux containers, Docker Engine 29.6.2, Docker Compose 5.3.1
- Người/thực thể thực hiện: Codex trên Windows PowerShell

## 2. Tóm tắt

- Hoàn thiện README ở root và `demo/`, kịch bản A–E tiếng Việt khoảng 4 phút, hướng dẫn lưu capture/evidence thật, và quy tắc ignore file local.
- Xác minh lệnh khởi chạy từ đúng thư mục `demo/`; Compose readiness, seed và Knox readiness thành công trên stack ban đầu trước khi kiểm tra project mới.
- Dùng project độc lập `apache-knox-p06-freshcheck-20261010`; volumes mới không trùng với project gốc. Seed hai lần, stop/restart, phục hồi owner và hai lượt runner đầy đủ đều giữ hai file HDFS.
- Không chạy `docker compose down -v`; volumes của project gốc và project kiểm thử không bị xóa.
- Lượt regression tổng hợp cuối trên project gốc exit 0; A–E, bốn suite và sáu nhóm regression đều PASS.
- Sau đó chạy full runner thêm lần nữa trên project `apache-knox-p06-final-20261010` với hai volume HDFS chưa tồn tại; runner exit 0 và A–E cùng mọi nhóm regression PASS. Dừng project mới bằng `stop`, giữ nguyên hai volume.
- Khởi động lại project gốc bằng Compose `up --wait`, xác nhận toàn bộ service healthy, seed giữ nguyên hai file và HDFS listing còn đủ hai file. Phase 06 đạt Definition of Done cho môi trường đã kiểm tra.
- Không kiểm thử trên máy thứ hai; giao diện Snipping Tool/Game Bar cũng chưa được xác minh trên host này.

## 3. Files thay đổi

| Đường dẫn | Nội dung |
|---|---|
| `README.md` | Mục tiêu, sơ đồ, phiên bản đã quan sát, cách chạy và giới hạn bảo mật |
| `demo/README.md` | Prerequisites, startup/readiness/seed, A–E, test, fresh project, recovery, stop/restart và troubleshooting |
| `docs/demo-ver-1/presentation-script.md` | Lời thoại 3–5 phút, expected/observed, nguồn sinh lỗi và lệnh A–E |
| `demo-backup/README.md` | Quy trình capture thật, metadata và SHA-256; capture phát sinh bị ignore |
| `.gitignore` | Ignore capture local và `.env` cá nhân, cho phép track `.env.example` cùng README của backup |
| `demo/docker-compose.yml` | Bật NameNode audit ra stdout để có bằng chứng backend thật trong Docker logs |
| `demo/tests/Test-KnoxGateway.ps1` | Chờ có giới hạn cho LDAP authenticated recovery và vẫn fail nếu không phục hồi |
| `demo/tests/Test-KnoxFailureInjection.ps1` | Nhận diện `NoHttpResponseException` đã quan sát khi NameNode dừng |
| `docs/superpowers/plans/2026-10-10-knox-packaging-phase-06.md` | Checklist và trạng thái thực hiện Phase 06 |
| `demo/README.md` | Nêu lệnh xem NameNode audit và phân biệt nó với Knox authorization audit |

Handoff này được commit riêng sau implementation commit.

## 4. Bằng chứng kiểm thử

| ID | Cách kiểm tra | Kết quả quan sát | Trạng thái |
|---|---|---|---|
| P06-DOCS | Acceptance check cho headings/commands trong root và demo README | Sau lần RED ban đầu, hợp đồng tài liệu đạt exit 0; lệnh startup smoke từ PowerShell root/demo chạy thành công trên stack ban đầu | PASS |
| P06-IGNORE | `git check-ignore` cho capture, `.env`, `.env.example` tại root và `demo/` | Capture và `.env` bị ignore; `demo-backup/README.md` và `.env.example` không bị ignore | PASS |
| P06-COMPOSE | `docker compose config --quiet` cho base + Knox và healthcheck-failure fixture | Cả hai Compose model hợp lệ | PASS |
| P06-XML | Parse `core-site.xml`, `hdfs-site.xml`, `demo.xml`, `demo-guest-allow.xml` | 4 tệp XML parse thành công | PASS |
| P06-PS | PowerShell Parser cho scripts; parse code block PowerShell trong tài liệu | 12 scripts và 18 code block parse thành công. PSScriptAnalyzer không có sẵn trong môi trường nên không chạy | PASS (PSScriptAnalyzer NOT RUN) |
| P06-STATIC | `git diff --check`, quét secrets/artifacts và file được track/ignore | Exit 0; không thấy private-key/token pattern, runtime artifact, `.env` hoặc capture bị lộ vào Git. README LF có cảnh báo Git sẽ đổi sang CRLF khi chạm lại | PASS |
| P06-FRESH-1 | Project `apache-knox-p06-freshcheck-20261010`, volumes mới, seed và full runner | `up --wait` thành công; HDFS có `apache-knox.txt`, `bigdata.txt`; A–E, bốn suite và sáu nhóm outage/ACL/route/backend/readiness/recovery PASS; runner exit 0 | PASS |
| P06-RECOVERY | Trên volumes mới riêng biệt, giả lập owner `0:0`, chạy `hdfs-volume-init`, seed và full runner | Owner đổi về UID:GID `1000:100`; hai file còn nguyên; readiness và runner đầy đủ PASS, exit 0 | PASS |
| P06-RESTART | Project mới: `stop`, `up --wait`, reseed, rồi `down` không `-v` | Listing/status hai file không đổi; sau `down`, cả hai named volumes của project mới còn tồn tại | PASS |
| P06-ORIGINAL | Thử `docker compose up -d --wait --wait-timeout 180` trên project gốc sau khi hạ project mới | Lần thử ban đầu timeout: dependency NameNode/LDAP không đạt trạng thái chờ; `dockerDesktopLinuxEngine` named-pipe `/_ping` không phản hồi trong 5 giây. Docker Engine sau đó hồi phục và lần khởi động cuối PASS ở `P06-ORIGINAL-RESTORE` | RECOVERED |
| P06-ORIGINAL-READONLY | Probe chỉ đọc qua network namespace của NameNode gốc và kiểm tra LDAP listener | `/dfshealth.html` trả thành công; JMX `NumLiveDataNodes=1`; WebHDFS JSON còn đúng hai file; LDAP TCP 33389 nhận kết nối. Knox readiness và full A–E sau lifecycle chưa xác nhận | PARTIAL |
| P06-ORIGINAL-REGRESSION-PRE-FIX | Full runner trên project gốc trước khi sửa audit output, LDAP recovery wait và exception pattern | Runner exit 1; Screen A/D gặp NameNode audit counter không tăng, LDAP recovery trả 401 sau readiness, backend-down evidence là `NoHttpResponseException` nhưng pattern test chưa nhận loại này. Log vẫn chứng minh HDFS JSON thật và Knox dispatch/access audit | FAIL — đã xử lý |
| P06-HDFS-AUDIT | Bật `HDFS_AUDIT_LOGGER=INFO,stdout`, restart NameNode giữ nguyên volume, chạy `hdfs dfs -ls /demo`, kiểm tra `docker compose logs namenode` | NameNode logs có event thật `cmd=listStatus src=/demo`; trong isolation test counter tăng 5→6 và 7→8 | PASS |
| P06-ORIGINAL-REGRESSION-FINAL | Từ `demo/`: `docker compose -p apache-knox-bigdata-demo -f docker-compose.yml -f docker-compose.knox.yml up -d --wait --wait-timeout 180`; ` .\tests\Test-KnoxDemo.ps1 -ProjectName apache-knox-bigdata-demo -TimeoutSeconds 180` | Log folder `knox-demo-v1-20261010-023319-ec91614780dd48b6b897b02c0668f1a9`; runner exit 0. Screens A–E, suites ISOLATION/AUTHENTICATION/AUTHORIZATION/FAILURE_INJECTION và sáu nhóm LDAP_OUTAGE/ACL_REVERSAL/MISSING_ROUTE/BACKEND_DOWN_AND_RECOVERY/READINESS_TIMEOUT_AND_RECOVERY/FINAL_STACK_RECOVERY đều PASS | PASS |
| P06-FRESH-FINAL | Kiểm tra trước khi chạy xác nhận chưa có volume `apache-knox-p06-final-20261010_*`; full runner với project này, sau đó `stop` không xóa volume | Log folder `knox-demo-v1-20261010-024052-26d8e106bafe402eaddac3297272bbad`; runner exit 0, A–E và toàn bộ suite/regression PASS; HDFS có hai file thật; hai named volumes mới vẫn tồn tại sau stop | PASS |
| P06-ORIGINAL-RESTORE | Sau fresh runner, chạy lại project gốc với `up -d --wait --wait-timeout 180`, `Seed-HdfsDemo.ps1` và `Wait-KnoxReady.ps1` | Compose báo NameNode, DataNode, LDAP, Gateway healthy; seed giữ nguyên `/demo/apache-knox.txt` và `/demo/bigdata.txt`; `hdfs dfs -ls /demo` trả đúng hai file. Các volume gốc còn nguyên | PASS |

Hai log runner local, không commit:

- `C:\Users\trinh\AppData\Local\Temp\knox-demo-v1-20261010-012227-c39e23f78657423b83c2f28a1d766576` — kết thúc 01:28:48 +07:00.
- `C:\Users\trinh\AppData\Local\Temp\knox-demo-v1-20261010-013101-6c85a93df93642859195f94f6631fc7a` — kết thúc 01:37:24 +07:00.
- `C:\Users\trinh\AppData\Local\Temp\knox-demo-v1-20261010-021630-be5a29611cf645ed95edf4364eaf59f7` — lượt regression trên project gốc, runner exit 1; kết thúc 02:19:04 +07:00.
- `C:\Users\trinh\AppData\Local\Temp\knox-demo-v1-20261010-023319-ec91614780dd48b6b897b02c0668f1a9` — runner cuối trên project gốc, exit 0; kết thúc 02:40:09 +07:00.
- `C:\Users\trinh\AppData\Local\Temp\knox-demo-v1-20261010-024052-26d8e106bafe402eaddac3297272bbad` — runner trên project volumes mới, exit 0; kết thúc 02:49:06 +07:00.
- Hai full runner cuối (project gốc và project volumes mới) đều có marker PASS cho screens A–E, suites và nhóm regression; scan không tìm thấy `admin-password` hoặc `guest-password` trong các log đó.

Volumes dự án gốc được giữ nguyên: `apache-knox-bigdata-demo_hdfs_namenode`, `apache-knox-bigdata-demo_hdfs_datanode`. Volumes mới của kiểm tra cuối là `apache-knox-p06-final-20261010_hdfs_namenode` và `apache-knox-p06-final-20261010_hdfs_datanode`; tên được kiểm tra trước khi `up` và xác nhận còn tồn tại sau `stop`. Các volume `apache-knox-p06-freshcheck-20261010_*` từ lượt trước cũng được giữ nguyên.

## 5. Quyết định và giới hạn

- HDFS audit được gửi ra stdout trong cấu hình demo bằng `HDFS_AUDIT_LOGGER=INFO,stdout`, để assertion backend kiểm tra event thật. Knox audit vẫn là nguồn bằng chứng cho authentication, AclsAuthz và dispatch/access.
- LDAP recovery test cho phép tối đa 45 giây để xác thực bằng tài khoản đã xác minh trước outage; nếu không nhận HTTP 200 và hai file WebHDFS thật thì test vẫn fail.
- Backend-down assertion nhận `NoHttpResponseException`, loại lỗi thực tế được ghi khi NameNode dừng; HTTP 500, audit `unavailable` và phục hồi route vẫn được kiểm tra riêng.
- Full A–E chạy trên cả volumes gốc và một project volumes mới. Không thử trên máy thứ hai; không tuyên bố quy trình đã được người khác xác nhận.
- Không tạo ảnh/video minh họa. README backup hướng dẫn lưu file được quay/chụp từ phiên demo thật; thao tác UI capture chưa được xác minh trên host này.
- Giới hạn demo: TLS tự ký; LDAP accounts là fixture demo-only; `dfs.permissions.enabled=false`; backend/LDAP không publish host port nhưng client khác trong Docker network vẫn có thể gọi backend.
- Không chạy `down -v`, không sửa/xóa HDFS volume gốc, không commit log/capture/secrets, không tạo PR, không merge/rebase/force-push.

## 6. Blocker và bước tiếp theo

Không còn blocker Phase 06 trong môi trường đã kiểm chứng. Tài liệu ghi rõ giới hạn chưa kiểm thử trên máy thứ hai và UI capture; runtime log nằm local, không commit. Các sửa lỗi được kiểm chứng bằng full runner trên stack gốc và project volumes mới.

## 7. Checklist bàn giao

- [x] README/runbook, kịch bản trình bày và quy trình evidence local đã được soạn.
- [x] Static validation và fresh-project A–E/recovery/restart chạy thành công.
- [x] Named volumes cũ được giữ nguyên; không dùng `down -v`.
- [x] Compose readiness và full A–E regression cuối trên project gốc sau fresh-project lifecycle.
- [x] Full A–E regression trên project volumes mới; volumes còn nguyên sau stop.
- [x] Phase 06 DONE.
- [x] Không tạo PR.
