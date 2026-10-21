# Hợp đồng client dẫn đường v1

Server chọn tuyến, định vị và đánh giá vật cản; thiết bị giữ camera, timestamp,
giao diện TalkBack, TTS tiếng Việt, rung và xử lý mất hỗ trợ. Chưa sửa Flutter.
Schema wire chuẩn ở `docs/plan/02-contracts.md`; không đưa chi tiết model vào UI.

1. Token thiết bị qua Authorization Bearer header; không query token. HTTP lấy
   map/places/routes published, chọn tuyến một chiều đã thu, POST session.
2. Kết nối WebSocket bằng header. Mỗi capture_request mới chụp một ảnh mới,
   pixels upright, JPEG tối đa384KiB, timestamp monotonic tăng; echo seq/token.
   Không gửi video tự do hoặc cache frame trước challenge.
3. RGB luôn distance/TTC=null. RGB-D chỉ gửi grayscalePNG16bit căn ảnh màu,
   đúng calibration_id/scale phiên và skew<=50ms. Thiếu depth phải hold.
4. Nhận frame_result: movement_held=true luôn xóa hàng đợi lệnh di chuyển,
   kể cả instruction=null do cooldown. Status pause/lost/worker lỗi cũng xóa.
5. Chỉ bắt đầu phát instruction nếu tuổi capture **<1000ms** và thời gian hiện
   tại **<receive+valid_for_ms**. Tính lại trước khi TTS thực sự bắt đầu, không
   chỉ lúc nhận JSON. ID đã trình bày thì không đọc lại trừ thao tác repeat.
6. ACK received khi nhận; ACK presented khi bắt đầu TTS/hiển thị lúc còn hạn.
   Chỉ ID departure hiện tại server nhận trước deadline mới mở bước kế tiếp.
   ACK không chứng minh người dùng đã rẽ hoặc đã tới checkpoint.
7. Emergency/warning mới hủy guidance đang chờ. Không giữ câu “đi tiếp” để đọc
   sau cảnh báo. Không tự đọc lại lệnh cũ sau reconnect hoặc hết TTL.
8. Watchdog1500ms không có frame_result **mới, còn hạn**: hủy movement, đọc một
   lần “Đã mất kết nối hoặc hình ảnh mới. Hướng dẫn đang tạm dừng.”, báo rung.
   Heartbeat chỉ báo kết nối; không làm mới watchdog hoặc tuổi ảnh.
9. Hỗ trợ pause/resume/repeat/stop bằng điều khiển tiếp cận được. Reconnect vào
   paused cần resume; backend định vị lại last/next, không nhảy cả tuyến.
10. Token revoked/expired hoặc server restart: báo trạng thái rõ và tạo phiên
    mới khi được cấp quyền; không giả tiếp tục phiên cũ từ cache điện thoại.

Replay chỉ trình bày stdout với `presentation_kind=stdout_simulation`; không
thể dùng nó để khẳng định TTS, mic, rung, TalkBack hoặc người dùng thật đã thử.
Thiết bị thật cần nhiệm vụ riêng đo camera/network/heading/calibration/audio và
foreground lifecycle. Bản RGB không tự tránh vật cản, không thay thế gậy/hỗ trợ.
