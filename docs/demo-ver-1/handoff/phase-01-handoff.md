# HANDOFF — PHASE 01: Tái lập và ổn định HDFS + WebHDFS

## 1. Metadata

- Phase: 01 — ổn định HDFS, WebHDFS và seed dữ liệu thật
- Trạng thái: DONE
- Ngày giờ + múi giờ: 2026-10-09 22:56, Asia/Ho_Chi_Minh
- Nhánh Git: feat/demo-ver-1-knox-gateway
- Base SHA lúc bắt đầu: 87f507fc36cd60089931065d974ecefc3d1559b3
- SHA commit implementation đã tạo: 276289e55fccf180ee78cef6accf348c300da72f
- Remote: implementation đã push lên origin/feat/demo-ver-1-knox-gateway; handoff được commit và push riêng theo workflow.
- Người/thực thể thực hiện: Codex trên Windows PowerShell

## 2. Tóm tắt đã làm

- Mục tiêu phase: làm HDFS Compose khởi động lại được trên volume cũ và mới, có readiness thật, seed idempotent, WebHDFS thật và kiểm tra persistence/failure.
- Kết quả quan sát được: NameNode healthy, DataNode running; dfsadmin báo đúng một DataNode live; WebHDFS LISTSTATUS trả HTTP 200 và JSON có cả apache-knox.txt, bigdata.txt. Main HDFS giữ nguyên hai named volume và dữ liệu qua down/up.
- Thay đổi quan trọng và tại sao: one-shot hdfs-volume-init chuẩn bị quyền cho riêng /data/name và /data/data; healthcheck và Wait-HdfsReady kiểm tra HTTP, HDFS report và trạng thái DataNode đang chạy; Seed-HdfsDemo chỉ tạo file còn thiếu. Có test riêng để xác nhận lỗi quyền không cho HDFS khởi động giả thành công.
- Phần chưa làm/chưa kiểm chứng: Knox, LDAP, HTTPS, topology, Knox ACL, audit và đóng publish cổng NameNode thuộc các phase sau; không có Knox trong phase này.

## 3. Files thay đổi

| Đường dẫn | Thay đổi | Lý do |
|---|---|---|
| demo/docker-compose.yml | Sửa | Init quyền volume giới hạn, dependency và healthcheck NameNode |
| demo/docker-compose.phase01-test.yml | Tạo | Tắt host port trong project test cô lập |
| demo/docker-compose.phase01-init-permission-failure.yml | Tạo | Override non-root để mô phỏng lỗi quyền init |
| demo/scripts/Wait-HdfsReady.ps1 | Tạo | Chờ NameNode HTTP, DataNode running và report có một DataNode live |
| demo/scripts/Seed-HdfsDemo.ps1 | Tạo | Seed hai file HDFS chỉ khi thiếu, bảo toàn file có sẵn |
| demo/tests/Test-FreshHdfsStartup.ps1 | Tạo | Kiểm tra startup trên project/volume mới |
| demo/tests/Test-IdempotentHdfsSeed.ps1 | Tạo | Kiểm tra nội dung, metadata và JSON WebHDFS sau khi seed hai lần |
| demo/tests/Test-HdfsReadinessFailure.ps1 | Tạo | Dừng DataNode, xác nhận readiness thất bại, sau đó khôi phục |
| demo/tests/Test-HdfsVolumeInitFailure.ps1 | Tạo | Xác nhận lỗi permission init chặn NameNode và DataNode |

## 4. Bằng chứng kiểm thử THẬT

| Test ID | Lệnh/cách chạy | Exit code / HTTP status thực | Bằng chứng output/log | Kết quả |
|---|---|---|---|---|
| P01-CONFIG | docker compose -f demo/docker-compose.yml config --quiet | 0 | Không có lỗi cấu hình | PASS |
| P01-PS-PARSER | PowerShell Parser trên sáu file .ps1 trong demo | 0 | PASS parser cho 2 script và 4 test script | PASS |
| P01-FRESH | Test-FreshHdfsStartup.ps1 -ProjectName knox-p01-release-20261009 -TimeoutSeconds 180 | 0 | NameNode HTTP 200; Live datanodes (1) | PASS |
| P01-SEED | Test-IdempotentHdfsSeed.ps1 -ProjectName knox-p01-release-20261009 -TimeoutSeconds 180 | 0 | Seed hai lần; giữ sentinel content và modificationTime; WebHDFS trả đúng apache-knox.txt, bigdata.txt | PASS |
| P01-READY-NEGATIVE | Test-HdfsReadinessFailure.ps1 -ProjectName knox-p01-release-20261009 | 0 | Khi DataNode dừng, readiness timeout với HTTP 200 nhưng DataNode service not running; sau đó DataNode được khởi động và readiness PASS | PASS |
| P01-PERM-NEGATIVE | Test-HdfsVolumeInitFailure.ps1 -ProjectName knox-p01-release-perm-20261009 -TimeoutSeconds 45 | 0 | Init non-root ghi chown: changing ownership of /data/name: Operation not permitted; Compose thất bại và NameNode/DataNode không chạy | PASS |
| P01-RESTART | docker compose -f demo/docker-compose.yml down; sau đó docker compose -f demo/docker-compose.yml up -d --wait --wait-timeout 180 | 0 và 0 | Hai file còn sau restart; dfsadmin báo Live datanodes (1) | PASS |
| P01-WEBHDFS | curl.exe -sS -w status tới /webhdfs/v1/demo?op=LISTSTATUS&user.name=hadoop | exit 0, HTTP 200 | JSON thật có FileStatuses.FileStatus với pathSuffix apache-knox.txt và bigdata.txt | PASS |
| P01-FINAL-STATE | Wait-HdfsReady.ps1; Seed-HdfsDemo.ps1; docker compose ps -a; dfsadmin -report; hdfs dfs -ls /demo | 0 | NameNode Up (healthy), DataNode Up, init Exited (0), đúng hai file | PASS |
| P01-VOLUME | docker volume inspect hai volume HDFS chính | 0 | Cả hai CreatedAt vẫn là 2026-10-09T08:08:51Z | PASS |

- OS + Docker/Compose/Knox/Hadoop versions dùng khi test: Windows PowerShell 5.1.26100.9444; Docker Client/Server 29.6.2; Compose v5.3.1; apache/hadoop:3.4.3; Knox chưa được cài/cấu hình ở phase này.
- Container statuses và readiness: main project apache-knox-bigdata-demo: namenode Up (healthy), datanode Up, hdfs-volume-init Exited (0); dfsadmin báo một DataNode live.
- Cách phân biệt nguồn lỗi ở Knox/LDAP/WebHDFS/network: phase này chưa có Knox/LDAP; kiểm tra WebHDFS trực tiếp tới NameNode và đọc lỗi init/readiness từ container/Compose. Các bài kiểm tra WebHDFS không giả lập response.
- Test âm tính / failure injection đã chạy: DataNode dừng; init chạy UID:GID 1000:100 và thất bại khi chown. Cả hai test xác nhận lỗi được trả về và dịch vụ phụ thuộc không được coi là ready.
- Test restart / data persistence đã chạy: main stack down không có -v rồi up lại; hai file còn, JSON vẫn trả đúng nội dung và hai volume giữ nguyên CreatedAt.
- Những kiểm thử chưa chạy + lý do: Knox, LDAP, HTTPS, ACL, audit, backend isolation và các ca demo A–E nằm ngoài Phase 01, sẽ làm ở phase được chỉ định.

## 5. Quyết định kỹ thuật và giới hạn

- Volume initializer chạy root một lần và chỉ chạm hai đường dẫn cụ thể; NameNode/DataNode vẫn chạy bằng user mặc định hadoop của image.
- Compose nội suy ký hiệu dollar cả trong shell command; script init dùng $$ để shell trong container nhận đúng biến. Bản thử chưa escape đã bị Compose thay bằng PATH của host và lỗi; sau khi sửa, config và fresh startup đều PASS.
- NameNode có thể còn báo DataNode live trong lúc heartbeat cũ chưa hết sau khi container bị dừng. Wait-HdfsReady kiểm tra thêm DataNode service đang chạy để không trả readiness sai.
- Root URL của NameNode chuyển hướng 302 sang UI; test theo redirect và xác nhận HTTP cuối 200. Endpoint /dfshealth.html trả trực tiếp HTTP 200.
- Khác biệt so với Master/phase spec: không có; Phase 01 vẫn publish 127.0.0.1:9870 để kiểm tra trực tiếp, cần gỡ ở Phase 04.
- Security notes: dfs.permissions.enabled=false là cấu hình lab-only, không phải production. Backend chỉ bind localhost trong phase này; cổng sẽ được đóng ở Phase 04. Không thay đổi cấu hình bảo mật HDFS.
- Rủi ro hoặc technical debt còn lại: chưa có kiểm thử gateway vì Knox chưa được triển khai; project test để lại named volumes cô lập, containers/networks đã được dừng bằng down không -v.

## 6. Blocker / việc tiếp theo

- Blocker: không có cho Phase 01.
- Phase kế tiếp: 02 — Knox và LDAP.
- Tập tin phase kế tiếp Codex được phép đọc: docs/demo-ver-1/spec/phase-02-knox-ldap.md.
- Lệnh đầu tiên khi resume:
  1. git status --short --branch
  2. Đọc docs/demo-ver-1/spec/MASTER-SPEC.md
  3. Đọc handoff gần nhất (file này)
  4. Chỉ đọc docs/demo-ver-1/spec/phase-02-knox-ldap.md

## 7. Checklist trước khi bàn giao

- [x] Có code/config/test thực; runtime evidence đạt gate.
- [x] Test dựa trên HDFS/WebHDFS thật; failure injection không báo PASS giả.
- [x] Không commit secrets, private keys, Docker volumes hoặc log artifact.
- [x] Commit implementation tiếng Việt: 276289e.
- [x] Handoff ghi SHA implementation thật.
- [x] Handoff được chuẩn bị commit riêng và push lên feature branch.
- [x] Không tạo PR, không merge, không rebase/force push.