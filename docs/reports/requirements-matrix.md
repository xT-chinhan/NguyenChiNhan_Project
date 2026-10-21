# Đối chiếu yêu cầu cuối

Ngày2026-10-21. Source cuối ở build-inputs.json. `VALIDATED` chỉ nghĩa code/hành vi trong test scope có bằng chứng, không tự cấp G3/G4 hoặc chứng nhận an toàn.
Bằng chứng tổng: fresh-copy-tests.xml —326 pass+18 subtests; verification.json; model-smoke.json; container-final.json. Các test tương đối backend/tests/unit hoặc integration như tên file.

| Yêu cầu | Kết luận | Bằng chứng / phạm vi |
|---|---|---|
| T00.01 | VALIDATED | [T00.md](../implementation/T00.md); test_settings.py |
| T00.02 | ADAPTED_RESOURCE_CPU_01 | [T00.md](../implementation/T00.md); test_settings.py |
| T00.03 | VALIDATED | [T00.md](../implementation/T00.md); test_settings.py |
| T00.04 | VALIDATED | [T00.md](../implementation/T00.md); test_settings.py |
| T00.05 | VALIDATED | [T00.md](../implementation/T00.md); test_settings.py |
| T00.06 | VALIDATED | [T00.md](../implementation/T00.md); test_settings.py |
| T00.07 | VALIDATED | [T00.md](../implementation/T00.md); test_settings.py |
| T00.08 | VALIDATED | [T00.md](../implementation/T00.md); test_settings.py |
| T00.09 | VALIDATED | [T00.md](../implementation/T00.md); test_settings.py |
| T00.10 | VALIDATED | [T00.md](../implementation/T00.md); test_settings.py |
| T00.11 | VALIDATED | [T00.md](../implementation/T00.md); test_settings.py |
| T00.12 | VALIDATED | [T00.md](../implementation/T00.md); test_settings.py |
| T00 scope | Package/source audit, resource check, lock, import/config/logging, notices, receipt, bootstrap | Xem bước đánh số trong plan04/05 và receipt tương ứng |
| T01.01 | VALIDATED | [T01.md](../implementation/T01.md); test_contracts.py; test_fixture_integrity.py |
| T01.02 | VALIDATED | [T01.md](../implementation/T01.md); test_contracts.py; test_fixture_integrity.py |
| T01.03 | VALIDATED | [T01.md](../implementation/T01.md); test_contracts.py; test_fixture_integrity.py |
| T01.04 | VALIDATED | [T01.md](../implementation/T01.md); test_contracts.py; test_fixture_integrity.py |
| T01.05 | VALIDATED | [T01.md](../implementation/T01.md); test_contracts.py; test_fixture_integrity.py |
| T01.06 | VALIDATED | [T01.md](../implementation/T01.md); test_contracts.py; test_fixture_integrity.py |
| T01.07 | VALIDATED | [T01.md](../implementation/T01.md); test_contracts.py; test_fixture_integrity.py |
| T01.08 | VALIDATED | [T01.md](../implementation/T01.md); test_contracts.py; test_fixture_integrity.py |
| T01.09 | VALIDATED | [T01.md](../implementation/T01.md); test_contracts.py; test_fixture_integrity.py |
| T01.10 | VALIDATED | [T01.md](../implementation/T01.md); test_contracts.py; test_fixture_integrity.py |
| T01 scope | Types/strict schema, null metrics, seeded4-checkpoint fixture, independent expected events | Xem bước đánh số trong plan04/05 và receipt tương ứng |
| T02.01 | VALIDATED | [T02.md](../implementation/T02.md); test_migrations.py; test_catalog_storage.py |
| T02.02 | VALIDATED | [T02.md](../implementation/T02.md); test_migrations.py; test_catalog_storage.py |
| T02.03 | VALIDATED | [T02.md](../implementation/T02.md); test_migrations.py; test_catalog_storage.py |
| T02.04 | VALIDATED | [T02.md](../implementation/T02.md); test_migrations.py; test_catalog_storage.py |
| T02.05 | VALIDATED | [T02.md](../implementation/T02.md); test_migrations.py; test_catalog_storage.py |
| T02.06 | VALIDATED | [T02.md](../implementation/T02.md); test_migrations.py; test_catalog_storage.py |
| T02.07 | VALIDATED | [T02.md](../implementation/T02.md); test_migrations.py; test_catalog_storage.py |
| T02.08 | VALIDATED | [T02.md](../implementation/T02.md); test_migrations.py; test_catalog_storage.py |
| T02.09 | VALIDATED | [T02.md](../implementation/T02.md); test_migrations.py; test_catalog_storage.py |
| T02.10 | VALIDATED | [T02.md](../implementation/T02.md); test_migrations.py; test_catalog_storage.py |
| T02 scope | Six tables, cross-map FK, pool/transactions, snapshots, f4 vectors, isolated DB, migration, revision lock | Xem bước đánh số trong plan04/05 và receipt tương ứng |
| T03.01 | VALIDATED | [T03.md](../implementation/T03.md); test_auth.py; test_errors.py; test_health.py |
| T03.02 | VALIDATED | [T03.md](../implementation/T03.md); test_auth.py; test_errors.py; test_health.py |
| T03.03 | VALIDATED | [T03.md](../implementation/T03.md); test_auth.py; test_errors.py; test_health.py |
| T03.04 | VALIDATED | [T03.md](../implementation/T03.md); test_auth.py; test_errors.py; test_health.py |
| T03.05 | VALIDATED | [T03.md](../implementation/T03.md); test_auth.py; test_errors.py; test_health.py |
| T03.06 | VALIDATED | [T03.md](../implementation/T03.md); test_auth.py; test_errors.py; test_health.py |
| T03.07 | VALIDATED | [T03.md](../implementation/T03.md); test_auth.py; test_errors.py; test_health.py |
| T03.08 | VALIDATED | [T03.md](../implementation/T03.md); test_auth.py; test_errors.py; test_health.py |
| T03.09 | VALIDATED | [T03.md](../implementation/T03.md); test_auth.py; test_errors.py; test_health.py |
| T03.10 | VALIDATED | [T03.md](../implementation/T03.md); test_auth.py; test_errors.py; test_health.py |
| T03 scope | Roles/token hash/expiry/revoke, private CLI files, envelope/redaction, health, CORS, body cap, not-ready metadata | Xem bước đánh số trong plan04/05 và receipt tương ứng |
| T04-prep.01 | VALIDATED | [T04.md](../implementation/T04.md); test_export_parity.py; test_receipts.py |
| T04-prep.02 | VALIDATED | [T04.md](../implementation/T04.md); test_export_parity.py; test_receipts.py |
| T04-prep.03 | VALIDATED | [T04.md](../implementation/T04.md); test_export_parity.py; test_receipts.py |
| T04-prep.04 | VALIDATED | [T04.md](../implementation/T04.md); test_export_parity.py; test_receipts.py |
| T04-prep.05 | VALIDATED | [T04.md](../implementation/T04.md); test_export_parity.py; test_receipts.py |
| T04-prep.06 | VALIDATED_WITH_DOCUMENTED_TOPK_TIES | [T04.md](../implementation/T04.md); test_export_parity.py; test_receipts.py |
| T04-prep.07 | VALIDATED | [T04.md](../implementation/T04.md); test_export_parity.py; test_receipts.py |
| T04-prep.08 | VALIDATED | [T04.md](../implementation/T04.md); test_export_parity.py; test_receipts.py |
| T04-prep.09 | VALIDATED | [T04.md](../implementation/T04.md); test_export_parity.py; test_receipts.py |
| T04-prep scope | Explicit fetch, pinned DINO revision/YOLO hash, separate export, shapes/parity/manifest/fingerprint, safe local runtime files | Xem bước đánh số trong plan04/05 và receipt tương ứng |
| T04-runtime.01 | VALIDATED | [T04.md](../implementation/T04.md); tests/model/*; test_worker.py |
| T04-runtime.02 | VALIDATED | [T04.md](../implementation/T04.md); tests/model/*; test_worker.py |
| T04-runtime.03 | VALIDATED | [T04.md](../implementation/T04.md); tests/model/*; test_worker.py |
| T04-runtime.04 | VALIDATED | [T04.md](../implementation/T04.md); tests/model/*; test_worker.py |
| T04-runtime.05 | VALIDATED | [T04.md](../implementation/T04.md); tests/model/*; test_worker.py |
| T04-runtime.06 | VALIDATED | [T04.md](../implementation/T04.md); tests/model/*; test_worker.py |
| T04-runtime.07 | VALIDATED | [T04.md](../implementation/T04.md); tests/model/*; test_worker.py |
| T04-runtime scope | Local hash/warmup, explicit device, off-loop single real job, typed result, cancellation retains slot, verify CLI | Xem bước đánh số trong plan04/05 và receipt tương ứng |
| T05.01 | VALIDATED | [T05.md](../implementation/T05.md); test_catalog_api.py; test_route_publish.py; test_admission.py |
| T05.02 | VALIDATED | [T05.md](../implementation/T05.md); test_catalog_api.py; test_route_publish.py; test_admission.py |
| T05.03 | VALIDATED | [T05.md](../implementation/T05.md); test_catalog_api.py; test_route_publish.py; test_admission.py |
| T05.04 | VALIDATED | [T05.md](../implementation/T05.md); test_catalog_api.py; test_route_publish.py; test_admission.py |
| T05.05 | VALIDATED | [T05.md](../implementation/T05.md); test_catalog_api.py; test_route_publish.py; test_admission.py |
| T05.06 | VALIDATED | [T05.md](../implementation/T05.md); test_catalog_api.py; test_route_publish.py; test_admission.py |
| T05.07 | VALIDATED | [T05.md](../implementation/T05.md); test_catalog_api.py; test_route_publish.py; test_admission.py |
| T05.08 | VALIDATED | [T05.md](../implementation/T05.md); test_catalog_api.py; test_route_publish.py; test_admission.py |
| T05.09 | VALIDATED | [T05.md](../implementation/T05.md); test_catalog_api.py; test_route_publish.py; test_admission.py |
| T05.10 | VALIDATED | [T05.md](../implementation/T05.md); test_catalog_api.py; test_route_publish.py; test_admission.py |
| T05 scope | REST, canonical names/UUID/revision, atomic refs, worker/admission, publish checks, safe queries, immutable route, snapshots/races | Xem bước đánh số trong plan04/05 và receipt tương ứng |
| T06.01 | VALIDATED | [T06.md](../implementation/T06.md); test_tracking.py; test_depth.py; test_obstacles.py; test_obstacle_priority.py |
| T06.02 | VALIDATED | [T06.md](../implementation/T06.md); test_tracking.py; test_depth.py; test_obstacles.py; test_obstacle_priority.py |
| T06.03 | VALIDATED | [T06.md](../implementation/T06.md); test_tracking.py; test_depth.py; test_obstacles.py; test_obstacle_priority.py |
| T06.04 | VALIDATED | [T06.md](../implementation/T06.md); test_tracking.py; test_depth.py; test_obstacles.py; test_obstacle_priority.py |
| T06.05 | VALIDATED | [T06.md](../implementation/T06.md); test_tracking.py; test_depth.py; test_obstacles.py; test_obstacle_priority.py |
| T06.06 | VALIDATED | [T06.md](../implementation/T06.md); test_tracking.py; test_depth.py; test_obstacles.py; test_obstacle_priority.py |
| T06.07 | VALIDATED | [T06.md](../implementation/T06.md); test_tracking.py; test_depth.py; test_obstacles.py; test_obstacle_priority.py |
| T06.08 | VALIDATED | [T06.md](../implementation/T06.md); test_tracking.py; test_depth.py; test_obstacles.py; test_obstacle_priority.py |
| T06.09 | VALIDATED | [T06.md](../implementation/T06.md); test_tracking.py; test_depth.py; test_obstacles.py; test_obstacle_priority.py |
| T06.10 | VALIDATED | [T06.md](../implementation/T06.md); test_tracking.py; test_depth.py; test_obstacles.py; test_obstacle_priority.py |
| T06 scope | Adapted tracking, metres/scale, one-to-one expiry, image zones, nearest peak, closing/TTC, RGB nulls/RGBD latch, center fallback, pure core | Xem bước đánh số trong plan04/05 và receipt tương ứng |
| T07.01 | VALIDATED | [T07.md](../implementation/T07.md); test_localization.py; test_navigation.py |
| T07.02 | VALIDATED | [T07.md](../implementation/T07.md); test_localization.py; test_navigation.py |
| T07.03 | ADAPTED_PURE_BOUNDARY | [T07.md](../implementation/T07.md); test_localization.py; test_navigation.py |
| T07.04 | VALIDATED | [T07.md](../implementation/T07.md); test_localization.py; test_navigation.py |
| T07.05 | VALIDATED | [T07.md](../implementation/T07.md); test_localization.py; test_navigation.py |
| T07.06 | VALIDATED | [T07.md](../implementation/T07.md); test_localization.py; test_navigation.py |
| T07.07 | VALIDATED | [T07.md](../implementation/T07.md); test_localization.py; test_navigation.py |
| T07.08 | VALIDATED | [T07.md](../implementation/T07.md); test_localization.py; test_navigation.py |
| T07.09 | VALIDATED | [T07.md](../implementation/T07.md); test_localization.py; test_navigation.py |
| T07.10 | VALIDATED | [T07.md](../implementation/T07.md); test_localization.py; test_navigation.py |
| T07 scope | Top2 median/cosine/margin, heading/allowed seq, pure proposals,3 unique frames, action semantics, state machine, resume bounds, fake clock, arrival arbitration | Xem bước đánh số trong plan04/05 và receipt tương ứng |
| T08.01 | VALIDATED | [T08.md](../implementation/T08.md); test_decisions.py; test_messages.py; test_runtime_instructions.py |
| T08.02 | VALIDATED | [T08.md](../implementation/T08.md); test_decisions.py; test_messages.py; test_runtime_instructions.py |
| T08.03 | VALIDATED | [T08.md](../implementation/T08.md); test_decisions.py; test_messages.py; test_runtime_instructions.py |
| T08.04 | VALIDATED | [T08.md](../implementation/T08.md); test_decisions.py; test_messages.py; test_runtime_instructions.py |
| T08.05 | VALIDATED | [T08.md](../implementation/T08.md); test_decisions.py; test_messages.py; test_runtime_instructions.py |
| T08.06 | VALIDATED | [T08.md](../implementation/T08.md); test_decisions.py; test_messages.py; test_runtime_instructions.py |
| T08.07 | VALIDATED | [T08.md](../implementation/T08.md); test_decisions.py; test_messages.py; test_runtime_instructions.py |
| T08.08 | VALIDATED | [T08.md](../implementation/T08.md); test_decisions.py; test_messages.py; test_runtime_instructions.py |
| T08.09 | VALIDATED | [T08.md](../implementation/T08.md); test_decisions.py; test_messages.py; test_runtime_instructions.py |
| T08.10 | VALIDATED | [T08.md](../implementation/T08.md); test_decisions.py; test_messages.py; test_runtime_instructions.py |
| T08 scope | Single priority decision, cloned next state, holds/cooldowns, Vietnamese codes, bounded instruction identity/TTL, arrival hold, repeat and ACK | Xem bước đánh số trong plan04/05 và receipt tương ứng |
| T09-create.01 | VALIDATED | [T09.md](../implementation/T09.md); test_sessions.py; test_limits.py; test_runtime_postgres.py; test_restart.py |
| T09-create.02 | VALIDATED | [T09.md](../implementation/T09.md); test_sessions.py; test_limits.py; test_runtime_postgres.py; test_restart.py |
| T09-create.03 | VALIDATED | [T09.md](../implementation/T09.md); test_sessions.py; test_limits.py; test_runtime_postgres.py; test_restart.py |
| T09-create.04 | VALIDATED | [T09.md](../implementation/T09.md); test_sessions.py; test_limits.py; test_runtime_postgres.py; test_restart.py |
| T09-create.05 | VALIDATED | [T09.md](../implementation/T09.md); test_sessions.py; test_limits.py; test_runtime_postgres.py; test_restart.py |
| T09-create.06 | VALIDATED | [T09.md](../implementation/T09.md); test_sessions.py; test_limits.py; test_runtime_postgres.py; test_restart.py |
| T09-create.07 | VALIDATED | [T09.md](../implementation/T09.md); test_sessions.py; test_limits.py; test_runtime_postgres.py; test_restart.py |
| T09-create.08 | VALIDATED | [T09.md](../implementation/T09.md); test_sessions.py; test_limits.py; test_runtime_postgres.py; test_restart.py |
| T09-create scope | Shared admission, auth/capacity/fingerprint, off-loop DB snapshot, per-session state, immutable shared models, ownership/tombstone, restart | Xem bước đánh số trong plan04/05 và receipt tương ứng |
| T09-stream.01 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.02 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.03 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.04 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.05 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.06 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.07 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.08 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.09 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.10 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.11 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.12 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.13 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.14 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.15 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.16 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.17 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream.18 | VALIDATED | [T09.md](../implementation/T09.md); test_stream.py; test_freshness.py; test_runtime_freshness.py; test_runtime_output.py; test_stream_cancellation.py |
| T09-stream scope | Preaccept auth, connect/welcome, challenge, one consumption, strict decode,100ms slot, worker observation, final guard, no stale mutation, staged clone, watchdog, real-call concurrency, queue8,250ms sender, heartbeat, revoke, controls, loop liveness | Xem bước đánh số trong plan04/05 và receipt tương ứng |
| T10-import.01 | VALIDATED | [T10.md](../implementation/T10.md); test_route_bundle.py |
| T10-import.02 | VALIDATED | [T10.md](../implementation/T10.md); test_route_bundle.py |
| T10-import.03 | VALIDATED | [T10.md](../implementation/T10.md); test_route_bundle.py |
| T10-import.04 | VALIDATED | [T10.md](../implementation/T10.md); test_route_bundle.py |
| T10-import.05 | VALIDATED | [T10.md](../implementation/T10.md); test_route_bundle.py |
| T10-import.06 | VALIDATED | [T10.md](../implementation/T10.md); test_route_bundle.py |
| T10-import scope | Confined explicit bundle, admin REST, no direct DB, private env, partial draft receipt, no scan of personal media | Xem bước đánh số trong plan04/05 và receipt tương ứng |
| T10-replay.01 | VALIDATED | [T10.md](../implementation/T10.md); test_video.py; test_replay.py; test_replay_client.py; test_replay_paused.py |
| T10-replay.02 | VALIDATED | [T10.md](../implementation/T10.md); test_video.py; test_replay.py; test_replay_client.py; test_replay_paused.py |
| T10-replay.03 | VALIDATED | [T10.md](../implementation/T10.md); test_video.py; test_replay.py; test_replay_client.py; test_replay_paused.py |
| T10-replay.04 | VALIDATED | [T10.md](../implementation/T10.md); test_video.py; test_replay.py; test_replay_client.py; test_replay_paused.py |
| T10-replay.05 | VALIDATED | [T10.md](../implementation/T10.md); test_video.py; test_replay.py; test_replay_client.py; test_replay_paused.py |
| T10-replay.06 | VALIDATED | [T10.md](../implementation/T10.md); test_video.py; test_replay.py; test_replay_client.py; test_replay_paused.py |
| T10-replay.07 | VALIDATED | [T10.md](../implementation/T10.md); test_video.py; test_replay.py; test_replay_client.py; test_replay_paused.py |
| T10-replay.08 | VALIDATED | [T10.md](../implementation/T10.md); test_video.py; test_replay.py; test_replay_client.py; test_replay_paused.py |
| T10-replay.09 | VALIDATED | [T10.md](../implementation/T10.md); test_video.py; test_replay.py; test_replay_client.py; test_replay_paused.py |
| T10-replay.10 | VALIDATED | [T10.md](../implementation/T10.md); test_video.py; test_replay.py; test_replay_client.py; test_replay_paused.py |
| T10-replay scope | ffmpeg argv, upright5fps, hash/PTS, preserved source, challenge1x/no backlog, fresh capture, trace mapping, TTL/ACK, stdout, clean EOF | Xem bước đánh số trong plan04/05 và receipt tương ứng |
| T10-evaluator.01 | CODE_VALIDATED; G3_BLOCKED_DATA | [T10.md](../implementation/T10.md); test_evaluator.py; test_trace_validation.py |
| T10-evaluator.02 | CODE_VALIDATED; G3_BLOCKED_DATA | [T10.md](../implementation/T10.md); test_evaluator.py; test_trace_validation.py |
| T10-evaluator.03 | CODE_VALIDATED; G3_BLOCKED_DATA | [T10.md](../implementation/T10.md); test_evaluator.py; test_trace_validation.py |
| T10-evaluator.04 | CODE_VALIDATED; G3_BLOCKED_DATA | [T10.md](../implementation/T10.md); test_evaluator.py; test_trace_validation.py |
| T10-evaluator.05 | CODE_VALIDATED; G3_BLOCKED_DATA | [T10.md](../implementation/T10.md); test_evaluator.py; test_trace_validation.py |
| T10-evaluator.06 | CODE_VALIDATED; G3_BLOCKED_DATA | [T10.md](../implementation/T10.md); test_evaluator.py; test_trace_validation.py |
| T10-evaluator scope | Independent labels/windows, evidence kinds, anti-leak splits, metrics, bound reports, missing-data exit2 | Xem bước đánh số trong plan04/05 và receipt tương ứng |
| T12.01 | VALIDATED | [T12.md](../implementation/T12.md); container-final.json; backup-restore.json; fresh-copy.json |
| T12.02 | VALIDATED | [T12.md](../implementation/T12.md); container-final.json; backup-restore.json; fresh-copy.json |
| T12.03 | VALIDATED | [T12.md](../implementation/T12.md); container-final.json; backup-restore.json; fresh-copy.json |
| T12.04 | VALIDATED | [T12.md](../implementation/T12.md); container-final.json; backup-restore.json; fresh-copy.json |
| T12.05 | VALIDATED | [T12.md](../implementation/T12.md); container-final.json; backup-restore.json; fresh-copy.json |
| T12.06 | VALIDATED | [T12.md](../implementation/T12.md); container-final.json; backup-restore.json; fresh-copy.json |
| T12.07 | VALIDATED | [T12.md](../implementation/T12.md); container-final.json; backup-restore.json; fresh-copy.json |
| T12.08 | DOCUMENTED_CUDA_NOT_RUN | [T12.md](../implementation/T12.md); container-final.json; backup-restore.json; fresh-copy.json |
| T12.09 | VALIDATED | [T12.md](../implementation/T12.md); container-final.json; backup-restore.json; fresh-copy.json |
| T12.10 | VALIDATED | [T12.md](../implementation/T12.md); container-final.json; backup-restore.json; fresh-copy.json |
| T12 scope | Frozen CPU image/non-root, read-only models/no secrets, loopback DB, health/startup, bounded graceful application cleanup, backup, explicit native CUDA path, client contract, unchanged Flutter | Xem bước đánh số trong plan04/05 và receipt tương ứng |
| T09-cleanup | VALIDATED | Lost observations/no progress; resume/reset/latch; idle/total; disconnect epoch; sticky>10s worker fault;500-session cleanup. test_runtime_instructions, test_runtime_sessions, test_faults, test_worker, cleanup-rss.json. |
| T11.01 | VALIDATED_WITH_EXTERNAL_GAPS | V01–V30 table below; V29/fullV30 remain blocked. |
| T11.02 | CPU_VALIDATED; CUDA_NOT_RUN | Real models CPU; no CUDA timing/VRAM claim. |
| T11.03 | BLOCKED_DATA | Public RGB1/4-session30+300s measured; benchmark-public-cpu-summary.json. Independent route acceptance absent. |
| T11.04 | CODE_VALIDATED; MEASUREMENT_BLOCKED | Collectors and public30+300s1/4-session performance measured; independent route gate remains absent. |
| T11.05 | CODE_VALIDATED; MEASUREMENT_BLOCKED | Quantile/count/report tests and public300s measurements; independent-route acceptance absent. |
| T11.06 | VALIDATED | Fault injection only explicit test seams; no simulate endpoint. |
| T11.07 | VALIDATED | 1000ms unchanged; CPU4-thread tuning based recorded repeated-image profile, no G4 claim. |
| T11.08 | VALIDATED | Encoder/model/input unchanged; exact fingerprint/artifact hashes. |
| T11.09 | PARTIAL_VALIDATED | Token/payload logging checks and500-session RSS pass; long model allocator load not measured. |
| T13.01 | VALIDATED_SPLIT_EVIDENCE | Fresh source + empty DB326 tests; clean runtime dependency installation in Docker frozen build. |
| T13.02 | PARTIAL_G3_BLOCKED_DATA | Core real algorithms and actual models pass; independent query pilot absent. |
| T13.03 | VALIDATED | Data requirements and user confirmation recorded; public smoke excluded from G3. |
| T13.04 | VALIDATED | Final build/source/lock/model/policy/container/runtime receipts; older reports labelled intermediate. |
| T13.05 | VALIDATED_WITHIN_TEST_SCOPE | Epoch/deadline/owner/isolation tests and external-process WS; independent field test remains absent. |
| T13.06 | VALIDATED | Readiness/handoff disclose device/calibration/data/audio/performance limits. |
| T13.07 | DEFERRED_AFTER_G4 | Flutter integration belongs to next separately scoped task. |
| T13.08 | VALIDATED | No git init/commit/push/public deployment/release; local compose only. |

## Ma trận V01–V30

| ID | Trạng thái | Bằng chứng |
|---|---|---|
| V01 | VALIDATED | test_contracts; test_errors; test_freshness |
| V02 | VALIDATED | test_images; test_errors |
| V03 | VALIDATED | test_auth |
| V04 | VALIDATED | test_sessions; test_stream; test_external_process |
| V05 | VALIDATED | test_catalog_storage; test_catalog_api; test_route_publish |
| V06 | VALIDATED | test_route_publish; test_catalog_api; test_sessions |
| V07 | VALIDATED | test_encoder_real; test_pipeline_real |
| V08 | VALIDATED | test_detector_postprocess; test_detector_real; test_export_parity |
| V09 | VALIDATED | test_tracking |
| V10 | VALIDATED | test_tracking |
| V11 | VALIDATED | test_depth; test_stream_depth |
| V12 | VALIDATED | test_depth; test_obstacles |
| V13 | VALIDATED | test_obstacles; test_obstacle_priority |
| V14 | VALIDATED | test_localization; test_navigation; test_fixture_integrity |
| V15 | VALIDATED | test_navigation; test_fixture_integrity |
| V16 | VALIDATED | test_localization |
| V17 | VALIDATED | test_decisions; test_runtime_instructions |
| V18 | VALIDATED | test_decisions; test_obstacles; test_runtime_instructions |
| V19 | VALIDATED | test_runtime_freshness |
| V20 | VALIDATED | test_runtime_freshness; test_freshness; test_stream_cancellation |
| V21 | VALIDATED | test_worker; test_runtime_freshness |
| V22 | VALIDATED | test_stream; test_freshness |
| V23 | VALIDATED | test_sessions; test_stream |
| V24 | VALIDATED | test_isolation; test_limits; test_runtime_sessions |
| V25 | VALIDATED | test_runtime_output; test_faults |
| V26 | VALIDATED | test_freshness |
| V27 | VALIDATED | test_restart; test_runtime_sessions; container-final.json |
| V28 | VALIDATED | test_runtime_instructions; test_replay; test_freshness |
| V29 | BLOCKED_DATA | User has no independent pilot; public Ada single-recording smoke excluded |
| V30 | PARTIAL; BENCHMARK_BLOCKED_DATA | Scheduling/isolation/500-session cleanup pass; public300s1/4 performance measured, independent-route acceptance not run |

Không có API/model/hardware accuracy nào được suy ra từ synthetic fixtures. RGB-D algorithms đã kiểm bằng depth fixtures, hardware chưa kiểm. Source hashes bao gồm mọi thay đổi local được allowlist, không chỉ HEAD; không đọc env riêng.
