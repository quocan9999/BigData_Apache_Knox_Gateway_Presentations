# PHASE 05 — E2E 5 màn A–E, audit và thử lỗi có chủ đích

## Mục tiêu

Cung cấp test harness/demo runner **chạy stack thật** trên PowerShell Windows, tái hiện 5 màn rõ kết quả; chụp bằng chứng audit hợp lệ. Các test phải thực sự tìm lỗi, không viết để xanh cho có.

## Đầu vào

Phase 04 DONE. Đọc Master, handoff 04 và spec này.

## Hành vi kiểm thử

| Màn | Hành động thật | Nghiệm thu |
|---|---|---|
| A | Host curl tới 9870 | Không kết nối được **vì port không publish**; Knox còn truy cập HDFS |
| B | Invalid credentials vào Knox | Authn denial từ Knox; xác nhận status/log |
| C | Valid LDAP guest không ACL | Knox AclsAuthz denial; kiểm tra status thật và nguồn denial |
| D | Valid LDAP admin allow | HTTP 200 + `FileStatuses.FileStatus` gồm hai file thật |
| E | Kiểm tra Knox audit log sau B/C/D | Sự kiện có principal, action/resource/outcome theo schema thực tế; không ghi nội dung giả |

## Công việc kỹ thuật

- Tạo script PowerShell từ root/demo chạy sẵn sàng, seed an toàn, thực hiện HTTP requests và assertions. Nếu có script shell phụ thì không được bỏ PowerShell path chính.
- Không echo password trong log public; có thể dùng demo fixtures công khai với nhãn lab-only. Không commit credentials cá nhân. Nếu in output, redact token/cookie.
- HTTP test phải assert status, parsed JSON, có đúng hai filenames và proof URL **qua 8443**, không fallback sang direct 9870/mocked response. Test negative phải fail khi ta cố ý cấu hình sai password/policy/service.
- Audit kiểm tra source log thật từ Knox (đường dẫn theo image runtime), không tự append/fabricate, không tuyên bố user hiện diện nếu audit không có. Ghi timestamp, limitation và chứng cứ được scrub.
- Có test outage/backend-down: khi NameNode ngừng, Knox không thể trả JSON fake 200; sau restore phục hồi. Không làm hỏng dữ liệu volume.
- Thử restart, timeout readiness, thiếu LDAP, thiếu route; script phải báo fail khác 0 khi điều kiện không đạt. Sau test phục hồi đủ stack.
- Có summary PASS/FAIL/BLOCKED theo từng màn kèm hướng xem full logs cục bộ.

## Done khi

Mọi màn A–E chạy **thật, lặp lại được** và log tương ứng, test bắt sai lệch, không có 401/403 được gán nhầm backend. Nếu 403 không được hỗ trợ đúng như mong muốn, ghi blocker/đề xuất có chứng cứ, không tự coi DONE chỉ vì chặn được bằng 401.

## Handoff

Commit script/test/evidence docs, rồi `handoff/phase-05-handoff.md`: bảng ca test + command + exit code + HTTP status + audit source + failure injection; commit riêng và push. Không commit toàn bộ logs chứa dữ liệu nhạy cảm.
