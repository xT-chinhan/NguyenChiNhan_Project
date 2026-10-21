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
  const b = await call('post', '/api/auth/login/verify', { username, code: a.data.devCode }, null, { 'x-device-name': encodeURIComponent(device), 'x-device-platform': 'Android 14' })
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
r = await call('post', '/api/tools/ocr', { image: (await import('node:fs')).readFileSync(new URL('./ocr-sample.jpg', import.meta.url)).toString('base64'), source: 'en', target: 'vi' }, S)
ok(r.status === 200 && r.data.lines === 3 && r.data.text.includes('EMERGENCY EXIT') && r.data.translated.length > 0, 'OCR ảnh -> chữ -> dịch', r.data)
r = await call('post', '/api/tools/ocr', { image: (await import('node:fs')).readFileSync(new URL('./ocr-photo-vi.jpg', import.meta.url)).toString('base64'), target: 'en' }, S)
ok(r.status === 200 && r.data.source === 'vi' && r.data.pairs.length >= 2 && /SMOKING/i.test(r.data.translated), 'OCR ảnh mờ tiếng Việt -> Anh', r.data)
r = await call('post', '/api/tools/translate', { text: 'Xin chào các bạn\nGood morning everyone', target: 'vi' }, S)
ok(r.status === 200 && r.data.pairs[0].lang === 'vi' && r.data.pairs[1].lang === 'en' && r.data.pairs[0].translated === 'Xin chào các bạn' && /chào/i.test(r.data.pairs[1].translated), 'dịch tự nhận ngôn ngữ từng dòng', r.data)
r = await call('post', '/api/tools/ocr', { image: 'abc' }, S)
ok(r.status === 400, 'OCR ảnh hỏng bị chặn', r)
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
ok((await call('get', '/api/me/sessions', null, kh2.token)).data.items.find((x) => x.current)?.device === 'Chrome · Windows ' + uniq, 'tên thiết bị có dấu · không lỗi font')
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

// --- Chấm công GPS (nhánh feature/cham-cong) ---
const adT = (await login('chinhan', 'Admin@123', 'Admin Phone')).token
const khT = (await login('baongoc', 'User@123', 'Galaxy A54')).token
const nvName = `nv${uniq}`
r = await call('post', '/api/users', { fullName: 'Nhân Viên Test', username: nvName, email: 'nv@example.com', password: 'Staff@123', role: 'Staff' }, adT)
ok(r.status === 201, 'admin tạo nhân viên test', r)
const nvT = (await login(nvName, 'Staff@123', 'NV Phone')).token
const SITE = { lat: 10.80182, lng: 106.71481 }
const IN = { lat: 10.802, lng: 106.7149, accuracy: 12 } // ~22 m
const EDGE_IN = { lat: 10.80262, lng: 106.71481, accuracy: 10 } // ~89 m
const EDGE_OUT = { lat: 10.80272, lng: 106.71481, accuracy: 10 } // ~100,1 m
const FAR = { lat: 10.8231, lng: 106.6297, accuracy: 10 } // ~9,6 km

r = await call('get', '/api/attendance/today', null, khT)
ok(r.status === 403, 'khách không chấm công', r)
r = await call('get', '/api/attendance/today', null, nvT)
ok(r.status === 200 && r.data.status === 'none' && r.data.serverTime && r.data.hint && r.data.site.radius === 100 && r.data.site.lat === SITE.lat, 'today: chưa vào ca + giờ máy chủ + mốc', r.data)
r = await call('post', '/api/attendance/check-location', IN, nvT)
ok(r.status === 200 && r.data.allowed && r.data.code === 'INSIDE' && r.data.distance > 15 && r.data.distance < 30 && r.data.message.startsWith('Trong khu vực'), 'check-location trong khu vực', r.data)
r = await call('post', '/api/attendance/check-location', EDGE_IN, nvT)
ok(r.data.allowed === true && r.data.distance <= 100, 'biên 89 m: được', r.data)
r = await call('post', '/api/attendance/check-location', EDGE_OUT, nvT)
ok(r.data.allowed === false && r.data.code === 'OUTSIDE_AREA', 'biên 100,1 m: không được', r.data)
r = await call('post', '/api/attendance/check-location', FAR, nvT)
ok(r.data.allowed === false && r.data.code === 'OUTSIDE_AREA' && r.data.distanceText.endsWith('km') && r.data.message.includes('Cần ở trong 100 m'), 'check-location ngoài 9,6 km', r.data)
r = await call('post', '/api/attendance/check-location', { ...IN, isMocked: true }, nvT)
ok(r.data.allowed === false && r.data.code === 'MOCK_LOCATION', 'vị trí giả lập bị chặn', r.data)
r = await call('post', '/api/attendance/check-location', { ...IN, accuracy: 400 }, nvT)
ok(r.data.allowed === false && r.data.code === 'GPS_INACCURATE', 'GPS sai số 400 m bị chặn', r.data)
r = await call('post', '/api/attendance/check-location', {}, nvT)
ok(r.status === 400 && r.data.code === 'LOCATION_REQUIRED', 'thiếu tọa độ', r)

r = await call('post', '/api/attendance/check-out', IN, nvT)
ok(r.status === 409 && r.data.code === 'NOT_CHECKED_IN', 'tan ca khi chưa vào ca', r)
r = await call('post', '/api/attendance/check-in', null, nvT)
ok(r.status === 400 && r.data.code === 'LOCATION_REQUIRED', 'vào ca không gửi GPS bị chặn', r)
r = await call('post', '/api/attendance/check-in', FAR, nvT)
ok(r.status === 403 && r.data.code === 'OUTSIDE_AREA' && r.data.distance > 9000, 'vào ca ở xa bị chặn', r.data)
r = await call('post', '/api/attendance/check-in', { ...IN, isMocked: true }, nvT)
ok(r.status === 403 && r.data.code === 'MOCK_LOCATION', 'vào ca bằng vị trí giả bị chặn', r.data)
r = await call('get', '/api/attendance/today', null, nvT)
ok(r.data.status === 'none', 'bị chặn thì không ghi gì', r.data)
r = await call('post', '/api/attendance/check-in', IN, nvT)
ok(r.status === 201 && r.data.record.checkIn && typeof r.data.record.late === 'boolean' && r.data.record.inDistanceText.endsWith(' m'), 'vào ca trong khu vực', r.data)
r = await call('post', '/api/attendance/check-in', IN, nvT)
ok(r.status === 409 && r.data.code === 'ALREADY_CHECKED_IN', 'vào ca 2 lần bị chặn', r)
r = await call('get', '/api/attendance/today', null, nvT)
ok(r.data.status === 'working' && r.data.workingMinutes >= 0 && r.data.hint.includes('đi trễ'), 'today: đang làm', r.data)
r = await call('post', '/api/attendance/check-out', FAR, nvT)
ok(r.status === 403 && r.data.code === 'OUTSIDE_AREA', 'tan ca ở xa bị chặn', r.data)
r = await call('post', '/api/attendance/check-out', EDGE_IN, nvT)
ok(r.status === 200 && r.data.record.checkOut && r.data.record.minutes >= 0 && r.data.record.outDistanceText, 'tan ca trong khu vực', r.data)
r = await call('post', '/api/attendance/check-out', IN, nvT)
ok(r.status === 409 && r.data.code === 'ALREADY_CHECKED_OUT', 'tan ca 2 lần bị chặn', r)
r = await call('get', '/api/attendance/today', null, nvT)
ok(r.data.status === 'done' && r.data.hint === 'Hẹn gặp lại ngày mai.', 'today: đã tan ca', r.data)
r = await call('get', '/api/attendance/me', null, nvT)
ok(r.status === 200 && r.data.days === 1 && r.data.items[0].checkOut && r.data.totalHoursText.endsWith('h') && r.data.lateDays === (r.data.items[0].late ? 1 : 0), 'bảng công tháng', r.data)

// Mốc chấm công
r = await call('get', '/api/attendance/site', null, nvT)
ok(r.status === 200 && r.data.radius === 100 && r.data.name, 'xem mốc', r.data)
r = await call('put', '/api/attendance/site', { radius: 200 }, nvT)
ok(r.status === 403, 'nhân viên không đổi mốc', r)
r = await call('put', '/api/attendance/site', { radius: 5 }, adT)
ok(r.status === 400, 'bán kính 5 m bị chặn', r)
r = await call('put', '/api/attendance/site', { ...FAR, isMocked: true }, adT)
ok(r.status === 403 && r.data.code === 'MOCK_LOCATION', 'admin đặt mốc bằng vị trí giả bị chặn', r)
r = await call('put', '/api/attendance/site', { lat: FAR.lat, lng: FAR.lng, radius: 200 }, adT)
ok(r.status === 200 && r.data.site.lat === FAR.lat && r.data.site.radius === 200 && r.data.site.address, 'admin đặt mốc tại vị trí hiện tại', r.data)
r = await call('post', '/api/attendance/check-location', IN, nvT)
ok(r.data.allowed === false && r.data.radius === 200, 'mốc mới áp dụng ngay (chỗ cũ thành ngoài)', r.data)
r = await call('post', '/api/attendance/check-location', FAR, nvT)
ok(r.data.allowed === true, 'mốc mới: tại chỗ mới được', r.data)
r = await call('put', '/api/attendance/site', { ...SITE, radius: 100, name: 'Chí Nhân Store' }, adT)
ok(r.status === 200 && r.data.site.lat === SITE.lat && r.data.site.radius === 100, 'đặt lại mốc HUTECH 100 m', r.data)

// Admin xem theo ngày
r = await call('get', '/api/attendance', null, nvT)
ok(r.status === 403, 'nhân viên không xem công người khác', r)
r = await call('get', '/api/attendance', null, adT)
const mine = r.data.items?.find((x) => x.username === nvName)
ok(r.status === 200 && r.data.isToday && mine?.record?.inDistanceText && r.data.present >= 1, 'admin xem chấm công hôm nay + khoảng cách', r.data)
r = await call('get', '/api/attendance?date=2020-01-01', null, adT)
ok(r.status === 200 && r.data.present === 0 && r.data.date === '2020-01-01' && r.data.isToday === false, 'admin xem ngày cũ', r.data)
await call('delete', `/api/users/${(await call('get', `/api/users?q=${nvName}`, null, adT)).data.items[0].id}`, null, adT)

console.log(`\n${pass} pass, ${fail} fail`)
process.exit(fail ? 1 : 0)
