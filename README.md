<div align="center">

# Nguyễn Chí Nhân

![Flutter](https://img.shields.io/badge/Flutter-3.47-111?logo=flutter&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-Express-111?logo=nodedotjs&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-Neon-111?logo=postgresql&logoColor=white)
![Vercel](https://img.shields.io/badge/API-Vercel-111?logo=vercel&logoColor=white)

[**Tải APK**](https://github.com/xT-chinhan/NguyenChiNhan_Project/releases/latest) · [**Bản web (iPhone)**](https://nguyenchinhan-app.vercel.app) · [Web API](https://nguyenchinhan-webapi.vercel.app/swagger) · [Hướng dẫn](HUONG_DAN.md) · [Checklist](CHECKLIST.txt)

<img src="design/mockup/shots/01-dang-nhap.png" width="160"> <img src="design/mockup/shots/10-kh-cua-hang.png" width="160"> <img src="design/mockup/shots/70-cc-chua-vao-ca.png" width="160"> <img src="design/mockup/shots/40-ad-tong-quan.png" width="160">

</div>

## Tài khoản

| Vai trò | Tên đăng nhập | Mật khẩu |
|---|---|---|
| Quản trị | `chinhan` | `Admin@123` |
| Nhân viên | `phuc` | `Staff@123` |
| Khách hàng | `baongoc` | `User@123` |

> OTP gửi về `hutech.vn.online@gmail.com`. Muốn tự nhận mã: **Tạo tài khoản mới** bằng email của bạn.

## Chức năng

- [x] **Đăng ký qua email** · OTP kích hoạt
- [x] **Đăng nhập** · tên + mật khẩu + OTP email
- [x] **Phân quyền** · Quản trị / Nhân viên / Khách hàng
- [x] **CRUD** · Danh mục · Sản phẩm · Người dùng
- [x] **Dịch realtime** · camera + ảnh chụp
- [x] **Đo tiếng ồn** · dB realtime, cảnh báo > 85 dB
- [x] **Chia sẻ vị trí** · GPS → link Google Maps
- [x] **Email cảnh báo đăng nhập** · “Không phải tôi” khóa tài khoản *(tính năng mới)*
- [x] **Chấm công GPS** · vào / tan ca trong bán kính cửa hàng
- [x] **Giao diện** · theo mockup, sáng / tối

## Cấu trúc

```
NguyenChiNhan_WebAPI/   Web API Node.js · CSDL nguyenchinhan_db
nguyen_chi_nhan_app/    App Flutter (chỉ giao diện)
design/mockup/          41 màn thiết kế
```

## Chạy

```bash
# API
cd NguyenChiNhan_WebAPI && npm install && npm run dev   # npm test: 96 bước E2E

# App
cd nguyen_chi_nhan_app && flutter pub get && flutter run
```
