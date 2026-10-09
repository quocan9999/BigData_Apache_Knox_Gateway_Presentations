# PHASE 06 — Đóng gói, tài liệu vận hành và trình diễn ổn định

## Mục tiêu

Demo v1 có thể dùng trong bài thuyết trình bởi Quốc An hoặc Sony trên Windows; có hướng dẫn cho người mới clone repo, command ngắn dễ gõ, checklist thuyết trình, báo cáo giới hạn bảo mật và phương án dự phòng trung thực.

## Đầu vào

Phase 05 DONE. Đọc Master, handoff 05 và spec này.

## Công việc

1. Hoàn thiện README root/demo: mục tiêu, sơ đồ ASCII, phiên bản image, prerequisites (Docker Desktop/Linux containers, RAM), cấu hình, khởi động/fresh start, stop/restart, seed, test, troubleshooting và recovery permissions. Chỉ mô tả chức năng đã test.
2. Một kịch bản trình diễn 3–5 phút tiếng Việt: dẫn nhập single entry point, A (9870 từ host fail), B (authn fail), C (ACL deny), D (HDFS JSON qua Knox), E (audit); lời thoại ngắn, rõ ai sinh lỗi, expected vs observed; chuẩn bị slide-friendly summary (không làm slide chưa được giao).
3. Chuẩn bị phương án dự phòng: lệnh quay video/screenshot từ chạy thật nếu cần, quy định file lưu ở `demo-backup/` hoặc docs và metadata ngày/phiên bản; không làm giả evidence, không commit clip lớn/log/secrets tự động.
4. Đảm bảo clone sạch với Docker volumes mới có thể chạy theo runbook; môi trường có volumes cũ không bị mất dữ liệu. Nếu không test được trên máy thứ hai, ghi giới hạn rõ, không nói đã test.
5. Static validation: YAML/XML, script syntax/quality, git ignore, kiểm tra file rác (logs, volumes, artifacts, secrets, environment cá nhân). Runtime regression: tất cả A–E, stop/restart, permission/reseed, outage/restore; validate đúng root path trên Windows.
6. Kết thúc chỉ khi tài liệu và source nói cùng một sự thật; nếu khác nhau, sửa code/docs rồi test lại.

## Definition of Done dự án demo v1

- Knox Gateway/LDAP/AclsAuthz/WebHDFS thật, host chỉ công khai gateway, HDFS có hai file seed, A–E được test và có evidence.
- Có cách reproducible startup trên Windows không yêu cầu lệnh chown thủ công; không xóa data khi restart.
- Ít nhất một người khác có thể chạy theo README hoặc có log tái hiện/review peer có dẫn chứng; những điều chưa kiểm chứng ghi rõ.
- Git history dễ review: phase boundaries rõ, test/commit/handoff tách biệt; không file rác/secrets/claim sai.
- Có báo cáo gọn về các giới hạn production security: backend không bật HDFS strong authz, self-signed TLS local, host exposure != kiểm soát truy cập nội bộ.

## Bàn giao cuối

Commit hoàn thiện code/docs rồi handoff `phase-06-handoff.md`, push feature branch; gửi báo cáo tổng hợp trạng thái từng phase, SHA và các bước thuyết trình. **DỪNG — không tạo PR** trước yêu cầu explicit của chủ repo. Không resolve conversation review thay reviewer.
