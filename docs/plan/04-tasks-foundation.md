# 04 — Công việc T00–T06

Làm từ thư mục gốc `/home/chinhan/projects/blind-navigation-combine`.
Các lệnh dưới đây là lệnh agent sẽ chạy khi triển khai, chưa được chạy trong phiên viết plan.
Đọc 02/03 trước khi viết schema hoặc logic. Không dùng requirements hai repo gốc để cài gộp.

## Quy tắc thực hiện chung

- Một integration owner là writer duy nhất của checkout chính.
- Nếu dùng nhiều agent theo AGENTS.md: research/review read-only có thể đọc cùng checkout;
  writer khác phải làm trên bản sao riêng và giao patch, integration owner mới đưa vào backend/.
- Chưa có `.git`; không tự init/commit/push để tạo worktree.
- MCP coordination chỉ dùng nếu được đăng ký/cấu hình; không suy ra có tool chỉ từ tên trong AGENTS.md.
- Mỗi task tạo `docs/implementation/Txx.md`: đầu vào/hash, file đổi, quyết định, lệnh, exit code,
  kết quả, limitation và task tiếp theo. Không ghi token/env đầy đủ.
- Báo cáo task là receipt cho thay đổi cục bộ được giao; không phải phép deploy/release.
- Khi test thất bại, sửa code/task đúng phạm vi rồi chạy lại test bị ảnh hưởng; không bỏ assertion.
- Không sửa code upstream để test mới dễ qua. Port ca test sang package backend.

## T00 — Tạo package và khóa môi trường

**Phụ thuộc:** không. **Gate:** nền cho G0.

### File cần tạo

- `backend/pyproject.toml`, `backend/uv.lock`.
- `backend/src/navcore/__init__.py`, `settings.py`, `app.py`, `logging.py`.
- `backend/src/navcore/cli/{__init__,__main__,bootstrap}.py`.
- `backend/tests/conftest.py`, `backend/tests/unit/test_settings.py`.
- `backend/config/.env.example`, `backend/.gitignore`, `backend/THIRD_PARTY_NOTICES.md`.
- `backend/scripts/record_build_inputs.py`.

### Các bước

1. Kiểm tra hash nguồn trong 01-source-audit; chỉ đọc các file upstream.
2. Kiểm tra `python3 --version`, `uv --version`, `docker --version`, disk trống và GPU metadata.
   Nếu ít hơn12GiB: chưa tải profile lớn; CPU-only được áp dụng RESOURCE-CPU-01 trong
   [quyết định thực thi](../implementation/decisions.md) sau khi đã đo đúng wheel set và disk reserve.
3. Python target `>=3.12,<3.13`; package name `navigation-core`, import `navcore`, src layout.
4. Dùng dependency baseline và CPU/CUDA extras ở 07-operations, lock transitive bằng uv.
5. `create_app(settings=None, vision=None, clock=None)` là factory cho test tiêm dependency.
   Không connect DB/load model lúc import package.
6. Settings đọc env; thiếu DB URL/admin token ở runtime → fail startup rõ, không fallback token mặc định.
7. Default host 127.0.0.1, API port 8095, PostgreSQL dev port 55439, test port 55440.
8. `.gitignore`: .env, .venv, .cache, .pytest_cache, __pycache__, models/, output/, raw captures,
   credentials, generated private datasets; không ignore migrations/uv.lock/test fixture nhỏ.
9. Logging JSON chuẩn Python, fields event/request_id/session_id/task_id/timing/code.
   Redact Authorization/token/image_b64/png_b64/DB password; không log body nguyên vẹn.
10. Notices giữ MIT attribution cho phần BlindNav adapted; ghi NAVI/model licenses như source audit.
11. `record_build_inputs.py` ghi Python/packages/uv.lock SHA/source hashes/model manifest SHA/policy SHA.
    Chỉ quét backend/src, config không-secret, migrations và fixture đã chọn; không hash/đọc .env.
12. Tạo `bootstrap-dev` ngay T00 theo07, chạy được không cần app/DB/model; T02 dùng .env này.
    CLI dispatcher T00 chỉ biết bootstrap-dev; T03/T04/T10/T11 mới thêm subcommand tương ứng.

### Lệnh và nghiệm thu

```bash
uv lock --project backend
uv sync --project backend --extra cpu --group dev --locked
uv run --project backend --extra cpu python -m navcore.cli bootstrap-dev
uv pip check --python backend/.venv/bin/python
uv run --project backend --extra cpu --group dev pytest backend/tests/unit/test_settings.py -q
```

Pass: package import không đụng camera/audio/model/network/DB; settings reject missing/bad values;
lock resolve được và pip check qua. Nếu pin xung đột, ghi exact resolver error rồi sửa T00 kèm lý do;
không tự nâng NumPy lên 2 hoặc cài đồng thời hai OpenCV package.

## T01 — Types, schema và fixture core

**Phụ thuộc:** T00. **Gate:** một phần G1.

### File

- `src/navcore/core/types.py`.
- `src/navcore/schemas/catalog.py`, `stream.py`, `events.py`.
- `tests/fixtures/synthetic/route.json`, `observations.jsonl`, `expected_events.jsonl`.
- `tests/unit/test_contracts.py`, `test_fixture_integrity.py`.
- Các đường dẫn trong task này trở đi tương đối `backend/` nếu không ghi khác.

### Các bước

1. Tạo enum State/Mode/Action/Priority/InstructionCode theo đúng 02/03.
2. Tạo dataclass Detection, TrackState, SensorProfile, Reference, Checkpoint, RouteSnapshot,
   MatchResult, NavigationState, NavigationProposal, ObstacleResult, Decision.
3. Distance/TTC/heading chưa biết là Optional; serialization giữ null, không thay 0 hoặc 999.
4. Tạo Pydantic requests/responses; validate finite, limits, type/enum, extra fields.
5. Synthetic route có 4 checkpoint: 0 straight, 1 left, 2 right, 3 arrive.
   Mỗi checkpoint 3 reference vector 768 chiều, normalized.
6. Tạo vector bằng numpy với seed 20261021, mỗi checkpoint gần một basis vector khác nhau;
   positive sample có score vượt ngưỡng, negative/ambiguous sample được tính ra có kiểm tra.
7. Fixture phải lưu actual vectors/scores mong đợi hoặc generator có seed; không phụ thuộc model tải ngoài.
8. Observation timeline ghi seq, capture_ms, image_hash, embedding, detections, optional depth fixture.
9. Expected events liệt kê code, checkpoint, state, frame seq; exact IDs/time kiểm tra theo fake clock.
10. Không dùng chính implementation match/decision để sinh expected assertions.

### Kiểm tra

```bash
uv run --project backend --extra cpu --group dev pytest backend/tests/unit/test_contracts.py backend/tests/unit/test_fixture_integrity.py -q
```

Pass: valid examples round-trip; bad enum/extra/NaN/negative timestamp/missing depth calibration reject;
synthetic expected values do toán độc lập xác nhận. Ghi rõ đây chưa là dữ liệu AI thật.

## T02 — PostgreSQL và migration

**Phụ thuộc:** T01. **Gate:** một phần G0.

### File

- `storage/database.py`, `storage/models.py`, `storage/catalog.py`, `storage/devices.py`.
- `migrations/env.py`, `migrations/versions/0001_catalog_devices.py`.
- `config/alembic.ini`, `config/compose.yaml`, `config/compose.test.yaml`.
- `tests/integration/test_migrations.py`, `test_catalog_storage.py`.

### Các bước

1. Tạo 6 bảng maps/places/routes/checkpoints/reference_images/devices đúng 02-contracts.
2. Composite FK phải ngăn route nối place thuộc map khác ngay ở DB, không chỉ kiểm tra HTTP.
3. SQLAlchemy 2 sync Session, pool_size=5, max_overflow=0, pool_pre_ping=True.
4. Một transaction cho một mutation; session DB đóng ở cả success/error.
5. Repository trả dataclass/snapshot, không để ORM object lazy sống qua thread/WS frame.
6. Vector serialize `<f4` và validate đúng 3072 byte khi đọc/ghi.
7. DB dev chỉ bind 127.0.0.1:55439; test instance 127.0.0.1:55440, DB name `navcore_test`.
8. Test DB dùng tmpfs hoặc volume test riêng; helper reject DSN không kết thúc database `_test`.
9. Migration chạy ở lệnh riêng trước app, không tự create_all hay drop schema khi startup.
10. Khi tạo revision route, lock row map bằng SELECT FOR UPDATE rồi cấp max(revision)+1.

### Lệnh

```bash
docker compose --project-name navcore-test --env-file backend/config/.env -f backend/config/compose.test.yaml up -d db
uv run --project backend --extra cpu --group dev --env-file backend/config/.env pytest backend/tests/integration/test_migrations.py backend/tests/integration/test_catalog_storage.py -q
```

Test migration upgrade trên DB trống, insert hợp lệ, reject FK/unique/check, downgrade rồi upgrade CHỈ test DB.
Test rollback upload checkpoint không để lại reference rời rạc.
Không chạy downgrade/drop trên dev hoặc dữ liệu người dùng.

## T03 — Auth, health và lỗi

**Phụ thuộc:** T02. **Gate:** hoàn tất G0 phần hạ tầng; ready AI chờ T04.

### File

- `api/auth.py`, `api/errors.py`, `api/health.py`.
- `cli/__init__.py`, `cli/__main__.py`, `cli/devices.py`.
- `tests/integration/test_auth.py`, `test_health.py`, `test_errors.py`.

### Các bước

1. Admin Bearer constant-time compare với NAV_ADMIN_TOKEN; không có hardcoded default.
2. Device Bearer → SHA-256 lookup → expiry/revocation check; không nhận device_id tự khai trong request.
3. CLI argparse `python -m navcore.cli device-create --name replay-01 --output-env backend/config/replay-device.env`
   sinh token bằng secrets, ghi NAV_API_URL/NAV_DEVICE_TOKEN vào file mode0600, không ghi token ra stdout.
   Refuse ghi đè file có sẵn. Chỉ in device UUID/expiry/path; báo cáo task không chép nội dung file.
   Nếu ghi file lỗi thì rollback insert device để không tạo token không lấy lại được.
   Tạo file bằng exclusive create mode0600, ghi+fsync trước commit DB. DB commit lỗi thì chỉ dọn
   file vừa tạo bởi thao tác này, không đụng file đã tồn tại. Không truyền token qua shell command args.
4. CLI `device-revoke --id <UUID>` cập nhật revoked_at idempotent.
5. Error handler cho validation/HTTP/unexpected; đúng envelope và status 02-contracts.
6. Không `except Exception` biến lỗi auth/model/chưa publish thành HTTP 200.
7. live độc lập DB/AI; ready kiểm DB + models warm + worker state. Tạm thời chưa có model phải 503.
8. CORS mặc định không bật; cấu hình origin cụ thể nếu thêm browser về sau.
9. Middleware cap HTTP body admin upload 4 MiB trước parse, không chỉ kiểm từng file sau parse.
10. Khởi động dev cho phép vào admin CRUD metadata dù ready model đang 503;
    reference upload/session creation cần vision ready, chưa sẵn sàng trả 503.

### Kiểm tra

```bash
uv run --project backend --extra cpu --group dev --env-file backend/config/.env pytest backend/tests/integration/test_auth.py backend/tests/integration/test_health.py backend/tests/integration/test_errors.py -q
```

Pass: thiếu/sai/revoked/expired token đều bị chặn; token không xuất hiện trong capture logs;
device không gọi admin mutation; DB down vẫn live 200, ready 503; internal error không lộ DSN.

## T04 — Model thật và inference pipeline

**Phụ thuộc:** T01, T03. **Gate:** G2 khi model smoke thật qua.

### File

- `vision/images.py`, `encoder.py`, `detector.py`, `pipeline.py`, `artifacts.py`.
- `runtime/worker.py`, `cli/models.py`.
- `tests/unit/test_images.py`, `test_detector_postprocess.py`.
- `tests/model/test_encoder_real.py`, `test_detector_real.py`, `test_pipeline_real.py`.
- Generated private/untracked: `backend/models/manifest.json`, weights/model export.

### Các bước chuẩn bị model

1. CLI `models-fetch --model-dir backend/models`: explicit download, không download lúc server nhận request.
2. DINOv2 snapshot đúng revision trong 01, allowlist config.json/preprocessor_config.json/model.safetensors;
   nếu repo dùng shard thì tải đúng index+shards được index đó tham chiếu trong cùng revision.
3. YOLO `.pt` chỉ URL/hash cố định trong 01; hash sai phải xóa file tạm vừa tải và exit nonzero.
4. Export bằng môi trường riêng (`backend/.venv-export`), Ultralytics phiên bản ở 07.
5. Export ONNX float32, imgsz224, opset17, batch1, dynamic=False, end2end=True, nms=False,
   simplify=False để tránh thêm dependency không cần. Không INT8/FP16 trong baseline.
6. Sau export assert input/output shape và compare PyTorch/ONNX một ảnh smoke với tolerance hợp lý;
   shape sai → fail, không sửa parser để đoán phiên bản khác.
7. Manifest chứa URLs/revision/sha256/bytes/licenses/input/output/COCO labels/preprocess_version.
8. Encoder fingerprint chỉ tính encoder config+processor+weights+preprocess_version, không gồm YOLO.
9. Chỉ load weights `.pt` từ asset vừa xác minh hash trong exporter; runtime chỉ safetensors/ONNX.

### Các bước runtime

1. Startup lifespan load artifacts local, kiểm hash và warm-up một ảnh; thiếu/sai → not_ready.
2. Không fallback model khác, không tự đổi CUDA sang CPU âm thầm; settings quyết định profile.
3. Decode và inference chạy ngoài event loop. Worker chỉ 1 job thật tại một thời điểm.
4. Nhận RGB array đã validate, trả embedding+detections+timing; không đọc session/DB trong pipeline.
5. Hết await timeout không release slot nếu thread vẫn chạy; thêm test chặn job bằng Event.
6. Onnx session nạp một lần; torch model nạp một lần; không có detector/tracker global trộn lẫn.
7. CLI `models-verify --model-dir ...` kiểm manifest/hashes/shapes không sửa artifact.

### Lệnh và nghiệm thu

```bash
uv run --project backend --extra cpu --env-file backend/config/.env python -m navcore.cli models-fetch --model-dir backend/models
uv run --project backend --extra cpu --env-file backend/config/.env python -m navcore.cli models-verify --model-dir backend/models
uv run --project backend --extra cpu --group dev pytest backend/tests/unit/test_images.py backend/tests/unit/test_detector_postprocess.py -q
uv run --project backend --extra cpu --group dev --env-file backend/config/.env pytest backend/tests/model -m model -q
```

Pass unit: valid size, rotation ở admin, invalid base64, bomb/truncated image, no filename traversal;
bbox edge/clamp/class âm/non-finite/one-to-many output bị xử lý đúng.
Pass model: vector 768 finite norm≈1, cosine cùng ảnh≈1, ONNX đúng shape, pipeline thật không crash.
Không bắt detector phải thấy người trong một ảnh chưa có nhãn; test detection có nhãn ở G3.
Nếu thiếu mạng/model: đánh dấu G2 BLOCKED_MODEL, chạy tiếp unit/core tasks với adapter fixture.

## T05 — Catalog REST và publish validator

**Phụ thuộc:** T02, T03, T04 cho upload ảnh thật.

### File

- `api/catalog.py`, cập nhật `storage/catalog.py`, `schemas/catalog.py`.
- `tests/integration/test_catalog_api.py`, `test_route_publish.py`.

### Các bước

1. Implement đúng endpoint catalog/admin trong 02, không thêm generic CRUD generator.
2. Canonicalize names, server-generated UUID/revision; token caller không quyết định id/map trái phép.
3. Upload checkpoint xử lý all-or-nothing; count 3..8, seq, bytes/pixels, heading và source_group hợp lệ.
4. Encoder tính reference ở cùng vision worker. Nếu đang active session thì CATALOG_BUSY, không tranh GPU.
5. Inference xong mới mở DB transaction, recheck route còn draft và catalog vẫn được mutation.
6. Publish kiểm đủ 8 điều kiện trong 03, fingerprint rồi commit atomic.
7. Query device không trả draft/vector/raw image hoặc auth metadata.
8. Published route không có PATCH/DELETE; API nhận method không hỗ trợ trả 405.
9. Load route snapshot gồm references/cp/action/hash một lần khi start session.
10. Test create-session/publish race bằng lock chung catalog admission; không TOCTOU giữa RAM và DB mutation.

### Kiểm tra

```bash
uv run --project backend --extra cpu --group dev --env-file backend/config/.env pytest backend/tests/integration/test_catalog_api.py backend/tests/integration/test_route_publish.py -q
```

Các ca bắt buộc: cross-map route, seq gap, chỉ có một reference, duplicate pixel,
vector sai fingerprint/NaN/norm, ambiguous reference, checkpoint cuối không arrive,
published mutation, retry publish idempotent, rollback một ảnh lỗi, pagination cursor.

## T06 — Tracking, depth và obstacle policy

**Phụ thuộc:** T01, T04. **Gate:** obstacle portion của G1.

### File

- `core/tracking.py`, `core/depth.py`, `core/obstacles.py`.
- `tests/unit/test_tracking.py`, `test_depth.py`, `test_obstacles.py`.
- `tests/fixtures/synthetic/depth_*` nhỏ hoặc generator deterministic.

### Các bước

1. Port các phần liệt kê trong audit bằng types mới; giữ attribution BlindNav ở notice/header thích hợp.
2. Dùng mét xuyên core; conversion uint16 scale chỉ trong depth adapter.
3. Tracker IoU/one-to-one/expiry/smoothing theo 03, không import production script để lấy class.
4. Position theo vùng ảnh normalized, không dùng HFOV RealSense cho mọi camera.
5. Distance theo trimmed samples/nearest supported peak, invalid trả None.
6. Velocity từ capture delta, TTC từ range-closing; không đưa ego compensation/source IMU gate vào v1.
7. RGB heuristic chỉ notice; depth/TTC luôn null. RGB-D áp hai lớp distance+TTC và latch.
8. Depth-only center fallback áp cùng scale/calibration; không đánh unknown thành clear.
9. Bỏ playback/TTS/log-upload code khỏi module core.
10. Ghi rõ các hành vi chủ ý khác upstream trong báo cáo T06 và ca test đi kèm.

### Kiểm tra

```bash
uv run --project backend --extra cpu --group dev pytest backend/tests/unit/test_tracking.py backend/tests/unit/test_depth.py backend/tests/unit/test_obstacles.py -q
```

Pass: ca nguồn được port có ý nghĩa, mỗi thay đổi intentional có assertion riêng;
RGB không lộ số mét giả; missing/misaligned depth không giữ distance cũ;
user tiến về tường vẫn có closing speed dù tường đứng yên; warning luôn thắng guidance ở T08.
Chưa có hardware không được báo RealSense đã được kiểm thử.

