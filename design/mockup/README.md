# Chí Nhân Store · Mockup mobile (chờ duyệt)

Mở `index.html` trực tiếp. Ảnh 2x trong `shots/`, toàn bộ ở `shots/overview.png`. Chụp lại: `node design/shoot.mjs [tiền tố]`.
Style lấy nguyên token của Thu Chi (`styles.css`); phần riêng ở `ncn.css`.

| Mục | Màn | Yêu cầu đề |
|---|---|---|
| A | 01 Đăng nhập · 02 Đăng ký · 03 OTP xác thực email · 04 OTP đăng nhập · 05 OTP sai · 06 Email OTP | 1, 2 |
| B | 10 Cửa hàng · 11 Chi tiết SP · 12 Tiện ích · 13 Tài khoản (Khách hàng) | 3 |
| C | 20 Dịch camera · 21 Dịch ảnh chụp · 22–23 Đo tiếng ồn · 24–25 Chia sẻ vị trí | 5 (f, d, b) |
| D | 30 Dashboard NV · 31 Sản phẩm · 32 Sửa SP · 33 Đã lưu | 3, 4 |
| E | 40 Dashboard Admin · 41–43 Danh mục CRUD · 44 Sản phẩm (có Xóa) · 45–46 Người dùng + đổi vai trò · 47 Tài khoản | 3, 4 |
| F | 50 Email cảnh báo đăng nhập · 51 Lịch sử đăng nhập · 52 Sau “Không phải tôi” | 6 |
| G | 60 Đang tải · 61 Không tìm thấy · 62 Mất kết nối | 7 |

## Quyết định
- Đăng nhập 2 bước: tên đăng nhập + mật khẩu → OTP 6 số qua email (hiệu lực 5 phút, sai 3 lần phải lấy mã mới).
- Đăng ký công khai luôn là Khách hàng; Quản trị viên đổi vai trò ở màn 46.
- Phân quyền: Khách hàng 3 tab, Nhân viên 4 tab (thêm/sửa SP, không xóa), Quản trị 5 tab (xóa được, quản lý người dùng; Tiện ích vào từ Tài khoản).
- Màu chỉ mang nghĩa: đỏ = vượt 85 dB / xóa / OTP sai, vàng = đăng nhập lạ / chưa xác thực, xanh = thành công.
- Mục 6: mỗi lần đăng nhập thành công gửi email (thời gian, thiết bị, vị trí theo IP) có nút “Không phải tôi” → đăng xuất mọi thiết bị, gửi mã đặt lại mật khẩu, báo Admin. Bật/tắt ở Tài khoản.
