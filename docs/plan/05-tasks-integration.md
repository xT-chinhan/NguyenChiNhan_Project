# 05 — Công việc T07–T13

Điều kiện nền: hoàn thành T00–T06 hoặc báo rõ phần model thật đang bị thiếu.
Các path dưới đây tương đối `backend/`, trừ `docs/...` tính từ thư mục gốc dự án.

## T07 — Localization và state machine tuyến

**Phụ thuộc:** T01, T05. **Gate:** navigation portion của G1.

### File

- `core/localization.py`, `core/navigation.py`.
- `tests/unit/test_localization.py`, `test_navigation.py`.

### Các bước

1. Implement cosine và median top-2 reference đúng 03; assert dimensions/fingerprint từ snapshot.
2. Score tất cả checkpoint, kiểm top1 margin, heading circular và allowed_seqs.
3. Tạo immutable NavigationState; advance trả proposal, chưa mutate runtime.
4. Xác nhận 3 frame trong window, chống timestamp/request/pixel trùng.
5. Mapping checkpoint `depart_action` phải giữ đúng nghĩa: chỉ nói rẽ khi đã match chỗ rẽ.
6. State machine đủ initial localization, navigating, lost, pause/resume, completed/stopped.
7. Resume chỉ match last hoặc next; không chọn một điểm giống hình ở cuối tuyến để nhảy tới đích.
8. Timer lost/initial timeout lấy Clock được tiêm, không sleep thật 15 giây trong unit test.
9. Arrival chỉ là proposal cho tới khi T08 cho phép commit; obstacle có thể chặn arrival.
10. Không gọi GPT hoặc dịch vụ bên ngoài trong module.

### Kiểm tra

```bash
uv run --project backend --extra cpu --group dev pytest backend/tests/unit/test_localization.py backend/tests/unit/test_navigation.py -q
```

Pass tối thiểu:
- Sequence fixture 0→1→2→3 cho đúng CONTINUE/TURN_LEFT/TURN_RIGHT/ARRIVED.
- Một hit không advance, ba frame cùng pixels không advance.
- Top1 ngoài allowed, margin thấp, heading ngược, reference mismatch không advance.
- Pause rồi resume không reset về checkpoint0; resume không nhảy quá một checkpoint.
- Wrong corridor đủ 15s → lost, không tự khuyên đi lùi hoặc tiếp tục.
- Không có lệnh rẽ trước frame xác nhận thứ ba hoặc sau completed.

## T08 — Decision và tiếng Việt

**Phụ thuộc:** T06, T07. **Gate:** hoàn tất thuật toán G1.

### File

- `core/decisions.py`, `core/messages.py`.
- `tests/unit/test_decisions.py`, `test_messages.py`.

### Các bước

1. Implement đúng thứ tự ưu tiên 03; không concatenate nhiều câu cạnh tranh trong một frame.
2. Kết quả có `next_navigation_state`, instruction nullable, hold_reason, observation summary.
3. Khi hold, không commit proposal chuyển chặng; clear candidate để xác nhận lại khi hết hold.
4. Phân biệt cooldown tiếng nói với hold decision: bị cooldown không được trở thành cho phép đi.
5. Code→text_vi từ bảng cố định, không nhét distance nếu v1 chưa hỗ trợ câu đó.
6. Instruction ID UUID mới chỉ khi có sự kiện thật; heartbeat/frame không sinh UUID hướng dẫn giả.
7. Dedupe theo checkpoint transition hoặc obstacle key, có TTL; không lưu vô hạn.
8. ARRIVED bị emergency/warning cùng frame chặn; khi xác nhận lại mới được complete.
9. repeat chỉ trả instruction chưa hết hạn, không đổi state hoặc kéo dài TTL cũ.
10. Pending departure/ACK và fresh revalidation theo03: không làm mất câu rẽ vì TTL hết khi gửi chậm;
    test ACK received khác presented và ACK ID cũ không mở khóa bước tiếp.

### Kiểm tra

```bash
uv run --project backend --extra cpu --group dev pytest backend/tests/unit/test_decisions.py backend/tests/unit/test_messages.py -q
```

Pass: warning/emergency luôn thắng guidance; RGB không nói mét; missing depth không phát đi tiếp;
repeat stale chỉ WAIT_FOR_FRESH_FRAME; tăng nguy hiểm vượt cooldown; không có PATH_CLEAR.

## T09 — Session REST và stream có deadline

**Phụ thuộc:** T03, T08. **Gate:** giao thức runtime trong G4, chưa đủ G4 nếu thiếu G3.

### File

- `runtime/sessions.py`, `runtime/coordinator.py`, hoàn thiện `runtime/worker.py`.
- `api/sessions.py`, `api/stream.py`, nối router/lifespan trong `app.py`.
- `tests/integration/test_sessions.py`, `test_stream.py`, `test_freshness.py`, `test_isolation.py`.

### Tạo và sở hữu phiên

1. Admission lock chung bảo vệ session registry và admin catalog mutation.
2. POST session xác thực device, kiểm active count/capacity và route published/fingerprint.
3. Snapshot route từ DB bằng threadpool, rồi gắn vào RuntimeSession riêng.
4. RuntimeSession chứa tracker, navigation, sensor, candidate, cooldown, epoch, WS reference và clock.
5. Chỉ model/policy immutable và pool DB được dùng chung; không dùng chung tracker/last_instruction.
6. GET/DELETE kiểm ownership trước trả snapshot; DELETE terminal idempotent đến khi tombstone hết TTL.
7. Giữ tombstone terminal tối đa 5 phút để retry DELETE/GET có kết quả nhất quán rồi dọn.
8. Restart không restore phiên; instance mới không đọc state từ report/log.

### Stream

1. Auth/ownership trước accept; client thứ hai cùng session bị reject.
2. Connect active → welcome/capture_request; connect paused → welcome rồi đợi resume.
3. Cấp seq tăng và random frame_token; ghi issued_at monotonic server.
4. Một capture_request chỉ nhận một frame. Token hợp lệ bị consume ngay khi nhận;
   ảnh lỗi thì reject và cấp yêu cầu mới nếu phiên vẫn active, không tái sử dụng token cũ.
5. Kiểm size/schema/token/time/camera profile; decode ngoài event loop.
6. Chờ worker slot<=100ms. Nếu bận: reject WORKER_BUSY, reset candidate, không tạo queue ảnh.
7. Job có token+epoch+request deadline; worker trả observation, không được đụng session state.
8. Coordinator chỉ tạo/commit proposal sau khi đã khóa phiên và recheck age/epoch/state/token.
9. Kết quả quá hạn: không cập nhật tracker/progress/dedupe/last_instruction từ kết quả đó.
10. Vì tracker mutable, xử lý core trên bản state candidate riêng; chỉ swap vào session khi commit hợp lệ.
    Không deep-copy weights/ảnh lớn. Dùng clone dataclass/dict state nhỏ.
11. Watchdog 100ms xử lý expiry dù model thread vẫn bận; bump epoch, pause và xóa pending movement.
12. Không cancel giả rồi mở slot mới: slot chỉ release khi callable inference thật đã return.
13. Outbound một sender task, queue8; không gọi send_json đồng thời từ watchdog/worker/control.
14. Send timeout250ms hoặc queue đầy → pause; cố gửi status, không được thì close1013 và cleanup.
15. Heartbeat2s chỉ phản ánh state; không thay capture/request deadline.
16. Mỗi 10s kiểm device revoked/expired; pause/close1008 nếu mất quyền.
17. Control pause/stop được xử lý ngay cả khi inference bận; late model result bị epoch guard loại.
18. Lỗi/model không được chặn event loop khiến heartbeat/watchdog không chạy.

### Lost, idle và cleanup

- `lost` không advance tự động; nhận control resume mới định vị lại.
- Khi lost gửi observation dùng fresh frame nếu client tiếp tục, nhưng không phát chuyển hướng.
- Paused không cấp capture mới; resume bắt đầu request mới, clear tracker/histories/candidate.
- 5 phút idle hoặc 30 phút total → stopped; hủy sender/watchdog và xóa tensors/session references.
- Disconnect tạm dừng và tăng epoch, không tự tạo phiên khác hoặc tự phát lại câu rẽ.
- Global worker job >10s: đánh readiness not_ready và pause mọi phiên; không tự spawn worker mới.
  Job return thì slot được giải phóng, nhưng operator phải restart để xóa fault sticky.

### Kiểm tra

```bash
uv run --project backend --extra cpu --group dev --env-file backend/config/.env pytest backend/tests/integration/test_sessions.py backend/tests/integration/test_stream.py backend/tests/integration/test_freshness.py backend/tests/integration/test_isolation.py -q
```

Pass: wrong token/owner, duplicated/future seq, old token, slow inference, pause during inference,
disconnect/reconnect, revoke, TTL, capacity, không hai WS và không hai thật model job/session.
Test ở age999ms vẫn có thể commit; age1000ms không commit. Clock kiểm tra trước cả mutation.
Thread bị block bằng Event: timeout không làm global simultaneous jobs vượt1.
Hai device chạy khác tuyến cùng lúc không chia sẻ candidate, track IDs/cooldown hoặc instruction.

## T10 — Import tuyến, replay và evaluator

**Phụ thuộc:** T05, T09. **Gate:** G3/G4 nếu có dữ liệu thật đủ.

### File

- `cli/route_import.py`, `cli/replay.py`, `cli/evaluate.py`.
- `tests/unit/test_route_bundle.py`, `test_evaluator.py`.
- `tests/integration/test_replay_client.py`.
- `tests/fixtures/real/README.md`, không giả dữ liệu video đã có.

### Importer

1. Bundle JSON theo format 06; chỉ đọc ảnh dưới bundle root, reject symlink/path thoát root.
2. Client importer gọi admin REST để tạo map/places/route/checkpoints/publish.
3. Không ghi trực tiếp DB để bỏ qua validator. Không dùng server endpoint nhận arbitrary filesystem path.
4. Token lấy env `NAV_ADMIN_TOKEN`, URL lấy `NAV_API_URL`; không token trong args/log/bundle.
5. Nếu lỗi giữa chừng, để draft hợp lệ với receipt ID; không cố publish route thiếu checkpoint.
6. Import là explicit action, không tự tìm video/ảnh trong home directory.

### Prepare-video và replay

1. `prepare-video --input <file> --output-dir <dir>` dùng ffprobe/ffmpeg subprocess argv, shell=False.
2. ffmpeg áp rotation metadata, bỏ audio, xuất JPEG upright 5fps, fit tối đa640×480 giữ aspect ratio.
3. Ghi frames.jsonl: sample_index, pts_ms, relative_path, pixel_sha256; ghi hash video gốc.
4. Không tự sửa file gốc; output-dir không rỗng phải fail trừ khi trùng manifest đã xác minh.
5. Replay qua POST session + WS thật. Mỗi capture_request chọn frame tiếp theo theo playback1x;
   nếu xử lý chậm thì bỏ qua frame cũ, không chạy nhanh để xả backlog.
6. Decode tại thời điểm capture request; echo capture_monotonic_ms thật của client.
7. Ghi local seq→video_pts_ms vào trace; không thêm trường pts riêng trái schema WS.
8. Client kiểm hai điều kiện TTL, dedupe instruction IDs, invalidate pending guidance khi nhận warning/status.
   Gửi ACK received khi nhận và presented khi event hợp lệ đã được trình bày ra stdout hoặc TTS.
   Replay không audio phải ghi `presentation_kind=stdout_simulation`, không coi đã kiểm tra tiếng nói.
9. Mặc định không phát tiếng, chỉ in event và ghi trace JSONL để backend test không cần audio.
10. Video hết: stop session và đóng WS; exit0 chỉ có nghĩa kết thúc stream, không tự báo route thành công.

### Evaluator

1. Đọc trace + ground_truth, so code/timewindow/checkpoint/arrival.
2. Separate `logic`, `model`, `network_replay` evidence; không gộp accuracy test giả với video thật.
3. Kiểm split/hash/source_group reference khác query; fail nếu có leakage.
4. Đo false turn, missed turn, early arrival, out-of-route false progress, stale delivery/drop.
5. Report JSON và Markdown theo gate 06; include exact model/policy/data/code/lock hashes.
6. Không đủ video/annotation: exit2 `BLOCKED_DATA`, không tạo report “100% success”.

### Lệnh

```bash
uv run --project backend --extra cpu --env-file backend/config/.env python -m navcore.cli route-import --bundle /absolute/path/to/pilot/bundle.json
uv run --project backend --extra cpu --env-file backend/config/.env python -m navcore.cli prepare-video --input /absolute/path/to/query.mp4 --output-dir backend/output/query-frames
uv run --project backend --extra cpu --env-file backend/config/replay-device.env python -m navcore.cli replay --route-id UUID --frames backend/output/query-frames/frames.jsonl --output backend/output/replay.jsonl
uv run --project backend --extra cpu --env-file backend/config/.env python -m navcore.cli evaluate --trace backend/output/replay.jsonl --ground-truth /absolute/path/to/ground_truth.json --report-dir docs/reports/pilot-rgb
```

Theo mặc định replay/evaluate report không chứa raw ảnh, base64 hoặc token.

## T11 — Failure tests và benchmark

**Phụ thuộc:** T09, T10. **Gate:** độ bền runtime trong G4.

### File

- `cli/benchmark.py`, `tests/integration/test_faults.py`, `test_limits.py`, `test_restart.py`.
- `scripts/check.sh`, `docs/reports/benchmark-<run_id>.json`.

### Các bước

1. Hoàn thành ma trận V01–V30 trong 06-validation, không thay bằng test chỉ assert HTTP200.
2. Benchmark CPU functional trước; CUDA explicit sau khi model/device validate.
3. Hai workload riêng: 1 session và 4 session. 30s warm-up +300s đo, client5fps tối đa theo protocol.
   Chuẩn bị 4 device token khác nhau bằng CLI device-create vào `backend/config/benchmark-devices/`;
   không dùng một device token tạo4 phiên trái giới hạn. CLI benchmark đọc `--device-env-dir`, không in token.
4. Đo request→receive client, request→server result, stage timings, inference slot wait,
   rejected/expired frame, event loop lag, RSS/VRAM peak và dropped instruction.
5. Report p50/p95/p99, số mẫu và cấu hình. Không chỉ báo trung bình/FPS từ inference đơn lẻ.
6. Failure injection ở test adapter/client, không mở production endpoint `simulate_error`.
7. Không đổi REQUEST_DEADLINE_MS để làm benchmark qua. Nếu chậm thì ghi gate performance fail;
   chỉ tối ưu phần có timing chứng minh, chạy lại ca bị ảnh hưởng và benchmark.
8. Không thay encoder/model/input resolution khi chưa tạo fingerprint/reference revision phù hợp.
9. Kiểm log không chứa token/rawframes và không tăng RAM theo số frame đã xử lý.

### Lệnh

```bash
bash backend/scripts/check.sh
uv run --project backend --extra cpu python -m navcore.cli benchmark --device-env-dir backend/config/benchmark-devices --route-id UUID --frames-jsonl /absolute/path/frames.jsonl --model-dir backend/models --sessions 1 --warmup-seconds 30 --duration-seconds 300 --server-receipt /absolute/path/server-receipt.json --report-dir docs/reports
uv run --project backend --extra cpu python -m navcore.cli benchmark --device-env-dir backend/config/benchmark-devices --route-id UUID --frames-jsonl /absolute/path/frames.jsonl --model-dir backend/models --sessions 4 --warmup-seconds 30 --duration-seconds 300 --server-receipt /absolute/path/server-receipt.json --report-dir docs/reports
```

Benchmark thật cần data/model; synthetic load chỉ chứng minh scheduling/isolation và phải ghi adapter_kind.
4 session không có throughput cam kết; nếu overload thì phải giữ freshness bằng reject/hold, không backlog.

## T12 — Đóng gói và runbook cục bộ

**Phụ thuộc:** T11.

### File

- `Dockerfile`, `.dockerignore`, hoàn thiện `config/compose.yaml`, `compose.test.yaml`.
- `docs/implementation/runbook.md`, `docs/implementation/device-client-contract.md`.

### Các bước

1. CPU image là baseline; non-root UID riêng, lockfile frozen, một uvicorn worker.
2. Model volume read-only, .env không nằm trong image/build context.
3. Compose dev chỉ bind loopback, service tên `navcore-dev`; DB volume tên riêng.
4. Healthcheck chỉ gọi local endpoint, readiness không giả do thiếu model.
5. App startup không migration/seed/download; runbook nêu thứ tự rõ.
6. Graceful shutdown: pause/notify WS, không nhận job mới, chờ job hiện tại tối đa thời hạn cấu hình;
   không claim đã cancel GPU kernel chỉ vì HTTP task bị cancel.
7. Runbook có backup/restore catalog sang DB rỗng, không hướng dẫn wipe DB đang dùng.
8. CUDA chạy native qua extra cuda; chưa bắt buộc GPU Docker và không tự thay host driver.
9. Device-client-contract ghi camera upright, capture challenge, text TTL, audio ưu tiên,
   watchdog client1500ms, local TTS vi-VN, reconnect/resume và RGB limitations.
10. Không sửa Flutter ở task này. Không publish container, mở firewall hoặc deploy Internet.

### Nghiệm thu

Compose config hợp lệ; CPU container khởi động với model có sẵn; restart không mất catalog,
phiên cũ trả not_found; DB/models không được container tự ghi lại ngoài scope.
Backup restore được kiểm tra trên DB test riêng. Kiểm `.dockerignore` không đưa .env vào context.

## T13 — Nghiệm thu và bàn giao

**Phụ thuộc:** T10–T12; data thật cho G3/G4.

### Sản phẩm

- `docs/reports/backend-readiness.md`: G0–G5 từng trạng thái PASS/FAIL/BLOCKED, evidence links.
- `docs/reports/backend-readiness.json`: cùng trạng thái machine-readable.
- `docs/implementation/agent-handoff.md`: file map cuối, lệnh chạy, task còn lại, lỗi đã biết.
- OpenAPI snapshot generated từ app thật, WS JSON schema snapshot và model/policy manifests.

### Checklist cuối

1. Fresh checkout/copy backend + DB test trống + local model artifacts chạy theo runbook được.
2. G1 không dùng fake chính thuật toán; G2 phải model thật; G3 phải independent query video.
3. Không có data thì ghi chính xác dataset cần thêm theo 06 và phần đã làm xong.
4. Runtime evidence dùng đúng source/lock/model/config/data hashes; report cũ không dùng cho code mới.
5. Không có frame cũ phát hướng dẫn mới, không phiên khác truy cập được và không tiến độ bị trộn.
6. Thông báo còn thiếu hiệu chỉnh/thiết bị/đánh giá nào, không gắn nhãn production-safe.
7. Mốc tiếp theo nếu G4 qua: nối Flutter theo device-client-contract bằng nhiệm vụ riêng.
8. Không auto commit/push/deploy/release. Handoff là kết thúc triển khai cục bộ, không là release gate.

