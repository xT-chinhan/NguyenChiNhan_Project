# 07 — Dependency, cấu hình, chạy server và app tương lai

## 1. Baseline dependency cho T00

Đã kiểm tra PyPI metadata ngày 2026-10-21; baseline bên dưới chưa được resolve/install cùng nhau.
Đây là input của T00, không phải lockfile đã kiểm thử. Agent phải tạo uv.lock và chạy pip check.
Không đưa requirements cũ vào cùng môi trường để “đỡ thiếu package”.

| Runtime dependency | Pin |
|---|---|
| fastapi | 0.156.4 |
| pydantic | 2.14.1 |
| uvicorn[standard] | 0.54.0 |
| python-multipart | 0.0.32 |
| Pillow | 13.0.0 |
| numpy | 1.26.4 |
| opencv-python-headless | 4.11.0.86 |
| transformers | 4.56.0 |
| onnxruntime | 1.31.0 |
| SQLAlchemy | 2.1.5 |
| psycopg[binary] | 3.3.6 |
| alembic | 1.20.0 |
| httpx | 0.28.1 |
| websockets | 17.3 |

CPU extra: `torch==2.13.0`, `torchvision==0.28.0` từ PyTorch CPU index.
CUDA extra: cùng cặp version, từ cu126 index. Chỉ chọn một extra trong một môi trường.
Dev: pytest9.1.1, pytest-asyncio1.4.0, Ruff0.17.1.
Build system: setuptools84.2.1, `setuptools.build_meta`, tự tìm package dưới src/.
WebSocket client dùng dependency websockets trực tiếp đã pin, không dựa transitives ngầm.

Model exporter là môi trường riêng:
- Ultralytics8.4.183, onnx1.23.2; torch/torchvision theo cặp đã chọn.
- Không đưa `ultralytics`, `opencv-python`, SDK Pi/RealSense, diffusers, SAM, OpenAI/Anthropic vào runtime.
- Export manifest ghi đủ phiên bản transitive; nếu exporter cần package khác, khai báo/lock ở tool group riêng.

Nguồn đối chiếu:
- [PyTorch official previous versions](https://pytorch.org/get-started/previous-versions/).
- [uv PyTorch indexes/extras](https://docs.astral.sh/uv/guides/integration/pytorch/).
- [FastAPI WebSocket](https://fastapi.tiangolo.com/advanced/websockets/).
- [YOLO ONNX](https://docs.ultralytics.com/integrations/onnx/).

### Cấu hình uv cụ thể

- Python requires `>=3.12,<3.13`.
- Optional dependency cpu và cuda mỗi cái khai báo torch2.13.0/torchvision0.28.0.
- `tool.uv.conflicts = [[{extra="cpu"},{extra="cuda"}]]`.
- Hai `[[tool.uv.index]]`: pytorch-cpu URL `https://download.pytorch.org/whl/cpu`,
  pytorch-cu126 URL `https://download.pytorch.org/whl/cu126`; cả hai `explicit=true`.
- `[tool.uv.sources]` torch và torchvision mỗi package có hai entry index+extra tương ứng.
- Package thông thường chỉ từ PyPI; không bật unsafe-best-match trên mọi dependency.
- CPU/CUDA cùng một lock với extras mutually exclusive; `uv sync --locked --extra cpu` là mặc định.
- CI chỉ Linux x86_64 Python3.12 v1; không thêm Windows/ARM/macOS support trong T00.
- Nếu resolve pair/index không tồn tại: ghi exact lỗi T00; không tự chọn CUDA13 cần driver khác.

Không thay host Python/driver hoặc install global pip. Mọi package trong backend/.venv.
CUDA6GiB là tài nguyên quan sát được, chưa đo đủ VRAM; CPU luôn là đường kiểm tra chức năng.

## 2. Environment variables

T00 tạo `.env.example` với tên biến + placeholder, không credential dùng được.
`backend/config/.env` do bootstrap cục bộ tạo bằng secrets, không đưa vào image/report.
PostgreSQL dev password và admin token sinh ngẫu nhiên; không dùng user/password demo hardcode trong code.

| Biến | Giá trị / ý nghĩa |
|---|---|
| NAV_ENV | development hoặc test; không tự bật public deployment |
| NAV_API_URL | http://127.0.0.1:8095 cho CLI |
| NAV_DB_URL | postgresql+psycopg://navcore:<generated>@127.0.0.1:55439/navcore |
| NAV_TEST_DB_URL | postgresql+psycopg://navcore:<generated>@127.0.0.1:55440/navcore_test |
| POSTGRES_USER | navcore |
| POSTGRES_PASSWORD | generated random |
| POSTGRES_DB | navcore |
| NAV_ADMIN_TOKEN | generated random>=32 chars |
| NAV_DEVICE_TOKEN | client dùng token CLI tạo; không cần trong server process |
| NAV_MODEL_DIR | absolute path tới backend/models |
| NAV_VISION_DEVICE | cpu hoặc cuda:0; mặc định cpu |
| NAV_LOG_LEVEL | DEBUG trong development theo yêu cầu local; INFO khi nghiệm thu latency |
| NAV_HTTP_HOST / NAV_HTTP_PORT | 127.0.0.1 / 8095 |

Policy thresholds ở frozen config code theo03; v1 không thêm env override cho mỗi ngưỡng.
Evaluator nhận file policy JSON validated để chạy experiment riêng, server runtime dùng baseline đã chốt.
Nếu sửa baseline cần cập nhật fingerprint/report, không dùng experiment để thay runtime âm thầm.

Device token không truyền bằng query string hoặc --token vì URL/process listing/log có thể lộ.
Không copy `.env`/hardcoded URL/key của NAVI vào backend mới.

## 3. Bootstrap được T00 tạo

Agent tạo CLI `bootstrap-dev` trong `cli/bootstrap.py` ngay T00:
- Chỉ tạo backend/config/.env nếu chưa tồn tại; file mode0600.
- Dùng secrets sinh DB password, admin token; ghi env với định dạng uv đọc được.
- Không in nội dung secret; chỉ in đường dẫn file đã tạo.
- Nếu file tồn tại: kiểm trường bắt buộc, không ghi đè/rotate secret tự động.
- NAV_MODEL_DIR resolve absolute trong dự án; không chọn thư mục người dùng khác.
- Không khởi động Docker/network service trong bootstrap; làm theo lệnh riêng bên dưới.

## 4. Lệnh chạy dev sau khi triển khai

Từ thư mục gốc dự án:

```bash
uv sync --project backend --extra cpu --group dev --locked
uv run --project backend --extra cpu python -m navcore.cli bootstrap-dev
docker compose --project-name navcore-dev --env-file backend/config/.env -f backend/config/compose.yaml up -d db
uv run --project backend --extra cpu --env-file backend/config/.env alembic -c backend/config/alembic.ini upgrade head
uv run --project backend --extra cpu --env-file backend/config/.env python -m navcore.cli models-fetch --model-dir backend/models
uv run --project backend --extra cpu --env-file backend/config/.env python -m navcore.cli models-verify --model-dir backend/models
uv run --project backend --extra cpu --env-file backend/config/.env uvicorn navcore.app:create_app --factory --host 127.0.0.1 --port 8095 --workers 1 --ws-max-size 1100000
```

Terminal khác sau khi ready:

```bash
uv run --project backend --extra cpu --env-file backend/config/.env python -m navcore.cli device-create --name replay-01 --output-env backend/config/replay-device.env
```

CLI ghi NAV_DEVICE_TOKEN/NAV_API_URL vào replay-device.env mode0600, không in token.
CLI replay đọc file client riêng qua uv --env-file; CLI admin/import đọc NAV_ADMIN_TOKEN.
Các CLI chỉ load settings mình cần: replay không được yêu cầu DB URL, admin token hay model dir.
CLI benchmark đọc nhiều file env client; không load server settings hoặc dùng chung một token cho4 phiên.

Mỗi lệnh độc lập; không giấu lỗi bằng `|| true`.
App lifespan reject cấu hình worker_count khác1 vì session RAM và model slot thuộc process.
Uvicorn multi-worker chưa được hỗ trợ; không tăng workers để chữa tắc inference.

### CUDA profile

```bash
uv sync --project backend --extra cuda --group dev --locked
```

Set NAV_VISION_DEVICE=cuda:0 ở file env cục bộ đã chọn, xác minh torch.cuda available và model smoke.
Chạy app/CLI với `--extra cuda` thay cpu. Không trộn timing trước/sau sync vào cùng report.
Không tự đổi profile vì gặp CUDA error; startup/report phải phản ánh lỗi thật.

## 5. Compose và container

- Compose config ở backend/config; build context phải trỏ đúng backend/, không đưa cả home vào context.
- Service db dùng PostgreSQL16-alpine; T00/T12 resolve image digest vào build receipt.
- Service api dùng image build từ Dockerfile, non-root, chỉ bind 127.0.0.1:8095.
- Trong network compose DB hostname là db:5432, không dùng localhost:55439.
  Compose override NAV_DB_URL tương ứng container, không đổi env host cho CLI.
- Model artifacts mount read-only; không download trong Docker build để tránh artifact thay đổi ngầm.
- Dev data volume riêng `navcore-dev-db`; test tmpfs/volume `navcore-test-db` riêng.
- compose.test override POSTGRES_DB=navcore_test dù .env host đang đặt POSTGRES_DB=navcore.
- Không `down -v` hoặc xóa volume dev; runbook backup bằng pg_dump, restore test DB rỗng.
- Container Python base `python:3.12-slim-bookworm`, resolve digest và ghi lại trong receipt.
- Image và package pin là input build, không phải lời khẳng định đã security-audit toàn bộ dependency.
- Không tự public/push image hoặc cài GPU container toolkit vào host.

## 6. Quan sát hệ thống

Structured log các sự kiện:
startup/model_load/readiness/session_create/frame_requested/frame_rejected/inference_complete/
checkpoint_confirmed/instruction_created/session_paused/token_revoked/session_stopped/shutdown.

Fields tối thiểu: timestamp UTC, request_id khi có, session UUID, frame seq, code,
state trước/sau, epoch, stage timings. Không log toàn bộ embedding/ảnh/depth/token.
DEBUG có thể thêm score/margin/track count đã ẩn danh; không dùng print base64 để debug.
Health ready false khi DB/models/worker fault; log nội bộ có reason, public response chỉ not_ready.

Report metrics tổng hợp ra JSON, chưa cần Prometheus/Grafana stack cho v1.
Số liệu bắt buộc xem06: latency phân vị, reject/expire, concurrency thực, loop lag, RSS/VRAM.

## 7. App tương lai phải làm chính xác những gì

Đây là hợp đồng bàn giao, chưa phải task sửa Flutter:

1. Chọn map/điểm đầu/điểm đích, lấy routes published và tạo session.
2. Kết nối WSS với Authorization header khi có endpoint TLS được triển khai riêng.
3. Camera preview giữ tại thiết bị; chỉ gửi JPEG mới sau capture_request, không gửi video vô hạn.
4. Chuẩn hóa upright pixels, giữ timestamp monotonic và không reuse ảnh cache cũ.
5. Nhận frame_result, hiển thị trạng thái đơn giản, đọc text_vi bằng local TTS vi-VN.
6. Dedupe instruction IDs; bỏ hướng dẫn quá hạn theo cả capture_age và valid_for_ms.
7. Emergency/warning mới invalidate pending guidance; không để câu “đi tiếp” chờ sau câu dừng.
8. Watchdog client: 1500ms không có fresh frame_result thì hủy pending movement,
   đọc một lần “Đã mất kết nối hoặc hình ảnh mới. Hướng dẫn đang tạm dừng.” và báo rung.
9. Heartbeat còn tới không reset watchdog freshness của frame_result.
10. Nút/voice controls tối thiểu: pause, resume, repeat, stop; hỗ trợ TalkBack.
11. Reconnect không dùng lại instruction cũ; resume backend định vị lại vùng cho phép.
12. Local TTS/rung hoạt động khi mạng mất; mất mạng không được coi là tiếp tục có dẫn đường.
13. Nếu camera RGB thường, UI không hiển thị mét/TTC giả và không quảng bá tự tránh va chạm.
14. Pi/RealSense client riêng phải gửi depth aligned và calibration theo02; backend không tự giả depth.

Chưa chuyển toàn bộ Supabase auth/UI NAVI sang backend trong T00–T13.
Agent làm app sau này phải grep mọi caller của ClipService/RealTimeNavigationService trước thay,
thay logic bằng hợp đồng client này rồi kiểm tra mic/camera/compass/TTS/foreground lifecycle trên máy thật.

## 8. Điều kiện ra ngoài môi trường dev

Giai đoạn này chỉ chuẩn bị artifact/runbook cục bộ.
Trước thử có người dùng thật cần nhiệm vụ riêng cho thiết bị, mạng thực, calibration và audio;
trước public server cần TLS, token provisioning/rotation và cấu hình host/network được cấp phép.
NAVI license thiếu bản rõ ràng và model Ultralytics có điều kiện riêng phải được xử lý ở release gate.
Không thêm thanh toán, thuê cloud, phát hành app hay công bố source chỉ từ plan backend này.

