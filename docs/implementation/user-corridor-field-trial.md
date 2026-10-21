# Tuyến hành lang từ video đầu

Nguồn: `/home/chinhan/Downloads/2758876741140513705.mp4`.
Đã publish tuyến `Hành lang video đầu của bạn`, hướng đi từ mốc khoảng5s tới
cửa đôi cuối hành lang (~13–14s), trước chỗ rẽ vào cầu thang.

Hướng dẫn và ảnh hai đầu tuyến:
https://act-personal-costa-costa.trycloudflare.com/mobile/corridor-guide.html
Nút mở trang camera trong hướng dẫn đã preset map/from/to đúng chiều.
Dùng token thiết bị hiện tại; không dùng token quản trị. Không tự bắt đầu phiên
hay bật camera; người dùng nhập token và bấm bắt đầu.

-2checkpoint,6ảnh tham chiếu; hành động straight→arrive.
-Kiểm trực tiếp REST/WS/model thật nhận CONTINUE_STRAIGHT và ARRIVED trên6ảnh
cùng video. Không coi đây là kiểm thử độc lập hoặc đo chính xác tuyến.
-Playwright qua Cloudflare xác nhận preset đúng map/hai điểm/route, auth browserWS,
nhận kết quả ảnh và pause/resume/stop. Camera giả lập.
-31unit tests route/bundle và3Node guard tests pass.
-Preview JPEG public chỉ là2ảnh hành lang đã chọn trong video; asset allowlist
vẫn chặn file tùy ý. Dữ liệu tham chiếu và import receipt lưu trong
`backend/output/corridor-first-video-route`.

Không thay model, match threshold, freshness1s, camera timeout300ms,
3-hit confirmation1500ms hoặc lost timeout15s. Hiện trường khác sáng/góc nhìn,
chậm mạng hoặc đi lâu giữa2mốc vẫn có thể không xác nhận được. Thử có người đi
cùng, dừng trước cầu thang; không dùng để tự quyết định đường đi an toàn.
Receipt hiện tại: `docs/reports/user-corridor-field-trial.json`.
