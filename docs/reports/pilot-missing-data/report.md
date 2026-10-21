# Pilot evaluation

Run: eb0fa7f4-aca3-4774-8dda-cb12de785068

Evidence: network_replay; adapter: unverified_server

| Gate | Result |
|---|---|
| G0 | NOT_RUN |
| G1 | NOT_RUN |
| G2 | BLOCKED_MODEL |
| G3 | BLOCKED_DATA |
| G4 | BLOCKED_DATA |
| G5 | NOT_RUN |

## counts

| Metric | Value |
|---|---|
| frames_requested | 0 |
| frames_received | 0 |
| frames_expired | 0 |
| stale_instructions_presented | 0 |
| stale_proposals_dropped | 0 |

## navigation

| Metric | Value |
|---|---|
| false_turns | null |
| missed_turns | null |
| early_arrivals | null |
| out_of_route_progress | null |
| completed_positive_clips | null |

## perception

| Metric | Value |
|---|---|
| precision | null |
| recall | null |
| object_frames_observed | null |
| clear_frames_observed | null |

## latency_ms

| Metric | Value |
|---|---|
| p50 | null |
| p95 | null |
| p99 | null |

## inputs

| Metric | Value |
|---|---|
| source_sha256 | "d854e95ed29c934d6a511e7930daf5d4b5c6b54fa282732489b4b1c78a83fa7c" |
| policy_sha256 | "fa3f3c2d70be7d49bbedf5f85f48966500d585886473ceee1913c3ebff54c8a2" |
| uv_lock_sha256 | "29835fa8c47e3963699736590f1d2fe197471b568d380dc90e301f3b867dd2cf" |
| model_manifest_sha256 | null |
| dataset_manifest_sha256 | null |

## Limitations

- Missing pilot input: missing-ground-truth.json
- Missing pilot input: dataset-manifest.json
- Missing pilot input: bundle.json
- No network replay traces supplied
