# Chí Nhân Store · Nguyễn Chí Nhân

Đồ án Lập trình di động. **App Flutter chỉ là giao diện, mọi nghiệp vụ nằm ở Web API.**

| Thành phần | Thư mục | Công nghệ |
|---|---|---|
| Web API | `NguyenChiNhan_WebAPI/` | Node.js (Express 5) · deploy Vercel · Swagger `/swagger` |
| Cơ sở dữ liệu | `nguyenchinhan_db` | PostgreSQL (Neon trên Vercel / local cổng 5433) |
| App mobile | `nguyen_chi_nhan_app/` | Flutter 3.47 · Android / iOS |
| Mockup | `design/mockup/` | 34 màn, mở `index.html` |

## Tài khoản mẫu (seed lần đầu, OTP gửi về email seed)
| Vai trò | Tên đăng nhập | Mật khẩu | Vào trang |
|---|---|---|---|
| Quản trị | `chinhan` | `Admin@123` | Tổng quan · Danh mục · Sản phẩm · Người dùng · Tài khoản |
| Nhân viên | `phuc` | `Staff@123` | Tổng quan · Sản phẩm · Tiện ích · Tài khoản |
| Khách hàng | `baongoc` | `User@123` | Cửa hàng · Tiện ích · Tài khoản |

## Đối chiếu yêu cầu
| # | Yêu cầu | Làm ở |
|---|---|---|
| 1 | Đăng ký qua email | `POST /api/auth/register` → OTP email → `/verify-email` |
| 2 | Đăng nhập tên + mật khẩu + OTP | `/auth/login` (gửi OTP) → `/auth/login/verify` (JWT) |
| 3 | Phân quyền Admin / Nhân viên / Khách | JWT `role`, middleware `auth('Admin','Staff')`, app chọn trang theo role |
| 4 | CRUD | Danh mục, Sản phẩm, Người dùng (+ lịch sử hoạt động) |
| 5 | 3 chức năng | f Dịch realtime/ảnh chụp · d Đo tiếng ồn · b Chia sẻ vị trí (`/api/tools/*`) |
| 6 | Tính năng mới | Email cảnh báo đăng nhập + “Không phải tôi” khóa tài khoản, báo Admin |
| + | Chấm công (nhánh `feature/cham-cong`) | `/api/attendance/*`: Vào ca / Tan ca bằng GPS trong bán kính cửa hàng; API tính khoảng cách, chặn vị trí giả / GPS sai số > 150 m, đi trễ sau 08:00; Admin đổi mốc + bán kính |
| 7 | Giao diện | Theo mockup đã duyệt, sáng/tối, skeleton, trạng thái rỗng/mất mạng |

## Chạy
```bash
# API local (Postgres 5433)
cd NguyenChiNhan_WebAPI && cp .env.example .env && npm install && npm run dev
npm test        # E2E toàn bộ API (cần MAIL_DEV=1)

# App
cd nguyen_chi_nhan_app && flutter pub get
flutter run                                              # dùng API trên Vercel
flutter run --dart-define=API_URL=http://10.0.2.2:5055   # dùng API local từ máy ảo Android
flutter test                                             # dựng các màn với dữ liệu thật, so ảnh
```
