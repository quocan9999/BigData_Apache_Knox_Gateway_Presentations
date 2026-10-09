# Đóng gói demo Apache Knox Phase 06 — Kế hoạch triển khai

> **For agentic workers:** Kế hoạch này được thực hiện trực tiếp trong phiên hiện tại theo yêu cầu hoàn tất Phase 06. Các bước dùng checkbox để theo dõi.

**Goal:** Hoàn thiện tài liệu để nhóm có thể chạy và trình bày demo Knox v1 trên Windows, đồng thời kiểm chứng luồng clone sạch và bảo toàn volume HDFS.

**Architecture:** Giữ Compose hiện có làm nguồn cấu hình chuẩn; mở rộng README gốc và runbook demo, thêm kịch bản trình diễn tiếng Việt cùng hướng dẫn lưu evidence thật. Dùng project name riêng cho kiểm tra volume sạch để tách biệt dữ liệu hiện hữu.

**Tech Stack:** Windows PowerShell 5.1, Docker Desktop Linux containers, Docker Compose, Hadoop 3.4.3, Apache Knox 3.0.0-release.

**Spec:** `docs/demo-ver-1/spec/phase-06-dong-goi-va-bao-cao.md`

## Global Constraints

- Demo phải chạy trên Windows + Docker Desktop; chỉ mô tả chức năng đã kiểm thử.
- Không xóa HDFS data, không dùng `docker compose down -v`, không ghi secrets/log/video lớn vào Git.
- Test A–E, stop/restart, permission/reseed và outage/restore trên stack thật; ghi rõ điều chưa thử trên máy thứ hai.
- Tài liệu phải nêu rõ self-signed TLS, credentials demo-only và giới hạn `dfs.permissions.enabled=false`.
- Tách implementation commit và handoff commit; push lên `origin/feat/demo-ver-1-knox-gateway`; không tạo PR.

## Review Focus

- Lệnh runbook chạy từ root repo hay `demo/` không nhất quán — xác nhận bằng cách chạy lệnh từ PowerShell đúng thư mục đã ghi.
- Project name mới có thể vô tình dùng lại named volumes cũ — dùng tên duy nhất và kiểm tra Compose volume names trước khi `up`.
- Reseed có thể ghi đè dữ liệu hoặc đổi nội dung file — chạy hai lần và so sánh listing/status trước-sau.
- Hướng dẫn recovery quyền có thể gây mất dữ liệu — thử trên volume mới riêng, không sửa owner của volume cũ.
- Capture hoặc transcript có thể chứa credentials/log nhạy cảm — kiểm tra `.gitignore` và xác nhận sample path bị ignore.

---

### Task 1: README gốc và runbook demo

**Files:**
- Modify: `README.md`
- Modify: `demo/README.md`

**Interfaces:**
- Consumes: Compose files, `Seed-HdfsDemo.ps1`, `Wait-KnoxReady.ps1`, `Test-KnoxDemo.ps1`.
- Produces: command sequence và troubleshooting steps khớp với script/Compose hiện hành.

- [x] Viết README gốc với mục tiêu, sơ đồ ASCII, phiên bản đã quan sát và liên kết tới runbook/kịch bản.
- [x] Mở rộng runbook với prerequisites, startup, seed, A–E, test suite, stop/restart, recovery permission và troubleshooting.
- [x] Đối chiếu mọi lệnh với tham số thật của script; chạy các lệnh smoke từ PowerShell ở root/`demo` như tài liệu chỉ dẫn.

Kiểm tra hợp đồng tài liệu trước khi sửa, dự kiến FAIL vì root README hiện rỗng và runbook thiếu các mục Phase 06:

```powershell
$required = @{
  'README.md' = @('Apache Knox Gateway', 'Sơ đồ kiến trúc', 'Môi trường đã kiểm thử', 'Chạy demo')
  'demo/README.md' = @('Điều kiện tiên quyết', 'Khởi chạy lần đầu', 'Phục hồi quyền volume', 'Khắc phục sự cố', 'Dừng và khởi động lại')
}
$missing = foreach ($path in $required.Keys) {
$content = Get-Content -LiteralPath $path -Raw -Encoding UTF8
  foreach ($phrase in $required[$path]) { if ([string]::IsNullOrEmpty($content) -or $content -notmatch [regex]::Escape($phrase)) { "$path :: $phrase" } }
}
if ($missing) { $missing; exit 1 }
```

### Task 2: Kịch bản 3–5 phút và phương án evidence

**Files:**
- Create: `docs/demo-ver-1/presentation-script.md`
- Create: `demo-backup/README.md`
- Create: `.gitignore`

**Interfaces:**
- Consumes: trạng thái A–E đã kiểm thử ở Phase 05 và Windows capture tools.
- Produces: lời thoại tiếng Việt theo thời gian, expected/observed, nguồn sinh lỗi, quy tắc metadata/evidence và đường dẫn lưu cục bộ.

- [x] Soạn kịch bản A–E 3–5 phút, không tạo slide, ghi response thực và cách giải thích nguồn lỗi.
- [x] Viết quy trình quay/chụp từ phiên demo thật, metadata tối thiểu và chính sách không chỉnh sửa nội dung gây sai nghĩa.
- [x] Ignore mọi nội dung local trong `demo-backup/` trừ README; ignore `.env` cá nhân nhưng cho phép `.env.example`.
- [x] Xác nhận `git check-ignore` chặn đường dẫn capture mẫu nhưng vẫn track được `demo-backup/README.md`.

Kiểm tra artifact/policy trước khi tạo, dự kiến FAIL do các tệp và ignore rule chưa có:

```powershell
$missing = @()
if (!(Test-Path -LiteralPath 'docs/demo-ver-1/presentation-script.md')) { $missing += 'docs/demo-ver-1/presentation-script.md missing' }
if (!(Test-Path -LiteralPath 'demo-backup/README.md')) { $missing += 'demo-backup/README.md missing' }
git check-ignore -q --no-index demo-backup/capture-sample.mp4
if ($LASTEXITCODE -ne 0) { $missing += 'demo-backup/capture-sample.mp4 not ignored' }
git check-ignore -q --no-index demo-backup/README.md
if ($LASTEXITCODE -eq 0) { $missing += 'demo-backup/README.md incorrectly ignored' }
git check-ignore -q --no-index .env
if ($LASTEXITCODE -ne 0) { $missing += '.env not ignored' }
git check-ignore -q --no-index .env.example
if ($LASTEXITCODE -eq 0) { $missing += '.env.example incorrectly ignored' }
git check-ignore -q --no-index demo/.env
if ($LASTEXITCODE -ne 0) { $missing += 'nested demo/.env not ignored' }
git check-ignore -q --no-index demo/.env.example
if ($LASTEXITCODE -eq 0) { $missing += 'nested demo/.env.example incorrectly ignored' }
if ($missing) { $missing; exit 1 }
```

### Task 3: Kiểm chứng clone sạch và dữ liệu cũ

**Files:**
- No source changes expected unless a documented command exposes a defect.

**Interfaces:**
- Consumes: base Compose + Knox overlay and existing seed/readiness/test scripts.
- Produces: runtime evidence for unique project volumes and proof that the original project remains intact.

- [x] Ghi nhận listing và hai file trong project hiện tại; xác minh HDFS healthy.
- [x] Dùng project name duy nhất `apache-knox-p06-freshcheck-20261010`; inspect volume names trước khi start và xác nhận hai volume có prefix dự án mới.
- [x] Chạy `up --wait`, seed hai lần, full A–E/failure suite và stop/restart chỉ trên project mới.
- [x] Trên stack mới đã stop, mô phỏng owner `0:0` chỉ cho hai volume mới bằng `docker compose @freshCompose run --rm --no-deps --entrypoint /usr/bin/chown hdfs-volume-init -R 0:0 /data/name /data/data`; xác nhận owner sai, chạy lại `hdfs-volume-init` one-off, xác nhận owner `hadoop`, rồi `up --wait`, seed và full suite để chứng minh phục hồi.
- [x] Stop project fresh bằng `down` không có `-v`; xác nhận volumes mới còn nguyên. Khi thử bật lại project gốc, Compose timeout; probe chỉ đọc trong network namespace vẫn xác nhận NameNode `/dfshealth.html`, JMX `NumLiveDataNodes=1`, LDAP TCP listener và WebHDFS JSON hai file.
- [ ] Chạy `docker compose up --wait` thành công và full A–E regression cuối trên project gốc sau fresh-project lifecycle; yêu cầu Docker API/readiness hồi phục trước khi đóng gate.

### Task 4: Static checks và tổng kiểm thử regression

**Files:**
- Verify all Compose YAML, Hadoop/Knox XML, PowerShell scripts, `.gitignore`, and changed documentation.

**Interfaces:**
- Consumes: deliverables from Tasks 1–3.
- Produces: recorded exit codes, HTTP bodies/status, runtime status and artifact/log paths for the Phase 06 handoff.

- [x] Parse các Compose file/config, XML và tất cả PowerShell scripts; rà file rác, secrets và `git diff --check`.
- [x] Chạy full A–E runner cùng stop/restart, seed/reseed, permission recovery và outage/restore trên volumes mới.
- [ ] Re-run full A–E trên project hiện tại sau khi đưa project mới xuống; xác minh Compose healthy và data nguyên vẹn.
- [x] Evidence thiếu của project gốc và UI capture được ghi NOT RUN/CHƯA KIỂM CHỨNG; không đánh dấu Phase 06 DONE.

### Task 5: Commit và bàn giao Phase 06

**Files:**
- Create: `docs/demo-ver-1/handoff/phase-06-handoff.md`

**Interfaces:**
- Consumes: final test output, current Git state and exact implementation commit SHA.
- Produces: truthful final handoff and separate commits pushed to the existing feature branch.

- [x] Commit implementation/docs với Conventional Commit tiếng Việt và body bullet liền nhau.
- [x] Điền handoff với commands, output, versions, timestamp/timezone, limitations và SHA implementation.
- [ ] Tạo handoff commit riêng, push cả hai commit, verify remote tip và clean worktree; dừng, không tạo PR.
