# Demo v1 — Apache Knox Gateway

Đây là **bộ đặc tả giao việc cho Codex CLI**, chưa phải mã nguồn đã triển khai.

## Bắt đầu ở đâu?

1. Đọc handoff lịch sử: `docs/handoff/00-bang-giao-boi-canh-du-an.md` (chỉ ở lần đầu; sau compact đọc lại khi cần).
2. Đọc **`spec/MASTER-SPEC.md`** trước mỗi phiên làm việc hoặc sau khi compact.
3. Xác định phase tiếp theo bằng handoff đã hoàn thành và trạng thái Git/runtime thật.
4. **Chỉ đọc file spec của phase hiện tại**; không nạp toàn bộ thư mục `spec/`.
5. Làm, kiểm thử, commit, viết handoff từ `handoff/HANDOFF-TEMPLATE.md`, commit handoff và push. Không tự tạo PR.

## Mục lục

| Thứ tự | Spec | Trọng tâm |
|---|---|---|
| 00 | `spec/phase-00-audit-va-khoi-tao.md` | Git an toàn, đối soát thực trạng |
| 01 | `spec/phase-01-hdfs-on-dinh.md` | HDFS/WebHDFS có thể tái tạo |
| 02 | `spec/phase-02-knox-ldap.md` | Knox Gateway + xác thực LDAP |
| 03 | `spec/phase-03-phan-quyen.md` | Knox AclsAuthz và bằng chứng denial |
| 04 | `spec/phase-04-co-lap-backend.md` | Đóng cổng backend, xác nhận gateway duy nhất từ host |
| 05 | `spec/phase-05-kiem-thu-va-audit.md` | Test thật A–E và audit |
| 06 | `spec/phase-06-dong-goi-va-bao-cao.md` | Runbook, diễn tập, bàn giao cuối |

`handoff/HANDOFF-TEMPLATE.md` là **mẫu**, không đánh dấu một phase là hoàn thành. Handoff thực được tạo lần lượt: `phase-00-handoff.md` tới `phase-06-handoff.md` trong thư mục `handoff/`.

## Trạng thái tại thời điểm viết

Nguồn người dùng xác nhận HDFS/NameNode/DataNode với image `apache/hadoop:3.4.3` đã chạy trên Windows; request WebHDFS trực tiếp trả `200` và hai file. Knox/LDAP/Authz **chưa được chứng minh chạy thật**. Trên remote `main` chưa thấy `demo/`, local có thay đổi chưa commit. Không suy đoán tình trạng đã thay đổi; luôn kiểm tra trực tiếp.
