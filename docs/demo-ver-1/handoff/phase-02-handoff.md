# HANDOFF — PHASE 02: Knox Gateway + LDAP

## 1. Metadata

- Phase: 02 — Knox Gateway và xác thực LDAP thật
- Trạng thái: DONE
- Ngày giờ + múi giờ: 2026-10-09 23:33, Asia/Ho_Chi_Minh
- Nhánh Git: `feat/demo-ver-1-knox-gateway`
- Base SHA lúc bắt đầu: `b7a9fb871eee1d3dd463e6e13941f5b7eaf6f406`
- **SHA commit implementation đã tạo:** `1a40f0a839b15538eb31dd249382044a241b185d`
- Remote: implementation đã push lên `origin/feat/demo-ver-1-knox-gateway`; handoff được commit và push riêng sau đó.
- Người/thực thể thực hiện: Codex trên Windows PowerShell

## 2. Tóm tắt đã làm

- Mục tiêu phase: chạy Knox Gateway và LDAP demo thật trong Compose; dùng HTTPS qua Knox để xác thực và truy cập WebHDFS thật.
- Kết quả quan sát được: Knox chặn yêu cầu chưa đăng nhập và password sai bằng HTTP 401; tài khoản LDAP `guest` nhận HTTP 200 cùng WebHDFS JSON có `apache-knox.txt` và `bigdata.txt`; khi LDAP dừng, đăng nhập bị từ chối kèm lỗi kết nối mới trong log; sau khi LDAP chạy lại, yêu cầu lại nhận HTTP 200.
- Thay đổi quan trọng và tại sao: thêm overlay Compose với image Knox release được pin bằng manifest digest; thêm Knox Demo LDAP riêng và topology Shiro/LDAP/WebHDFS; healthcheck kiểm tra LDAP TCP và HTTPS Basic challenge. Thêm timeout kết nối LDAP 3 giây để outage trả lỗi kịp thời. Luồng test và README gọi seed HDFS idempotent trước khi truy vấn, để hoạt động trên volume mới.
- Phần nào chưa làm/chưa kiểm chứng: Knox ACL chi tiết thuộc Phase 03; đóng publish NameNode 9870 thuộc Phase 04; audit và ma trận ca kiểm thử thuộc phase sau. Không kiểm tra lại `CreatedAt` của HDFS volume trong phase này; data qua main stack restart được kiểm chứng bằng seed-preserve và WebHDFS HTTP 200.

## 3. Files thay đổi

| Đường dẫn | Thay đổi | Lý do |
|---|---|---|
| `demo/docker-compose.knox.yml` | Tạo | Thêm Knox Gateway và Knox Demo LDAP với image pinned, healthcheck và port Gateway loopback-only |
| `demo/knox/topologies/demo.xml` | Tạo | Cấu hình Shiro LDAP, identity assertion Default, NameNode và WebHDFS backend |
| `demo/scripts/Wait-KnoxReady.ps1` | Tạo | Đợi Compose healthy; báo cả trạng thái service và log khi timeout |
| `demo/tests/Test-KnoxGateway.ps1` | Tạo | Chạy kiểm tra end-to-end cho challenge, login, password sai, LDAP outage và recovery |
| `demo/scripts/Seed-HdfsDemo.ps1` | Sửa | Thêm tùy chọn dùng Compose overlay trong Phase 02, giữ nguyên cách gọi Phase 01 mặc định |
| `demo/scripts/Wait-HdfsReady.ps1` | Sửa | Cho phép readiness gọi bằng cùng Compose overlay khi được seed script dùng trong Phase 02 |
| `demo/README.md` | Tạo | Hướng dẫn startup, seed, truy cập Knox, test và cleanup an toàn |
| `docs/superpowers/plans/2026-10-09-knox-ldap-phase-02.md` | Tạo | Ghi kế hoạch và quyết định triển khai Phase 02 |

## 4. Bằng chứng kiểm thử THẬT

| Test ID | Lệnh/cách chạy | Exit code / HTTP status thực | Bằng chứng output/log (đã redacted) | Kết quả |
|---|---|---|---|---|
| P02-CONFIG | `docker compose -p apache-knox-bigdata-demo -f demo/docker-compose.yml -f demo/docker-compose.knox.yml config --quiet` | 0 | Cấu hình Compose hợp lệ | PASS |
| P02-PS-PARSER | PowerShell Parser trên các file `.ps1` trong `demo/scripts` và `demo/tests` | 0 | `PowerShell parser PASS: 8 scripts.` | PASS |
| P02-FRESH-E2E | `Test-KnoxGateway.ps1 -ProjectName apache-knox-p02-fresh-20261009 -TimeoutSeconds 180` | 0; unauthenticated 401; valid 200; invalid 401; LDAP outage 401; recovery 200 | Fresh project tạo mới hai file; JSON qua Knox chứa đúng hai path; log outage có `CommunicationException` và `SocketTimeoutException: Connect timed out` | PASS |
| P02-MAIN-E2E | `Test-KnoxGateway.ps1 -TimeoutSeconds 180` | 0; unauthenticated 401; valid 200; invalid 401; LDAP outage 401; recovery 200 | Seed báo giữ nguyên cả hai file; log sai password có `INVALID_CREDENTIALS`; outage có lỗi kết nối mới; sau recovery WebHDFS qua Knox trả JSON đúng | PASS |
| P02-READY | `Wait-KnoxReady.ps1 -ProjectName apache-knox-bigdata-demo -TimeoutSeconds 180` | 0 | `Compose reports healthy LDAP and Gateway; Gateway healthcheck verifies the HTTPS route and Basic challenge.` | PASS |
| P02-WEBHDFS | `curl.exe -sS -w status http://127.0.0.1:9870/webhdfs/v1/demo?op=LISTSTATUS` | curl exit 0, HTTP 200 | JSON có `apache-knox.txt` và `bigdata.txt`, trước và sau khi khởi động lại main stack | PASS |
| P02-XML | Parse `demo/knox/topologies/demo.xml` bằng XML parser của PowerShell | 0 | `Knox topology XML PASS.` | PASS |

- OS + Docker/Compose/Knox/Hadoop versions dùng khi test: Windows PowerShell 5.1.26100.9444; Docker CLI 29.6.2; Docker Compose v5.3.1; `apache/knox:3.0.0-release`; `apache/hadoop:3.4.3`. Knox image chạy linux/amd64, Temurin Java 17.0.20.1. Manifest digest được pin: `sha256:058733ba7de9b6f7a37f850a50db343ebb8d0e72bc6bd5ecf668736906f2034c` (linux/amd64 image digest: `sha256:d67102356ab9190a8f8701e7e3d681b8b405b2a8508990f3e74957fed1c85d2c`). Docker Desktop/Engine 29.6.2 được ghi trong Phase 01 handoff; lượt truy vấn chi tiết `docker version` ở phase này gặp Go runtime out-of-memory khi host còn khoảng 1 GiB RAM trống, nhưng lệnh version ngắn và Compose vẫn chạy.
- Container statuses và readiness cuối: `namenode` Up (healthy), `datanode` Up, `knox-ldap` Up (healthy), `knox-gateway` Up (healthy), `hdfs-volume-init` Exited (0). `Wait-HdfsReady` xác nhận NameNode HTTP 200, service DataNode đang chạy và `dfsadmin -report` có một DataNode live.
- Cách phân biệt nguồn lỗi ở Knox/LDAP/WebHDFS/network: sai mật khẩu trả HTTP 401 và Gateway log `INVALID_CREDENTIALS`; khi LDAP dừng, HTTP vẫn bị từ chối và log mới cho thấy `CommunicationException`/`SocketTimeoutException`; khi LDAP lên lại, WebHDFS JSON có hai path trả HTTP 200 qua URL Knox. Một yêu cầu direct WebHDFS riêng cũng trả HTTP 200.
- Test âm tính / failure injection đã chạy: request không credentials; sai password `guest:wrong-password`; dừng service `knox-ldap`, xác nhận xác thực thất bại, sau đó khởi động lại và xác nhận recovery.
- Test restart / data persistence đã chạy: dùng `docker compose down` không có `-v` cho project chính, chạy E2E trên project/volume mới, dừng project mới cũng không có `-v`, rồi khởi động project chính trên named volumes cũ. Seed báo `Preserving existing HDFS file` cho hai file và WebHDFS trả HTTP 200. Không xóa named volumes.
- Những kiểm thử chưa chạy + lý do: không kiểm tra thủ công account `admin` (account `guest` được kiểm chứng end-to-end); không chạy `docker volume inspect` sau restart do giới hạn bộ nhớ đã nêu. Phase01 handoff đã kiểm chứng việc giữ nguyên CreatedAt của hai HDFS volume qua restart.

## 5. Quyết định kỹ thuật và giới hạn

- Image `apache/knox:3.0.0-release` được pin theo OCI manifest digest để tránh thay đổi ngầm. LDAP dùng demo fixture tích hợp trong image: `guest` / `guest-password` và `admin` / `admin-password`; đây chỉ là thông tin lab.
- `ShiroProvider` dùng `KnoxLdapRealm`, LDAP URL `ldap://knox-ldap:33389`, DN template `uid={0},ou=people,dc=hadoop,dc=apache,dc=org`, và JNDI `com.sun.jndi.ldap.connect.timeout=3000`. `Default` identity assertion giữ username đã xác thực. HDFS route dùng `NAMENODE hdfs://namenode:8020` và `WEBHDFS http://namenode:9870/webhdfs`.
- Tài liệu tham khảo: [Apache Knox User Guide](https://knox.apache.org/books/knox-2-1-0/user-guide.html), [Knox 3.0 `KnoxLdapContextFactory`](https://github.com/apache/knox/blob/v3.0.0-release/gateway-provider-security-shiro/src/main/java/org/apache/knox/gateway/shirorealm/KnoxLdapContextFactory.java), [Apache Shiro `JndiLdapContextFactory`](https://apache.googlesource.com/shiro/+/719e56e97d46e1e1325c33aeaaee77d6b33acd19/1.2.x/core/src/main/java/org/apache/shiro/realm/ldap/JndiLdapContextFactory.java).
- Khác biệt so với Master/phase spec: không có. Phase 02 giữ nguyên Compose HDFS cơ sở; NameNode vẫn publish `127.0.0.1:9870` theo biên Phase 01 và sẽ được đóng ở Phase 04. Knox HTTPS bind `127.0.0.1:8443`; LDAP 33389 không publish ra host.
- Security notes: cert HTTPS tự ký và chỉ dùng cho lab; lệnh `curl.exe -k` bỏ qua xác minh chứng chỉ cho demo local. Demo credentials không dùng trong production. `dfs.permissions.enabled=false` là cấu hình HDFS lab-only từ Phase 01. Port 9870 vẫn truy cập được từ host cho tới Phase 04.
- Rủi ro hoặc technical debt còn lại: chưa cấu hình Knox ACL chi tiết; đây là mục tiêu Phase 03. Chưa có audit hay kiểm thử ma trận ca A–E trong phase này.

## 6. Blocker / việc tiếp theo

- Blocker: không có cho Phase 02.
- Phase kế tiếp: 03 — phân quyền Knox.
- Tập tin phase kế tiếp Codex được phép đọc: `docs/demo-ver-1/spec/phase-03-phan-quyen.md` (chỉ đọc sau khi bắt đầu Phase 03).
- Lệnh đầu tiên khi resume:
  1. `git status --short --branch`
  2. Đọc `docs/demo-ver-1/spec/MASTER-SPEC.md`
  3. Đọc handoff gần nhất: `docs/demo-ver-1/handoff/phase-02-handoff.md`
  4. Chỉ đọc `docs/demo-ver-1/spec/phase-03-phan-quyen.md`

## 7. Checklist trước khi bàn giao

- [x] Có code/config/test thực; runtime evidence đạt gate trên volume mới và volume chính.
- [x] Test kiểm tra WebHDFS thật, wrong password, LDAP outage và recovery.
- [x] Không commit secrets, private keys, Docker volumes hoặc log artifacts.
- [x] Commit implementation tiếng Việt: `1a40f0a`.
- [x] Handoff ghi SHA commit implementation đầy đủ, không tự tham chiếu.
- [x] Handoff được commit riêng và push lên feature branch.
- [x] Không tạo PR, không merge, không rebase/force push.
