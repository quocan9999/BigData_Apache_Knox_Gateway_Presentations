# Apache Knox Gateway — demo v1

Demo chạy thật Apache Knox Gateway trước Hadoop HDFS/WebHDFS trên Windows và Docker Desktop. Knox cung cấp một điểm vào HTTPS, xác thực với LDAP demo, áp dụng ACL cho dịch vụ WebHDFS, chuyển tiếp request vào HDFS và ghi audit. Đây là lab học tập, không phải cấu hình production.

## Sơ đồ kiến trúc

```text
Windows PowerShell / curl.exe
          │ HTTPS 127.0.0.1:8443
          ▼
   Apache Knox Gateway ─── Knox demo LDAP
   topology / authn / ACL / proxy / audit
          │ Docker network riêng
          ▼
   NameNode :9870 / WebHDFS
          │
      HDFS DataNode
```

Host chỉ publish Knox ở `127.0.0.1:8443`. NameNode `:9870`, DataNode, HDFS RPC và LDAP không có host port mapping. Knox gọi WebHDFS bằng hostname `namenode` trên Docker network. Các container khác trong network vẫn có thể gọi backend; đây là cô lập bằng port/network Compose, không phải Knox chặn mọi đường đi.

## Môi trường đã kiểm thử

| Thành phần | Phiên bản/giá trị đã quan sát |
|---|---|
| Máy kiểm thử | Windows 11 Home, Windows PowerShell 5.1.26100.9444 |
| Docker Engine | Client/Server 29.6.2, Linux containers, 16 CPU |
| RAM Docker khả dụng khi kiểm thử | 8,128,749,568 bytes (~7.57 GiB); đây là cấu hình quan sát, không phải ngưỡng tối thiểu đã xác định |
| Docker Compose | 5.3.1 |
| Hadoop | `apache/hadoop:3.4.3` |
| Knox Gateway + LDAP demo | `apache/knox:3.0.0-release`, digest `sha256:058733ba7de9b6f7a37f850a50db343ebb8d0e72bc6bd5ecf668736906f2034c` |

## Chạy demo

Từ thư mục gốc repository, chạy runbook trong [`demo/README.md`](demo/README.md). Runbook có lệnh khởi động, kiểm tra readiness, seed HDFS, chạy 5 màn A–E, xử lý lỗi, khởi động lại và bảo toàn named volumes. Kịch bản nói 3–5 phút nằm tại [`docs/demo-ver-1/presentation-script.md`](docs/demo-ver-1/presentation-script.md).

Lệnh kiểm thử tổng hợp, sau khi chuyển vào thư mục `demo/`:

```powershell
.\tests\Test-KnoxDemo.ps1 -TimeoutSeconds 180
```

Các suite xác nhận host không truy cập trực tiếp NameNode, xác thực LDAP, ACL Knox, JSON từ HDFS thật và audit runtime. Log của runner nằm trong `%TEMP%\knox-demo-v1-*`, chỉ lưu trên máy chạy.

## Giới hạn bảo mật

- LDAP accounts/passwords trong fixture chỉ dùng cho demo. Không dùng lại ở môi trường khác.
- Chứng thư TLS tự ký; `curl.exe -k` chỉ dùng cho localhost trong lab.
- HDFS đang tắt permission enforcement (`dfs.permissions.enabled=false`). Knox kiểm soát request đi qua Gateway, không thay thế strong authentication/authorization của HDFS.
- Không publish backend ra host giúp minh họa một điểm vào; nó không ngăn các client trong Docker network truy cập backend.
- Không chạy `docker compose down -v`; lệnh đó xóa named volumes HDFS.

## Tài liệu

- [Runbook vận hành và khắc phục sự cố](demo/README.md)
- [Kịch bản trình diễn tiếng Việt](docs/demo-ver-1/presentation-script.md)
- [Handoff Phase 06](docs/demo-ver-1/handoff/phase-06-handoff.md) — trạng thái và bằng chứng đóng gói cuối.
