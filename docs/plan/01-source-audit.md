# 01 — Nguồn đã kiểm tra và quyết định tái sử dụng

## 1. Hiện trạng có thật

- NAVI và BlindNav đã clone vào hai thư mục con; `.git` của cả hai đã bị xóa theo yêu cầu.
- Không có backend tích hợp, lockfile chung, schema chung hoặc giao thức giữa hai repo.
- Không biết commit từ metadata Git đã xóa; dùng SHA-256 các file bên dưới làm mốc đối chiếu.
- Mới đọc nguồn và metadata; chưa cài dependency, chưa chạy model, chưa chạy test upstream.
- Không thấy `.onnx`, `.pt` hoặc RealSense `.bag` trong hai bản clone.
- Có `BlindNav/media/IMG_4122.MOV`: HEVC, 1920×1080, khoảng 9.435 giây.
  Clip này chưa được gán nhãn tuyến đường, chỉ đủ làm ứng viên smoke test decode/inference.

## 2. NAVI: phần nào đang ở đâu

| Nguồn | Nội dung | Cách dùng cho backend mới |
|---|---|---|
| `NAVI/scripts/dinov2_http_gateway.py:636` | Load `facebook/dinov2-base` | Dùng cùng model, cố định revision/artifact |
| cùng file, `encode_with_dinov2():713` | CLS token, L2 normalization | Viết implementation nhỏ trong `vision/encoder.py` |
| cùng file, `/encode*:862–1028` | HTTP ảnh → vector | Tham chiếu; không chạy gateway cũ trong core mới |
| `NAVI/lib/services/real_time_navigation_service.dart:441` | So vector hiện tại với waypoint | Chuyển hành vi thành Python theo 03-core-rules |
| cùng file, `:660` | Chuyển sequence, kết thúc tuyến | Dùng state machine mới, xác nhận nhiều frame |
| cùng file, `:875` | Phục hồi vị trí bằng nhiều ảnh | Dùng tìm lại gần chặng cũ, không nhảy toàn tuyến |
| `NAVI/lib/models/path_models.dart:333` | Waypoint, heading, turn, sequence | Giữ ý nghĩa nhưng chuẩn hóa tên/đơn vị mới |
| `NAVI/lib/services/continuous_path_recorder.dart` | Ghi tuyến và ảnh theo waypoint | Làm nguồn tham khảo cho importer; chưa sửa client |
| `NAVI/lib/services/supabase_service.dart:1334` | Lưu navigation_paths và path_waypoints | Không tái sử dụng lớp truy cập Supabase trong backend |
| `NAVI/database_scheme.sql` | Chỉ khai báo maps và map_nodes | Không coi đây là migration đủ để chạy toàn NAVI |

Các điểm phải sửa trong thiết kế mới:
- NAVI có nhiều logic dẫn đường ở Dart, không thể chỉ đặt HTTP wrapper trước script Python.
- Cosine cao là độ giống hình, không phải xác suất “đã tới đúng vị trí”.
- Một lần match hiện có thể chuyển waypoint; backend mới cần 3 frame độc lập và kiểm tra mơ hồ.
- Inpainting xóa người/vật mang theo: không phù hợp làm đầu vào cảnh báo vật cản.
- Gateway có model fallback khác số chiều; backend mới chỉ nhận đúng fingerprint 768 chiều.
- Có URL IP nội bộ hardcode và CORS mở; backend mới đưa cấu hình vào env và đóng auth.
- Không chuyển câu khuyên “đi lùi vài bước” từ recovery cũ sang v1.

## 3. BlindNav: phần tái sử dụng được

Nguồn chính: `BlindNav/raspberry_pi/yolo_realsense_navigation.py`, khoảng hơn 3.000 dòng.
Không import file này từ server: đầu file có thư viện phần cứng và cấu hình side effect.

| Symbol nguồn | Đích mới | Quy tắc chuyển |
|---|---|---|
| `letterbox_resize():2645` | `vision/detector.py` | Giữ cách pad và đổi tọa độ; không dùng buffer global |
| `yolo_postprocess():2658` | `vision/detector.py` | Kiểm tra shape, finite, class và bbox chặt hơn |
| `ObjectTracker:2339`, `Track:2376` | `core/tracking.py` | Tracker riêng từng session; timestamp từ capture |
| `get_smart_distance():2678` | `core/depth.py` | Chuyển mm/cm giả định sang scale mét tường minh |
| `evaluate_track_motion():2597` | `core/obstacles.py` | TTC dùng range-closing velocity; không gọi vật xa là đang áp sát khi thiếu bằng chứng |
| `ThreatAssessment:2455` | `core/obstacles.py` | Chỉ tham khảo ngưỡng; policy mới theo đúng hợp đồng RGB/RGB-D |
| `EgoMotionCompensator:2713` | Chưa chuyển ở v1 | Không cần bù ego để tính TTC từ khoảng cách khép lại |
| `VoiceAssistant`, `PiperVoice`, `aplay` | Không chuyển | Server trả text/code; audio do client xử lý |
| `SceneDescriber`, voice command cloud | Không chuyển | Ngoài luồng core v1 |
| `main():2818` | Không chuyển | Camera/IMU/inference/voice đang gắn chung |

Lưu ý khi chuyển tracker:
- Một detection không được match hai track; một track không được nhận hai detection cùng frame.
- Track mới phải đánh dấu đã dùng ngay; nguồn cần thêm test cho trường hợp này.
- Ghost filter 3 lần quan sát đặt ở policy, không giấu track trong tracker.
- Track chưa đo được depth phải có `distance_m=null`, `ttc_s=null`.
- Không reuse depth đã cũ hoặc dùng depth của frame khác.
- Không lấy timestamp xử lý trên server làm timestamp đo tốc độ vật thể.
- Không suppress vật thể đứng yên khi người dùng đang tiến về phía nó.

`tests/test_blindnav.py` và `tests/test_blindnav_v326.py` có các ca tốt về
letterbox, bbox, IoU, smoothing, depth, ngưỡng và chống phát lặp.
Chuyển các ca liên quan sang kiểm tra module mới; không copy cả harness mock phần cứng.
Không tuyên bố toàn bộ test audio/Pi upstream đã được chuyển hoặc đã chạy.

## 4. Bất tương thích dependency đã thấy

| Thành phần | NAVI | BlindNav | Quyết định |
|---|---|---|---|
| NumPy | `2.0.1` | `1.26.4` | Baseline backend `1.26.4` |
| OpenCV | `4.12.0.88` | `>=4.8.0` | Headless `4.11.0.86`, tránh kéo NumPy 2 vào baseline |
| Mô hình detector | Ultralytics `8.3.191`, YOLOv8 | YOLO26n ONNX | Model export môi trường riêng, runtime chỉ ONNX |
| Phần cứng | Camera Flutter | RealSense/Pi/IMU | Không import SDK phần cứng vào server |
| Audio | Flutter TTS | Piper/aplay | Core chỉ tạo sự kiện và câu Việt |
| Database | Supabase client từ app | Không có catalog tuyến | PostgreSQL và migration mới |

Đây là ràng buộc thiết kế, không phải tuyên bố file requirements BlindNav đã đầy đủ.
Ví dụ production script còn import `pyrealsense2` mà requirements hiện có không kê đủ.

## 5. Môi trường quan sát tại thời điểm viết plan

- Python hệ thống: 3.12.3.
- Docker: 29.1.3.
- `uv` có sẵn trong PATH.
- GPU: NVIDIA GeForce RTX 3050 Laptop, 6.144 MiB VRAM; driver 570.211.01.
- Không đo RAM, dung lượng trống hoặc hiệu năng model; T00/T04 phải đo trước khi tải/nạp.
- Chỉ xem metadata thiết bị; không thay driver, không đặt mua/tạo server.

## 6. Nguồn model đã đối chiếu

- DINOv2: https://huggingface.co/facebook/dinov2-base
- Revision API trả về: `f9e44c814b77203eaa57a6bdbbd535f21ede1415`.
- Chỉ tải config/processor và safetensors của revision này; không dùng `trust_remote_code`.
- YOLO26n: https://github.com/ultralytics/assets/releases/tag/v8.4.0
- Asset: `https://github.com/ultralytics/assets/releases/download/v8.4.0/yolo26n.pt`.
- Kích thước asset theo GitHub: 5.544.453 byte.
- SHA-256 asset theo GitHub API:
  `9b09cc8bf347f0fc8a5f7657480587f25db09b34bf33b0652110fb03a8ad4fef`.
- ONNX do T04 export; phải tạo SHA-256 riêng sau export, không dùng hash `.pt` cho `.onnx`.
- Đối chiếu export: https://docs.ultralytics.com/integrations/onnx/
- NMS-free/end-to-end: https://docs.ultralytics.com/models/yolo26/

Không suy ra model nhận đủ loại chướng ngại chỉ vì output có 80 COCO classes.
Depth không được sinh ra từ YOLO detection model này.

## 7. Giấy phép và nguồn gốc

- BlindNav có `LICENSE` MIT, copyright Anthonyiswhy 2026: giữ thông báo khi chuyển code.
- NAVI README có badge MIT nhưng bản clone không có LICENSE độc lập.
  V1 dùng mô tả hành vi và công thức để viết module mới; chưa sao chép nguyên khối Dart/Python.
- Không đặt nhãn MIT cho toàn sản phẩm vì model YOLO có điều kiện giấy phép riêng.
- Tài liệu Ultralytics công bố AGPL-3.0/Enterprise cho code/model:
  https://docs.ultralytics.com/models/yolo26/#citations-and-acknowledgments
- DINOv2-base model card ghi Apache-2.0.
- T00 tạo `backend/THIRD_PARTY_NOTICES.md`, ghi nguồn, phần đã copy/adapt, model và license.
- Việc triển khai nội bộ theo plan không tự cấp quyền publish thương mại/đóng mã.
  Rà điều kiện cấp phép ở release gate; không tự mua license hoặc đổi model trong task khác.

## 8. Hash nguồn làm mốc

```text
43a82a4a661987f351b1ecda30589a1ee18161e61e7ee7017d8ec3b71e07bf09  NAVI/scripts/dinov2_http_gateway.py
5c5fdae474a434f256b4ffff77babd8d36972ff7bb1b2f39961d5c71f3563e84  NAVI/lib/services/real_time_navigation_service.dart
c7195932e3708bb41034ccad6cf0869430545985e9331c63bc8f98821d3a8597  NAVI/lib/models/path_models.dart
7a8efbda71d873ca0c3d52796c93e4ed1cd5a9ba2d6844ade52032cebb724cd3  NAVI/database_scheme.sql
f87e881659d25cf9cfc0351149c68463f511e432e7c517565ae760fa5d398131  NAVI/requirements.txt
df2284fff2cc7dd2841b64dda79805a1f77cc3b62713889c7f04310dbbe2aa82  BlindNav/raspberry_pi/yolo_realsense_navigation.py
2078a7848d8e4595ab60017d52ed5f8125e23c9427acba840fa6197a87c78ad4  BlindNav/tests/test_blindnav.py
b98a72bfccc4e1809ce10c110acf2eea15e602c2d2ac2735d12b4f2b442adb08  BlindNav/tests/test_blindnav_v326.py
1c157fbd17cd61510f449cb49ff3694eba65c02689dc124dbb1c40b696c1d80a  BlindNav/LICENSE
```

Nếu hash thay đổi trước triển khai, agent đọc diff tương ứng và cập nhật audit.
Không cố khôi phục `.git`, không tự tạo commit để thay thế bằng chứng nguồn.

