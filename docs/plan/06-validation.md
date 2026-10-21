# 06 — Dữ liệu và điều kiện nghiệm thu

Không dùng bảng này để tuyên bố an toàn ngoài đời. Đây là kiểm tra nguyên mẫu trong phạm vi đã chốt.
Các gate phải được báo độc lập: test logic, model smoke và video thực không thay thế lẫn nhau.

## 1. Ba lớp dữ liệu

| Lớp | Nguồn | Chứng minh được | Không chứng minh |
|---|---|---|---|
| Synthetic | Vector/detection/depth xác định được | State, units, priority, freshness, protocol | AI hiểu video thật |
| Model smoke | Ảnh/clip có thật, model thật | Decode/inference/output contract | Dẫn đúng tuyến |
| Pilot độc lập | Reference riêng + query riêng + nhãn người kiểm tra | Hành vi trên tuyến và điều kiện thử đó | Tổng quát mọi nhà/đường phố/người dùng |

Không có pilot dataset trong clone hiện tại. Agent phải tạo importer/evaluator đầy đủ,
để `real/README.md` ghi thiếu gì và đánh dấu BLOCKED_DATA nếu chưa nhận được footage hợp lệ.
Không tự lấy webcam của người dùng hoặc quay người khác để làm dữ liệu mà chưa có chỉ dẫn.

## 2. Synthetic fixture bắt buộc

### Route

UUID trong fixture cố định, không dùng ID ngẫu nhiên làm assertion khó tái hiện.
4 checkpoint: seq0 straight, seq1 left, seq2 right, seq3 arrive.
Reference vector của checkpoint i gần basis vector e_i trong R768, 3 reference khác nhau.
Tự tính cosine/norm kỳ vọng bằng công thức độc lập với implementation.

### Positive timeline

| Frame | Embedding / điều kiện | Kỳ vọng |
|---|---|---|
| 1–3 | Match checkpoint0, 3 ảnh/capture khác nhau | Chỉ frame3 xác nhận0, CONTINUE_STRAIGHT |
| 4–6 | Match checkpoint1 | Chỉ frame6 TURN_LEFT, last=1 |
| 7–9 | Match checkpoint2 | Chỉ frame9 TURN_RIGHT, last=2 |
| 10–12 | Match checkpoint3 | Chỉ frame12 ARRIVED, completed |

Khoảng capture200ms; pixel hashes khác nhau dù embedding có thể giống.
Chèn ACK presented sau instruction ở frame3,6,9 trước nhóm frame của checkpoint tiếp theo.
Ground truth tuyệt đối không được sinh bằng gọi advance_navigation/decide của code đang kiểm tra.

### Negative timeline

- Một ảnh lặp 20 lần không được xác nhận checkpoint đầu.
- Một hit tốt rồi một hit mơ hồ: reset về0 hit, không giữ tích lũy xuyên miss.
- Match checkpoint3 khi đang target1: không arrival.
- Score0.95 nhưng margin0.01: không xác nhận.
- Heading359° và reference1°: sai khác2°, không358°.
- Heading sai180° với accuracy5°: reject dù cosine cao.
- Thiếu heading: match visual có thể đạt, orientation_verified=false được giữ trong output/report.
- Warning xuất hiện đúng frame thứ3 của một checkpoint: không commit; hết warning cần xác nhận lại.
- Instruction chưa ACK presented: không xác nhận chặng tiếp. Hết TTL phải dùng 3 frame mới xác nhận
  lại checkpoint vừa tới rồi tạo ID mới; ACK received/ID cũ không mở khóa chặng tiếp.

### Depth fixture

Tạo mảng uint16 nhỏ 640×480 theo seed cố định, scale0.001:
- Uniform1000 →1.0m; cùng raw1000 scale0.0001 →0.1m.
- Raw0/out-of-range/all invalid →None, không0m và không clear.
- Hai lớp gần1m/xa3m, mỗi lớp support đủ → chọn peak gần.
- Foreground support quá ít: ghi hạn chế và kết quả theo thuật toán, không fake chất lượng đo.
- Mất depth sau cảnh báo: giữ latch, không lấy sample cũ.
- 3 frame valid center>=0.9m không hazard → bỏ latch, không phát PATH_CLEAR.
- TTC distance1m closing0.6m/s →~1.667s, emergency.
- User tiến về tường: range giảm dù object không tự chuyển động → vẫn TTC hợp lệ.
- Capture gap>500ms hoặc jump>1.5m → velocity không đáng tin cho tới đủ sample mới.

## 3. Bundle tuyến thật

Một directory do người phụ trách dữ liệu cung cấp:

```text
pilot-route-a/
  bundle.json
  references/cp0/{01,02,03}.jpg
  references/cp1/{01,02,03}.jpg
  references/cp2/{01,02,03}.jpg
  references/cp3/{01,02,03}.jpg
  queries/dev.mp4
  queries/positive-01.mp4
  queries/positive-02.mp4
  queries/wrong-corridor.mp4
  queries/reverse-direction.mp4
  ground_truth.json
  dataset-manifest.json
```

```json
{
  "schema_version": 1,
  "map": {"name":"Tầng thử nghiệm"},
  "from_place": {"name":"Cửa vào"},
  "to_place": {"name":"Phòng A"},
  "route": {"name":"Cửa vào đến phòng A"},
  "checkpoints": [
    {"seq":0,"depart_action":"straight","landmark":"Cửa hành lang","heading_deg":null,"source_group":"ref-walk-01","images":["references/cp0/01.jpg","references/cp0/02.jpg","references/cp0/03.jpg"]},
    {"seq":1,"depart_action":"left","landmark":"Góc rẽ thứ nhất","heading_deg":null,"source_group":"ref-walk-01","images":["references/cp1/01.jpg","references/cp1/02.jpg","references/cp1/03.jpg"]},
    {"seq":2,"depart_action":"right","landmark":"Góc rẽ thứ hai","heading_deg":null,"source_group":"ref-walk-01","images":["references/cp2/01.jpg","references/cp2/02.jpg","references/cp2/03.jpg"]},
    {"seq":3,"depart_action":"arrive","landmark":"Cửa phòng A","heading_deg":null,"source_group":"ref-walk-01","images":["references/cp3/01.jpg","references/cp3/02.jpg","references/cp3/03.jpg"]}
  ]
}
```

Ảnh tham chiếu phải là ảnh thật của đúng nơi, không lấy từ query test.
Dev để thử ngưỡng trước khi khóa cấu hình; positive/negative test giữ độc lập.
Quay mỗi query bằng lượt đi khác với reference, không cắt một video làm hai split rồi gọi là độc lập.
Không auto suy luận turn/arrival từ model để tạo ground truth.

### Ground truth

```json
{
  "schema_version":1,
  "clips":[
    {
      "clip_id":"positive-01",
      "file":"queries/positive-01.mp4",
      "split":"test",
      "capture_group":"query-walk-02",
      "expected_completion":true,
      "checkpoints":[
        {"seq":0,"visible_start_ms":0,"visible_end_ms":2500,"expected_code":"CONTINUE_STRAIGHT"},
        {"seq":1,"visible_start_ms":6000,"visible_end_ms":8500,"expected_code":"TURN_LEFT"},
        {"seq":2,"visible_start_ms":12000,"visible_end_ms":14500,"expected_code":"TURN_RIGHT"},
        {"seq":3,"visible_start_ms":18000,"visible_end_ms":21000,"expected_code":"ARRIVED"}
      ],
      "objects":[],
      "forbidden_intervals":[]
    }
  ]
}
```

Ví dụ thời gian trên là minh họa schema, không phải nhãn clip đã có.
Người gán nhãn thay bằng thời điểm quan sát thực của từng query.
Objects label: `{pts_ms,class_name,bbox:[x1,y1,x2,y2],rgb_notice_expected:bool}`.
Forbidden interval: `{start_ms,end_ms,codes:["TURN_LEFT","TURN_RIGHT","ARRIVED"],reason}`.
Wrong corridor/reverse clip: expected_completion=false, cấm mọi checkpoint progress trong toàn clip,
trừ khi annotation cho phép checkpoint đầu nhìn thấy thực sự trước khi đổi hướng.
Evaluator hỗ trợ `allowed_confirmed_seqs` để diễn đạt ngoại lệ này; mặc định danh sách rỗng.

### Dataset manifest

- schema_version, dataset_id, created_at, capture groups, split từng file.
- SHA-256 file bytes, canonical frame hashes và source reference/query.
- Chuẩn quay/camera, upright rotation, ánh sáng và điều kiện giới hạn đã biết.
- Không chứa tên, số điện thoại hoặc thông tin riêng của người tham gia.
- Không đưa raw footage vào Git/image/container; chỉ file manifest và README nhỏ.
- CLI không được đọc bất kỳ path nào resolve ra ngoài bundle root, kể cả qua symlink.

## 4. Điều kiện pass pilot G3

Đủ tối thiểu: một route4 checkpoint, 12 reference ảnh khác nhau, 1 dev clip,
2 positive test độc lập và 2 negative test; mỗi query đủ thấy tình huống được gán nhãn.

- Hai positive hoàn thành; mỗi transition đúng thứ tự và trong cửa sổ visible của checkpoint.
- 0 early turn, 0 turn sai hướng, 0 early arrival trên bộ thử này.
- Negative không có progress/turn/arrival ngoài allowed_confirmed_seqs trong annotation.
- Mất vị trí được biểu diễn lost/hold; không phát lời khuyên đi lùi để “thử lại”.
- Không dùng ảnh query làm reference; không tuning lại theo test rồi giữ tên split cũ.
- Báo rõ tỷ lệ frame orientation_verified; thiếu heading không được báo orientation đã kiểm chứng.
- Với obstacle smoke có nhãn: >=30 frame có class person/chair và >=30 frame không có class đó,
  matched detection IoU>=0.5, confidence>=0.38; report precision/recall và số mẫu.
- Baseline detector gate trên bộ mẫu này: precision>=0.80 và recall>=0.80.
  Không đạt thì G3 FAIL_PERCEPTION; không sửa nhãn để tăng điểm.
- Thử RGB notice riêng nơi có vật thể đáp ứng heuristic; phân biệt notice với đo nguy cơ va chạm.

Nếu một ngưỡng không đạt: giữ report thất bại, xác định bottleneck bằng dữ liệu,
đổi config trên dev, khóa revision mới rồi dùng query test độc lập mới để xác nhận.
Không cam kết những tỷ lệ này sẽ đạt chỉ từ việc ghép hai repo.

## 5. Ma trận kiểm tra V01–V30

| ID | Test/đầu vào | Kỳ vọng quan sát |
|---|---|---|
| V01 | JSON extra/NaN/enum sai | 422 hoặc frame reject, không mutation |
| V02 | Image quá byte/pixel, invalid base64, truncated | Chặn trước cấp phát lớn/inference |
| V03 | Device gọi admin, token sai/hết hạn | 401/403, không catalog mutation |
| V04 | Device B GET/DELETE/WS session A | HTTP404/WS403, không lộ dữ liệu A |
| V05 | Cross-map FK, seq gap, final action sai | DB/API reject đúng code |
| V06 | Draft, duplicate/ambiguous refs, fingerprint khác | Không publish hoặc không tạo session |
| V07 | Encoder cùng ảnh, vector norm/shape | 768 finite normalized; model thật ở G2 |
| V08 | Detector negative class/NaN/wrong shape | Loại invalid row hoặc fail artifact shape |
| V09 | Hai detection overlap trong cùng frame | Không gán hai lần một track, cả track mới |
| V10 | Track expiry tại1000 và1001ms | Tại1000 còn,1001 expire |
| V11 | Depth scale/alignment/skew sai | Không trả khoảng cách cũ hoặc metric giả |
| V12 | Depth zeros, tiny ROI, out-of-range | None/insufficient, không PATH_CLEAR |
| V13 | TTC/user tiến tường/clock gap/jump | Closing đúng; gap/jump làm unreliable |
| V14 | Cùng pixels lặp, một hit/miss/margin thấp | Không advance |
| V15 | 3 hit tốt, threshold đúng biên | Advance đúng một cp, không skip |
| V16 | Wrap heading359/1, heading sai180 | Circular match đúng; wrong heading reject |
| V17 | Warning đúng lúc turn/arrival | Cảnh báo thắng, checkpoint chưa commit |
| V18 | Warning bị cooldown | Voice có thể null, vẫn hold, không advance |
| V19 | Age999ms và1000ms | Chỉ trường hợp dưới deadline được commit |
| V20 | Pause/stop/disconnect trong inference | Late result không đổi bất kỳ state nào |
| V21 | Worker timeout nhưng thread chưa xong | Inference concurrency thực<=1 |
| V22 | Frame token cũ, duplicate, không request | Reject, không xả backlog, 3 lỗi close |
| V23 | Hai WS/session; device active session thứ2 | Reject; không lấy quyền phiên trước |
| V24 | Hai/four sessions xen frame và control | Không trộn progress/tracker/cooldown/instruction |
| V25 | Slow receiver/output queue đầy | Pause/close1013; không giữ lệnh di chuyển chờ |
| V26 | Revoked token sau connect | Trong<=10.1s pause/close1008 |
| V27 | Idle5min, total30min, server restart | Stop/cleanup; restart catalog còn, phiên cũ not_found |
| V28 | lost/resume, repeat stale, heartbeat | Re-localize vùng cho phép; repeat không kéo dài TTL |
| V29 | Pilot videos, independent split | G3 theo mục4, không dùng synthetic thay thế |
| V30 | 1/4 session benchmark + loop cleanup | Có latency/drop/RSS/VRAM và evidence source-bound |

Các test timer dùng FakeClock/Event điều khiển, không sleep dài hoặc dựa timing máy CI may rủi.
Kiểm 3 lớp: core pure, app test adapter với DB thật, WS client độc lập với server process.

## 6. Hiệu năng cần đo

Workload: input640×480 JPEG quality75, tối đa5fps, RGB thật, route4 checkpoint/3 refs mỗi checkpoint.
Warmup30s, đo300s; ghi cả CPU và CUDA profile nếu đã chạy, không trộn hai profile vào một percentile.

Mục tiêu realtime nguyên mẫu cho **1 session, mạng thử có RTT p95<=100ms**:
- Server request→result p95<=700ms.
- Client capture-request→result receive p95<=900ms, p99<=1000ms cho kết quả được chấp nhận.
- Frame expired/rejected do tải <=1% khi không inject lỗi; tính mẫu gồm cả bị reject, không giấu tail.
- Event loop lag p95<=50ms, watchdog không bị inference chặn.
- Stale instruction được client phát: đúng0.

Đây là mục tiêu nghiệm thu, chưa phải kết quả máy RTX3050 đã đạt.
4 session chỉ pass scheduling khi không stale commit, không OOM và queue/concurrency đúng giới hạn;
throughput đo được quyết định capacity thực, không hứa 4×5fps.

Kiểm cleanup: sau warmup, tạo/stop500 phiên, gc, không còn session/task/reference ảnh của phiên cũ.
RSS steady-state tăng<=100MiB so với baseline warmup; nếu model allocator cache khác phải báo riêng,
không xóa assertion rồi coi không rò bộ nhớ.

## 7. Report JSON chuẩn

```json
{
  "schema_version":1,
  "run_id":"UUID",
  "evidence_kind":"network_replay",
  "adapter_kind":"real_models",
  "gates":{"G0":"PASS","G1":"PASS","G2":"PASS","G3":"BLOCKED_DATA","G4":"BLOCKED_DATA","G5":"NOT_RUN"},
  "inputs":{"source_sha256":"...","uv_lock_sha256":"...","model_manifest_sha256":"...","policy_sha256":"...","dataset_manifest_sha256":null},
  "environment":{"python":"...","profile":"cpu","gpu":null},
  "counts":{"frames_requested":0,"frames_received":0,"frames_expired":0,"stale_instructions_presented":0},
  "navigation":{"false_turns":null,"missed_turns":null,"early_arrivals":null,"completed_positive_clips":null},
  "latency_ms":{"p50":null,"p95":null,"p99":null},
  "limitations":["No independent pilot dataset supplied"]
}
```

Report thiếu sample không dùng0 thay null cho metric chưa đo.
False turn/arrival đếm sự kiện client hợp lệ đã nhận và còn TTL; stale server proposal phải đếm riêng.
JSON và Markdown phải đồng nhất gate/counts; evaluator kiểm tra trước khi ghi.

## 8. Lệnh kiểm tra chuẩn và ý nghĩa

```bash
uv run --project backend --extra cpu --group dev pytest backend/tests/unit -q
uv run --project backend --extra cpu --group dev --env-file backend/config/.env pytest backend/tests/integration -q
uv run --project backend --extra cpu --group dev --env-file backend/config/.env pytest backend/tests/model -m model -q
```

`scripts/check.sh` chạy lint + unit + integration trên test DB; model test chạy riêng khi có artifacts.
Model test không có artifacts trả skip rõ với lý do; gate G2 vẫn BLOCKED_MODEL, không PASS.
Real-data evaluator thiếu bundle trả exit2; lỗi schema/implementation/test fail trả exit1.
Hoàn thành evaluator/report thành công trả exit0, nhưng report có gate FAIL thì CI nghiệm thu trả exit1.

## 9. Các tuyên bố bị cấm trong handoff nếu chưa có bằng chứng

- “Core đã dẫn đường an toàn” chỉ vì test synthetic pass.
- “Chạy realtime” chỉ từ inference time không tính mạng, decode, hàng đợi và client.
- “Đo khoảng cách” từ camera RGB mà distance không có nguồn cảm biến đáng tin.
- “Hỗ trợ mọi vật cản/hố/cầu thang/kính/ngoài đường” từ COCO detection.
- “Đã thử với người khiếm thị” khi chỉ có replay hoặc quay video bởi người phát triển.
- “Dữ liệu mới độc lập” nếu chỉ tách frame từ cùng clip reference.
- “Tích hợp app xong” khi chỉ có contract và CLI.

