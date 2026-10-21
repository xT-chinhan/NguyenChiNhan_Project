# Pilot evaluation

Run: 6b6ea7c9-1258-481a-b39b-a785dd54baaa

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
| source_sha256 | "e3f00d6f727378bfd8cbade748418f78813d917190a78042af900d73e877786c" |
| uv_lock_sha256 | "e5237ceae0a978461b5506a176913b47fd3f282cca9e089d530e97515958613c" |
| model_manifest_sha256 | "4d0c48ad5902221d9bae9e50be21b232eacbfc313ce55b0d669b54eb7d63cac7" |
| policy_sha256 | "fa3f3c2d70be7d49bbedf5f85f48966500d585886473ceee1913c3ebff54c8a2" |
| dataset_manifest_sha256 | null |

## Limitations

- Missing pilot input: ground_truth.json
- Missing pilot input: dataset-manifest.json
- Missing pilot input: bundle.json
- No network replay traces supplied
