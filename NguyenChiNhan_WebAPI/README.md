# NguyenChiNhan_WebAPI

Web API Node.js (Express 5) cho Chí Nhân Store · Nguyễn Chí Nhân · CSDL `nguyenchinhan_db` (PostgreSQL). Tài liệu: `/swagger`.

- `src/app.js` ráp route, `src/db.js` tạo bảng + seed (tự chạy lần đầu), `src/security.js` JWT/OTP, `src/account.js` phiên + email cảnh báo, `src/mail.js` email Gmail.
- Route: `auth`, `me` (lịch sử đăng nhập, “Không phải tôi”), `categories`, `products`, `users`, `dashboard`, `tools` (dịch, tiếng ồn, vị trí).
- Biến môi trường: xem `.env.example`. Vercel: `api/index.js` + `vercel.json`.
- `npm test`: E2E 57 bước (đăng ký → OTP → phân quyền → CRUD → tiện ích → cảnh báo đăng nhập → khóa → đặt lại mật khẩu).
