# 02 — Hợp đồng dữ liệu, REST và WebSocket

Đây là nguồn chuẩn cho tên trường, đơn vị, giới hạn và mã lỗi.
Không đổi tên tương đương ở task sau. JSON dùng `snake_case`, UTF-8, UUID dạng chuỗi.
Pydantic đầu vào: `extra="forbid"`, cấm NaN/Infinity, không ép bool thành số nguyên.
Tất cả datetime lưu DB là UTC có timezone. Thời hạn runtime dùng đồng hồ monotonic.

## 1. Quy ước chung

- Khoảng cách: mét; thời gian TTC: giây; timestamp capture: mili giây monotonic của client.
- Heading: độ `[0,360)`, hướng camera, không phải hướng màn hình; `null` nếu không có.
- Accuracy heading: độ `[0,180]`; thiếu/không đáng tin phải là `null`.
- Bbox: `[x1,y1,x2,y2]`, tọa độ pixel trong ảnh đã xoay đúng chiều; `x2>x1`, `y2>y1`.
- Cosine: `[-1,1]`; không gọi trường này là xác suất chính xác.
- HTTP error: `{"error":{"code":"...","message":"...","request_id":"...","details":[]}}`.
- `request_id`: server tạo UUID, header `X-Request-ID`; không dùng giá trị client dài tùy ý.
- Không trả stack trace, DSN, token, đường dẫn model, ảnh hoặc vector trong lỗi/log.
- REST POST trả resource đã tạo, không trả dictionary thiếu schema.
- API mặc định `/v1`; health ở `/health/live`, `/health/ready`.

## 2. PostgreSQL schema

Tạo migration `backend/migrations/versions/0001_catalog_devices.py`.
Mọi khóa chính là UUID server sinh; không dùng ID từ filename upload.

### `maps`

| Cột | Kiểu / ràng buộc |
|---|---|
| id | UUID PK |
| name | VARCHAR(120), trim, không rỗng |
| created_at | TIMESTAMPTZ, default now() |

### `places`

| Cột | Kiểu / ràng buộc |
|---|---|
| id | UUID PK |
| map_id | UUID FK maps, RESTRICT |
| name | VARCHAR(120), trim, không rỗng |
| name_key | TEXT, Unicode casefold + whitespace collapse; casefold có thể dài hơn tên gốc |
| created_at | TIMESTAMPTZ |

Unique `(map_id,name_key)`; unique `(id,map_id)` để composite FK routes kiểm tra cùng map.
Không bỏ dấu tiếng Việt khi tạo `name_key`.

### `routes`

| Cột | Kiểu / ràng buộc |
|---|---|
| id | UUID PK |
| map_id | UUID FK maps |
| name | VARCHAR(120), trim |
| from_place_id / to_place_id | Composite FK `(place_id,map_id)` → places, hai đầu khác nhau |
| revision | INTEGER >=1, server cấp dưới transaction/lock map |
| status | VARCHAR, CHECK `draft` hoặc `published`, default draft |
| encoder_fingerprint | VARCHAR(64), nullable ở draft chưa có reference; publish phải có SHA-256 encoder |
| route_fingerprint | CHAR(64), nullable trước publish |
| created_at / published_at | TIMESTAMPTZ, published_at nullable |

Unique `(map_id,from_place_id,to_place_id,revision)`.
Index `(map_id,from_place_id,to_place_id,status,revision)`.
Một chiều: không tự tạo tuyến ngược, không đảo ảnh/sequence để giả tuyến về.

### `checkpoints`

| Cột | Kiểu / ràng buộc |
|---|---|
| id | UUID PK |
| route_id | UUID FK routes, RESTRICT |
| seq | INTEGER >=0, unique `(route_id,seq)` |
| depart_action | VARCHAR CHECK straight/left/right/arrive |
| landmark | VARCHAR(120), mô tả ngắn do admin nhập |
| heading_deg | FLOAT nullable, `[0,360)` |
| heading_accuracy_deg | FLOAT nullable, `[0,180]`; chỉ có khi heading_deg có giá trị |

Publish mới kiểm tra seq liên tục `0..N-1`, N=2..64, chỉ checkpoint cuối được `arrive`.
Ý nghĩa: xác nhận tới checkpoint k thì phát hành động rời checkpoint k.
Ví dụ k=1 là trước góc rẽ: chỉ sau xác nhận k=1 mới phát `TURN_LEFT`.

### `reference_images`

| Cột | Kiểu / ràng buộc |
|---|---|
| id | UUID PK |
| checkpoint_id | UUID FK checkpoints, RESTRICT |
| jpeg_bytes | BYTEA, ảnh canonical JPEG đã bỏ metadata |
| width / height | SMALLINT, kích thước canonical |
| pixel_sha256 | CHAR(64), SHA-256 width+height+RGB pixels trước JPEG re-encode |
| source_group | VARCHAR(80), ID lần thu reference |
| embedding | BYTEA, 768 số float32 little-endian, đúng 3.072 byte |
| encoder_fingerprint | CHAR(64) |
| created_at | TIMESTAMPTZ |

Unique `(checkpoint_id,pixel_sha256)`; publish kiểm tra trùng pixel xuyên checkpoint.
Không nhận vector do client cung cấp; backend tính từ ảnh.
Ảnh/vectors không xuất hiện trong list catalog cho device.
N=3..8 ảnh/checkpoint, tổng JPEG một route <=64 MiB.

### `devices`

| Cột | Kiểu / ràng buộc |
|---|---|
| id | UUID PK |
| name | VARCHAR(80) |
| token_sha256 | CHAR(64) unique NOT NULL |
| created_at / expires_at | TIMESTAMPTZ; mặc định hạn 90 ngày |
| revoked_at | TIMESTAMPTZ nullable |

Không lưu plaintext token trong DB. CLI tạo token `navdev_` + `secrets.token_urlsafe(32)`.
CLI ghi token vào file client env mode0600 được chỉ định, không ghi token ra stdout/report.
Admin key nằm trong `NAV_ADMIN_TOKEN`, tối thiểu 32 ký tự ngẫu nhiên.
Device token không phải tài khoản người dùng và không chứa tên/định danh người khiếm thị.

### Những thứ không lưu DB ở v1

- Tracker, request token, candidate localization, trạng thái WS, audio queue.
- Ảnh camera trực tiếp và depth từng frame.
- Session đang đi: không tự phục hồi sau restart.
- Không tạo bảng user/profile/organization hoặc signup.

## 3. HTTP endpoints

Tất cả endpoint ngoài health yêu cầu `Authorization: Bearer <token>`.
Admin token dùng route admin và đọc catalog; device token dùng catalog/phiên.

| Method + path | Quyền | Input | Kết quả |
|---|---|---|---|
| GET `/health/live` | Public | Không | 200 `{"status":"alive"}` |
| GET `/health/ready` | Public | Không | 200 ready; 503 not_ready; không lộ chi tiết nội bộ |
| POST `/v1/admin/maps` | Admin | `{name}` | 201 Map |
| POST `/v1/admin/maps/{map_id}/places` | Admin | `{name}` | 201 Place |
| POST `/v1/admin/routes` | Admin | `{map_id,name,from_place_id,to_place_id}` | 201 Route draft |
| POST `/v1/admin/routes/{route_id}/checkpoints` | Admin | Multipart bên dưới | 201 Checkpoint summary |
| POST `/v1/admin/routes/{route_id}/publish` | Admin | `{}` | 200 Route published |
| GET `/v1/admin/routes/{route_id}` | Admin | Không | Metadata, checkpoint và lỗi publish; không tự trả bytes ảnh |
| GET `/v1/maps` | Device/Admin | cursor UUID?, limit 1..100 default 50 | `{items,next_cursor}` |
| GET `/v1/maps/{map_id}/places` | Device/Admin | cursor?, limit? | `{items,next_cursor}` |
| GET `/v1/routes` | Device/Admin | map_id, from_place_id, to_place_id bắt buộc | `{items}` published, revision giảm dần |
| POST `/v1/sessions` | Device | SessionCreate | 201 Session |
| GET `/v1/sessions/{session_id}` | Device chủ phiên | Không | SessionSnapshot |
| DELETE `/v1/sessions/{session_id}` | Device chủ phiên | Không | 204, stop idempotent |

`items` của maps/places sắp xếp UUID tăng dần để cursor ổn định.
GET routes trả tối đa 20 revision, không ghép graph và không tự chọn đường chưa thu.
Không có draft ở response device. Không có tuyến phù hợp: `items=[]`.
POST session chỉ nhận một `route_id` đã publish; app/CLI chọn revision đầu nếu muốn bản mới nhất.
Session của device khác: HTTP 404. Sai role: 403. Thiếu/sai token: 401.
Các mutation admin cần lock chống race với tạo phiên: có phiên active thì 409 `CATALOG_BUSY`.
Session state `localizing`, `navigating`, `lost`, `paused` đều tính active.

### Thêm checkpoint

Multipart có đúng một `metadata` JSON string và `images` lặp lại 3..8 file JPEG/PNG.
Tổng request <=4 MiB, mỗi file <=384 KiB; không nhận URL/path thay file.

```json
{
  "seq": 0,
  "depart_action": "straight",
  "landmark": "Cửa vào hành lang",
  "heading_deg": null,
  "heading_accuracy_deg": null,
  "source_group": "reference-entrance-2026-10-21"
}
```

Validate và encode toàn bộ ảnh trước insert. Một ảnh lỗi: cả checkpoint không được lưu.
Route published không thêm/sửa checkpoint, trả 409 `ROUTE_IMMUTABLE`.
Không hỗ trợ update/delete trong v1; tạo draft mới khi cần thay reference.
Publish đã published: idempotent 200, không đổi hash/thời gian hoặc phiên đang chạy.

### Tạo session RGB

```json
{
  "route_id": "11111111-1111-4111-8111-111111111111",
  "sensor": {"mode": "rgb"},
  "language": "vi-VN"
}
```

RGB-D dùng sensor:
`{"mode":"rgbd","depth_scale_m":0.001,"calibration_id":"d435-aligned-profile-01"}`.
Scale `[0.000001,0.01]`, calibration_id 1..80 ký tự; immutable trong suốt phiên.
Language chỉ nhận `vi-VN`. Không nhận `device_id` do caller tự chọn.

```json
{
  "id": "22222222-2222-4222-8222-222222222222",
  "state": "localizing",
  "mode": "rgb",
  "route_id": "11111111-1111-4111-8111-111111111111",
  "route_revision": 1,
  "last_confirmed_seq": -1,
  "target_seq": 0,
  "checkpoint_count": 4,
  "stream_path": "/v1/sessions/22222222-2222-4222-8222-222222222222/stream",
  "expires_at": "2026-10-21T12:30:00Z"
}
```

Một device chỉ có một session active, tạo thêm trả 409 `DEVICE_SESSION_EXISTS`.
Tối đa 4 active session/server; vượt trả 503 `SESSION_CAPACITY`, `Retry-After: 1`.
TTL tuyệt đối 30 phút; idle 5 phút không frame/control thì stop và dọn RAM.
GET/health/heartbeat không kéo dài idle TTL. Completed/stopped không trở lại active.
UUID không tìm thấy sau restart trả 404 `SESSION_NOT_FOUND`; client tạo phiên mới.

## 4. WebSocket và độ mới không cần đồng bộ đồng hồ

Path: `/v1/sessions/{id}/stream`, Bearer header lúc handshake.
V1 dành cho Flutter/Python client có gửi header; chưa có browser client.
Handshake không có auth hoặc không sở hữu session bị từ chối HTTP 403 trước accept.
Session terminal/expired có auth hợp lệ: gửi lỗi rồi close 1008.
Một session chỉ có một WS; kết nối thứ hai bị từ chối, không đá kết nối cũ.

Server gửi yêu cầu chụp; client chỉ trả ảnh chụp SAU khi nhận yêu cầu đó.
Thời gian từ lúc server gửi yêu cầu đến lúc chốt kết quả là cận trên tuổi ảnh.
Đây là cách kiểm tra freshness v1; không so trực tiếp đồng hồ client với server.
Client phải giữ capture timestamp của chính nó để kiểm tra tuổi kết quả lúc phát tiếng.

### Thứ tự thông điệp

1. Server gửi `welcome`.
2. Server gửi `capture_request` với seq/token mới.
3. Client chụp frame mới, gửi `frame` có cùng seq/token.
4. Server validate → inference → chốt trạng thái nếu còn hạn → gửi `frame_result`.
5. Chỉ sau khi xử lý xong mới cấp capture_request tiếp; tối đa 5 request/giây/phiên.

Không có hàng đợi ảnh phía session. Frame gửi tự do hoặc token cũ bị reject.

```json
{"type":"welcome","protocol_version":1,"session_id":"22222222-2222-4222-8222-222222222222","mode":"rgb","state":"localizing","max_result_age_ms":1000,"heartbeat_interval_ms":2000}
```

```json
{"type":"capture_request","seq":1,"frame_token":"33333333-3333-4333-8333-333333333333","deadline_ms":1000,"preferred_width":640,"preferred_height":480}
```

`deadline_ms` tính từ lúc server phát yêu cầu, không phải sau khi upload xong.

```json
{
  "type": "frame",
  "seq": 1,
  "frame_token": "33333333-3333-4333-8333-333333333333",
  "capture_monotonic_ms": 1234567,
  "heading_deg": null,
  "heading_accuracy_deg": null,
  "image_b64": "<base64 JPEG, không có data: prefix>",
  "depth": null
}
```

RGB-D depth:
`{"png_b64":"<16-bit PNG>","capture_monotonic_ms":1234567,"aligned_to_color":true,"calibration_id":"d435-aligned-profile-01"}`.
Depth phải cùng kích thước/chiều với màu, cùng calibration phiên, lệch capture <=50 ms.
PNG depth phải grayscale16-bit thật (IHDR bit_depth=16, color_type=0), không nhận PNG8-bit
rồi cast thành uint16. Kiểm header trước decode, giữ giá trị raw uint16 không normalize về0..255.
RGB không được gửi depth. RGB-D thiếu depth: nhận ảnh nhưng output `depth_status=missing`, chặn hướng dẫn di chuyển.
Depth sai kích thước/calibration/format bị reject, không dùng depth cũ thay thế.
Depth raw uint16 nhân với `sensor.depth_scale_m` mới ra mét; raw 0 là unknown.

### Giới hạn frame

- WS text message <=1.100.000 byte; mỗi ảnh encoded base64 <=524.288 ký tự.
- Byte decoded từng ảnh <=393.216; kích thước 32..1280 × 32..720, <=921.600 pixels.
- Màu chỉ JPEG trong WS; admin upload cho phép PNG nhưng canonical thành JPEG.
- Không nhận animated, ảnh bị lỗi, data URL, external URL, filename/path hoặc vector.
- Không đọc EXIF để tự quay ở WS: client gửi pixels đã upright, bỏ EXIF metadata ở server.
- capture timestamp là integer >=0, tăng nghiêm ngặt; delta >1.000 ms reset lịch sử vận tốc.
- JSON/base64 phải kiểm tra size trước decode; image header trước giải nén toàn bộ.
- Mỗi token chỉ nhận một frame. 3 vi phạm protocol trên cùng WS thì close 1008.
- Close 1009 cho message quá lớn; không trả raw payload trong error.

### Kết quả

```json
{
  "type": "frame_result",
  "seq": 1,
  "capture_monotonic_ms": 1234567,
  "state": "localizing",
  "last_confirmed_seq": -1,
  "target_seq": 0,
  "localization": {"candidate_seq":0,"similarity":0.91,"margin":0.07,"confirmed":false,"orientation_verified":false},
  "obstacles": [{"track_id":1,"class_name":"person","bbox":[210,150,400,470],"confidence":0.83,"position":"ahead","distance_m":null,"ttc_s":null}],
  "depth_status": "not_supported",
  "movement_held": true,
  "hold_reason": "LOCALIZING",
  "instruction": null,
  "timing": {"decode_ms":2.0,"queue_ms":0.0,"inference_ms":120.0,"core_ms":1.0,"request_to_result_ms":160.0}
}
```

`depth_status`: not_supported/valid/missing/invalid/insufficient.
Instruction object khi có:

```json
{"id":"44444444-4444-4444-8444-444444444444","code":"TURN_LEFT","text_vi":"Đến chỗ rẽ. Rẽ trái.","priority":"guidance","valid_for_ms":600,"frame_seq":4,"capture_monotonic_ms":1235000,"replace_pending":true}
```

`valid_for_ms` = max(0,1000 − tuổi cận trên tại server), không phải thêm 1.000 ms mới.
Client chỉ phát nếu tuổi capture trên đồng hồ client <1.000 ms VÀ chưa tới thời gian nhận+valid_for_ms.
Instruction hướng dẫn di chuyển hết hạn thì bỏ; không tự phát lại sau reconnect.
Warning/STOP cũng là nhận định có hạn; thông báo tình trạng mất hỗ trợ dùng event không dựa ảnh.
Không phát câu đi tiếp sau khi instruction STOP/warning mới hơn đã tới.

### Control, ACK, heartbeat và lỗi

- Client: `{"type":"control","command":"pause|resume|repeat|stop"}`.
- Server trả `control_result` với command, state và instruction nullable.
- `repeat`: chỉ lặp instruction chưa hết hạn; nếu hết hạn trả code `WAIT_FOR_FRESH_FRAME`.
- ACK: `{"type":"ack","instruction_id":"UUID","stage":"received|presented"}`.
- `presented` nghĩa là bắt đầu đọc/phát hiện thị instruction khi nó còn hạn; không đợi đọc hết câu.
- ACK idempotent; `presented` không chứng minh người dùng đã rẽ hoặc đã tới checkpoint.
- Chỉ ACK ID departure hiện tại, đúng epoch, server nhận trước deadline mới mở khóa.
- `movement_held=true` luôn hủy movement đang đợi dù instruction=null do cooldown.
- Timing bổ sung `event_loop_lag_ms`: lag watchdog đo thực tế, không gán0 để đạt benchmark.
- Hướng dẫn rời checkpoint chưa được ACK presented thì không xác nhận checkpoint tiếp;
  hết TTL chỉ được tạo lại câu đó sau khi frame mới xác nhận lại checkpoint hiện tại (xem03).
- Server heartbeat mỗi 2 giây: `{"type":"heartbeat","state":"paused"}`; không kéo dài tuổi instruction.
- Event tình trạng: `{"type":"status","code":"STREAM_STALE","state":"paused","text_vi":"Hướng dẫn đã tạm dừng vì thiếu hình ảnh mới."}`.
- Lỗi frame: `{"type":"frame_rejected","seq":1,"code":"FRAME_EXPIRED"}`.
- Lỗi chung: `{"type":"error","code":"...","message":"...","request_id":"UUID"}`.
- Reconnect vào phiên paused không tự chạy: client gửi `resume`, backend định vị lại vùng cho phép.
- Recheck revoked/expired device token mỗi 10 giây trên WS; nếu hết quyền, pause và close 1008.

## 5. Mã lỗi phải có

| HTTP hoặc WS code | Ý nghĩa |
|---|---|
| AUTH_REQUIRED / AUTH_INVALID | 401, token thiếu/sai/hết hạn/revoked |
| ROLE_FORBIDDEN | 403, sai quyền |
| RESOURCE_NOT_FOUND / SESSION_NOT_FOUND | 404, không thấy hoặc không sở hữu |
| VALIDATION_ERROR | 422, dữ liệu sai schema |
| PAYLOAD_TOO_LARGE | 413 HTTP hoặc close 1009 WS |
| IMAGE_INVALID / DEPTH_INVALID | 422 HTTP hoặc frame_rejected WS |
| ROUTE_IMMUTABLE / ROUTE_NOT_PUBLISHED | 409 |
| ROUTE_INVALID / ROUTE_AMBIGUOUS | 422, details chỉ ra checkpoint và điều kiện lỗi |
| MODEL_FINGERPRINT_MISMATCH | 409, reference khác encoder hiện tại |
| DEVICE_SESSION_EXISTS / CATALOG_BUSY | 409 |
| SESSION_CAPACITY / VISION_UNAVAILABLE | 503 |
| FRAME_TOKEN_INVALID / FRAME_DUPLICATE / FRAME_EXPIRED | frame_rejected, không thay đổi tiến độ |
| CAPTURE_TIME_INVALID / PROTOCOL_ERROR | frame_rejected; đếm vi phạm |
| WORKER_BUSY | frame_rejected; có status hold, không xếp hàng vô hạn |
| SESSION_TERMINAL | error WS rồi close 1008 |

Unknown error: 500 `INTERNAL_ERROR` với request_id; log traceback nội bộ đã bỏ secret.
Không catch mọi HTTPException rồi biến 401/422/503 thành 500.

