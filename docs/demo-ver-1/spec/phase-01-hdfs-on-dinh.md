# PHASE 01 — Tái lập và ổn định HDFS + WebHDFS thật

## Mục tiêu

Từ baseline người dùng đã chạy, tạo hệ thống Hadoop HDFS Compose **khởi động lặp lại được**, không đòi chown thủ công, không xóa volume; seed dữ liệu HDFS thật idempotent để các phase sau dùng.

## Đầu vào

Handoff Phase 00 `DONE`; đọc Master + spec hiện tại + handoff 00. Không đọc các spec phase sau.

## Phạm vi triển khai

- Giữ NameNode/DataNode image Hadoop pin phiên bản, `fs.defaultFS=hdfs://namenode:8020`, `dfs.webhdfs.enabled=true`, replication=1.
- Sửa bài toán permissions volume (/data/name, /data/data), chạy init/chown giới hạn thư mục có tên cụ thể và quyền phù hợp, không để mọi service chạy root lâu dài; hạn chế thay đổi dữ liệu HDFS cũ.
- Tạo startup/readiness probes thực: NameNode HTTP/HDFS RPC, `hdfs dfsadmin -report` nhìn thấy một DataNode live. `depends_on` đơn thuần không chứng minh ready.
- Seed `/demo/apache-knox.txt` và `/demo/bigdata.txt` hoặc data có ý nghĩa; không dùng response JSON hardcode. Nếu viết file thật khác rỗng thì ghi rõ giá trị/mục tiêu. Seed chạy lại không phá dữ liệu có sẵn; có cách reset an toàn chỉ khi user đồng ý.
- Tối thiểu: `docker compose config`, `docker compose up -d`, `ps -a`, `hdfs dfs -ls /demo`, `curl.exe ...LISTSTATUS...`; thời gian chờ có timeout hợp lý.
- Có PowerShell hoặc câu lệnh chạy dễ copy trên Windows. Nếu backend đang tạm publish `127.0.0.1:9870`, đánh dấu chỉ dành cho Phase 01, sẽ đóng ở Phase 04.

## Test phải bắt bug

1. Fresh volume startup: một DataNode live, NameNode Up, API JSON gồm cả hai `pathSuffix`.
2. Rerun init/seed: không duplicate, không xóa file cũ/ghi đè bất ngờ; exit code đúng.
3. `docker compose down` (không `-v`) rồi up: dữ liệu vẫn còn.
4. Simulate thiếu readiness/volume permission: check script fail rõ ràng, không trả 0 giả.
5. `curl` kiểm tra **HTTP status + JSON fields**, không chỉ grep chữ `200` hoặc test container Up.

## Done khi

Có log/HTTP JSON **thật**, không lỗi quyền, không cần manual chmod/chown mỗi lần. Không thay đổi ngầm bảo mật HDFS sang production; ghi rõ `dfs.permissions.enabled=false` là lab-only.

## Commit / handoff

Commit code/config/test Phase 01 → lưu SHA; tạo `handoff/phase-01-handoff.md` từ template nêu data persistence/commands/evidence/lỗi còn lại → commit riêng và push. Nếu bất kỳ tiêu chí runtime chưa thử: BLOCKED, không mở Phase 02.
