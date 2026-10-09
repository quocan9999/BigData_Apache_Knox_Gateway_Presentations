# PHASE 04 — Cô lập backend khỏi Windows host

## Mục tiêu

Chứng minh màn A: **host không truy cập NameNode trực tiếp**, nhưng vẫn truy cập dữ liệu HDFS thật qua Knox. Tách rõ hiệu ứng Docker networking và chính sách gateway.

## Đầu vào

Phase 03 DONE. Đọc Master, handoff 03, spec hiện tại.

## Công việc

1. Bỏ ánh xạ host `127.0.0.1:9870:9870` của NameNode; không publish DataNode/LDAP/HDFS RPC ra host. Chỉ publish `127.0.0.1:8443:8443` cho gateway. `expose`/nội bộ container dùng phù hợp.
2. Sau `docker compose up -d`, xem `docker compose ps` / `docker inspect` xác minh host ports; tránh đánh đồng `docker ps` empty và `Exited`.
3. Từ **Windows host** chạy `curl.exe --connect-timeout 3 -i http://localhost:9870`; phải fail kết nối đúng bối cảnh (nếu cổng 9870 bị process khác chiếm thì cần phân biệt, không báo PASS nhầm).
4. Từ host chạy request authenticated+allowed vào Knox `https://localhost:8443/gateway/demo/webhdfs/v1/demo?op=LISTSTATUS`, nhận 200 JSON 2 file; chứng minh backend sống và DNS nội bộ.
5. Thử restart các service mà không làm mất HDFS; kiểm tra không expose sau restart. Giữ minh bạch rằng containers khác cùng mạng có thể gọi backend, Knox không có magic blocking.

## Test tránh pass giả

- Negative check 9870 failure **và** positive check Knox 8443 cùng lúc là bắt buộc; chỉ 9870 fail khi NameNode chết thì không đạt.
- Kiểm tra port mappings từ Docker Engine, không chỉ dựa vào lỗi curl.
- Không xóa volumes/không dùng `down -v` và không thay user policy Phase 03.

## Handoff

Commit config/test, ghi SHA và output port mapping, HTTP failure+success; viết `handoff/phase-04-handoff.md`, commit riêng và push. Không mở Phase 05 nếu gateway không truy cập được backend.
