# Handoff bối cảnh Apache Knox Gateway (09/10/2026)

> Tài liệu bàn giao cho Codex CLI, tổng hợp từ cuộc trao đổi với chủ dự án, kết quả terminal/ảnh/log do người dùng cung cấp và kiểm tra GitHub. **Không thay thế việc agent tự đọc working tree và chạy test.** Trạng thái dưới đây là trạng thái được báo cáo vào 09/10/2026.

## 1. Bối cảnh và mục tiêu

- Repo: https://github.com/quocan9999/BigData_Apache_Knox_Gateway_Presentations
- Clone local Windows: `E:\Huit_Local\HK7\BigData\BigData_Apache_Knox_Gateway_Presentations`.
- Nhóm môn Nhập môn Big Data gồm **Quốc An** và **Sony**. Mục tiêu chung: bài thuyết trình PowerPoint/Canva có demo **Apache Knox Gateway thật**. Dự kiến 12 slide, ~15 phút, chưa phải yêu cầu thời lượng đã được giảng viên xác nhận.
- Knox là application/security gateway / reverse proxy một điểm truy cập cho REST API/UI trong Hadoop ecosystem, **không phải** engine lưu trữ hoặc xử lý Big Data. Không sa đà vào Spark/MapReduce/HDFS.
- Phạm vi kỹ thuật hiện tại: **demo v1**, không dựng Spark, Hive, Ranger, Kerberos, Kubernetes; không tạo slide trong đợt này khi chưa được yêu cầu.

## 2. Outline thuyết trình tham khảo (không phải thành phẩm)

12 mục dự kiến: giới thiệu; bài toán nhiều endpoint Hadoop; Knox là gì; vị trí gateway; Topology/Provider/Service; request flow; authentication/authorization/audit/TLS; ví dụ XML; tích hợp Hadoop; Knox so với Ranger; demo; lợi ích/giới hạn/kết luận. Lịch sử/tác giả/công ty sử dụng không phải trọng tâm; tránh khẳng định không có chứng cứ.

Tài liệu chính thức tham khảo: https://knox.apache.org/ ; https://knox.apache.org/books/knox-2-1-0/user-guide.html ; https://hadoop.apache.org/docs/ .

## 3. Thiết kế demo v1 cần hoàn thiện

```text
Windows/PowerShell curl
    │ HTTPS localhost:8443
    ▼
Apache Knox Gateway — topology, authentication, authorization, proxy, audit
    ├──── Demo LDAP (nội bộ Docker)
    ▼
NameNode WebHDFS :9870 (Docker network backend)
    ▼
HDFS NameNode + DataNode
```

- Docker Desktop Windows + Compose; Hadoop image **`apache/hadoop:3.4.3`**.
- Compose project trong starter: `apache-knox-bigdata-demo`; Hadoop services `namenode`, `datanode`; Docker network `backend`.
- Baseline hiện publish **`127.0.0.1:9870:9870`** ở NameNode chỉ để kiểm thử WebHDFS. Sau khi Knox chạy thành công, phải loại bỏ publish cổng backend để demo client chỉ vào Knox. Đó là **network isolation + cách cấu hình ports**, không phải chức năng Knox tự chặn cổng.
- Knox + demo LDAP + ShiroProvider + AclsAuthz là **kiến trúc dự kiến/chưa kiểm chứng trên máy người dùng**. Một gói cấu hình overlay được soạn trong chat trước đó (tên gợi ý `docker-compose.knox.yml`, `knox/topologies/demo.xml`) nhưng **chưa có bằng chứng đã được copy vào repo, đã chạy, hoặc là cấu hình hợp lệ**. Kiểm tra image/tag Knox, entrypoint, đường dẫn mount, LDAP users, URL routing, semantics 401/403 theo tài liệu và kiểm thử thật; có thể sửa thiết kế và ghi lý do.
- Không dùng WebHDFS mock. Không thêm Ranger vào demo v1. Knox AclsAuthz và backend policy không được đánh đồng.

## 4. Sự kiện đã được người dùng kiểm chứng

### 4.1 Git/repo

Tại thời điểm GitHub được kiểm tra, nhánh mặc định `main`, root remote chỉ có `README.md` (rỗng) và `docs/README.md`. Thư mục `demo/` đã chạy trên **local repo**, **chưa thấy trên remote main**. Prompt local đang ở nhánh `main` và có thay đổi/chưa theo dõi (`+1 ... !`). Agent phải inspect `git status` và bảo vệ các file local, không reset/clean/stash/drop bừa bãi.

Trước đây có 8 GitHub Issues (Quốc An và Sony), được chia **trước khi chốt demo**; không mặc định chính xác, không tự đóng/chỉnh.

### 4.2 Cấu hình Hadoop starter đã cung cấp trước đó

```text
demo/
  docker-compose.yml
  hadoop/
    core-site.xml
    hdfs-site.xml
```

Thông số: `fs.defaultFS=hdfs://namenode:8020`; `dfs.webhdfs.enabled=true`; `dfs.replication=1`; `dfs.permissions.enabled=false` (lab **không phải production security**). Docker **named volumes** `hdfs_namenode:/data/name`, `hdfs_datanode:/data/data`.

Ban đầu `docker compose up -d` báo `Started` nhưng `docker compose ps` trống; `ps -a` thấy `Exited (1)`. Log:
- NameNode: `java.io.IOException: Cannot create directory /data/name/current/current`.
- DataNode: `EPERM: Operation not permitted` khi chmod, `Too many failed volumes` ở `/data/data`.
- Đã khắc phục quyền sở hữu volume bằng chạy container root tạm thời: `chown -R hadoop /data/name && chmod -R u+rwX /data/name` và tương tự `/data/data`, sau `docker compose down` **không dùng `-v`**.
- Sau sửa: cả NameNode/DataNode `Up 3 minutes`, `hdfs dfsadmin -report` cho `Live datanodes (1)`. Agent nên tự động hóa bootstrap/permissions an toàn, idempotent, không xóa HDFS khi restart.

### 4.3 Baseline chạy THÀNH CÔNG

Người dùng đã chạy thật:
- `docker compose exec namenode hdfs dfs -mkdir -p /demo`.
- `hdfs dfs -touchz /demo/apache-knox.txt` và `/demo/bigdata.txt`.
- `hdfs dfs -ls /demo`: **Found 2 items**, hai file trên, owner `hadoop`, file rỗng.
- `curl.exe -i "http://localhost:9870/webhdfs/v1/demo?op=LISTSTATUS&user.name=hadoop"`: **HTTP/1.1 200 OK** + JSON `FileStatuses.FileStatus` chứa `pathSuffix`: `apache-knox.txt` và `bigdata.txt`.
- NameNode UI `http://localhost:9870`: `namenode:8020 (active)`, 1 live node, 0 dead nodes, `Security is off`.
**Kết luận chính xác:** Hadoop HDFS + WebHDFS backend thật đã chạy; **chưa có kết quả chứng minh Knox/LDAP hoạt động**.

## 5. Kịch bản demo đã thống nhất: **5 màn** A–E

| Màn | Hành vi | Bằng chứng bắt buộc |
|---|---|---|
| A | Từ Windows gọi thẳng `http://localhost:9870` sau khi đóng port backend | Connection refused/failed; `docker compose ps` cho thấy không publish 9870; vẫn đi được qua Knox. Cơ chế là network isolation/port mapping |
| B | Sai mật khẩu qua Knox | Lỗi xác thực từ **Knox** (mục tiêu 401), có log/response chứng minh |
| C | LDAP đúng nhưng Knox ACL chặn WEBHDFS | **Knox AclsAuthz** chặn trước backend; kỳ vọng 403 nhưng **không khẳng định mã khi chưa đo được**; xác minh vị trí denial |
| D | User có quyền gọi Knox → WebHDFS thật | Thành công + JSON liệt kê **hai file HDFS thật**, không fake hoặc hardcode |
| E | Xem Knox audit | Bằng chứng log audit thực với user/action/resource/outcome theo field hiện hữu, không output dựng |

Các account `admin`, `guest`, các password kiểu `admin-password` hay `guest-password` trong hội thoại trước **chỉ là ví dụ**, chưa được xác thực thực sự tồn tại trong LDAP. Phải thiết lập fixtures nhất quán, ghi nhãn **demo-only**. Không commit credentials thực hoặc private key production.

## 6. Rủi ro và tiêu chí chất lượng

- HTTP 401/403 có thể phụ thuộc Knox version/configuration; service backend cũng có thể tự từ chối. Không suy từ status code rằng Knox chắc chắn chặn: xem log, test đối chứng hoặc evidence tương đương.
- HDFS đang `dfs.permissions.enabled=false`; Knox bảo vệ **cửa vào** chứ không đồng nghĩa bảo mật toàn diện HDFS. Các client trong Docker network có thể bypass gateway nếu thiết kế network không ngăn.
- Nếu Knox tự ký TLS, `curl -k` chỉ chấp nhận trong demo local; cảnh báo rõ không dành cho production.
- Test phải bắt lỗi thật (sai mật khẩu, user đúng nhưng không quyền, backend down, JSON đúng đường đi, no exposure), không viết test superficial chỉ để pass, không fake 200. Thêm startup readiness, seed HDFS idempotent, hỗ trợ PowerShell Windows (`curl.exe`), kiểm tra restart và tài nguyên Docker.
- Không push logs, volumes, artifacts, private keys, secrets, `.env` cá nhân, cache; chỉ giữ sample data/generator phù hợp. Có thể quay video/ảnh **thật** làm fallback có nhãn.

## 7. Workflow Codex CLI bắt buộc

1. **KHÔNG implement trên `main`**. Trước tiên kiểm tra `pwd`, `git status --short --branch`, `git remote -v`, `git branch -a`, files `demo/`, `docker compose config`, `docker compose ps -a`. Không phá thay đổi uncommitted của người dùng. Dùng feature branch từ base hợp lệ.
2. Sau mỗi phase: tự **commit và push** lên cùng remote feature branch, handoff ngắn gọn gồm files, decisions, runtime evidence, test commands/results, commit SHA, blockers, next phase.
3. Chỉ khi người dùng yêu cầu rõ mới **tạo PR lên `main`**. Sau đó ChatGPT đóng vai reviewer, đăng comment inline findings. Người code **không tự resolve review conversations**; reviewer kiểm chứng và resolve.
4. Bộ tài liệu phase **sẽ được viết ở bước kế tiếp**, chưa có trong handoff này: `docs/demo-ver-1/spec/MASTER-SPEC.md`, các phase spec riêng; `docs/demo-ver-1/handoff/` chứa handoff hoàn thành sau mỗi phase. Agent đọc master rồi **chỉ** spec của phase hiện tại, không nạp hết; khi context compact đọc lại master + handoffs liên quan.
5. Conventional commit **tiếng Việt**, cách header và body đúng **một dòng trống**; body là một hoặc nhiều bullet `- `, **không có dòng trống giữa các bullet**. Ví dụ:

```text
feat(demo): tích hợp Knox Gateway với WebHDFS

- Cấu hình topology và reverse proxy kết nối HDFS
- Bổ sung xác thực và kiểm thử các trường hợp truy cập
- Ghi lại lệnh chạy và bằng chứng kết quả demo
```

6. Chỉ đánh dấu hoàn thành phase khi chứng cứ test đáng tin cậy; nếu Docker không thể chạy trong môi trường Codex, ghi **CHƯA KIỂM CHỨNG**, không dựng output tưởng tượng.

## 8. Cách đọc handoff và bước kế tiếp

- Handoff này chứa **thông tin lịch sử**, không phải nguồn ưu tiên cao hơn actual code. Nếu test mới mâu thuẫn, tin source thực + official docs + log, và giải thích thay đổi.
- Phân biệt **ĐÃ XÁC NHẬN** (HDFS/WebHDFS 200), **ĐÃ ĐỀ XUẤT** (Knox/LDAP/AclsAuthz, 5 màn) và **CHƯA KIỂM CHỨNG** (Knox Docker, HTTP 403, audit, idempotency, portability).
- Không tự động xem file handoff này đã tồn tại ở local chỉ vì được push trên nhánh tài liệu GitHub; người dùng/agent cần fetch/checkout hoặc cherry-pick đúng nhánh.
- **Bước tiếp theo sau khi bàn giao context:** soạn master spec và phase specs trong `docs/demo-ver-1/spec/`, chuẩn bị cơ chế phase handoff `docs/demo-ver-1/handoff/`; **chưa implement demo, chưa tạo PR, chưa viết prompt `/goal` trong bước hiện tại**. Prompt `/goal` về sau phải **< 3999 ký tự**.
