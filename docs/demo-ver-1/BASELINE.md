# Baseline dự án — Phase 00

> Kiểm kê thực tế trước khi triển khai Apache Knox Gateway demo v1. Ghi nhận lúc 2026-10-09 15:23 UTC (22:23, Asia/Ho_Chi_Minh). Các kết luận Knox được đánh dấu riêng vì stack hiện tại chưa có dịch vụ Knox.

## Git và dữ liệu repo

- Remote `origin`: `https://github.com/quocan9999/BigData_Apache_Knox_Gateway_Presentations`.
- Branch hiện tại: `feat/demo-ver-1-knox-gateway`, tại SHA `f132593b6220333c32398294486485958d6e6846`; working tree sạch tại thời điểm bắt đầu audit (trước khi thêm tài liệu baseline này).
- Local và remote `origin/feat/demo-ver-1-knox-gateway` cùng ở SHA `f132593`. Branch có một commit mà `origin/main` chưa có (`git rev-list --left-right --count origin/main...HEAD` trả `0 1`); `origin/main` và local `main` ở `43e3a80`. Branch tài liệu `origin/docs/handoff-context-20261009` vẫn ở `b7a4e04`.
- Branch feature đã tồn tại và an toàn để tiếp tục; không checkout, tạo lại branch, reset, clean, stash hoặc sửa dữ liệu HDFS trong Phase 00.
- Repo đang track `demo/docker-compose.yml`, `demo/hadoop/core-site.xml`, `demo/hadoop/hdfs-site.xml` cùng tài liệu handoff/spec. Root `README.md` rỗng; `docs/README.md` có nội dung ngắn. Chưa có `.gitignore`, `demo/README.md` hoặc `demo/.gitignore`.
- Trong `demo/` hiện chỉ có Compose Hadoop với `namenode`, `datanode` và hai file cấu hình Hadoop. Chưa có Knox, LDAP, topology, script seed, runbook hoặc test demo. Không thấy `.env` hay file credential trong các file được track.

## Docker và HDFS hiện tại

Các lệnh dưới đây chạy tại `demo/`; mọi lệnh kiểm tra đều trả exit code `0`:

| Kiểm tra | Kết quả quan sát |
|---|---|
| `docker version --format 'Client={{.Client.Version}} Server={{.Server.Version}}'` | Client/Server `29.6.2` |
| `docker compose version` | Docker Compose `v5.3.1` |
| `docker compose config --quiet` | Compose config hợp lệ |
| `docker compose ps -a` | NameNode và DataNode đều `Up 7 hours`, image `apache/hadoop:3.4.3`; NameNode publish `127.0.0.1:9870->9870/tcp` |
| `docker image inspect apache/hadoop:3.4.3 --format '{{.RepoTags}} {{.Id}}'` | Image ID `sha256:127774dadab40ce84df7ac668a7a8c99945688b3fe336f1388f4477ca33e1529` |
| `docker volume ls --format '{{.Name}}'` (lọc `*hdfs*`) | `apache-knox-bigdata-demo_hdfs_namenode`, `apache-knox-bigdata-demo_hdfs_datanode` |
| `docker compose exec -T namenode hdfs dfsadmin -report` | `Live datanodes (1)`, không có block thiếu/corrupt |
| `docker compose exec -T namenode hdfs dfs -ls /demo` | `Found 2 items`: `/demo/apache-knox.txt`, `/demo/bigdata.txt` |
| `curl.exe -sS -w "\nHTTP_STATUS=%{http_code}\n" "http://localhost:9870/webhdfs/v1/demo?op=LISTSTATUS&user.name=hadoop"` | HTTP `200`; JSON WebHDFS thật có `pathSuffix` đúng hai file trên |

`docker compose logs --tail=40 namenode datanode` cho thấy DataNode đăng ký thành công với NameNode; không thấy crash trong phần log đã kiểm tra. Có một cảnh báo DataNode cho biết `dfs.datanode.directoryscan.throttle.limit.ms.per.sec` vượt 1000 và Hadoop dùng giá trị mặc định; hiện không ngăn HDFS hoạt động.

## Trạng thái xác minh và lưu ý

- **ĐÃ XÁC NHẬN:** Docker Compose chạy được; NameNode/DataNode sống; một DataNode đăng ký; hai named volume đang được dùng; HDFS chứa hai file seed; WebHDFS trả `200` cùng JSON liệt kê hai file thật.
- **CHƯA KIỂM CHỨNG:** Knox, LDAP, topology, HTTPS, xác thực, AclsAuthz, audit và routing qua Knox. Compose hiện không định nghĩa Knox/LDAP.
- Cổng NameNode `9870` vẫn publish trên loopback để kiểm tra backend trong Phase 01. Chưa đóng cổng ở Phase 00; việc cô lập backend thuộc Phase 04.
- `dfs.permissions.enabled=false`; HDFS này là lab, không phải cấu hình bảo mật production. Giữ nguyên named volumes; tuyệt đối không dùng `docker compose down -v` trong các phase sau.

