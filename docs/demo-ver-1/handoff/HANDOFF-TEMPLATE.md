# HANDOFF — PHASE XX: <TÊN PHASE>

> **Đây là TEMPLATE**, không phải kết quả phase thực. Khi xong phase, sao chép thành `docs/demo-ver-1/handoff/phase-XX-handoff.md` và điền bằng kết quả thật. Xoá toàn bộ placeholder. **Tuyệt đối không ghi PASS từ dự đoán.**

## 1. Metadata

- Phase: `XX` — <tên>
- Trạng thái: `DONE` / `BLOCKED` (chọn một, không để mập mờ)
- Ngày giờ + múi giờ:
- Nhánh Git: `feat/demo-ver-1-knox-gateway` (hoặc nhánh thực)
- Base SHA lúc bắt đầu:
- **SHA commit implementation đã tạo:** <SHA thực, không ghi SHA của chính commit handoff>
- Remote đã push? <Yes/No, branch>
- Người/thực thể thực hiện:

## 2. Tóm tắt đã làm

- Mục tiêu phase:
- Kết quả quan sát được (ngắn gọn):
- Thay đổi quan trọng và tại sao:
- Phần nào *chưa làm/chưa kiểm chứng*:

## 3. Files thay đổi

| Đường dẫn | Thay đổi | Lý do |
|---|---|---|
| <path> | <new/edit/delete> | <reason> |

## 4. Bằng chứng kiểm thử THẬT

| Test ID | Lệnh/cách chạy | Exit code / HTTP status thực | Bằng chứng output/log (đường dẫn hoặc excerpt đã redacted) | Kết quả |
|---|---|---|---|---|
| <test> | <command> | <observed> | <evidence> | PASS/FAIL/NOT RUN |

- OS + Docker/Compose/Knox/Hadoop versions dùng khi test:
- Container statuses và readiness:
- Cách phân biệt nguồn lỗi ở Knox/LDAP/WebHDFS/network:
- Test âm tính / failure injection đã chạy:
- Test restart / data persistence đã chạy:
- Những kiểm thử chưa chạy + lý do:

> Nếu Docker không sẵn: đánh dấu `NOT RUN`, **không** thay output bằng giả lập. Nếu cổng gate không đạt, status phải là `BLOCKED`.

## 5. Quyết định kỹ thuật và giới hạn

- Quyết định và lý do (có dẫn docs/log):
- Khác biệt so với Master/phase spec:
- Security notes (self-signed cert, demo credentials, `dfs.permissions.enabled=false`, port publish):
- Rủi ro hoặc technical debt còn lại:

## 6. Blocker / việc tiếp theo

- Blocker (nếu có): <điều kiện + cách tái hiện + ảnh hưởng>
- Hướng khắc phục: <bước ngắn, không đoán quá mức>
- Phase kế tiếp: <XX> (chỉ khi DONE)
- Tập tin phase kế tiếp Codex được phép đọc: `docs/demo-ver-1/spec/phase-XX-....md`
- Lệnh đầu tiên khi resume:
  1. `git status --short --branch`
  2. Đọc `docs/demo-ver-1/spec/MASTER-SPEC.md`
  3. Đọc handoff phase gần nhất (file này)
  4. Chỉ đọc spec phase tiếp theo

## 7. Checklist trước khi bàn giao

- [ ] Có code/config/test thực (hoặc ghi BLOCKED rõ).
- [ ] Test đúng hành vi, không hardcode expected thành pass.
- [ ] Không secrets/private keys cá nhân/log khổng lồ/file rác.
- [ ] Commit implementation tiếng Việt + body bullet liền nhau.
- [ ] Handoff ghi **SHA commit implementation** thực, không phải SHA tự tham chiếu.
- [ ] Commit riêng file handoff, cùng format và push remote feature branch.
- [ ] **Không tạo PR; không resolve review conversations.**
