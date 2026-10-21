# Backend NAVI + BlindNav — bàn giao cục bộ

Cập nhật mới: [web mobile thử server](mobile-web.md) đã có tại
http://127.0.0.1:8095/mobile. Source/evidence của bản mới ở
`../reports/mobile-web-readiness.json`; các benchmark bên dưới thuộc snapshot
backend trước khi thêm web. Flutter vẫn chưa sửa; web dùng cùng core/API.

Ngày2026-10-21. Workspace `/home/chinhan/projects/blind-navigation-combine`.
Đọc `../reports/backend-readiness.md` trước khi tuyên bố nghiệm thu.
Code nền/core/AI/runtime/client/container đã triển khai; nghiệm thu tuyến thật
và benchmark chuẩn chưa hoàn thành. Không tự hạ điều kiện G3/G4.

## Trạng thái và bằng chứng

- G0 PASS: config/lock, PostgreSQL migration/auth/health, container CPU.
- G1 PASS: thuật toán thật với fixture độc lập, freshness/priority/isolation.
- G2 PASS: DINOv2+YOLO ONNX thật, hash/revision/parity, model smoke và public video.
- G3/G4 BLOCKED_DATA: chưa có independent pilot bundle/annotation. Public Ada
  smoke reuses cùng clip làm reference, không được nâng thành route acceptance.
- G5 NOT_RUN, RGBD_HARDWARE_NOT_EVALUATED, CUDA NOT_RUN.
- Fresh source copy + PostgreSQL rỗng:326 tests,18 subtests pass. Source/hash
  và lệnh thực tế ở build-inputs.json, verification.json, fresh-copy.json/XML.

## Bản đồ code

| Path dưới backend/ | Vai trò |
|---|---|
| src/navcore/core | Types, policy, localization, route proposals, depth/tracking/priority/câu Việt |
| src/navcore/vision | Decode/upright/limits, artifact verification, DINOv2 và YOLO ONNX |
| src/navcore/storage + migrations | PostgreSQL6 bảng, vector/fingerprint/transactions/revisions |
| src/navcore/api | Auth, catalog, session và WS admission, health/error/body limits |
| src/navcore/runtime | Session ownership, challenge/epoch/deadline, single model worker, bounded sender |
| src/navcore/cli | Bootstrap/device, models, import, prepare-video, replay, evaluate, benchmark |
| tests/unit | Pure algorithm/contract/client/worker cases; seeded data không dùng model để tạo expected |
| tests/integration | PostgreSQL thật, WS fault/isolation/cleanup, server subprocess |
| tests/model | Ba ca model thật; skip không được coi là G2 pass |
| config/exporter | Lock và môi trường export riêng, không gộp Ultralytics vào runtime |
| scripts | check.sh, source/build input recorder, local server receipt recorder |

Không sửa code upstream NAVI/BlindNav. Hai repo không còn .git theo yêu cầu trước
của người dùng; workspace chưa có Git repo. Không tự git init/commit/push/deploy.
Một writer mỗi checkout; root là integration owner của manifest/lock/migration.

## Lệnh chạy đã dùng

Tại workspace gốc. Không in/copy nội dung secret env.

```bash
uv sync --project backend --extra cpu --group dev --locked
uv run --project backend --extra cpu python -m navcore.cli bootstrap-dev
docker compose --project-name navcore-dev --env-file backend/config/.env -f backend/config/compose.yaml up -d --wait db
uv run --project backend --extra cpu --env-file backend/config/.env alembic -c backend/config/alembic.ini upgrade head
uv run --project backend --extra cpu python -m navcore.cli models-verify --model-dir backend/models
docker compose --project-name navcore-dev --env-file backend/config/.env -f backend/config/compose.yaml build api
docker compose --project-name navcore-dev --env-file backend/config/.env -f backend/config/compose.yaml up -d --wait api
curl --fail http://127.0.0.1:8095/health/ready
```

Models đã có ở máy này; server không tải weights. Trên máy mới dùng explicit
models-fetch theo runbook trước verify/start. Không tự bật CUDA/GPU Docker.
Nếu chạy native, dừng đúng API container của dự án trước để tránh trùng8095;
không dừng dịch vụ khác của người dùng.

```bash
docker compose --project-name navcore-test --env-file backend/config/.env -f backend/config/compose.test.yaml up -d --wait db
uv run --project backend --extra cpu --group dev --locked --env-file backend/config/.env bash backend/scripts/check.sh --model
```

Test DSN phải kết thúc `_test`. Không dùng dev DB làm test, không down-v hay wipe
volume. Backup/restore vào DB rỗng riêng theo runbook; receipt thực tế ở reports.

## Public video đã chuẩn bị

Nguồn: https://webdiis.unizar.es/~glopez/dataset.html — Scenario1 Ada Byron.
Dataset record: https://zenodo.org/records/6322990.

- Raw: `backend/output/public-video/zaragoza-ada/Ada.flv`.
- MP4 để xem thuận tiện: `backend/output/public-video/zaragoza-ada/ada-indoor-rgb.mp4`.
- Samples5fps: `.../frames/frames.jsonl`, source manifest và914 JPEG.
- Smoke bundle/REST import receipt: `.../smoke-bundle/`.
- Route UUID: `446ea14e-b6c4-4814-9ae4-2daaddd508aa` (chỉ DB dev máy này).
- Private device env: `backend/config/public-video-smoke.env`, mode0600.
- Final replay trace: `.../replay-final.jsonl`; stdout chỉ mô phỏng trình bày.
- Report public-video-zaragoza.{json,md} chứa số đo/source/build/server receipt.

Để chạy lại, dùng tên output mới; CLI từ chối ghi đè trace:

```bash
uv run --project backend --extra cpu --locked --env-file backend/config/public-video-smoke.env python -m navcore.cli replay --route-id 446ea14e-b6c4-4814-9ae4-2daaddd508aa --frames backend/output/public-video/zaragoza-ada/frames/frames.jsonl --output backend/output/public-video/zaragoza-ada/replay-next.jsonl --clip-id public-zaragoza-ada-smoke
```

Không chạy evaluator với nhãn do model tự sinh; không chép reference của smoke
bundle vào một manifest tự nhận independent. Không có route/perception accuracy
được đo trong public smoke này. Video download không sửa nguồn gốc, không publish.

## Các bước còn bắt buộc

1. Chuẩn bị một tuyến4 checkpoint/3 reference riêng mỗi điểm. Quay reference walk
   riêng với query. Có ít nhất1 dev,2 positive test,2 negative test độc lập.
2. Người chú giải đánh dấu cửa sổ checkpoint/rẽ/arrival,30 object frames và30 clear
   frames theo06-validation, trước khi xem output model. Mỗi PTS phải riêng.
3. Lập dataset-manifest/bundle/ground_truth theo README fixture real. Query cần
   duration_ms đo thật; source_group/split/pixel hashes phải chống leakage.
4. Route-import qua REST; prepare-video và replay từng clip qua server model thật.
   Gắn source/lock/model/policy và trace hashes bằng local server receipt. Có script
   record_server_receipt.py; đọc `--help`, dùng PID đúng instance đang xử lý.
5. Evaluate tất cả test clips. Thiếu dữ liệu exit2; fail schema/metric exit1.
   Không thay threshold sau khi nhìn test, không đổi1000ms deadline để làm pass.
6. Với route/query đủ điều kiện, chạy benchmark1 và4 device riêng,30s warmup+300s.
   Xem cờ đầy đủ ở plan05/CLI help; không chỉ chép latency inference đơn lẻ.
7. Chỉ cập nhật G3/G4 khi có bằng chứng đạt. Sau đó nhiệm vụ riêng để nối Flutter,
   TalkBack/camera/TTS/network lifecycle và thử có giám sát G5.

## Giới hạn đang tồn tại

RGB chỉ nhận vùng vật thể; distance_m/ttc_s luôn null, không báo đường an toàn.
Lost không tự khuyên tiếp tục/rẽ; muốn định vị lại cần resume. Nhắc lost mỗi5s,
movement hold vẫn liên tục. Các ngưỡng là nguyên mẫu, chưa hiệu chỉnh thực địa.

Session RAM mất sau restart. Một worker thật cho model; job treo>10s sticky
not_ready cần operator restart. Thread/GPU callable không thể bị hủy chỉ bằng
cancel await; không báo đã dừng kernel. Mạng Internet/TLS/public server chưa chạy.

Starlette TestClient hiện có deprecation warning với HTTPX đã pin; tests vẫn qua.
ORT native có thể warning telemetry ID trên home read-only; không làm ready giả.
Dung lượng /home còn thấp: đo lại disk trước cài CUDA/tải dataset lớn. Không xóa
cache/dữ liệu ngoài dự án để lấy chỗ. Model license/source release gate giữ như
THIRD_PARTY_NOTICES; hiện chỉ triển khai và kiểm tra cục bộ.


## Cập nhật đo tải CPU

Đã chạy public RGB load1/4 phiên, mỗi lượt30s warmup+300s đo.1 phiên917/917 ảnh, p95≈494ms;4 phiên956/4583 ảnh,3627 WORKER_BUSY rejects (79.1%), p95≈633ms trên ảnh được xử lý. Không stale/OOM/runtime errors được ghi nhận. Khuyến nghị1 active user trên CPU này. Đây là performance evidence riêng; các đoạn nói benchmark chưa chạy ở trên chỉ còn áp dụng nghiệm thu tuyến độc lập. Xem [báo cáo](../reports/benchmark-public-cpu-summary.md). G3/G4 vẫn BLOCKED_DATA.
