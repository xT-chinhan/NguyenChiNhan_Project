# CPU: đo1 và4 phiên

Cả hai lượt có30s warmup+300s đo, model thật qua REST/WS, JPEG640×480 quality75 từ public Ada video đã thêm viền đen. Không thay model, policy hay TTL1000ms.

| Số đo |1 phiên |4 phiên |
|---|---|---|
| Requests | 917 | 4583 |
| Kết quả xử lý | 917 | 956 |
| WORKER_BUSY rejects | 0 | 3627 |
| Tỷ lệ reject | 0.0% | 79.1% |
| Kết quả/giây tổng | 3.06 | 3.19 |
| Client p95 | 494ms | 633ms |
| Client p99 | 647ms | 756ms |
| Event-loop lag p95 | 3.6ms | 4.2ms |
| RSS peak | 893.0MiB | 983.4MiB |
| Stale presentations | 0 | 0 |

**Khuyến nghị:1 người hoạt động tại một thời điểm trên CPU này.**1 phiên đạt mục tiêu độ trễ nguyên mẫu.4 phiên có79.1% request bị từ chối do worker bận; tổng throughput gần bằng1 phiên. Giữ freshness bằng từ chối ảnh thay vì xếp hàng cũ hoạt động đúng, nhưng cập nhật không đủ đều để khẳng định dẫn đường4 người. Không tăng workers vì session RAM/worker ownership chưa hỗ trợ nhiều tiến trình.

p95/p99 chỉ mô tả ảnh được xử lý; bảng giữ cả reject để tránh hiểu sai.4-session status MEASURED_CAPACITY không phải PASS4-user navigation; server_queue_concurrency_invariants còn null trong report tải và được kiểm riêng bằng deterministic tests. Không có OOM/runtime error, frame expired/unresolved hoặc stale delivery được ghi nhận trong hai lượt.

[JSON summary](benchmark-public-cpu-summary.json), [1-session report](benchmark-public-cpu-1/report.md), [4-session JSON](benchmark-public-cpu-4/benchmark-7277c3d6-f514-4bfa-94f7-b8cbb2454f51.json), [source/process/workload receipt](server-benchmark-public.json), [input transform](benchmark-input-public.json).

G3/G4 vẫn BLOCKED_DATA: cần independent reference/dev/test videos và nhãn thủ công. Performance load không cần nhãn để đo latency, nên hai lượt này hoàn thành phần đo tải công khai; không thay thế đánh giá dẫn đúng tuyến. CUDA, điện thoại/mạng thực và TTS chưa kiểm.
