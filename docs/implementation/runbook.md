# Chạy và kiểm tra backend cục bộ

Mọi lệnh từ `/home/chinhan/projects/blind-navigation-combine`.
Chỉ dùng cổng loopback8095/55439/55440. Không dùng các container của dự án khác.
Đây là runbook nguyên mẫu; trạng thái nghiệm thu nằm trong `docs/reports/`.

## 1. Chuẩn bị

```bash
uv sync --project backend --extra cpu --group dev --locked
uv run --project backend --extra cpu python -m navcore.cli bootstrap-dev
uv pip check --python backend/.venv/bin/python
docker compose --project-name navcore-dev --env-file backend/config/.env -f backend/config/compose.yaml up -d --wait db
uv run --project backend --extra cpu --env-file backend/config/.env alembic -c backend/config/alembic.ini upgrade head
```

Bootstrap giữ nguyên secret cũ, file0600. Không chép `.env` vào report hoặc Docker.
Chỉ một profilecpu/cuda trong mỗi venv. Giữ ít nhất4GiB disk trống theo quyết định
RESOURCE-CPU-01; CUDA cần ngân sách riêng, không thay driver để chạy lệnh này.

## 2. Model

Exporter tách riêng; OpenCV có GUI chỉ có trong exporter, runtime dùng headless.

```bash
UV_PROJECT_ENVIRONMENT=/home/chinhan/projects/blind-navigation-combine/backend/.venv-export uv sync --project backend/config/exporter --locked
uv pip check --python backend/.venv-export/bin/python
uv run --project backend --extra cpu --env-file backend/config/.env python -m navcore.cli models-fetch --model-dir backend/models
uv run --project backend --extra cpu --env-file backend/config/.env python -m navcore.cli models-verify --model-dir backend/models
uv run --project backend --extra cpu --group dev --env-file backend/config/.env pytest backend/tests/model -m model -q
```

Chỉ CLI fetch tải model. Server không download/seed/migrate khi khởi động.
Manifest lưu revision/hash, cấu hình export và bằng chứng so sánh PT/ONNX.
Không sửa hash manifest để bỏ qua lỗi. Export bị ngắt có thể để lại ONNX chưa có
manifest: giữ log, xác minh nó do lần chạy này tạo trước khi xóa đúng file generated
đó rồi export lại; không xóa thư mục model hoặc checkpoint người dùng.

## 3. Server và token thiết bị

```bash
uv run --project backend --extra cpu --env-file backend/config/.env uvicorn navcore.app:create_app --factory --host 127.0.0.1 --port 8095 --workers 1 --ws-max-size 1100000
```

Terminal khác:

```bash
uv run --project backend --extra cpu --env-file backend/config/.env python -m navcore.cli device-create --name replay-01 --output-env backend/config/replay-device.env
```

CLI chỉ in UUID/expiry/path. Token trong file0600; không truyền qua `--token`/URL.
`GET /health/live` không phụ thuộc DB/model; `GET /health/ready` cần cả hai và worker
không bị sticky fault. Worker chạy>10s cần restart tiến trình sau khi lưu chẩn đoán;
không tăng workers vì state phiên nằm trong RAM. Restart làm mất phiên, giữ catalog.

## 4. Kiểm tra riêng DB test

```bash
docker compose --project-name navcore-test --env-file backend/config/.env -f backend/config/compose.test.yaml up -d --wait db
uv run --project backend --extra cpu --group dev --env-file backend/config/.env pytest backend/tests/unit backend/tests/integration -q
```

Test chỉ chấp nhận NAV_TEST_DB_URL có database kết thúc `_test`, dùng test cluster
cổng55440 và tmpfs. Không đặt DSN dev vào test. Upgrade/downgrade trong test chỉ
đụng DB test. Không chạy `down -v` trên dev, không truncate dữ liệu người dùng.

## 5. Backup/restore catalog

Đặt dump trong `backend/output/` đã ignore và giữ quyền thư mục0700/file0600.
Dump chứa reference và device-token hashes; không đính kèm issue/public report.

```bash
mkdir -p backend/output
chmod 700 backend/output
umask 077
docker compose --project-name navcore-dev --env-file backend/config/.env -f backend/config/compose.yaml exec -T db pg_dump -U navcore -d navcore --format=custom > backend/output/catalog.dump
```

Restore chỉ vào DB rỗng được tạo riêng, ví dụ `navcore_restore_test` trong test
cluster. Chạy `createdb` một lần; tên đã tồn tại phải dừng và kiểm tra, không xóa:

```bash
docker compose --project-name navcore-test --env-file backend/config/.env -f backend/config/compose.test.yaml exec -T db createdb -U navcore navcore_restore_test
docker compose --project-name navcore-test --env-file backend/config/.env -f backend/config/compose.test.yaml exec -T db pg_restore -U navcore -d navcore_restore_test --single-transaction --exit-on-error --no-owner < backend/output/catalog.dump
```

So sánh schema/table counts/fingerprints với nguồn. Không dùng `--clean`, không
restore đè dev. Bản dump test chỉ chứng minh khả năng phục hồi trong môi trường đó.

## 6. Container CPU

```bash
docker compose --project-name navcore-dev --env-file backend/config/.env -f backend/config/compose.yaml build api
docker compose --project-name navcore-dev --env-file backend/config/.env -f backend/config/compose.yaml up -d --wait api
```

Build context chỉ backend; `.dockerignore` allowlist source/lock, loại secret,
weights/captures/exporter. Models mount read-only, API UID10001, rootfs read-only,
không capability, port chỉ loopback. Model đã có trước build/start; migration riêng.
Docker CPU readiness phải kiểm tra thực tế, compose config hợp lệ chưa đủ nghiệm thu.

## 7. Dữ liệu và bước tiếp theo

Importer/replay/evaluator/benchmark đọc `--help` để lấy cờ đầy đủ. Trước nghiệm thu
G3 cần bộ pilot độc lập theo06-validation; clip9s trong BlindNav chỉ là smoke.
Không dùng synthetic làm bằng chứng AI đã dẫn đúng đường. Sau G4 mới nối Flutter
qua device-client-contract; chưa có kiểm tra camera/TTS/calibration phần cứng G5.
