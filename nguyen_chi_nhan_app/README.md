# nguyen_chi_nhan_app · Chí Nhân Store

App Flutter **chỉ là UI**: gọi `NguyenChiNhan_WebAPI` cho mọi nghiệp vụ (đăng nhập OTP, phân quyền, CRUD, dịch, đánh giá tiếng ồn, địa chỉ vị trí, cảnh báo đăng nhập). Máy chỉ làm phần cần phần cứng: camera + đọc chữ (ML Kit), micro đo dB, GPS.

```
lib/
  core/       api.dart (client + phiên), theme.dart (token mockup), fmt.dart, icons.dart
  widgets/    ui.dart (card, nút, ô nhập, list, sheet, skeleton), otp.dart
  features/   auth · home (tab theo vai trò) · shop · tools · staff · admin · account
_old_utility/ code tiện ích cũ (báo thức, YouTube, đổi đơn vị…) đã tạm ngưng
```
Đổi API: `flutter run --dart-define=API_URL=http://10.0.2.2:5055`. Mặc định `https://nguyenchinhan-webapi.vercel.app`.
