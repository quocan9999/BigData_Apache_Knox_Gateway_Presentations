# Lưu evidence demo thật (local only)

Thư mục này dành cho ảnh chụp, video và metadata được tạo từ một lượt demo đang chạy thật. Nội dung bên trong bị `.gitignore` loại khỏi Git, trừ README này. Không có bước nào tự commit hoặc upload tệp.

## Quy trình chụp/quay

1. Chạy demo và kiểm tra A–E theo [`demo/README.md`](../demo/README.md). Nếu dùng evidence cũ để dự phòng, ghi rõ ngày giờ và commit của lượt đó; không trình bày như kết quả vừa đo.
2. Trên Windows, có thể dùng Snipping Tool (`Win+Shift+S` để chụp; `Win+Shift+R` để bắt đầu quay nếu phiên bản Windows hỗ trợ). Microsoft hướng dẫn tại [Use Snipping Tool to capture screenshots](https://support.microsoft.com/en-us/windows/apps/use-snipping-tool-to-capture-screenshots). Nếu Xbox Game Bar đã bật, `Win+Alt+R` ghi video; Microsoft mô tả nơi lưu trong [Record your screen with Xbox Game Bar](https://support.microsoft.com/en-gb/accessibility/windows/use-a-screen-reader-to-record-your-screen-with-xbox-game-bar).
3. Lưu file gốc vào `demo-backup/`, ví dụ `20261010-134500-A.png`, `20261010-134500-DE.mp4`. Không chỉnh sửa response, status, audit hay nội dung để làm kết quả trông như một trạng thái khác. Crop vùng không liên quan được, nhưng giữ nguyên file gốc và ghi việc crop trong metadata.
4. Tạo metadata cho từng phiên chụp. Ghi thời điểm local cùng timezone, commit, Windows/PowerShell, Docker/Compose, image tag/digest, scenario A–E, tên file và ghi chú về các thao tác/biên tập.
5. Tạo SHA-256 để kiểm tra file có đổi sau khi ghi nhận:

```powershell
$captureRoot = Join-Path (git rev-parse --show-toplevel) 'demo-backup'
$captureFile = Join-Path $captureRoot '20261010-134500-DE.mp4'
$metadataPath = Join-Path $captureRoot '20261010-134500-metadata.json'
$metadata = [ordered]@{
  captured_at_local = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ss.fffK')
  timezone = [TimeZoneInfo]::Local.Id
  git_commit = (git rev-parse HEAD)
  windows = (Get-CimInstance Win32_OperatingSystem).Caption
  powershell = $PSVersionTable.PSVersion.ToString()
  docker = (docker version --format 'client={{.Client.Version}} server={{.Server.Version}}')
  compose = (docker compose version --short)
  hadoop_image = 'apache/hadoop:3.4.3'
  knox_image = 'apache/knox:3.0.0-release@sha256:058733ba7de9b6f7a37f850a50db343ebb8d0e72bc6bd5ecf668736906f2034c'
  scenarios = @('A', 'B', 'C', 'D', 'E')
  capture_file = [IO.Path]::GetFileName($captureFile)
  notes = 'Capture from the live local demo; list any crop or redaction here.'
}
$metadata | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $metadataPath -Encoding UTF8
Get-FileHash -LiteralPath $captureFile -Algorithm SHA256
```

Đổi tên file mẫu cho khớp với capture thực. Đừng ghi password/private key vào metadata. Nếu capture vô tình chứa dữ liệu nhạy cảm, không chia sẻ; tạo bản đã che thông tin mà vẫn giữ nguyên ý nghĩa và ghi rõ redaction, hoặc xóa bản local sau khi đã xử lý theo chính sách của nhóm.

## Giới hạn và lưu ý

- Máy kiểm thử hiện tại chưa xác nhận được Snipping Tool hoặc Xbox Game Bar; thao tác UI quay/chụp chưa được chạy thử trong Phase 06. Kiểm tra công cụ trên máy thuyết trình trước buổi demo.
- Test runner ghi log text trong `%TEMP%\knox-demo-v1-*`; log không tự được sao chép vào đây. Nếu cần giữ log làm evidence, kiểm tra nội dung trước, không đưa credentials hoặc dữ liệu nhạy cảm vào bản lưu.
- Các lệnh `curl.exe --user` trong kịch bản chứa fixture password công khai của demo. Chỉ chạy trên máy lab local; đừng thay bằng credentials thật khi ghi hình.
- Video lớn, ảnh, metadata runtime, transcript, logs, `.env` cá nhân và secrets không được commit. Xác nhận trước khi chia sẻ ra ngoài repo.
