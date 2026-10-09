# PHASE 02 — Knox Gateway + xác thực LDAP thật

## Mục tiêu

Triển khai Knox Gateway và demo LDAP vào Compose, dùng HTTPS qua Knox để truy cập WebHDFS thật; sai password bị chặn tại Knox. Chưa yêu cầu hoàn thiện quyền ACL chi tiết (Phase 03).

## Đầu vào / quy tắc đọc

Chỉ bắt đầu khi Phase 01 DONE. Đọc Master, handoff 01 và spec này; tìm thêm handoff cũ khi cần; không preload phase khác.

## Công việc

- Kiểm chứng image/tag Knox chính thức, architecture, Java/runtime, entrypoint, paths, cơ chế boot demo LDAP theo tài liệu chuẩn. Không tin mặc định overlay từ cuộc chat đã hoạt động.
- Tạo service `knox-gateway` + `knox-ldap` (hoặc tên hợp lý thống nhất) trong Compose; nếu dùng overlay, bảo đảm lệnh `docker compose -f ... -f ...` nhất quán trên toàn bộ scripts.
- Topology `demo`: ShiroProvider với LDAP thật, identity assertion phù hợp, `WEBHDFS` backend `http://namenode:9870/webhdfs` theo mapping chính xác của Knox (kiểm tra path/rewrite). Chỉ dùng cấu hình được xác thực theo docs/version.
- Cấu hình ít nhất một tài khoản demo có thông tin đăng nhập **được tạo và kiểm chứng thực tế**; tài khoản guest/admin dự kiến, không dùng chuỗi password suy đoán mà không có fixture. Password demo-only có cảnh báo, không commit dữ liệu production/private keys.
- HTTPS listener trên `127.0.0.1:8443` khi chạy trên host local; TLS self-signed là lab-only, giải thích `curl.exe -k`.
- Log/error rõ và readiness gate: Knox, LDAP thực sự sẵn, không chỉ container `Started`.

## Kịch bản kiểm thử

1. `docker compose config` hợp lệ, cả bốn service thực chạy, listener HTTPS phản hồi.
2. Sai mật khẩu thật qua endpoint Knox bị từ chối do authentication, kết quả hợp lý theo cấu hình; log/headers cho thấy do Knox, không do connect failed.
3. Tài khoản đúng có quyền căn bản đi qua Knox tới WebHDFS (khi Phase 03 chưa bật ACL), trả JSON với hai file có sẵn trong HDFS. Nếu URL mapping lỗi, debug theo log, không lấy direct WebHDFS 200 thay cho test Knox.
4. LDAP không sẵn: xác thực thất bại chứ không tự động cho truy cập không bảo vệ; báo rõ lỗi và recovery.

## Tiêu chí Done

Client → Knox HTTPS → LDAP → WebHDFS thật thành công; sai password thất bại; các lệnh trong README có thể làm lại. Không được tự nhận Knox hoạt động chỉ vì Hadoop 200 ở 9870.

## Bàn giao

Code/config/test commit riêng, ghi SHA; tạo `handoff/phase-02-handoff.md` ghi image versions, account fixtures demo-only, URL thực, HTTP status, log/evidence và blockers; commit riêng và push. Không tạo PR.
