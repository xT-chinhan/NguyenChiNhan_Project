# CPU benchmark —1 session

Lượt đo dùng video public ghi sẵn,30s warmup+300s đo; query đã pad640×480 và re-encode JPEG quality75. Mục đích là hiệu năng, không chấm dẫn đúng tuyến.

| Số đo | Kết quả |
|---|---|
| Requests / results | 917 / 917 |
| Kết quả mỗi giây | 3.06 |
| Client p50/p95/p99 | 262.4 / 493.9 / 647.2ms |
| Server request→result p95 | 493.7ms |
| Event loop lag p95 | 3.6ms |
| HTTP health RTT p95 | 9.9ms |
| Rejected / expired / unresolved | 0 / 0 / 0 |
| Stale presentations / stale results | 0 / 0 |
| RSS peak | 893.0MiB |
| Performance decision | PASS |

Các mục tiêu nguyên mẫu1 phiên đều đạt cho workload/máy này. Không suy ra server chịu được5fps ổn định hoặc mạng điện thoại sẽ có cùng độ trễ. G3/G4 vẫn BLOCKED_DATA vì chưa có independent reference/query pilot và human ground truth.

[JSON đầy đủ](benchmark-333aea9f-4262-4e89-a404-2ffca826b356.json), [lệnh/exit code](invocation.json), [public input transform](../benchmark-input-public.json), [server/process/workload receipt](../server-benchmark-public.json).

Không thay TTL1000ms hay model để làm pass. Một worker model thật, CPU profile; VRAM null vì không đo GPU. Source snapshot: `e3f00d6f727378bfd8cbade748418f78813d917190a78042af900d73e877786c`.
