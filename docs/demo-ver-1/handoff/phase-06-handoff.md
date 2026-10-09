# HANDOFF — PHASE 06: Đóng gói, runbook và trình diễn

## 1. Metadata

- Phase: 06 — đóng gói demo Apache Knox v1
- Trạng thái: **BLOCKED — chưa DONE**
- Thời gian kiểm chứng: 2026-10-10 01:22–02:19, Asia/Ho_Chi_Minh (UTC+07:00)
- Nhánh: `feat/demo-ver-1-knox-gateway`
- Base SHA: `2bcb31d09080f072e1f6d2b96d0b8c546ec249ea`
- SHA commit implementation: `7213b36f68c20eca117bb30f633df200f94e87a1`
- Môi trường: Windows 11 Home, Windows PowerShell 5.1.26100.9444, Docker Desktop Linux containers, Docker Engine 29.6.2, Docker Compose 5.3.1
- Người/thực thể thực hiện: Codex trên Windows PowerShell

## 2. Tóm tắt

- Hoàn thiện README ở root và `demo/`, kịch bản A–E tiếng Việt khoảng 4 phút, hướng dẫn lưu capture/evidence thật, và quy tắc ignore file local.
- Xác minh lệnh khởi chạy từ đúng thư mục `demo/`; Compose readiness, seed và Knox readiness thành công trên stack ban đầu trước khi kiểm tra project mới.
- Dùng project độc lập `apache-knox-p06-freshcheck-20261010`; volumes mới không trùng với project gốc. Seed hai lần, stop/restart, phục hồi owner và hai lượt runner đầy đủ đều giữ hai file HDFS.
- Không chạy `docker compose down -v`; volumes của project gốc và project kiểm thử không bị xóa.
- Lần khởi động project gốc sau project mới ban đầu bị timeout; sau đó Docker Engine hồi phục, Compose `up --wait` thành công và các dịch vụ chính báo healthy.
- Lượt regression cuối trên project gốc đã chạy, nhưng runner trả exit code 1 vì các assertion audit NameNode và khôi phục xác thực LDAP không đạt; xem `P06-ORIGINAL-REGRESSION` bên dưới. Phase 06 vẫn chưa đạt Definition of Done. Không kiểm thử trên máy thứ hai; giao diện Snipping Tool/Game Bar cũng chưa được xác minh trên host này.

## 3. Files thay đổi

| Đường dẫn | Nội dung |
|---|---|
| `README.md` | Mục tiêu, sơ đồ, phiên bản đã quan sát, cách chạy và giới hạn bảo mật |
| `demo/README.md` | Prerequisites, startup/readiness/seed, A–E, test, fresh project, recovery, stop/restart và troubleshooting |
| `docs/demo-ver-1/presentation-script.md` | Lời thoại 3–5 phút, expected/observed, nguồn sinh lỗi và lệnh A–E |
| `demo-backup/README.md` | Quy trình capture thật, metadata và SHA-256; capture phát sinh bị ignore |
| `.gitignore` | Ignore capture local và `.env` cá nhân, cho phép track `.env.example` cùng README của backup |
| `docs/superpowers/plans/2026-10-10-knox-packaging-phase-06.md` | Checklist và trạng thái thực hiện Phase 06 |

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
| P06-ORIGINAL | Thử `docker compose up -d --wait --wait-timeout 180` trên project gốc sau khi hạ project mới | Compose timeout: dependency NameNode/LDAP không đạt trạng thái chờ; `dockerDesktopLinuxEngine` named-pipe `/_ping` không phản hồi trong 5 giây và một số Docker CLI query bị treo | BLOCKED |
| P06-ORIGINAL-READONLY | Probe chỉ đọc qua network namespace của NameNode gốc và kiểm tra LDAP listener | `/dfshealth.html` trả thành công; JMX `NumLiveDataNodes=1`; WebHDFS JSON còn đúng hai file; LDAP TCP 33389 nhận kết nối. Knox readiness và full A–E sau lifecycle chưa xác nhận | PARTIAL |
| P06-ORIGINAL-REGRESSION | `docker compose -p apache-knox-bigdata-demo -f docker-compose.yml -f docker-compose.knox.yml up -d --wait --wait-timeout 180`; sau đó ` .\tests\Test-KnoxDemo.ps1 -ProjectName apache-knox-bigdata-demo -TimeoutSeconds 180` từ `demo/` | Compose/readiness và seed đạt; HDFS/WebHDFS thật có hai file; host không kết nối được `:9870`, Knox trả HTTP 200 JSON. Runner **exit 1**: Screen A fail vì NameNode `listStatus` audit counter không tăng (0→0); Screen B sai mật khẩu + Knox auth audit đạt nhưng LDAP recovery trả 401 sau khi LDAP/Gateway readiness đã healthy; Screen D admin nhận JSON thật và Knox dispatch/access audit thành công nhưng assertion NameNode audit không đạt. Guest-denial của C chưa được xác nhận trong lượt này; E chưa đạt gate suite. Các suite Isolation, Authentication, Authorization và Failure Injection báo FAIL; `READINESS_TIMEOUT_AND_RECOVERY` BLOCKED; `FINAL_STACK_RECOVERY` PASS. Stack cuối lượt đã healthy. | BLOCKED |

Hai log runner local, không commit:

- `C:\Users\trinh\AppData\Local\Temp\knox-demo-v1-20261010-012227-c39e23f78657423b83c2f28a1d766576` — kết thúc 01:28:48 +07:00.
- `C:\Users\trinh\AppData\Local\Temp\knox-demo-v1-20261010-013101-6c85a93df93642859195f94f6631fc7a` — kết thúc 01:37:24 +07:00.
- `C:\Users\trinh\AppData\Local\Temp\knox-demo-v1-20261010-021630-be5a29611cf645ed95edf4364eaf59f7` — lượt regression trên project gốc, runner exit 1; kết thúc 02:19:04 +07:00.
- Cả hai lượt có marker PASS cho screens A–E, suites và nhóm regression; scan không tìm thấy `admin-password` hoặc `guest-password` trong log.

Volumes dự án gốc được giữ nguyên: `apache-knox-bigdata-demo_hdfs_namenode`, `apache-knox-bigdata-demo_hdfs_datanode`. Hai volume project mới có prefix `apache-knox-p06-freshcheck-20261010_`; tên được kiểm tra trước khi `up` và xác nhận còn tồn tại sau `down` không kèm `-v`.

## 5. Quyết định và giới hạn

- Lượt A–E hoàn chỉnh của Phase 06 chạy trên volumes mới; hai lượt riêng xác nhận stack sạch và recovery sau thay đổi owner. Kết quả đó không thay thế lượt cuối trên project gốc.
- Probe network namespace chứng minh được HDFS data và LDAP process phản hồi tại thời điểm đo. Nó không chứng minh Compose healthy hoặc Knox sẵn sàng.
- Không tạo ảnh/video minh họa. README backup hướng dẫn lưu file được quay/chụp từ phiên demo thật; thao tác UI capture chưa được xác minh trên host này.
- Không thử trên máy thứ hai; không tuyên bố quy trình đã được người khác xác nhận.
- Giới hạn demo: TLS tự ký; LDAP accounts là fixture demo-only; `dfs.permissions.enabled=false`; backend/LDAP không publish host port nhưng client khác trong Docker network vẫn có thể gọi backend.
- Không chạy `down -v`, không sửa/xóa HDFS volume gốc, không commit log/capture/secrets, không tạo PR, không merge/rebase/force-push.

## 6. Blocker và bước tiếp theo

Docker Engine hiện phản hồi và project gốc đã healthy; blocker hiện tại là regression gate, không còn là khả năng khởi động Docker. Bằng chứng lần chạy mới nằm trong log local, không commit:

- `C:\Users\trinh\AppData\Local\Temp\knox-demo-v1-20261010-021630-be5a29611cf645ed95edf4364eaf59f7\01-screen-a-isolation.log`: isolation và JSON WebHDFS thật đạt, nhưng assertion NameNode `listStatus` audit tăng 0→0 nên suite fail.
- `C:\Users\trinh\AppData\Local\Temp\knox-demo-v1-20261010-021630-be5a29611cf645ed95edf4364eaf59f7\02-screen-b-authentication.log`: sai mật khẩu bị Knox từ chối và audit auth thất bại hiện hữu; sau phục hồi LDAP, readiness đạt nhưng xác thực admin vẫn HTTP 401.
- `C:\Users\trinh\AppData\Local\Temp\knox-demo-v1-20261010-021630-be5a29611cf645ed95edf4364eaf59f7\03-screens-cde-authorization.log`: admin nhận HTTP 200 + hai file thật; Knox dispatch/access audit ghi success; assertion NameNode audit làm lượt kiểm thử dừng trước khi chứng minh guest denial.
- Lệnh tái hiện: từ `demo/`, ` .\tests\Test-KnoxDemo.ps1 -ProjectName apache-knox-bigdata-demo -TimeoutSeconds 180` (exit 1; log folder nêu trên).

Phase 06 giữ trạng thái BLOCKED. Chưa đánh dấu DONE và chưa chuyển sang PR; cần xử lý các gate trên rồi chạy lại regression đầy đủ trước khi hoàn tất.

## 7. Checklist bàn giao

- [x] README/runbook, kịch bản trình bày và quy trình evidence local đã được soạn.
- [x] Static validation và fresh-project A–E/recovery/restart chạy thành công.
- [x] Named volumes cũ được giữ nguyên; không dùng `down -v`.
- [ ] Compose readiness và full A–E regression cuối trên project gốc sau fresh-project lifecycle.
- [ ] Phase 06 DONE.
- [x] Không tạo PR.
