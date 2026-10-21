// Tài liệu Swagger cho NguyenChiNhan_WebAPI (viết tay, gọn)
const obj = (props, required = []) => ({ type: 'object', required, properties: props })
const s = { type: 'string' }
const n = { type: 'number' }
const b = { type: 'boolean' }

// [method, path, tag, summary, roles|null(public), body?, query?]
const E = [
  ['post', '/api/auth/register', 'Xác thực', 'Đăng ký (Khách hàng) + gửi OTP xác thực email', null, obj({ fullName: s, username: s, email: s, password: s }, ['fullName', 'username', 'email', 'password'])],
  ['post', '/api/auth/verify-email', 'Xác thực', 'Nhập OTP kích hoạt tài khoản', null, obj({ username: s, code: s }, ['username', 'code'])],
  ['post', '/api/auth/login', 'Xác thực', 'Bước 1: tên đăng nhập + mật khẩu → gửi OTP qua email', null, obj({ username: s, password: s }, ['username', 'password'])],
  ['post', '/api/auth/login/verify', 'Xác thực', 'Bước 2: OTP → JWT + vai trò. Gửi email cảnh báo đăng nhập. Header tùy chọn X-Device-Name, X-Device-Platform', null, obj({ username: s, code: s }, ['username', 'code'])],
  ['post', '/api/auth/resend', 'Xác thực', 'Gửi lại OTP (chờ 45 giây giữa 2 lần)', null, obj({ username: s, purpose: { type: 'string', enum: ['verify_email', 'login', 'reset'] } }, ['username', 'purpose'])],
  ['post', '/api/auth/forgot', 'Xác thực', 'Quên mật khẩu: gửi OTP đặt lại', null, obj({ username: s }, ['username'])],
  ['post', '/api/auth/reset', 'Xác thực', 'Đặt mật khẩu mới bằng OTP', null, obj({ username: s, code: s, newPassword: s }, ['username', 'code', 'newPassword'])],
  ['post', '/api/auth/logout', 'Xác thực', 'Đăng xuất phiên hiện tại', []],
  ['get', '/api/me', 'Tài khoản', 'Thông tin người dùng đang đăng nhập', []],
  ['patch', '/api/me', 'Tài khoản', 'Bật/tắt email cảnh báo đăng nhập, đổi họ tên', [], obj({ loginAlert: b, fullName: s })],
  ['post', '/api/me/password', 'Tài khoản', 'Đổi mật khẩu', [], obj({ currentPassword: s, newPassword: s }, ['currentPassword', 'newPassword'])],
  ['get', '/api/me/sessions', 'Cảnh báo đăng nhập (mục 6)', 'Lịch sử đăng nhập, đánh dấu đăng nhập lạ', []],
  ['post', '/api/me/sessions/{id}/trust', 'Cảnh báo đăng nhập (mục 6)', '“Đúng là tôi”', []],
  ['post', '/api/me/sessions/{id}/deny', 'Cảnh báo đăng nhập (mục 6)', '“Không phải tôi”: đăng xuất mọi thiết bị, gửi mã đặt lại mật khẩu, báo Admin', []],
  ['get', '/api/categories', 'Danh mục', 'Danh sách danh mục (kèm số sản phẩm)', []],
  ['get', '/api/categories/{id}', 'Danh mục', 'Chi tiết danh mục', []],
  ['post', '/api/categories', 'Danh mục', 'Thêm danh mục', ['Admin'], obj({ name: s, description: s, icon: s }, ['name'])],
  ['put', '/api/categories/{id}', 'Danh mục', 'Sửa danh mục', ['Admin'], obj({ name: s, description: s, icon: s }, ['name'])],
  ['delete', '/api/categories/{id}', 'Danh mục', 'Xóa danh mục (sản phẩm không bị xóa)', ['Admin']],
  ['get', '/api/products', 'Sản phẩm', 'Danh sách sản phẩm', [], null, { q: 'Tìm theo tên/mô tả', categoryId: 'Lọc danh mục', sort: 'price_asc | price_desc | name | newest' }],
  ['get', '/api/products/{id}', 'Sản phẩm', 'Chi tiết sản phẩm', []],
  ['post', '/api/products', 'Sản phẩm', 'Thêm sản phẩm', ['Admin', 'Staff'], obj({ name: s, price: n, description: s, categoryId: n }, ['name', 'price'])],
  ['put', '/api/products/{id}', 'Sản phẩm', 'Sửa sản phẩm', ['Admin', 'Staff'], obj({ name: s, price: n, description: s, categoryId: n }, ['name', 'price'])],
  ['delete', '/api/products/{id}', 'Sản phẩm', 'Xóa sản phẩm', ['Admin']],
  ['get', '/api/users', 'Người dùng', 'Danh sách người dùng + số lượng theo vai trò', ['Admin'], null, { role: 'Admin | Staff | User', q: 'Tìm tên, email, tên đăng nhập' }],
  ['post', '/api/users', 'Người dùng', 'Tạo người dùng', ['Admin'], obj({ fullName: s, username: s, email: s, password: s, role: s }, ['fullName', 'username', 'email', 'password'])],
  ['put', '/api/users/{id}', 'Người dùng', 'Đổi vai trò / thông tin', ['Admin'], obj({ role: s, fullName: s, email: s })],
  ['delete', '/api/users/{id}', 'Người dùng', 'Xóa người dùng', ['Admin']],
  ['get', '/api/dashboard/admin', 'Dashboard', 'Tổng quan quản trị', ['Admin']],
  ['get', '/api/dashboard/staff', 'Dashboard', 'Tổng quan nhân viên', ['Admin', 'Staff']],
  ['get', '/api/tools/translate/languages', 'Tiện ích (mục 5)', 'Ngôn ngữ hỗ trợ', []],
  ['post', '/api/tools/translate', 'Tiện ích (mục 5)', 'f. Dịch chữ (app đọc chữ từ camera/ảnh)', [], obj({ text: s, source: s, target: s }, ['text'])],
  ['get', '/api/tools/noise/levels', 'Tiện ích (mục 5)', 'd. Bảng mức tiếng ồn', []],
  ['post', '/api/tools/noise/records', 'Tiện ích (mục 5)', 'd. Lưu lần đo, trả mức + lời khuyên', [], obj({ avgDb: n, maxDb: n, durationSec: n }, ['avgDb', 'maxDb', 'durationSec'])],
  ['get', '/api/tools/noise/records', 'Tiện ích (mục 5)', 'd. Lịch sử đo', []],
  ['post', '/api/tools/location/resolve', 'Tiện ích (mục 5)', 'b. Tọa độ → địa chỉ (không lưu)', [], obj({ lat: n, lng: n, accuracy: n }, ['lat', 'lng'])],
  ['post', '/api/tools/location/share', 'Tiện ích (mục 5)', 'b. Tọa độ → địa chỉ + nội dung chia sẻ', [], obj({ lat: n, lng: n, accuracy: n }, ['lat', 'lng'])],
  ['get', '/api/tools/location/history', 'Tiện ích (mục 5)', 'b. Lịch sử chia sẻ', []],
  ['get', '/api/attendance/today', 'Chấm công', 'Trạng thái hôm nay của tôi', ['Staff', 'Admin']],
  ['post', '/api/attendance/check-in', 'Chấm công', 'Vào ca (mỗi ngày 1 lần, sau 08:00 là trễ)', ['Staff', 'Admin']],
  ['post', '/api/attendance/check-out', 'Chấm công', 'Tan ca', ['Staff', 'Admin']],
  ['get', '/api/attendance/me', 'Chấm công', 'Bảng công tháng của tôi', ['Staff', 'Admin'], null, { month: 'YYYY-MM' }],
  ['get', '/api/attendance', 'Chấm công', 'Admin xem nhân viên đã chấm công trong ngày', ['Admin'], null, { date: 'YYYY-MM-DD' }],
]

const paths = {}
for (const [m, p, tag, summary, roles, body, query] of E) {
  const params = [...p.matchAll(/\{(\w+)\}/g)].map((x) => ({ name: x[1], in: 'path', required: true, schema: { type: 'integer' } }))
  for (const [k, d] of Object.entries(query || {})) params.push({ name: k, in: 'query', description: d, schema: s })
  paths[p] ??= {}
  paths[p][m] = {
    tags: [tag],
    summary: roles?.length ? `${summary} · [${roles.join(', ')}]` : summary,
    ...(roles ? { security: [{ bearer: [] }] } : {}),
    ...(params.length ? { parameters: params } : {}),
    ...(body ? { requestBody: { required: true, content: { 'application/json': { schema: body } } } } : {}),
    responses: { 200: { description: 'OK' }, 400: { description: 'Dữ liệu không hợp lệ' }, 401: { description: 'Chưa đăng nhập' }, 403: { description: 'Không đủ quyền' } },
  }
}

export const openapi = {
  openapi: '3.0.3',
  info: {
    title: 'NguyenChiNhan_WebAPI',
    version: '1.0.0',
    description: 'Web API cho app Chí Nhân Store · Nguyễn Chí Nhân · CSDL nguyenchinhan_db. Đăng nhập 2 bước (mật khẩu + OTP email), phân quyền Admin / Staff / User.',
  },
  components: { securitySchemes: { bearer: { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' } } },
  paths,
}

export const swaggerHtml = `<!doctype html><html lang="vi"><head><meta charset="utf-8"><title>NguyenChiNhan_WebAPI · Swagger</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css"></head>
<body><div id="ui"></div><script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
<script>SwaggerUIBundle({ url: '/openapi.json', dom_id: '#ui', persistAuthorization: true })</script></body></html>`
