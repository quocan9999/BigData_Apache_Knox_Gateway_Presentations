# PHASE 03 — Phân quyền Knox AclsAuthz và chứng minh denial

## Mục tiêu

Trình bày rõ **authentication khác authorization**. Có hai principal xác thực thành công nhưng chỉ principal được cấp quyền WebHDFS đi qua; principal còn lại bị chính **Knox AclsAuthz** chặn trước backend.

## Đầu vào

Phase 02 DONE. Đọc Master, handoff 02, spec này; không đọc trước Phase 04+.

## Công việc

- Khai báo Knox authorization provider `AclsAuthz` trong đúng topology/rule service `WEBHDFS`. Cấu trúc `user;group;IP` phải theo tài liệu phiên bản được pin; không giả định `webhdfs.acl=admin;*;*` luôn cho HTTP 403 theo kỳ vọng.
- Fixture tài khoản: một user được quyền (ví dụ admin), một user đúng password nhưng không quyền (ví dụ guest). Các fixture có thể khác tên mẫu nếu được tạo, test và ghi đầy đủ.
- Test phân biệt 3 trạng thái: (1) credentials sai = authentication failure, (2) credentials đúng nhưng ACL denial = authorization failure, (3) credentials đúng + ACL allow = request forwarded.
- Xác minh nguồn HTTP error bằng gateway log/audit và, khi có thể, kiểm tra WebHDFS/backend chưa nhận request bị chặn; không chỉ nhìn HTTP 403 rồi đoán do Knox.
- Bảo đảm backend không dùng Ranger; nếu backend HDFS trả denial thì không được dùng làm bằng chứng AclsAuthz.

## Nghiệm thu nghiêm ngặt

- Correct user + allow: WebHDFS thật trả 200 + JSON của /demo.
- Correct user + deny: Knox từ chối theo ACL với status và response **đo được**, ưu tiên 403 phục vụ slide; nếu cơ chế phiên bản cho 401/khác, phải điều tra/có bằng chứng và **báo blocker cho chủ dự án trước khi đổi yêu cầu màn C**. Không fake/chặn tùy tiện ở Nginx/mock server để tạo 403.
- Wrong credentials bị chặn ở authn độc lập với ACL.
- Test case đảo policy/cho user guest vào allow phải biến kết quả đúng chiều; nếu test vẫn pass mọi trường hợp thì test vô giá trị.

## Bàn giao

Commit config/test, sau đó handoff `phase-03-handoff.md` nêu rule thật, status thật, audit/log origin denial, khác biệt 401/403 và rủi ro còn lại; hai commit Conventional tiếng Việt, push feature branch. Không được tự sửa yêu cầu hoặc chuyển phase khi thiếu bằng chứng.
