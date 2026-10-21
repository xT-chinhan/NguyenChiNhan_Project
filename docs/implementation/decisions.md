# Quyết định thực thi — 2026-10-21

Phạm vi: code backend cục bộ theo T00–T13; không commit, release, deploy,
đụng dịch vụ ngoài dự án hay xóa dữ liệu/caches của người dùng.
Integration owner `/root` là writer duy nhất trong checkout chính.
Hai agent audit hợp đồng/môi trường chỉ đọc. Không có MCP Ruflo được đăng ký.

## Làm rõ hợp đồng trước khi triển khai

1. Checkpoint có thêm `heading_accuracy_deg` nullable `[0,180]`, mặc định null,
   trong storage, upload metadata và snapshot. Chỉ verify heading khi reference và
   live đều có accuracy<=20°. Reference cũ thiếu accuracy vẫn visual-only.
2. Center depth cảnh báo `<0.80m`; bbox depth `<0.70m`; cả hai emergency `<0.40m`.
3. Client chỉ nhận capture age **<1000ms**, đồng thời chưa tới receive+valid_for_ms.
4. `frame_result` bổ sung `movement_held` và `hold_reason`. Hold luôn hủy movement
   đang đợi ở client dù instruction=null do cooldown. Server phát status hold khi
   chuyển sang hold; sender kiểm epoch/deadline trước gửi movement đã xếp hàng.
5. ACK presented chỉ mở khóa pending departure khi đúng ID hiện tại, đúng epoch,
   và server nhận trước deadline. received/expired/warning ID không mở khóa.
6. Manual repeat trả đúng ID hiện tại với TTL còn lại, không áp cooldown5000ms
   và không gia hạn deadline. Cooldown đó chỉ dành cho autonomous repeat nếu có;
   v1 không tự repeat nên không có đường gọi autonomous repeat.
7. Frame reject không commit progress/tracker/cooldown/instruction; được reset
   candidate và tăng protocol count. Epoch cũ không được mutate bất kỳ state nào.
8. Center ROI thiếu support: depth_status=insufficient và hold; giữ các bbox
   distance hợp lệ trong observation, không dùng chúng để suy ra center clear.
9. Histogram depth: bin origin0m, width0.30m, support denominator sau trim;
   peak là bin nonempty có count>=hai bin kề (bin biên so một phía), support>=18%;
   chọn bin gần nhất, trả median các sample trong bin đó. Không peak thì median.
10. Admin được đọc ba endpoint catalog theo bảng02; không tạo/control device session.
11. Xác nhận lại last checkpoint reset last_position_ms, không tăng progress.
12. Draft chưa có reference cho phép encoder_fingerprint=null. Lần upload đầu tiên
    gắn fingerprint thật, published bắt buộc không null. Không dùng hash giả toàn0.
13. `name_key` làTEXT vì casefold có thể mở rộng tên hợp lệ120ký tự thành>120.
14. Publish đã hoàn tất là read idempotent: trả200 tài nguyên cũ dù model thiếu/có
    phiên active; không đổi DB. Publish draft vẫn cần vision và admission lock.
15. Timing có event_loop_lag_ms đo từ watchdog; client không tự coi field thiếu là0.
16. Giới hạn500dòng cho code/tài liệu viết tay; uv.lock machine-generated giữ nguyên
    định dạng uv để --locked có thể kiểm tra, không rút gọn hoặc chia lock giả.
17. DB mutation giữ admission lock tới khi thread DB kết thúc thực, kể cả request
    bị cancel. Device env publish bằng hard-link atomic từ temporary0600 đã fsync;
    commit lỗi chỉ xóa inode vừa tạo, không xóa file đã có hoặc đã bị thay thế.

## Tài nguyên và kiểm tra

Disk home7.71GiB <12GiB gate ban đầu: chưa tải model/CUDA; không dọn cache người dùng.
Sau `uv sync --dry-run --extra cpu --locked`, đúng62 wheel cần cho CPU có tổng
compressed357,870,631byte (341.3MiB), không có NVIDIA/CUDA transitives. Số byte từ
lockfile; hai wheel PyTorch lấy Content-Length đã kiểm riêng191,817,609/1,847,450.
Quyết định RESOURCE-CPU-01: cho phép CPU-only sync với ngân sách3GiB tổng dữ liệu
mới, giữ tối thiểu4GiB trống, kiểm disk sau sync và trước từng model. 12GiB vẫn
áp dụng CUDA/export profile lớn; không tự cài CUDA để tận dụng GPU. Đây là điều
chỉnh gate tài nguyên từ số đo, không giảm bất kỳ test/điều kiện G0–G4 nào.
T00 chỉ hoàn tất khi pinned sync/pip check/test qua. Kiểm bằng system Python trước
sync chỉ là provisional, không được ghi là pinned evidence.

Resume bắt đầu cửa sổ re-localization15s mới, không cộng thời gian paused.
Nếu bbox depth chứng minh emergency/near nhưng center thiếu support: giữ cảnh báo
đã đo, depth_status=insufficient và hold. Missing/invalid toàn depth không được suy
ra hazard mới hoặc clear từ distance cũ.

## Model smoke và tối ưu đã đo

YOLO exporter chọn one-to-one head ở bản copy, PT gốc mặc định one-to-many;
parity phải chọn `model.model.end2end=True` trước so sánh. Hai output top-k có
thể đổi thứ tự khi score gần bằng nhau: so ghép one-to-one không thứ tự toàn300
row, giữ tolerance1e-3, chỉ cho anchor khác ở score hòa tại cutoff cuối1e-6.
Không giảm confidence0.38, không NMS lần hai. Regression kiểm sai bbox/class
trên cutoff vẫn fail. Manifest ghi số row ghép và số cutoff-tie riêng.

CPU thread profile `docs/reports/cpu-thread-profile.json`: ảnh thật giống nhau,
5 mẫu/cấu hình sau warmup;8threadp95~716ms,4threadp95~230ms. Encoder CPU dùng4
thread từ đây. Đây chỉ là model latency, chưa phải G4 hoặc tổng mạng realtime.

Model downloads mới đã verify được đặt0644 để UID container10001 đọc được trên
mount read-only; secrets vẫn0600. Không chmod đệ quy thư mục người dùng. Container
base Python3.12.15 pin digest, host3.12.3; cùng targetminor3.12 và cùng uv.lock.
Hiện disk home<4GiB do thay đổi môi trường: không tải thêm wheel/model lớn hoặc
dọn cache ngoài scope; code/test nhỏ tiếp tục, Docker data nằm root filesystem.
# Final integration findings — 2026-10-21

- A fresh source copy exposed an integration test interpreter path tied to
  `backend/.venv`. The external-process test now uses `sys.executable`, so it
  exercises the selected pinned interpreter from an independent source copy.
- ASGI cancellation can repeat during each await. An unshielded WS cleanup
  could abandon its child tasks and surface a cancelled test-client future.
  A deterministic test cancels during receive and during cleanup. Cleanup now
  shields its bounded task drain with AnyIO CancelScope; AnyIO4.15.1 is a direct
  dependency, matching the already resolved transitive version. No worker slot
  is released until the actual inference callable returns.
- A public 182.753s indoor replay revealed HOLD_POSITION emitted on every lost
  frame. Lost voice reminders now use the existing 5000ms navigation cooldown
  in staged per-session core state. All intermediate frames still hold movement;
  a manual resume starts a new reminder episode. No threshold or TTL was loosened.
- Protocol-error sequence reflection is restricted to positive signed64 integers;
  invalid nested/string/bool sequence values are returned as null, never echoed.
- Public Zaragoza Ada footage is pipeline evidence only. Same-recording smoke
  reference frames and placeholder straight actions cannot satisfy G3 or G4.
- OpenAPI and typed WS schemas are generated from the app/Pydantic. Untyped WS
  envelope fields are explicitly transcribed from runtime source and labelled in
  the snapshot; this is not a claim that every outbound message uses Pydantic.
- Navigation helpers preserve caller input through cloned proposals; runtime's
  staged NavigationState remains a mutable dataclass. This implements observable
  immutability at the core boundary rather than a frozen Python dataclass.

