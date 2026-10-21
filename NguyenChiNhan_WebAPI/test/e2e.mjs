// E2E toàn bộ API. Cần server chạy với MAIL_DEV=1 (OTP trả về trong devCode).
// Chạy: API_URL=http://localhost:5055 node test/e2e.mjs
const BASE = process.env.API_URL || `http://localhost:${process.env.PORT || 5055}`
let pass = 0
let fail = 0
const ok = (cond, name, extra) => {
  if (cond) pass++
  else {
    fail++
    console.log('  ✗', name, extra !== undefined ? JSON.stringify(extra).slice(0, 300) : '')
  }
}
async function call(method, path, body, token, headers = {}) {
  const r = await fetch(BASE + path, {
    method: method.toUpperCase(),
    headers: { 'content-type': 'application/json', ...(token ? { authorization: `Bearer ${token}` } : {}), ...headers },
    body: body ? JSON.stringify(body) : undefined,
  })
  const text = await r.text()
  let data
  try {
    data = JSON.parse(text)
  } catch {
    data = text
  }
  return { status: r.status, data }
}
async function login(username, password, device = 'Test Device') {
  const a = await call('post', '/api/auth/login', { username, password })
  if (a.status !== 200) return { a }
  const b = await call('post', '/api/auth/login/verify', { username, code: a.data.devCode }, null, { 'x-device-name': device, 'x-device-platform': 'Android 14' })
  return { a, b, token: b.data.token }
}

const uniq = Date.now().toString(36)
const newUser = `kh${uniq}`

console.log('E2E', BASE)

// --- 1. Đăng ký qua email ---
let r = await call('post', '/api/auth/register', { fullName: 'Khách Test', username: newUser, email: 'test@example.com', password: '123' })
ok(r.status === 400, 'register: mật khẩu ngắn bị chặn', r)
r = await call('post', '/api/auth/register', { fullName: 'Khách Test', username: newUser, email: 'test@example.com', password: 'Test@123' })
ok(r.status === 201 && /^\d{6}$/.test(r.data.devCode) && r.data.maskedEmail === 'tes•••@example.com', 'register: tạo + OTP', r)
const regCode = r.data.devCode
r = await call('post', '/api/auth/login', { username: newUser, password: 'Test@123' })
ok(r.status === 403 && r.data.code === 'EMAIL_NOT_VERIFIED', 'login trước khi xác thực email bị chặn', r)
const badReg = regCode === '000000' ? '111111' : '000000'
r = await call('post', '/api/auth/verify-email', { username: newUser, code: badReg })
ok(r.status === 400 && r.data.code === 'OTP_INVALID' && r.data.attemptsLeft === 2, 'verify-email: mã sai', r)
r = await call('post', '/api/auth/verify-email', { username: newUser, code: regCode })
ok(r.status === 200, 'verify-email: mã đúng kích hoạt', r)
r = await call('post', '/api/auth/register', { fullName: 'X', username: newUser, email: 'x@example.com', password: 'Test@123' })
ok(r.status === 409, 'register: trùng tên đăng nhập đã kích hoạt', r)

// --- 2. Đăng nhập 2 bước + OTP sai ---
r = await call('post', '/api/auth/login', { username: newUser, password: 'sai' })
ok(r.status === 401, 'login: sai mật khẩu', r)
r = await call('post', '/api/auth/login', { username: newUser, password: 'Test@123' })
ok(r.status === 200 && r.data.otpRequired && r.data.devCode, 'login bước 1 gửi OTP', r)
const loginCode = r.data.devCode
const wrong = loginCode === '123456' ? '654321' : '123456'
r = await call('post', '/api/auth/login/verify', { username: newUser, code: wrong })
ok(r.status === 400 && r.data.code === 'OTP_INVALID' && r.data.attemptsLeft === 2, 'OTP sai: còn 2 lần', r)
r = await call('post', '/api/auth/login/verify', { username: newUser, code: loginCode }, null, { 'x-device-name': 'Galaxy A54', 'x-device-platform': 'Android 14' })
ok(r.status === 200 && r.data.role === 'User' && r.data.token, 'login bước 2: JWT + role User', r)
const khToken = r.data.token
r = await call('post', '/api/auth/login/verify', { username: newUser, code: loginCode })
ok(r.status === 400, 'OTP dùng lại bị chặn', r)
r = await call('post', '/api/auth/resend', { username: newUser, purpose: 'login' })
ok(r.status === 429 && r.data.resendAfter > 0, 'resend: cooldown 45s', r)

// --- 3. Phân quyền ---
const ad = await login('chinhan', 'Admin@123', 'Admin Phone')
ok(ad.b?.data.role === 'Admin', 'admin login -> Admin', ad.b?.data)
const nv = await login('phuc', 'Staff@123', 'Staff Phone')
ok(nv.b?.data.role === 'Staff', 'staff login -> Staff', nv.b?.data)
const A = ad.token
const S = nv.token
r = await call('get', '/api/me', null, khToken)
ok(r.status === 200 && r.data.username === newUser, 'GET /me', r)
r = await call('get', '/api/dashboard/admin', null, S)
ok(r.status === 403, 'staff không vào dashboard admin', r)
r = await call('get', '/api/dashboard/staff', null, khToken)
ok(r.status === 403, 'khách không vào dashboard staff', r)
r = await call('get', '/api/users', null, S)
ok(r.status === 403, 'staff không quản lý người dùng', r)
r = await call('get', '/api/products', null)
ok(r.status === 401, 'chưa đăng nhập không xem sản phẩm', r)

// --- 4. CRUD ---
r = await call('get', '/api/categories', null, khToken)
ok(r.status === 200 && r.data.length >= 3 && r.data[0].productCount >= 0, 'khách xem danh mục', r)
r = await call('post', '/api/categories', { name: 'Sách' }, S)
ok(r.status === 403, 'staff không thêm danh mục', r)
r = await call('post', '/api/categories', { name: 'Sách', description: 'Giáo trình' }, A)
ok(r.status === 201 && r.data.name === 'Sách', 'admin thêm danh mục', r)
const catId = r.data.id
r = await call('put', `/api/categories/${catId}`, { name: 'Sách & Truyện', description: 'Giáo trình, truyện' }, A)
ok(r.status === 200 && r.data.name === 'Sách & Truyện', 'admin sửa danh mục', r)
r = await call('post', '/api/products', { name: 'Giáo trình Flutter', price: 120000, categoryId: catId }, khToken)
ok(r.status === 403, 'khách không thêm sản phẩm', r)
r = await call('post', '/api/products', { name: 'Giáo trình Flutter', price: 120000, categoryId: catId, description: 'Sách' }, S)
ok(r.status === 201 && r.data.categoryName === 'Sách & Truyện' && r.data.price === 120000, 'staff thêm sản phẩm', r)
const pid = r.data.id
r = await call('put', `/api/products/${pid}`, { name: 'Giáo trình Flutter', price: 99000, categoryId: catId, description: 'Sách' }, S)
ok(r.status === 200 && r.data.price === 99000, 'staff sửa giá', r)
r = await call('get', '/api/dashboard/staff', null, S)
ok(r.status === 200 && r.data.recentActivities[0].title === 'Sửa giá Giáo trình Flutter' && r.data.recentActivities[0].detail.includes('120.000đ → 99.000đ') && r.data.myEditsToday >= 2, 'dashboard staff ghi hoạt động', r.data)
r = await call('delete', `/api/products/${pid}`, null, S)
ok(r.status === 403, 'staff không xóa sản phẩm', r)
r = await call('get', `/api/products?categoryId=${catId}&q=flutter`, null, khToken)
ok(r.status === 200 && r.data.length === 1, 'lọc + tìm sản phẩm', r)
r = await call('get', '/api/products?sort=price_desc', null, khToken)
ok(r.data[0].price >= r.data[1].price, 'sắp xếp giá giảm', r.data.slice(0, 2))
r = await call('delete', `/api/categories/${catId}`, null, A)
ok(r.status === 200 && r.data.unassignedProducts === 1, 'xóa danh mục, SP giữ lại', r)
r = await call('get', `/api/products/${pid}`, null, A)
ok(r.status === 200 && r.data.categoryId === null, 'SP không còn danh mục', r)
r = await call('delete', `/api/products/${pid}`, null, A)
ok(r.status === 200, 'admin xóa sản phẩm', r)
r = await call('post', '/api/products', { name: '', price: -1 }, A)
ok(r.status === 400, 'validate sản phẩm', r)

// Người dùng
r = await call('get', '/api/users?role=User', null, A)
ok(r.status === 200 && r.data.items.every((u) => u.role === 'User') && r.data.counts.Admin >= 1, 'admin lọc người dùng', r.data.counts)
const meRow = (await call('get', '/api/users', null, A)).data.items.find((u) => u.username === newUser)
r = await call('put', `/api/users/${meRow.id}`, { role: 'Staff' }, A)
ok(r.status === 200 && r.data.role === 'Staff', 'admin đổi vai trò -> Staff', r)
r = await call('get', '/api/me', null, khToken)
ok(r.status === 401, 'đổi vai trò thu hồi token cũ', r)
const selfId = (await call('get', '/api/me', null, A)).data.id
r = await call('delete', `/api/users/${selfId}`, null, A)
ok(r.status === 400, 'admin không tự xóa mình', r)
r = await call('get', '/api/dashboard/admin', null, A)
ok(r.status === 200 && r.data.users.total >= 4 && r.data.recentLogins.length >= 1, 'dashboard admin', r.data)

// --- 5. Tiện ích ---
r = await call('post', '/api/tools/translate', { text: 'EMERGENCY EXIT\nNO SMOKING', source: 'en', target: 'vi' }, S)
ok(r.status === 200 && r.data.translated.length > 0, 'dịch Anh -> Việt', r.data)
r = await call('get', '/api/tools/noise/levels', null, S)
ok(r.status === 200 && r.data.levels.length === 5, 'bảng mức ồn', r)
r = await call('post', '/api/tools/noise/records', { avgDb: 80, maxDb: 91, durationSec: 58 }, S)
ok(r.status === 201 && r.data.level.key === 'very_loud' && r.data.safeMinutes === 120, 'đo ồn 91 dB -> 2 giờ', r.data)
r = await call('post', '/api/tools/noise/records', { avgDb: 61, maxDb: 68, durationSec: 32 }, S)
ok(r.data.level.key === 'moderate' && r.data.safeMinutes === null, 'đo ồn 68 dB', r.data)
r = await call('post', '/api/tools/location/share', { lat: 10.80182, lng: 106.71481, accuracy: 8 }, S)
ok(r.status === 201 && r.data.mapsUrl.includes('10.80182,106.71481') && r.data.shareText.includes('📍'), 'chia sẻ vị trí', r.data)
r = await call('post', '/api/tools/location/share', { lat: 200, lng: 0 }, S)
ok(r.status === 400, 'tọa độ sai', r)

// --- 6. Email cảnh báo đăng nhập + “Không phải tôi” ---
let out = await call('get', '/api/dev/outbox')
ok(out.data.some((m) => m.subject.includes('Đăng nhập') && m.html.includes('Không phải tôi')), 'email cảnh báo đã gửi', out.data.map((m) => m.subject))
// đăng nhập từ thiết bị lạ bằng tài khoản mẫu khách hàng
const kh1 = await login('baongoc', 'User@123', 'Galaxy A54')
const kh2 = await login('baongoc', 'User@123', 'Chrome · Windows ' + uniq)
r = await call('get', '/api/me/sessions', null, kh1.token)
const strange = r.data.items.find((x) => x.device.startsWith('Chrome'))
ok(r.status === 200 && strange?.suspicious === true && r.data.items.find((x) => x.current), 'lịch sử: có đăng nhập lạ', r.data)
r = await call('patch', '/api/me', { loginAlert: false }, kh1.token)
ok(r.status === 200 && r.data.loginAlert === false, 'tắt cảnh báo', r)
await call('patch', '/api/me', { loginAlert: true }, kh1.token)
// link trong email: GET chỉ hiện trang xác nhận
out = await call('get', '/api/dev/outbox')
const alert = [...out.data].reverse().find((m) => m.html.includes('/deny?t='))
const denyLink = alert.html.match(/href="([^"]+\/deny\?t=[^"]+)"/)[1].replace(/^https?:\/\/[^/]+/, '')
r = await call('get', denyLink)
ok(r.status === 200 && String(r.data).includes('Khóa tài khoản ngay'), 'link email GET = trang xác nhận', String(r.data).slice(0, 80))
r = await call('get', '/api/me', null, kh2.token)
ok(r.status === 200, 'GET link chưa khóa gì', r)
// “Không phải tôi” từ app
r = await call('post', `/api/me/sessions/${strange.id}/deny`, null, kh1.token)
ok(r.status === 200 && r.data.revokedSessions >= 2 && r.data.adminsNotified >= 1, 'không phải tôi: khóa', r.data)
r = await call('get', '/api/me', null, kh1.token)
ok(r.status === 401 && r.data.code === 'SESSION_REVOKED', 'mọi phiên bị thu hồi', r)
r = await call('post', '/api/auth/login', { username: 'baongoc', password: 'User@123' })
ok(r.status === 403 && r.data.code === 'MUST_RESET', 'bị khóa: phải đặt mật khẩu mới', r)
out = await call('get', '/api/dev/outbox')
ok(out.data.some((m) => m.subject.includes('[Cảnh báo]')), 'admin nhận email báo', out.data.map((m) => m.subject))
const resetMail = [...out.data].reverse().find((m) => m.subject.includes('đặt lại mật khẩu'))
const resetCode = resetMail.subject.match(/(\d{6})$/)[1]
r = await call('post', '/api/auth/reset', { username: 'baongoc', code: resetCode, newPassword: 'User@123' })
ok(r.status === 200, 'đặt lại mật khẩu bằng mã trong email', r)
const kh3 = await login('baongoc', 'User@123', 'Galaxy A54')
ok(kh3.b?.status === 200, 'đăng nhập lại sau khi đặt mật khẩu', kh3.b?.data)
r = await call('post', '/api/auth/logout', null, kh3.token)
r = await call('get', '/api/me', null, kh3.token)
ok(r.status === 401, 'logout thu hồi phiên', r)

console.log(`\n${pass} pass, ${fail} fail`)
process.exit(fail ? 1 : 0)
