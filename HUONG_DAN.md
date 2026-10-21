# Hướng dẫn dùng Chí Nhân Store · Nguyễn Chí Nhân

- **Tải app (Android):** mục [Releases](https://github.com/xT-chinhan/NguyenChiNhan_Project/releases) → file `ChiNhanStore-NguyenChiNhan.apk` → cài (cho phép “Cài ứng dụng không rõ nguồn gốc”).
- **Web API + Swagger:** https://nguyenchinhan-webapi.vercel.app/swagger
- App cần Internet. Mọi xử lý nằm ở API, app chỉ hiển thị.

## Tài khoản mẫu
| Vai trò | Tên đăng nhập | Mật khẩu | Vào trang |
|---|---|---|---|
| Quản trị | `chinhan` | `Admin@123` | Tổng quan · Danh mục · Sản phẩm · Người dùng · Tài khoản |
| Nhân viên | `phuc` | `Staff@123` | Tổng quan · Sản phẩm · Chấm công · Tiện ích · Tài khoản |
| Khách hàng | `baongoc` | `User@123` | Cửa hàng · Tiện ích · Tài khoản |

Mã OTP của 3 tài khoản mẫu gửi về **hutech.vn.online@gmail.com**. Muốn tự nhận OTP: bấm **Tạo tài khoản mới** bằng email của mình (tài khoản mới là Khách hàng; Admin đổi vai trò ở tab Người dùng).

## 1. Đăng ký · Đăng nhập (OTP email)
1. **Đăng ký:** Tạo tài khoản mới → nhập họ tên, tên đăng nhập, email, mật khẩu → nhập mã 6 số trong email để kích hoạt.
2. **Đăng nhập:** tên đăng nhập + mật khẩu → **Tiếp tục** → nhập mã 6 số gửi về email (hiệu lực 5 phút, sai 3 lần phải lấy mã mới, gửi lại sau 45 giây).
3. **Quên mật khẩu:** nhập tên đăng nhập → **Quên mật khẩu?** → mã trong email → mật khẩu mới.

## 2. Phân quyền
App tự vào đúng trang theo vai trò API trả về: Quản trị → trang quản trị, Nhân viên → Dashboard nhân viên, Khách hàng → Cửa hàng.

## 3. Chức năng CRUD
- **Quản trị:** Danh mục (+ thêm, chạm để sửa, vuốt trái để xóa), Sản phẩm (thêm/sửa/xóa), Người dùng (thêm, đổi vai trò, xóa).
- **Nhân viên:** thêm và sửa sản phẩm (không xóa được), xem hoạt động gần đây.
- **Khách hàng:** xem, tìm, lọc danh mục, sắp xếp giá, xem chi tiết sản phẩm.

## 4. Ba chức năng (tab Tiện ích)
- **Dịch realtime:** hướng camera vào chữ tiếng Anh → bản dịch hiện trên khung hình; hoặc **Chụp & dịch** / **Chọn ảnh**.
- **Đo tiếng ồn:** đo dB bằng micro, trên 85 dB báo đỏ; **Dừng & lưu** để API đánh giá và lưu lần đo.
- **Chia sẻ vị trí:** lấy GPS → API tìm địa chỉ → **Chia sẻ vị trí** gửi link Google Maps qua Zalo/Messenger/SMS.

## 5. Tính năng mới: Email cảnh báo đăng nhập
- Mỗi lần đăng nhập, email báo thời gian, thiết bị, vị trí (theo IP).
- Bấm **Không phải tôi** (trong email hoặc Tài khoản → Lịch sử đăng nhập): đăng xuất mọi thiết bị, gửi mã đặt lại mật khẩu, báo Quản trị viên.
- Bật/tắt: Tài khoản → Bảo mật → Email cảnh báo đăng nhập.

## 6. Chấm công bằng GPS (Nhân viên)
1. Đăng nhập `phuc` → tab **Chấm công** → cho phép dùng vị trí.
2. Ở trong bán kính cửa hàng (dải xanh “Trong khu vực cửa hàng”) → **Vào ca**; cuối ngày → **Tan ca**. Mỗi ngày 1 lần, vào sau 08:00 tính là trễ.
3. Ngoài bán kính / vị trí giả / GPS sai số lớn: API chặn, nút bị khóa.
- **Mốc mặc định:** HUTECH 475A Điện Biên Phủ, bán kính 100 m. **Đổi mốc khi test ở chỗ khác:** đăng nhập `chinhan` → Tài khoản → **Vị trí chấm công** → **Đặt tại vị trí hiện tại của tôi** → chọn bán kính → **Lưu**.
- **Quản trị xem công:** Tài khoản → **Chấm công nhân viên** (chọn ngày, ai có mặt / trễ / chưa vào).

## Khác
- Giao diện tối: Tài khoản → Giao diện tối.
- Chạy app từ mã nguồn: `cd nguyen_chi_nhan_app && flutter pub get && flutter run`.
