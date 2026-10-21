# Web mobile thử backend

Mở trên máy đang chạy server: http://127.0.0.1:8095/mobile.
Không cần cài Flutter/APK. Trang dùng camera trình duyệt, gửi ảnh khi server
yêu cầu, chọn tuyến published, trình bày hướng dẫn và đọc tiếng Việt nếu browser
có giọng vi-VN. Nút pause/resume/repeat/stop có nhãn tiếp cận được.

## Token thiết bị

Đã tạo token riêng cho bản web trong
`backend/config/mobile-web-device.env` (quyền0600). Mở file cục bộ, lấy giá trị
`NAV_DEVICE_TOKEN` nhập vào trang. Không dùng `NAV_ADMIN_TOKEN`.
Token chỉ giữ trong bộ nhớ tab, input được xóa sau kết nối; không localStorage,
sessionStorage, URL, subprotocol hay bundle JS. Không gửi file token qua chat/public.

## Android qua USB — cách nhanh nhất

1. Bật Developer options và USB debugging, cắm USB, chấp nhận quyền trên điện thoại.
2. Tại máy này chạy `adb devices`; thiết bị phải hiện trạng thái `device`.
3. Chạy `adb reverse tcp:8095 tcp:8095` (chọn `adb -s SERIAL` nếu nhiều máy).
4. Mở Chrome điện thoại tại `http://localhost:8095/mobile`, nhập token thiết bị.
5. Cho phép camera, chọn khu vực/điểm đầu/điểm đến, tìm tuyến rồi bắt đầu.
6. Kết thúc phiên bằng nút Kết thúc. Khi xong USB, dùng
   `adb reverse --remove tcp:8095` trên đúng thiết bị.

Không tự chạy adb reverse khi chưa có thiết bị được xác nhận. Cách USB đưa
localhost server vào localhost điện thoại mà không mở port ra LAN/Internet.
Không thể chỉ nhập127.0.0.1 trên điện thoại rồi kỳ vọng đó là máy tính nếu chưa
có reverse/proxy. Địa chỉ `http://LAN-IP` thường không có quyền camera.

## Wi-Fi hoặc iPhone

Đã bật Cloudflare Quick Tunnel theo yêu cầu của người dùng:
https://act-personal-costa-costa.trycloudflare.com/mobile.
Dùng Wi-Fi hoặc mạng di động, cho phép camera. Nhập NAV_DEVICE_TOKEN từ
`backend/config/cloudflare-mobile-device.env` (0600, token thử riêng, hết hạn
2026-10-22 16:41 giờ Việt Nam). Chọn khu vực demo, Smoke start → Smoke end,
tìm tuyến rồi bật camera. Token không đặt trong URL hoặc bundle công khai.

Tunnel trỏ tới localhost8095; không cần mở firewall. API chỉ tin forwarded
headers từ127.0.0.1 và gateway Docker172.20.0.1 qua
`backend/config/compose.tunnel.yaml` và `backend/config/tunnel.env`.
Origin check vẫn được bật. Camera gửi qua Cloudflare tới server.

Giữ máy tính, container API và cloudflared đang chạy; URL tạm đổi nếu tạo lại
tunnel. PID/start_ticks/URL nằm ở
`backend/output/cloudflare-mobile/process.json`; chỉ dừng đúng tiến trình này,
không dùng pkill cloudflared vì máy có tunnel khác đang chạy.

Public HTTPS và luồng camera giả lập → WSS → model thật đã kiểm thành công;
chi tiết ở `docs/reports/cloudflare-mobile-readiness.json`. Chưa kiểm camera
hay giọng đọc trên điện thoại thật. Giọng vi-VN phụ thuộc trình duyệt/thiết bị.

## Tuyến và phạm vi thử

DB hiện có `Public Zaragoza Ada - SMOKE ONLY`, `Smoke start` → `Smoke end`.
Tuyến này chỉ để kiểm API/camera; không có liên hệ với hành lang người dùng
đang đứng. Chọn nó có thể nhận `localizing/lost`, không phải lỗi kết nối.
Chưa nhập tuyến thực từ video người dùng thành bản khảo sát được xác nhận.

Trang không tự tạo bản đồ hoặc hiểu mọi chỗ rẽ từ một video. Muốn hướng dẫn đúng
tại hiện trường phải có tuyến và ảnh tham chiếu của địa điểm đó. Các đánh giá
G3/G4 và thiết bị G5 vẫn chưa đạt; không dùng một mình hay đi cầu thang theo bản này.

## Hợp đồng trình duyệt

- REST giữ Bearer header như cũ; endpoint browser mới
  `/v1/mobile/sessions/{id}/stream` bắt buộc Origin cùng origin, accept rồi nhận
  đúng message đầu `{"type":"auth","token":"<device token>"}` trong3s.
  JSON≤512byte, không fields khác; kiểm auth DB≤3s và device role trước truy cập
  phiên. Không gửi welcome/challenge trước khi xác thực và kiểm ownership.
  Tiếp theo là giao thức capture/frame/control/ACK hiện có.
- Endpoint header-auth `/v1/sessions/{id}/stream` vẫn xác thực trước accept.
- Ảnh mới từ requestVideoFrameCallback, canvas upright fit640×480, JPEG quality75
  giới hạn384KiB; echo capture timestamp từ performance.now(), seq/frame_token.
  Không tự gửi liên tục hoặc lưu backlog, RGB heading/distance/TTC không giả.
- Hai TTL được kiểm trước TTS và tại onstart; presented ACK sau bắt đầu trình
  bày hợp lệ. Nếu tắt audio thì ACK theo lúc hiển thị. Repeat không kéo dài
  deadline cũ. Trình duyệt chưa hỗ trợ callback khung mới sẽ pause thay vì dùng
  ảnh cache. Không bảo đảm voice có sẵn trên mọi điện thoại.
- Watchdog1500ms chỉ dựa fresh frame result, không heartbeat. Pause/disconnect/
  hidden tab/camera end hủy lệnh chờ; hidden/stop đóng camera. Reconnect không
  auto-resume. Một phiên cho mỗi token thiết bị.

## Kiểm tra đã chạy

-338 pytest cases+18 subtests, PostgreSQL và model thật;1 deprecation warning.
-3 Node guard tests: strict capture/receipt TTL, watchdog và earliest repeat expiry.
-Playwright Chrome viewport390×844, camera giả lập, DB/model thật: chọn tuyến,
  token memory-only, camera→WS→fresh result, pause/resume/stop, release camera,
  không browser runtime errors. Không xem đây là camera/voice phone validation.
-Token/Origin/role/ownership/binary/oversize bị chặn; header clients vẫn chạy.
-Sửa lỗi startup cũ: load model lúc startup không còn bị tính vào inference
  worker10s sticky fault. Frame TTL1000ms và inference fault10s giữ nguyên.

Nguồn mới và evidence ở `docs/reports/mobile-web-readiness.json`,
`mobile-web-build-inputs.json`, `mobile-web-tests.xml` và browser report.
Các benchmark/receipt trước web giữ source hash cũ, không gán cho bản web mới.
Không đổi model, encoder fingerprint hoặc thresholds, không sửa upstream Flutter.
