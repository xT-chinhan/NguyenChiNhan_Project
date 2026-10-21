# Independent pilot data is absent

No independent route pilot, annotated query videos, or obstacle labels are supplied
in this repository. The existing BlindNav media clip may exercise decoding/model
smoke only. It cannot establish route accuracy, G3/G4, audio presentation, or use
with people who are blind. No footage is generated or downloaded by these CLIs.

Provide a directory with `bundle.json`, twelve distinct upright reference images
for four checkpoints, one independently captured dev clip, two independently
captured positive test clips, two negative test clips, `ground_truth.json`, and
`dataset-manifest.json`. Follow `docs/plan/06-validation.md` for route semantics.
Reference and query captures must be separate walks. Keep raw media outside Git.

`route-import` validates the whole explicit bundle before sending admin REST
mutations. Set `NAV_API_URL` and `NAV_ADMIN_TOKEN` in a private environment file.
`--receipt` defaults to `import-receipt.json` next to the bundle; existing receipts
are refused. On failure it records created IDs and leaves an unpublished draft.
It never accesses the server database directly. No CLI accepts a token argument.

`prepare-video --input ... --output-dir ...` requires ffprobe/ffmpeg and an empty
output directory. It preserves source bytes, applies ffmpeg's metadata rotation,
removes audio, samples at 5 fps, and fits within 640 by 480 without enlargement.
Maximum supported source duration is one hour. Output includes JPEG samples,
`source-manifest.json` with the source byte hash, normalized PTS origin, and a
hash of `frames.jsonl`. Each JSONL record is:

```json
{"sample_index":0,"pts_ms":0,"relative_path":"frame-000000.jpg","pixel_sha256":"<64 lowercase hex>"}
```

Pixel hashes use the shared image contract: SHA-256 of big-endian uint32 width,
uint32 height, then upright RGB8 bytes. Timestamps start at zero and advance 200ms.
Replay decodes and reencodes JPEG quality75 after each fresh capture challenge,
uses a monotonic 1x playback clock, and skips samples when the server is slow.
It reads only `NAV_API_URL` and `NAV_DEVICE_TOKEN`. Give `--clip-id` matching the
annotation clip ID. Its JSONL trace stores seq to video PTS and pixel identities,
latency, object boxes, freshness/hold, and `stdout_simulation` presentation events.
It contains no image bytes, base64, frame tokens, or bearer tokens. Exit0 means
the stream ended; it does not assert route completion or test audio playback.

The dataset manifest schema is explicit and rejects extra fields:

```json
{
  "schema_version":1,
  "dataset_id":"pilot-route-a",
  "created_at":"2026-10-21T00:00:00Z",
  "files":[
    {"path":"references/cp0/01.jpg","sha256":"<file hash>",
     "source":"reference","split":"reference","capture_group":"ref-walk-01",
     "pixel_sha256":["<canonical upright pixel hash>"]},
    {"path":"queries/positive-01.mp4","sha256":"<file hash>",
     "source":"query","split":"test","capture_group":"query-walk-02","duration_ms":60000,
     "pixel_sha256":["<every prepared frame canonical pixel hash>"]}
  ],
  "capture_groups":["ref-walk-01","query-walk-02"],
  "capture_conditions":{"camera":"...","upright_rotation":"...","lighting":"..."},
  "limitations":["Known conditions and exclusions"]
}
```

The last three metadata fields are optional. Sources are `reference|query`;
splits are `reference|dev|test`. File hashes are verified against bytes. Reference
pixel hashes are verified by decoding. Every query file requires its measured
`duration_ms`; absent durations produce `BLOCKED_DATA`. Perception annotation PTS
must be distinct within each clip; repeating one label cannot count as thirty
observations. Negative replay must cover its full source duration with fresh
observations near both ends. Trace source/video hashes and prepared
pixel identities must agree with the manifest. Shared bytes, pixels, or capture
groups across reference/query or dev/test are rejected. All dataset paths must be
relative files beneath the bundle root, without symlinks or traversal.

Ground truth follows plan06 and adds an explicit annotation provenance record:

```json
{"schema_version":1,
 "annotation_provenance":{"kind":"human","independent_of_model":true},
 "clips":[]}
```

Use a human's observed windows, never model-derived checkpoint/turn labels.
Each clip supports `perception_frames` in addition to plan06 `objects`. To label
clear frames unambiguously, use an empty objects list. At least thirty observed
test frames containing person/chair and thirty observed clear test frames are
required. Coordinates describe upright fit640x480 pixels, with each sample's
actual aspect ratio retained:

```json
{"pts_ms":200,"objects":[{"class_name":"person","bbox":[10,20,100,200],"rgb_notice_expected":true}]}
```

```json
{"pts_ms":400,"objects":[]}
```

`evaluate --trace ...` is repeatable for every test clip. Bundle/manifest default
to the ground truth directory; `--bundle` and `--dataset-manifest` may override
filenames in that same root. Dev annotations establish the tuning split; dev
replay is optional and excluded from test scoring. Missing data or coverage exits2
with G3 `BLOCKED_DATA` and null unmeasured metrics. Invalid schema/leakage exits1.
Complete measured failures exit1. JSON and Markdown are rendered from one report
object and existing reports are refused.

Replay does not attest which server build/model processed the connection. Without
`--server-receipt`, the evaluator reports `unverified_server`, G2 `BLOCKED_MODEL`,
and cannot claim real-model G3. A supplied local operator receipt must bind these
exact trace bytes and model smoke evidence, for example:

```json
{"schema_version":1,"adapter_kind":"real_models",
 "inputs":{"source_sha256":"<server source hash>","uv_lock_sha256":"<lock hash>",
           "model_manifest_sha256":"<artifact manifest hash>","policy_sha256":"<policy hash>"},
 "environment":{"profile":"cpu"},
 "attestation":{"kind":"local_run","model_smoke_verified":true,
                "trace_sha256":["<all trace hashes, sorted>"]}}
```

This is a local evidence claim requiring the operator's independent receipts;
it is not cryptographic remote attestation. G2 is labelled `PASS_ATTESTED` and the
adapter `real_models_local_attestation`, preserving that distinction. The report
includes evaluator source/policy/lock hashes, dataset/annotation/bundle/trace
hashes, and the supplied exact server inputs. G0/G1/G4/G5 are not inferred from
pilot replay. No hashes or model success are invented when inputs are absent.

An additional public video was explicitly downloaded for local pipeline testing:
Universidad de Zaragoza, Ada Byron, from
https://webdiis.unizar.es/~glopez/dataset.html. The 182.753s FLV and prepared samples
are ignored under `backend/output/public-video/zaragoza-ada/`. This is a single
recording without independent route annotations. Its smoke bundle deliberately
reuses that recording and MUST NOT count as G3 data. See
`docs/reports/public-video-zaragoza.md` for measured results and provenance.
