# HANDOFF — PHASE 03: Phân quyền Knox AclsAuthz

## 1. Metadata

- Phase: `03` — Phân quyền Knox AclsAuthz và chứng minh denial
- Trạng thái: `DONE`
- Ngày giờ + múi giờ: 2026-10-10 00:00, Asia/Ho_Chi_Minh
- Nhánh Git: `feat/demo-ver-1-knox-gateway`
- Base SHA lúc bắt đầu: `4af8270673788d62711718d5d9ef90a5a0573ba0`
- **SHA commit implementation đã tạo:** f57c4c35990771a8afeb09b81010f99fae78cd74
- Remote đã push? Yes, implementation commit nằm trên origin/feat/demo-ver-1-knox-gateway.
- Người/thực thể thực hiện: Codex trên Windows PowerShell

## 2. Tóm tắt đã làm

- Mục tiêu phase: phân biệt authentication với authorization và chứng minh Knox AclsAuthz chặn user LDAP hợp lệ trước khi request tới WebHDFS.
- Kết quả quan sát được: `admin` xác thực và nhận HTTP 200 cùng WebHDFS JSON có hai file thật; `guest` xác thực thành công nhưng nhận HTTP 403; audit Knox ghi `authorization` / `failure` và NameNode không có sự kiện `listStatus` mới cho request bị chặn. Sai password vẫn nhận HTTP 401 cùng `INVALID_CREDENTIALS`.
- Thay đổi quan trọng và tại sao: topology mặc định giới hạn `WEBHDFS` bằng `webhdfs.acl=admin;*;*`; fixture test riêng đảo quyền sang guest để chứng minh kết quả thay đổi theo policy. Test kiểm tra Compose đã mount đúng topology trước khi đổi chính sách và luôn phục hồi topology mặc định.
- Phần chưa làm/chưa kiểm chứng: chưa chạy lại toàn bộ test trên project/volume mới trong Phase 03; Phase 02 đã có kiểm thử fresh project và giữ nguyên named volumes. Backend NameNode vẫn publish `127.0.0.1:9870`; việc đóng cổng thuộc Phase 04.

## 3. Files thay đổi

| Đường dẫn | Thay đổi | Lý do |
|---|---|---|
| `demo/knox/topologies/demo.xml` | Sửa | Bật AclsAuthz và chỉ cho admin gọi WEBHDFS |
| `demo/knox/topologies/demo-guest-allow.xml` | Tạo | Fixture đảo ACL cho kiểm thử policy trên Knox thật |
| `demo/docker-compose.knox-acl-test.yml` | Tạo | Ghi đè topology mount trong lần chạy policy đảo |
| `demo/scripts/Wait-KnoxReady.ps1` | Sửa | Hỗ trợ readiness với overlay test ACL |
| `demo/tests/Test-KnoxAuthorization.ps1` | Tạo | Kiểm thử allow/deny, authn riêng, audit, backend và đảo policy |
| `demo/tests/Test-KnoxGateway.ps1` | Sửa | Dùng admin làm principal được ACL cho phép |
| `demo/README.md` | Sửa | Hướng dẫn phân biệt authentication/authorization và lệnh kiểm thử |
| `docs/superpowers/plans/2026-10-09-knox-aclsauthz-phase-03.md` | Tạo | Ghi kế hoạch và quyết định của Phase 03 |

## 4. Bằng chứng kiểm thử THẬT

| Test ID | Lệnh/cách chạy | Exit code / HTTP status thực | Bằng chứng output/log (đã redacted) | Kết quả |
|---|---|---|---|---|
| P03-COMPOSE | `docker compose -p apache-knox-bigdata-demo -f docker-compose.yml -f docker-compose.knox.yml config --quiet`; chạy lại và thêm `-f docker-compose.knox-acl-test.yml` | Cả hai exit 0 | `config --format json` xác nhận default source `demo.xml`; policy đảo source `demo-guest-allow.xml`, cùng target `/home/knox/knox/conf/topologies/demo.xml` | PASS |
| P03-XML | Parse hai topology bằng `[xml](Get-Content -Raw -Encoding UTF8 ...)` | Exit 0 | `Knox topology XML PASS: default and reversed-policy fixtures.` | PASS |
| P03-PS-PARSER | PowerShell Parser trên `demo/scripts` và `demo/tests` | Exit 0 | `PowerShell parser PASS: 9 scripts.` | PASS |
| P03-AUTHORIZATION | .\tests\Test-KnoxAuthorization.ps1 -TimeoutSeconds 180 | Lượt cuối exit 0; admin 200, guest 403, password sai 401; policy đảo guest 200/admin 403 | NameNode listStatus tăng 13 → 14 sau admin. Knox audit mới cho principal guest, service WEBHDFS, action authorization, URI /gateway/demo/webhdfs/v1/demo?op=LISTSTATUS và outcome failure; response 403, không có NameNode event mới. Policy đảo đổi kết quả; phục hồi default và xác nhận admin allow/guest deny. Ba lượt thử trước dừng trước ACL do Docker CLI lỗi khi bộ nhớ thấp (hai lần unknown shorthand flag -p, một lần Go OutOfMemoryException); cùng lệnh sau khi Compose hoạt động lại exit 0. | PASS |
| P03-GATEWAY-REGRESSION | .\tests\Test-KnoxGateway.ps1 -TimeoutSeconds 180 | Exit 0; anonymous 401, admin 200, password sai 401, LDAP outage 401, recovery 200 | Sai password có Knox INVALID_CREDENTIALS; outage có CommunicationException và SocketTimeoutException: Connect timed out; recovery trả WebHDFS JSON với hai path. | PASS |
| P03-SMOKE | `curl.exe -k -sS --include --user 'admin:admin-password' 'https://127.0.0.1:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS'`; chạy tương tự với guest | Cả lệnh exit 0; admin HTTP 200, guest HTTP 403 | Admin response `Content-Type: application/json` có `apache-knox.txt`, `bigdata.txt`; guest response `HTTP/1.1 403 Forbidden` và body `HTTP ERROR 403 Forbidden`. | PASS |
| P03-STATUS | `docker compose -p apache-knox-bigdata-demo -f docker-compose.yml -f docker-compose.knox.yml ps -a` | Exit 0 | NameNode `Up (healthy)`, DataNode `Up`, Knox LDAP `Up (healthy)`, Knox Gateway `Up (healthy)`, volume init `Exited (0)`. | PASS |

- OS + Docker/Compose/Knox/Hadoop versions dùng khi test: Windows PowerShell `5.1.26100.9444`; Docker CLI `29.6.2`, Compose `v5.3.1`, Hadoop `3.4.3`, Knox `3.0.0-release` (image manifest digest `sha256:058733ba7de9b6f7a37f850a50db343ebb8d0e72bc6bd5ecf668736906f2034c`, linux/amd64 digest `sha256:d67102356ab9190a8f8701e7e3d681b8b405b2a8508990f3e74957fed1c85d2c`), Java Temurin `17.0.20.1`. Docker/Compose versions được ghi nhận ở Phase 02; hai E2E command của Phase 03 chạy thành công. Lệnh đọc version sau test gặp Go runtime `OutOfMemoryException`, nên không đọc lại version ở lượt này.
- Container statuses và readiness cuối: các trạng thái như bảng P03-STATUS; Knox HTTPS bind loopback `127.0.0.1:8443`; NameNode vẫn publish `127.0.0.1:9870` tới khi hoàn thành Phase 04. `Wait-KnoxReady.ps1` và `Wait-HdfsReady.ps1` đều báo readiness thành công.
- Cách phân biệt nguồn lỗi ở Knox/LDAP/WebHDFS/network: sai password có HTTP 401/Basic challenge và Knox `INVALID_CREDENTIALS`; ACL denial có HTTP 403, Knox audit `authorization|failure` và access response 403; đối chứng NameNode không nhận `listStatus` từ guest. Admin allow tăng NameNode `listStatus` counter và trả JSON WebHDFS thật.
- Test âm tính / failure injection đã chạy: credentials sai; LDAP dừng rồi chạy lại; guest đúng credentials bị ACL từ chối; đảo ACL để guest allow/admin deny rồi xác nhận cả hai kết quả đảo chiều.
- Test restart / data persistence đã chạy: Phase 03 tái tạo riêng Knox Gateway khi đảo và phục hồi topology, không xóa/recreate named HDFS volumes; seed báo giữ nguyên hai file. Kiểm thử restart HDFS và persistence trên main/fresh project đã có trong handoff Phase 02.
- Những kiểm thử chưa chạy + lý do: chưa chạy ma trận ACL trên project fresh riêng; Phase 03 đã kiểm tra policy thực trên stack chính, còn Phase 02 đã xác nhận fresh project và dữ liệu volumes. Chưa chạy Phase 04 kiểm tra host không truy cập NameNode trực tiếp.

## 5. Quyết định kỹ thuật và giới hạn

- Quyết định và lý do: provider `AclsAuthz` áp dụng `webhdfs.acl` dạng `user;group;IP`, mặc định `admin;*;*`. Knox trả HTTP 403 trong runtime hiện tại; test không giả lập status. Apache Knox 3.0.0 `AclsAuthorizationFilter` ghi audit authorization failure, không gọi filter chain khi bị từ chối và gửi Forbidden. Tham khảo [Knox User Guide](https://knox.apache.org/books/knox-2-1-0/user-guide.html), [Knox 3.0.0 AclsAuthorizationFilter](https://github.com/apache/knox/blob/v3.0.0-release/gateway-provider-security-authz-acls/src/main/java/org/apache/knox/gateway/filter/AclsAuthorizationFilter.java), và [Docker Compose merge reference](https://github.com/docker/compose/blob/main/docs/reference/compose.md).
- Khác biệt so với Master/phase spec: không có. Status và response 403 được đo trực tiếp; test xác nhận nguồn denial bằng audit Knox và đối chứng NameNode.
- Security notes: TLS tự ký và tài khoản `admin`/`guest` chỉ dành cho demo; README dùng `curl.exe -k` cho lab local. `dfs.permissions.enabled=false` nên Knox bảo vệ gateway path, không thay thế quyền backend HDFS. NameNode port 9870 còn host-published đến Phase 04.
- Rủi ro hoặc technical debt còn lại: test kiểm tra NameNode audit bằng số lượng event `listStatus` trong cửa sổ 30 phút; nếu có traffic ngoài test cùng lúc, phép đếm có thể nhiễu. Denial vẫn cần đồng thời khớp audit Knox và counter backend không tăng. Fixture guest-allow chỉ dành cho test và không được dùng trong stack demo mặc định.

## 6. Blocker / việc tiếp theo

- Blocker: không có cho Phase 03.
- Hướng khắc phục: không áp dụng.
- Phase kế tiếp: `04` — cô lập backend, bỏ publish NameNode 9870.
- Tập tin phase kế tiếp Codex được phép đọc: `docs/demo-ver-1/spec/phase-04-co-lap-backend.md`
- Lệnh đầu tiên khi resume:
  1. `git status --short --branch`
  2. Đọc `docs/demo-ver-1/spec/MASTER-SPEC.md`
  3. Đọc handoff gần nhất: `docs/demo-ver-1/handoff/phase-03-handoff.md`
  4. Chỉ đọc spec `docs/demo-ver-1/spec/phase-04-co-lap-backend.md`

## 7. Checklist trước khi bàn giao

- [x] Có code/config/test thực, các gate Phase 03 đã chạy trên Knox/HDFS thật.
- [x] Test phân biệt authn, ACL allow/deny, audit Knox và backend forwarding; có đảo policy.
- [x] Không commit secrets, private keys, Docker volumes hoặc log artifacts.
- [x] Commit implementation tiếng Việt: f57c4c35990771a8afeb09b81010f99fae78cd74.
- [x] Handoff ghi SHA implementation, không tự tham chiếu.
- [x] Handoff sẽ được commit riêng và push cùng implementation lên remote feature branch.
- [x] Không tạo PR, không merge, không rebase/force push, không xóa HDFS volumes.
