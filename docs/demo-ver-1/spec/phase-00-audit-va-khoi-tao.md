# PHASE 00 — Kiểm kê repo, khởi tạo nhánh an toàn và baseline

## Mục tiêu

Nhận lại dự án đang có các file demo **local chưa chắc đã push**; xác lập git-safe workflow và bức tranh thực tế trước khi viết mã. Phase này không cấu hình Knox.

## Tài liệu cần đọc

`docs/demo-ver-1/spec/MASTER-SPEC.md`, `docs/handoff/00-bang-giao-boi-canh-du-an.md` (nếu chưa đọc), spec hiện tại; **không đọc các phase sau**.

## Công việc

1. Kiểm tra `pwd`, `git remote -v`, `git status --short --branch`, `git branch -avv`, `git log -n 8 --oneline`; phân biệt remote `main`, nhánh tài liệu và local thay đổi chưa commit.
2. Kiểm tra `demo/`, `docker-compose.yml`, `hadoop/core-site.xml`, `hdfs-site.xml`, README, ignore; so sánh cấu hình đang dùng với handoff, không giả định overlay Knox đã chạy.
3. Kiểm tra Docker availability: `docker version`, `docker compose version`, `docker compose config`, `docker compose ps -a`; chỉ chạy log/healthcheck đọc trạng thái. Ghi có hay không: image, volumes, HDFS sống, WebHDFS 200.
4. Tạo hoặc chuyển tới `feat/demo-ver-1-knox-gateway` từ nhánh tài liệu `origin/docs/handoff-context-20261009` **nếu an toàn**. Nếu working tree dirty gây nguy cơ ghi đè, dừng và xử lý giữ nguyên file theo hướng không phá dữ liệu; không tự chuyển trên main để code.
5. Tạo tài liệu kiểm kê tối thiểu trong `docs/demo-ver-1/` (ví dụ `BASELINE.md`) gồm SHA/branch, file hiện có, môi trường và các thiếu sót; chưa sửa code trừ trường hợp cần công cụ xác minh và không ảnh hưởng baseline.

## Tiêu chí nghiệm thu

- Repo tồn tại đúng remote; phát triển ở feature branch **khác main** và đã bảo vệ file người dùng.
- Báo cáo rõ trạng thái remote/local và tình trạng HDFS/Knox thật (KNOWN / NOT VERIFIED).
- Không mất HDFS volumes, không thay các file chưa commit, không phát sinh secrets/log thừa.
- Chạy các kiểm tra đọc trạng thái khi có công cụ; thiếu Docker phải ghi blocker, không mặc định PASS.

## Bàn giao

Commit tài liệu audit với Conventional Commit tiếng Việt và body bullet liền nhau; tạo `handoff/phase-00-handoff.md` từ template, ghi SHA commit kiểm kê, kết quả lệnh, blocker/rủi ro, next phase; commit handoff riêng và push feature branch. Nếu audit bị chặn, handoff `BLOCKED`, không tự nhảy Phase 01.
