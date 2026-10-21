# Backend readiness —2026-10-21

Backend đã triển khai và kiểm tra cục bộ ở CPU. Toàn bộ mục tiêu dẫn đường chưa nghiệm thu xong.

| Gate | Trạng thái | Bằng chứng |
|---|---|---|
| G0 | PASS | Locked dependencies, PostgreSQL/auth/health, container thật |
| G1 | PASS |326 tests+18 subtests, thuật toán thật/fixture độc lập, deadline/isolation/faults |
| G2 | PASS | Local model hashes/revision/export parity, model tests, ảnh/video thật qua pipeline |
| G3 | BLOCKED_DATA | Thiếu independent reference/query pilot và human ground truth |
| G4 | BLOCKED_DATA | Phụ thuộc G3; đã đo tải1/4 phiên với video public; chưa có nghiệm thu tuyến độc lập |
| G5 | NOT_RUN | Chưa nối app/camera/TTS và thử có giám sát |

[Kết quả JSON](backend-readiness.json), [đối chiếu yêu cầu](requirements-matrix.md), [handoff và lệnh chạy](../implementation/agent-handoff.md).

Fresh source copy đúng hash + PostgreSQL mới rỗng:326 pass,18 subtests,0 fail/skip. Các check lint/format/lock/runtime+exporter dependencies đều exit0. Một deprecation warning của Starlette TestClient được giữ nguyên. [Receipt kiểm tra](verification.json), [JUnit](fresh-copy-tests.xml), [fresh-copy receipt](fresh-copy.json).

Container CPU UID10001, rootfs/models read-only, ready200; byte hashes source/lock trùng checkout. Restart giữ catalog, phiên RAM trước restart404. [Container receipt](container-final.json). Backup/restore test kiểm6 bảng và row hashes: [receipt](backup-restore.json). Cleanup50 warmup+500 phiên: [RSS receipt](cleanup-rss.json).

Public Ada Byron video182.753s đã tải và chuẩn bị914 samples5fps. Final replay nhận489 kết quả từ490 requests; một request ở lúc video kết thúc không có result. Stale presentations0; latency p95≈618ms chỉ cho lần smoke này. Backend chỉ xác nhận điểm0 rồi vào lost; không khẳng định hoàn thành tuyến. [Video report](public-video-zaragoza.md).

## Phần chưa được kiểm chứng

Không có accuracy hoặc precision/recall được gán0 thay cho chưa đo. Public smoke dùng cùng clip làm reference/query và action placeholder, nên bị loại khỏi G3. [Missing-data CLI thực tế exit2](pilot-missing-final/command-receipt.json). [Đã đo CPU1/4 phiên30+300s](benchmark-public-cpu-summary.md);1 phiên đạt độ trễ,4 phiên reject79.1% vì worker bận.

RGB-D hardware/calibration, CUDA/VRAM, camera/TTS/app/TalkBack và supervised trials đều chưa kiểm. Không có public server/TLS/release. Worker thật treo>10s cần operator restart; cancel await không hủy callable/GPU kernel.

## Danh tính bản chạy

Source SHA256: `e3f00d6f727378bfd8cbade748418f78813d917190a78042af900d73e877786c`.
Lock SHA256: `e5237ceae0a978461b5506a176913b47fd3f282cca9e089d530e97515958613c`.
Model manifest SHA256: `4d0c48ad5902221d9bae9e50be21b232eacbfc313ce55b0d669b54eb7d63cac7`.
Policy SHA256: `fa3f3c2d70be7d49bbedf5f85f48966500d585886473ceee1913c3ebff54c8a2`.

[Exact source-file map/packages](build-inputs.json); [OpenAPI](contracts/openapi.json), [WS schema](contracts/websocket.json), [policy](contracts/policy.json), [public model manifest](contracts/models.json). WS envelopes chưa typed được transcribe từ runtime và được ghi rõ provenance.

Các report container-foundation-smoke, cpu-thread-profile, verification-tests và fresh-copy-initial là bằng chứng trung gian hoặc diagnostic khác nguồn; không tái sử dụng làm final acceptance. Fresh-copy-initial giữ lần thất bại trước khi sửa interpreter path/cancellation.

Bước tiếp theo: bộ pilot theo plan06 với reference walk riêng,1 dev+2 positive+2 negative, human labels và30 object/30 clear samples; import/replay/evaluate rồi đối chiếu lại benchmark với workload tuyến độc lập. Giữ mục tiêu chưa hoàn thành cho đến khi có các bằng chứng còn thiếu.
