# MASTER SPEC — Apache Knox Gateway Demo v1

**Phiên bản đặc tả:** v1.0 (09/10/2026). **Ngôn ngữ thực hiện/tài liệu:** tiếng Việt (giữ nguyên thuật ngữ API/Git/Docker). **Trạng thái:** chỉ là kế hoạch, chưa xác nhận Knox chạy.

## 1. Mục tiêu và ranh giới

Xây dựng demo **thật, có thể chạy lại được** trên Windows + Docker Desktop để minh hoạ Apache Knox Gateway đứng trước HDFS/WebHDFS. Đảm bảo nhóm Quốc An/Sony có thể thuyết trình 3–5 phút, đối chiếu trước/sau Knox và giải thích authentication, authorization, proxy, audit.

**Bắt buộc:** Hadoop HDFS thật, Knox Gateway thật, LDAP demo hoặc cơ chế xác thực Knox có giải thích rõ, Knox AclsAuthz, request/response từ WebHDFS thật, lệnh/test PowerShell, tài liệu vận hành, lỗi được báo chính xác.

**Không thuộc demo v1:** Ranger, Kerberos, Spark, Hive, Kubernetes, đa-node production, PR tự động, slide PowerPoint/Canva. Không giả lập Knox, không mock REST/WebHDFS, không screenshot/log/200 giả.

**Nguồn bối cảnh:** `docs/handoff/00-bang-giao-boi-canh-du-an.md`. Khi bối cảnh cũ khác source hoặc log mới, lấy thực tế làm chuẩn và ghi lại.

## 2. Kiến trúc đích

```text
Windows host
  curl.exe → HTTPS 127.0.0.1:8443
                 │
           Knox Gateway ─── Demo LDAP
            authn + AclsAuthz + topology + audit
                 │ private Docker network
        NameNode :9870 / WebHDFS
                 │
             DataNode / HDFS
```

- Image Hadoop baseline: `apache/hadoop:3.4.3`. Phiên bản Knox phải được xác thực image/tag, đường dẫn và compatibility qua tài liệu chính thức + log runtime; pin phiên bản/digest theo cách tái tạo được, không dùng `latest` mơ hồ.
- Backend `namenode:9870` không được publish ra host trong **trạng thái demo cuối**. Tạm publish chỉ khi xác minh Phase 01; loại bỏ ở Phase 04.
- HDFS lab hiện `dfs.permissions.enabled=false`; nói rõ Knox không thay thế security backend, đây không phải triển khai production. `curl -k`/self-signed cert chỉ dùng local lab.
- Kiểm thử phải phân biệt lỗi Knox gây ra với lỗi từ WebHDFS/LDAP/network.

## 3. Giao thức tải context tiết kiệm

**Đầu mỗi phiên Codex hoặc sau compact:**
1. Đọc **chỉ** file Master này; đọc lại `docs/handoff/00-bang-giao-boi-canh-du-an.md` nếu mất bối cảnh lịch sử.
2. Xem `git status --short --branch`, `git log -n 8 --oneline`, trạng thái branch, thư mục `docs/demo-ver-1/handoff/`. Đối chiếu Docker nếu cần.
3. Đọc handoff **phase gần nhất đã hoàn thành** (và các handoff sớm hơn chỉ khi có dependency chưa rõ); handoff là lịch sử chứ không thay thế test thực.
4. Chọn **một** phase chưa hoàn thành theo bảng ở mục 4 và **chỉ đọc spec phase đó**. Không đọc trước toàn bộ phase specs. Chỉ đi tiếp khi gate hiện tại PASS.
5. Nếu gặp blocker, tạo handoff trạng thái **BLOCKED**, kèm log và hướng xử lý; **không** đánh dấu hoàn thành hoặc tự chuyển phase.

## 4. Phase và cổng kiểm duyệt

| Phase | File spec (đọc khi đến lượt) | Cổng hoàn thành |
|---|---|---|
| 00 | `phase-00-audit-va-khoi-tao.md` | Nhánh feature an toàn; audit dữ liệu local/remote và Docker; không mất dữ liệu |
| 01 | `phase-01-hdfs-on-dinh.md` | 1 live DataNode, seed idempotent, WebHDFS 200 + JSON thật, restart không mất dữ liệu |
| 02 | `phase-02-knox-ldap.md` | Knox/LDAP Up, HTTPS có phản hồi đúng, authn thật và route tới WebHDFS |
| 03 | `phase-03-phan-quyen.md` | Admin được truy cập, user không quyền bị Knox ACL chặn; có bằng chứng origin denial |
| 04 | `phase-04-co-lap-backend.md` | Host không gọi trực tiếp 9870, gateway vẫn trả WebHDFS, không publish backend |
| 05 | `phase-05-kiem-thu-va-audit.md` | Các ca A–E, negative/regression/restart test và audit log thật, fail đúng khi lỗi |
| 06 | `phase-06-dong-goi-va-bao-cao.md` | Clone/runbook/script demo/cleanup/đối chứng, tổng kiểm thử thật có bằng chứng |

**Điểm cần xác minh:** Màn C nhắm tới HTTP `403` vì trình bày authorization; **không hardcode kết quả dự đoán**. Nếu Knox thực trả `401` hoặc mã khác, điều tra theo phiên bản/API, chứng minh nguồn gốc denial và ghi blocker/đề xuất điều chỉnh cho chủ dự án; không im lặng đổi chuẩn nghiệm thu.

## 5. Cách làm việc với Git — không được bỏ qua

- **Tuyệt đối không phát triển trên `main`**. Nhánh kế hoạch hiện có: `origin/docs/handoff-context-20261009`, chứa handoff lịch sử + specs. Khuyến nghị tạo **một** feature branch `feat/demo-ver-1-knox-gateway` từ nhánh kế hoạch này (để một PR về `main` sau khi người dùng yêu cầu). Nếu đã có branch feature đúng thì tiếp tục tại đó, không đè lịch sử.
- Local `main` đã từng có file `demo/` chưa commit/chưa push. **Trước khi checkout/switch**, kiểm tra `git status`, `git diff`, file untracked, tồn tại file trùng; giữ nguyên thay đổi người dùng. Nếu chuyển nhánh sẽ ghi đè, dừng hỏi hoặc tạo bản sao an toàn theo đường dẫn do người dùng chọn. Không tự ý `reset --hard`, `clean -fd`, `stash -u` hay `down -v`.
- **Mỗi phase là một tập commit tách biệt:** commit implementation/test cho phase trước; ghi commit SHA thực vào handoff phase; sau đó commit file handoff riêng. Push cả hai lên `origin` feature branch. Phase 00 cũng phải có commit kiểm kê/tài liệu thực và commit handoff. Không tự PR/merge/rebase/force push.
- Commit message chuẩn **Conventional Commits tiếng Việt**; header + **một dòng trống** + bullet body; tuyệt đối **không có dòng trống giữa các bullet**. Số bullet linh hoạt. Ví dụ:

```text
feat(demo): bổ sung cấu hình Knox Gateway cho WebHDFS

- Khai báo topology và tuyến đường tới NameNode
- Cấu hình LDAP mẫu và kiểm tra xác thực HTTP
- Bổ sung kiểm thử kết nối gateway với dữ liệu HDFS
```

- Handoff commit cũng tuân thủ định dạng, ví dụ `docs(handoff): bàn giao kết quả phase 02` kèm bullet body liên tiếp.
- Agent **chỉ tạo PR khi người dùng ra lệnh mới**, dù đã xong mọi phase; khi có PR, reviewer xử lý conversations. **Coder không tự resolve review conversations** dù đã sửa.

## 6. Quy định evidence và kiểm thử không hời hợt

- Không chấp nhận `docker compose up -d` như bằng chứng duy nhất; kiểm tra `ps -a`, readiness, service log và HTTP response body; xác minh 2 file là dữ liệu thật từ HDFS chứ không phải constant.
- Happy path/negative path bắt buộc, kiểm tra cả lỗi password, user bị ACL chặn tại Knox, backend down, endpoint không exposed, restart không mất HDFS, audit có sự kiện liên quan. Test script phải trả exit code khác 0 khi điều kiện không đúng, không `try/catch` nuốt lỗi.
- Test có thể dùng helper hoặc fake ở **unit tests** cho logic thuần túy nhưng bằng chứng E2E bắt buộc chạy stack thật; mock mode phải gắn nhãn rõ và không được dùng làm chứng nhận PASS.
- Trích tối thiểu mỗi gate: command, exit/status, output chính hoặc log excerpt, timestamp/timezone, môi trường/version, đường dẫn artifact/evidence nếu có. Không commit secrets, private key cá nhân, Docker volumes, logs khổng lồ, file rác.
- Nếu môi trường agent thiếu Docker/quyền mạng thì chạy static checks có thật, phân loại **CHƯA KIỂM CHỨNG E2E**; không tự nhận gate đã PASS. Dừng chuyển phase cho đến khi có runtime evidence hoặc được chủ dự án quyết định bằng văn bản.

## 7. Handoff mỗi phase và quy tắc chuyển phase

Tạo `docs/demo-ver-1/handoff/phase-XX-handoff.md` theo `docs/demo-ver-1/handoff/HANDOFF-TEMPLATE.md`. **Chỉ phase handoff có nội dung evidence thật và trạng thái DONE mới mở khoá phase sau.** Nếu BLOCKED, mô tả blocker và hướng kiểm tra; nếu mất context, đọc Master + latest handoff.

Hai commit mỗi phase: (1) code/spec/test thực hiện (ghi SHA vào handoff), (2) handoff; push. File handoff **không thể tự chứa SHA của chính commit handoff**; có thể chỉ lưu SHA commit implementation và lệnh xác định commit handoff bằng `git log`.

Chốt phase 06 rồi **dừng, báo cáo**. Chỉ sau lệnh người dùng mới tạo PR từ feature branch sang `main`; không tự resolve review conversations.

## 8. Tài liệu tham khảo và lưu ý

- Apache Knox chính thức: https://knox.apache.org/ và Knox User Guide: https://knox.apache.org/books/knox-2-1-0/user-guide.html
- Hadoop: https://hadoop.apache.org/docs/
- Lịch sử môi trường thực tế: `docs/handoff/00-bang-giao-boi-canh-du-an.md`.
- Những con số 401/403/200 và đường dẫn log minh họa từ kế hoạch cũ không được coi là sự thật nếu không tái kiểm tra.
