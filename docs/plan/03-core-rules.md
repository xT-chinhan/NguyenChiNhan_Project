# 03 — Thuật toán, trạng thái và thứ tự quyết định

Các con số trong tài liệu là baseline nguyên mẫu có test biên, chưa phải ngưỡng hiệu chỉnh thực địa.
Chỉ thay ngưỡng sau khi có báo cáo đánh giá, ghi cả cấu hình cũ/mới; không đổi để làm đẹp một video.

## 1. Interface của core

Core không import FastAPI, SQLAlchemy, torch, ONNX Runtime, SDK camera, audio hoặc mạng.
Types là dataclass/enum Python trong `core/types.py`; schema Pydantic chỉ ở lớp HTTP/WS.

Các interface đủ dùng:

```python
encode_image(rgb_u8) -> ndarray[float32, 768]       # vision, không thuộc core
detect_objects(rgb_u8) -> list[Detection]          # vision
match_checkpoint(embedding, route, allowed_seqs, heading) -> MatchResult
track_objects(tracker_state, detections, capture_ms) -> TrackingResult
assess_obstacles(tracks, depth, sensor, capture_ms) -> ObstacleResult
advance_navigation(state, match, frame_identity, now_ms) -> NavigationProposal
decide(state, navigation_proposal, obstacles, freshness) -> Decision
```

`NavigationProposal` chứa next_state và instruction candidate, chưa mutate session.
Runtime kiểm tra epoch/token/deadline lần cuối rồi mới commit `Decision.next_state`.
Test dùng observation xác định được ở seam này; không mock chính state machine cần kiểm tra.
AI thật và adapter fixture là hai implementation khác nhau ở cùng seam vision.
Fake chỉ được tiêm từ test factory, không có env `FAKE_AI=true` mở cổng giả thành server thật.

## 2. Config duy nhất của policy

| Tên | Giá trị baseline |
|---|---|
| REQUEST_DEADLINE_MS | 1000 |
| WATCHDOG_INTERVAL_MS | 100 |
| MAX_REQUEST_RATE_HZ | 5 |
| MODEL_SLOT_WAIT_MS | 100 |
| MAX_ACTIVE_SESSIONS | 4 |
| TRACK_MAX_AGE_MS | 1000 |
| TRACK_IOU_THRESHOLD | 0.30, match khi lớn hơn |
| TRACK_CONFIRM_HITS | 3 |
| WAYPOINT_CONFIRM_HITS | 3 |
| WAYPOINT_CONFIRM_WINDOW_MS | 1500 |
| MATCH_THRESHOLD_STRAIGHT | 0.88 |
| MATCH_THRESHOLD_TURN_OR_FINAL | 0.92 |
| MATCH_MARGIN | 0.04 |
| REFERENCE_AMBIGUITY_LIMIT | 0.97 |
| HEADING_MAX_ERROR_DEG | 25 |
| HEADING_MAX_ACCURACY_DEG | 20 |
| LOCALIZATION_LOST_MS | 15000 |
| INITIAL_LOCALIZATION_TIMEOUT_MS | 15000 |
| DETECTION_CONFIDENCE_MIN | 0.38 |
| RGB_NOTICE_CONFIDENCE_MIN | 0.50 |
| OBSTACLE_NOTICE_COOLDOWN_MS | 3000 |
| NAVIGATION_REPEAT_COOLDOWN_MS | 5000 |

Đặt trong frozen `PolicyConfig`, validate khi tạo app. Không lặp số magic ở module khác.
Record toàn bộ config + hash trong báo cáo đánh giá.
Configuration phục vụ test/hiệu chỉnh, không cho client sửa policy qua API.

## 3. Ảnh và inference

### Tiền xử lý dùng chung

1. Kiểm tra byte/pixel cap trước decode hoàn chỉnh.
2. PIL decode màu, reject truncated/animated/decompression bomb.
3. Ảnh admin: áp EXIF orientation rồi convert RGB; ảnh WS: đã upright từ client.
4. Canonical RGB uint8 C-contiguous, read-only cho pipeline, không inpainting.
5. Tạo pixel hash cho chống frame trùng; không lưu pixels trực tiếp vào log.
6. Với reference, re-encode canonical JPEG quality90, bỏ EXIF rồi decode chính bytes sẽ lưu để tính
   embedding. Như vậy vector có thể tái tạo từ artifact JPEG trong DB, không phụ thuộc ảnh tạm khác.

### DINOv2

- Model `facebook/dinov2-base`, revision cố định ở source audit.
- `AutoImageProcessor` cùng revision; không tự resize thêm bằng OpenCV trước processor.
- `model.eval()`, `torch.inference_mode()`, `use_safetensors=True`, `trust_remote_code=False`.
- Lấy `last_hidden_state[:,0,:]`; assert shape `(1,768)`.
- Cast float32, chia L2 norm; norm <=1e-12 hoặc giá trị non-finite → lỗi model.
- Không fallback CLIP, không lấy nhầm patch token hoặc 384 chiều từ comment cũ.
- Reference và live phải cùng encoder fingerprint; mismatch là lỗi, không so gần đúng.

### YOLO ONNX

- Float32 input `(1,3,224,224)`, RGB /255, letterbox pad 114, không méo aspect ratio.
- Scale `min(224/h,224/w)`, resize, padding trái/trên lấy floor phần chia 2.
- Chỉ nhận output `(1,300,6)`: `[x1,y1,x2,y2,confidence,class_id]` trong ảnh letterbox.
- Sai shape làm readiness fail; không thêm nhánh đoán output khác và không NMS hai lần.
- Chỉ confidence `[0,1]`, class_id nguyên `[0,79]`, finite.
- Confidence <0.38 loại; class âm/non-integer/bbox invalid loại.
- Đổi tọa độ về ảnh gốc, clamp `[0,w-1]`, `[0,h-1]`.
- Loại bbox rộng/cao <10 pixel sau clamp.
- Không copy blacklist outdoor của BlindNav vào policy mới; giữ 80 COCO classes.
- Map class names cố định từ manifest export; không lấy text label client gửi.

Mỗi job chạy detector + encoder cho cùng một ảnh. Một nhánh lỗi thì job không được xác nhận chặng.
Một cặp models nạp duy nhất trong process, một inference slot; không nạp lại theo request.
ONNX CPU mặc định; không cài đồng thời `onnxruntime` và `onnxruntime-gpu`.

## 4. Reference và publish tuyến

Publish transaction chỉ được thành công khi:
1. Route là draft, hai places khác nhau và cùng map.
2. N checkpoint 2..64, seq liên tục bắt đầu 0.
3. Chỉ checkpoint cuối có action arrive; checkpoint trước đó straight/left/right.
4. Mỗi checkpoint 3..8 ảnh canonical pixel hash khác nhau, vector 768 finite và norm gần 1.
5. Mọi encoder fingerprint giống model hiện tại, tổng ảnh <=64 MiB.
6. Không có pixel hash dùng ở hai checkpoint.
7. Với mọi cặp checkpoint, max cosine giữa các reference <0.97.
   Cặp >=0.97 bị báo `ROUTE_AMBIGUOUS`; không giảm ngưỡng để publish.
8. Tạo route fingerprint từ JSON canonical metadata/checkpoint IDs + image/vector hashes.

Mốc 0.97 chỉ chặn trường hợp quá giống; không chứng minh các checkpoint còn lại phân biệt được.
G3 bắt buộc kiểm tra video độc lập có cảnh tương tự, hướng ngược và ngoài tuyến.
Tuyến published immutable. Không re-encode tuyến cũ ngầm khi đổi model.
Muốn đổi encoder/processor/ngưỡng preprocessing: tạo draft/reference revision mới rồi đánh giá lại.

## 5. Match checkpoint

Với embedding live chuẩn hóa `q`, reference `r` cũng chuẩn hóa:
`cosine(q,r) = dot(q,r)`; score checkpoint = median của HAI score reference cao nhất.
Không dùng một ảnh reference duy nhất làm quyết định.

Quy trình:
1. Tính score TẤT CẢ checkpoint của route snapshot.
2. Chọn top1; hòa score trong 1e-6 thì ambiguous, không chọn theo ID.
3. `margin = top1 - top2`; N>=2 nên luôn có đối thủ.
4. Top1 phải thuộc allowed_seqs của trạng thái hiện tại.
5. Score >=0.92 nếu action left/right/arrive hoặc checkpoint ngay trước left/right; còn lại >=0.88.
6. Margin >=0.04.
7. Nếu cả reference heading và live heading có accuracy<=20°, yêu cầu sai khác vòng tròn <=25°.
8. Nếu heading thiếu/accuracy không đạt, vẫn cho visual prototype match nhưng `orientation_verified=false`.

Không bỏ checkpoint đã qua khỏi tập đối thủ: hình cũ giống checkpoint trước phải chặn nhảy tiến.
Không dùng heading điện thoại để suy ra khoảng cách.
Heading circular error = `abs((a-b+180)%360-180)`.

Để xác nhận:
- Cần 3 hit liên tiếp cùng candidate, trong tối đa 1500 ms capture span.
- Ba capture timestamp, request seq và pixel hash phải khác nhau.
- Frame trùng pixel không tăng hits; frame miss/ambiguous/wrong heading reset hits.
- Frame expired/rejected/pause/obstacle hold cũng reset candidate.
- Chỉ một checkpoint được xác nhận trong một frame; không vòng while để vượt nhiều checkpoint.

## 6. Navigation state machine

State: `localizing`, `navigating`, `lost`, `paused`, `completed`, `stopped`.
Fields riêng từng phiên:
`last_confirmed_seq=-1`, `target_seq=0`, `candidate`, `last_progress_ms`, `resume_allowed_seqs`.
Đồng hồ last_progress chỉ tính trong thời gian active, không tính lúc người dùng chủ động pause.

Giữ thêm `pending_departure_seq` và ID instruction hiện tại để theo dõi việc giao câu hướng dẫn.
Xác nhận checkpoint k vẫn cập nhật last=k, nhưng chưa nhận ACK presented cho câu rời k
thì chưa xác nhận checkpoint k+1. ACK chỉ mở việc kiểm tra bước tiếp theo, không thay bằng chứng vị trí.
Nếu câu rẽ bị drop/hết hạn trước khi được đọc: nhận ảnh mới, xác nhận lại k bằng 3 hit theo cùng
ngưỡng/margin rồi tạo instruction mới, ID/TTL mới, không tăng progress và không tái dùng ảnh cũ.
Lúc này allowed={k}; sau ACK presented mới allowed={k+1}. Chỉ ACK của ID hiện tại được mở khóa.
Nếu không xác nhận lại được k trong15s thì lost. Resume có thể tìm lại last hoặc next như bảng dưới.
ARRIVED là terminal; khi audio ARRIVED bị mất, client có thể hiển thị completed từ snapshot;
không biến completed thành một lệnh di chuyển mới hoặc dùng ACK để chứng minh đã tới nơi.

| State / sự kiện | Kết quả |
|---|---|
| Tạo phiên | localizing, chỉ allowed={0}, bắt đầu timeout 15s khi WS bắt đầu capture |
| Localizing xác nhận 0 | navigating; last=0, target=1; đề xuất depart_action của checkpoint 0 |
| Navigating xác nhận target k, k chưa cuối | last=k, target=k+1; đề xuất depart_action k |
| Xác nhận checkpoint cuối | completed; đề xuất ARRIVED; dừng cấp capture |
| Active 15s không xác nhận được vị trí mục tiêu | lost; HOLD_POSITION; không tự khuyên đi lùi |
| Control pause | paused, xóa candidate và pending movement instruction |
| Frame/request hết hạn hoặc WS disconnect | paused, reason stream_stale/disconnected |
| Control resume từ paused/lost | localizing; allowed={last,last+1} hợp lệ trong tuyến; nếu last=-1 chỉ {0} |
| Re-localize lại last đã xác nhận | navigating, target vẫn last+1, không tăng progress |
| Re-localize xác nhận last+1 | tăng đúng một chặng theo quy tắc bình thường |
| Control stop / DELETE / TTL | stopped, giải phóng runtime và WS |
| Completed/stopped nhận resume/frame | SESSION_TERMINAL; không mở lại phiên |

Trong navigating không có pending_departure, allowed chỉ có target hiện tại.
Còn pending_departure chưa được presented thì allowed chỉ có checkpoint đang chờ giao hướng dẫn.
Trong lost vẫn có thể nhận ảnh để hiển thị observation, nhưng không tự chuyển chặng;
chỉ control resume mới bắt đầu xác nhận lại. Không phát hướng dẫn di chuyển khi lost.
Re-localize checkpoint cuối phải qua cùng ngưỡng final và đủ 3 hit, không dựa ACK.
Pause/disconnect vô hiệu ID instruction cũ. Resume xác nhận lại last thì tạo câu rời last mới
và pending_departure mới; xác nhận next thì tạo câu của next như bình thường.

Nếu model job lỗi một lần: hold frame đó, reset candidate, thử request mới nếu còn active.
Lỗi 3 job liên tiếp của phiên: pause, `VISION_UNAVAILABLE`; cần resume sau khi model hoạt động lại.
Một job hợp lệ reset bộ đếm lỗi. Thiếu model/load fail là global not_ready, không nhận session mới.

## 7. Tracking

- `ObjectTracker` chứa tracks và next_id trong session, ID bắt đầu 1 và tăng dần.
- Expire khi capture_now - last_seen >1000 ms; đúng 1000 ms chưa expire.
- Sort detection theo confidence giảm, class_id tăng, bbox lexicographic để test xác định được.
- Match cùng class, IoU >0.30, chọn IoU lớn nhất; hòa chọn track ID nhỏ hơn.
- Một track chỉ match một detection/frame; track mới tạo cũng phải thêm vào matched_ids.
- Bbox smoothing: hit đầu giữ nguyên; từ hit tiếp theo alpha=0.6.
- Tracker trả cả track chưa đủ 3 hit; policy mới quyết định có cảnh báo hay không.
- Chỉ track được nhìn thấy ở FRAME HIỆN TẠI tham gia obstacle output/policy.
- Retained track cũ chỉ phục vụ match lần sau, không dùng bbox/depth cũ để cảnh báo mới.
- Ngắt capture >1000 ms: clear tracks, distance history và candidate.

## 8. RGB obstacle policy

Không có depth: `distance_m=null`, `ttc_s=null`, `depth_status=not_supported`.
Không đổi bounding-box area thành khoảng cách hoặc thời gian va chạm.

V1 chỉ có notice khi track thỏa TẤT CẢ:
- Được nhìn thấy trong frame hiện tại, >=3 hit và confidence>=0.50.
- Center x trong `[0.30w,0.70w]`.
- Bbox bottom >=0.65h.
- Bbox area / image area >=0.08.

Khi đó tạo `OBJECT_AHEAD`, không nói mét, không gợi ý lách trái/phải.
Notice chặn commit checkpoint và suppress movement instruction ở frame đó.
Cooldown chỉ hạn chế âm thanh lặp, không bỏ tác dụng hold.
Không thấy notice ở frame sau không đồng nghĩa “đường an toàn”; không phát PATH_CLEAR.
Những ngưỡng bbox trên là heuristic cần đo false positive/negative ở G3.

Vị trí tương đối cho output trái/giữa/phải:
- Center x <0.4w: left; >0.6w: right; còn lại ahead.
- Giữ nhãn tới khi center vượt qua biên vào vùng mới thêm 0.03w, đủ 2 frame khác nhau.
- Cache theo frame seq để gọi hàm nhiều lần trong một frame không tăng hysteresis.
- Không copy HFOV 69° RealSense áp cho camera điện thoại chưa hiệu chuẩn.

## 9. RGB-D distance và TTC

Nhánh này chỉ chạy khi sensor.mode=rgbd và depth đúng registration/scale/timestamp.
Thiếu hoặc sai depth không được fallback khoảng cách từ frame trước.

### Distance cho bbox

1. Raw uint16 * depth_scale_m → float mét.
2. Cắt center 60% bbox theo cả hai chiều.
3. Stride=max(2,floor(sqrt(ROI_area/4000))), chỉ sample tối đa gần 4000 pixel.
4. Giữ giá trị `0<d<8m`, cần >=30 sample hợp lệ.
5. Trim ngoài percentile 10..90; nếu còn <20 dùng tập valid trước trim.
6. Nếu IQR<0.45m: median là distance.
7. Nếu IQR>=0.45m: histogram bin 0.30m, chọn peak có support>=18% sample.
   Nhiều peak thì chọn peak GẦN NHẤT, không chọn nền xa đông pixel nhất.
8. Không có peak đủ support: median; trả quality info, không gọi đây là đo chắc chắn.

Peak gần nhất là thay đổi có chủ ý so với BlindNav; test phải ghi rõ thay đổi này.
Đo sai scale, depth registration sai hoặc foreground nhỏ vẫn có thể làm đo khoảng cách sai.

### Depth-only center fallback

- ROI x=35..65% width, y=25..95% height.
- Cần >=200 sample hợp lệ và valid ratio>=0.60.
- Lấy percentile 10 của depth hợp lệ; <0.80m là obstacle warning, <0.40m là emergency.
- Catches một số bề mặt không có detection; không tuyên bố nhìn xuyên kính hoặc phát hiện hố.

### Range velocity và TTC

- Dùng capture time của device, không dùng thời gian inference.
- Tối thiểu 3 distance sample, span>=150 ms, gap bất kỳ <=500 ms, cửa sổ tối đa 1 giây.
- Chênh distance nhỏ hơn `max(0.08m,0.03*max_distance)` → velocity=0.
- Tính slope OLS theo thời gian đã trừ mean; EMA alpha=0.5 sau giá trị hợp lệ đầu.
- Person |velocity|>8m/s, class khác >20m/s → unreliable, TTC=null.
- Jump >1.5m: chưa nhận ngay; đợi 2 số đo mới cách nhau<=0.4m, reset lịch sử và velocity.
- No depth/clock gap/reconnect → velocity chưa biết, TTC=null; không thay null bằng số 999.
- `closing_speed = -range_velocity`; chỉ khi closing_speed>0.03m/s mới xét TTC.
- `ttc = distance/closing_speed`; TTC>12s không dùng để nâng cảnh báo.
- Không trừ ego-motion khỏi range velocity cho TTC: chính người dùng tiến tới tường cũng là nguy cơ.

### Hai lớp cảnh báo khoảng cách + TTC

| Điều kiện | Priority/code | Chặn progress |
|---|---|---|
| Depth-only hoặc bbox distance <0.40m | emergency / EMERGENCY_STOP | Có, không chờ 3 track hit |
| 0.40<=distance<0.70m | warning / OBSTACLE_NEAR | Có, không chờ đủ hit |
| Track >=3 hit, TTC<2s | emergency / EMERGENCY_STOP | Có |
| Track >=3 hit, 2<=TTC<4s | warning / OBSTACLE_NEAR | Có |
| Track >=3 hit, 4<=TTC<8s | info / OBSTACLE_NOTICE | Chỉ suppress voice hướng dẫn trong frame này |
| RGB-D depth missing/invalid/insufficient | warning / DEPTH_UNAVAILABLE | Có |

Distance override không phụ thuộc TTC hay người dùng có đang di chuyển.
Warning/emergency tạo latch giữ hold. Chỉ bỏ latch sau 3 frame depth hợp lệ liên tiếp,
center fallback valid có range>=0.90m và không còn điều kiện warning/emergency.
Frame thiếu depth/detection không tự xóa latch; không phát câu “đường đã an toàn” khi bỏ latch.

## 10. Chọn hướng dẫn và chống phát lặp

Thứ tự ưu tiên, từ trên xuống:
1. Stop/expired/pause do control hoặc stream → bỏ pending movement, không advance.
2. Model/depth không dùng được → hold, không advance.
3. Emergency/latched warning → chọn cảnh báo, không advance.
4. RGB OBJECT_AHEAD → chọn notice, không advance.
5. Lost/localizing chưa đủ bằng chứng → HOLD_POSITION hoặc không phát thêm.
6. NavigationProposal hợp lệ → commit tối đa một checkpoint và phát câu của checkpoint đó.
7. Không có thay đổi → instruction=null; không phát GO_FORWARD liên tục.

Nếu perception notice mức info ở RGB-D trùng với navigation candidate:
chưa commit checkpoint, reset candidate để xác nhận lại ở frame sau, không làm mất câu rẽ.
Chỉ commit navigation khi đúng frame có thể phát instruction tương ứng.

Các code và câu chuẩn:

| Code | text_vi | Priority |
|---|---|---|
| CONTINUE_STRAIGHT | Tiếp tục theo hành lang. | guidance |
| TURN_LEFT | Đến chỗ rẽ. Rẽ trái. | guidance |
| TURN_RIGHT | Đến chỗ rẽ. Rẽ phải. | guidance |
| ARRIVED | Đã đến điểm đích của tuyến. | guidance |
| HOLD_POSITION | Chưa xác định được vị trí. Hướng dẫn đang tạm dừng. | warning |
| OBJECT_AHEAD | Hình ảnh cho thấy vật thể phía trước. Hãy kiểm tra đường đi. | warning |
| EMERGENCY_STOP | Có vật cản rất gần. Hãy dừng lại nếu có thể. | emergency |
| OBSTACLE_NEAR | Có vật cản gần phía trước. Hướng dẫn đang tạm dừng. | warning |
| OBSTACLE_NOTICE | Có vật thể đang ở gần hướng đi. | info |
| DEPTH_UNAVAILABLE | Chưa nhận được khoảng cách đáng tin cậy. Hướng dẫn đang tạm dừng. | warning |
| WAIT_FOR_FRESH_FRAME | Đang chờ hình ảnh mới để hướng dẫn. | info |

V1 không chèn distance vào tiếng nói; distance có trong observation để kiểm tra.
Không đưa landmark text do admin nhập thẳng vào mệnh lệnh do LLM sinh.
Cooldown notice theo `(code,position,class_name,floor(distance/0.3) hoặc unknown)` 3s.
Emergency mới hoặc tăng mức nguy hiểm được phát ngay, không bị cooldown warning trước chặn.
Instruction rẽ/đến đích chỉ phát khi chuyển checkpoint; repeat còn hạn mới được phát lại.

## 11. Runtime freshness và commit

- Mỗi connection có epoch; pause/stop/disconnect/timeout tăng epoch và xóa request/candidate.
- Request có trạng thái awaiting_frame/processing/finished. Consume token chỉ chuyển sang processing;
  token/issued_at vẫn giữ trong record để kiểm tra commit, nhưng không nhận frame thứ hai.
- Job giữ epoch và token ban đầu. Kết quả chỉ commit nếu epoch, token, session state và deadline còn đúng.
- Đúng mốc 1000 ms là hết hạn (`age>=1000`), không commit dù model trả vector tốt.
- Giữ inference slot cho tới khi thread thật kết thúc; timeout await không được giả là đã hủy CUDA job.
- Worker dùng `ThreadPoolExecutor(max_workers=1)` riêng; semaphore không được release sớm khi cancellation.
- Chờ slot tối đa 100ms; quá thì WORKER_BUSY/hold, không xếp hàng frame vô hạn.
- Watchdog 100ms chạy trên event loop; inference/DB/decode nặng không chạy trực tiếp trên event loop.
- Một task duy nhất gửi WS qua bounded outbound queue 8 message, status coalesce; không send đồng thời.
- Queue output đầy hoặc send >250ms: pause, hủy pending movement, close 1013 nếu không gửi được status.
- Capture request mới chỉ tạo sau job trước hoàn tất; không có hai model job cho cùng session.
- Idle TTL/revocation kiểm tra kể cả khi paused, không rò task/tensor khi socket đã đóng.

