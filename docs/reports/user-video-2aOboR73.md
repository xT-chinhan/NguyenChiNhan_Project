# Video khó hơn —2aOboR73

Đã chạy59 ảnh mẫu5fps trong11.886s, khác clip trước149 ảnh.
Nguồn720×1558, chuẩn hóa222×480 giữ tỉ lệ, bỏ audio; source hash trước/sau khớp.
Cùng DINOv2/YOLO ONNX, fingerprint/policy/model manifest như lần trước; không train.

[Video kết quả](../../backend/output/user-video-2aOboR73/annotated-model-test.mp4),
[contact sheet](../../backend/output/user-video-2aOboR73/model-contact-sheet.jpg),
[JSON evidence](user-video-2aOboR73.json).

## Kết quả

-59/59 ảnh qua pipeline model thật;42 ảnh có ít nhất1 detection,17 ảnh không có.
-42 person boxes,7 chair,3 mouse,1 dining table. Đây là số lần phát hiện trên ảnh,
  không phải số người hoặc số đồ vật khác nhau.
- Core RGB hold bật trên12 ảnh. Distance/TTC đều null. Không có detection/hold
  không có nghĩa cảnh an toàn; cuối clip camera chĩa xuống bàn không còn thấy lối.
- Khoảng0s nhận người gần camera;4.8s nhận được cả người đứng và người ngồi.
-3.2s: còn thấy thân người bị cắt sát camera nhưng model không trả box.
-6.4s: còn phần người ngồi ở mép trái nhưng model không trả box.
-Model-stage p95≈258ms. Đây là offline model/core diagnostic, không gồm mạng/API,
  không kiểm voice hoặc thời gian đáp ứng app. Detector input vẫn224×224 theo baseline.

Các nhận xét ví dụ từ assistant xem khung hình; không phải ground truth do người
chú giải và không dùng để tính precision/recall. Không tự điều chỉnh threshold
sau khi thấy test. Không tạo route/rẽ giả cho một clip xoay camera trong khu bàn ghế.
Chưa có ảnh tham chiếu/lượt query độc lập nên không chấm vị trí hay dẫn đúng tuyến.

Video MP4 đầu ra có59 frames,11.8s, chỉ video, không audio. Đã xác minh ffprobe,
hash source không đổi, normalized embeddings768D và RGB metricsnull. Code production,
model weights, policy và các receipts nguồn trước không thay đổi.
