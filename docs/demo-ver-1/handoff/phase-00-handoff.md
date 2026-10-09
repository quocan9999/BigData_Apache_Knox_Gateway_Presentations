# HANDOFF — PHASE 00: Kiểm kê repo và baseline

## 1. Metadata

- Phase: `00` — kiểm kê repo, branch và Docker/HDFS baseline
- Trạng thái: `DONE`
- Ngày giờ + múi giờ: 2026-10-09 15:25 UTC (22:25, Asia/Ho_Chi_Minh)
- Nhánh Git: `feat/demo-ver-1-knox-gateway`
- Base SHA lúc bắt đầu: `f132593b6220333c32398294486485958d6e6846`
- **SHA commit implementation đã tạo:** `45a61c132313d4890c955bffde23bfc2fa4c0182`
- Remote: implementation SHA đã được push lên `origin/feat/demo-ver-1-knox-gateway`; handoff này được commit riêng và push ngay sau đó theo workflow của phase.
- Người/thực thể thực hiện: Codex CLI trên Windows PowerShell

## 2. Tóm tắt đã làm

- Mục tiêu phase: xác nhận branch an toàn, đối soát repo local/remote và ghi lại Docker/HDFS trạng thái thật trước khi cấu hình Knox.
- Kết quả quan sát được: working tree sạch khi bắt đầu audit; branch feature hiện có khớp remote; Docker Compose hợp lệ; NameNode/DataNode đang sống; một DataNode đăng ký; hai file seed có trong HDFS; WebHDFS trả HTTP 200 cùng JSON thật.
- Thay đổi quan trọng và tại sao: thêm `docs/demo-ver-1/BASELINE.md` làm bản ghi lệnh và bằng chứng hiện trạng, tránh dựa riêng vào handoff lịch sử.
- Phần chưa làm/chưa kiểm chứng: Knox, LDAP, HTTPS, topology, authn/authz, audit; tự động seed/restart; chưa chạy failure injection hoặc restart test.

## 3. Files thay đổi

| Đường dẫn | Thay đổi | Lý do |
|---|---|---|
| `docs/demo-ver-1/BASELINE.md` | Tạo mới | Ghi nhận trạng thái Git, Docker, cấu hình và kết quả HDFS/WebHDFS tại thời điểm audit |
| `docs/demo-ver-1/handoff/phase-00-handoff.md` | Tạo mới | Bàn giao evidence và mở khóa Phase 01 |

## 4. Bằng chứng kiểm thử THẬT

| Test ID | Lệnh/cách chạy | Exit code / HTTP status thực | Bằng chứng output/log | Kết quả |
|---|---|---|---|---|
| P00-GIT | `git status --short --branch`; `git branch -avv`; `git rev-list --left-right --count origin/main...HEAD` | `0`; status sạch lúc bắt đầu; local feature khớp remote; ahead `origin/main` đúng 1 commit | SHA/nhánh và diff được ghi trong `docs/demo-ver-1/BASELINE.md` | PASS |
| P00-COMPOSE | `docker version`; `docker compose version`; `docker compose config --quiet`; `docker compose ps -a` | Tất cả `0` | Docker Client/Server `29.6.2`, Compose `v5.3.1`; config hợp lệ; hai container Hadoop Up; NameNode publish loopback `9870` | PASS |
| P00-HDFS | `docker compose exec -T namenode hdfs dfsadmin -report` | `0` | `Live datanodes (1)`; không có block thiếu/corrupt | PASS |
| P00-SEED | `docker compose exec -T namenode hdfs dfs -ls /demo` | `0` | `Found 2 items`: `apache-knox.txt`, `bigdata.txt` | PASS |
| P00-WEBHDFS | `curl.exe -sS -w "\nHTTP_STATUS=%{http_code}\n" "http://localhost:9870/webhdfs/v1/demo?op=LISTSTATUS&user.name=hadoop"` | exit `0`, HTTP `200` | JSON WebHDFS thực có `pathSuffix` của cả hai file; nội dung đã ghi trong baseline | PASS |
| P00-LOG | `docker compose logs --tail=40 namenode datanode` | `0` | DataNode đăng ký thành công; log tail không có crash; một WARN scanner tự dùng giá trị mặc định | PASS — cảnh báo được ghi nhận |

- OS + Docker/Compose/Knox/Hadoop versions dùng khi test: Windows/PowerShell; Docker `29.6.2`; Compose `v5.3.1`; image Hadoop `apache/hadoop:3.4.3` (image ID `sha256:127774dadab40ce84df7ac668a7a8c99945688b3fe336f1388f4477ca33e1529`); Knox chưa có trong compose nên chưa có version.
- Container statuses và readiness: `namenode` và `datanode` đều `running`/`Up`; report xác nhận 1 DataNode sống; WebHDFS trả JSON.
- Cách phân biệt nguồn lỗi ở Knox/LDAP/WebHDFS/network: chưa áp dụng vì Knox/LDAP chưa được cấu hình; Phase 02 trở đi phải dùng response và log runtime để phân biệt.
- Test âm tính / failure injection đã chạy: chưa chạy; không thuộc gate Phase 00.
- Test restart / data persistence đã chạy: chưa chạy; thuộc gate Phase 01.

## 5. Quyết định kỹ thuật và giới hạn

- Branch `feat/demo-ver-1-knox-gateway` đã có và khớp `origin`; không tạo lại hoặc chuyển nhánh. Working tree sạch trước thay đổi Phase 00.
- Giữ nguyên Hadoop Compose và hai named volumes. Cổng `127.0.0.1:9870` vẫn mở ở baseline; đóng cổng backend thuộc Phase 04.
- Knox, LDAP, authn/authz, audit và proxy **CHƯA KIỂM CHỨNG**. Không coi trạng thái HDFS/WebHDFS là bằng chứng Knox đã hoạt động.
- `dfs.permissions.enabled=false`; đây là lab, không phải bảo mật production. Tuyệt đối không xóa named volumes bằng `down -v`.
- Repo chưa có `.gitignore`, `demo/README.md` hoặc `demo/.gitignore`; cần xem xét khi đến phase đóng gói, tránh đưa secrets/logs vào repo.

## 6. Blocker / việc tiếp theo

- Blocker: không có blocker cho Phase 00.
- Phase kế tiếp: `01` — ổn định HDFS, seed idempotent và kiểm tra restart/persistence.
- Tập tin phase kế tiếp Codex được phép đọc: `docs/demo-ver-1/spec/phase-01-hdfs-on-dinh.md`.
- Lệnh đầu tiên khi resume:
  1. `git status --short --branch`
  2. Đọc `docs/demo-ver-1/spec/MASTER-SPEC.md`
  3. Đọc handoff phase gần nhất (`docs/demo-ver-1/handoff/phase-00-handoff.md`)
  4. Chỉ đọc `docs/demo-ver-1/spec/phase-01-hdfs-on-dinh.md`

## 7. Checklist trước khi bàn giao

- [x] Có tài liệu audit và bằng chứng runtime thực.
- [x] Test dựa trên trạng thái HDFS/WebHDFS thật, không mock.
- [x] Không có thay đổi HDFS volume, secrets, private keys hay log artifact được thêm vào repo.
- [x] Commit implementation tiếng Việt, body bullet liền nhau: `45a61c1`.
- [x] Handoff ghi SHA implementation thật; SHA của commit handoff xác định bằng `git log` sau commit.
- [x] Handoff được chuẩn bị để commit riêng và push lên feature branch ngay sau khi tạo commit.
- [x] Không tạo PR, không merge, không resolve review conversations.

