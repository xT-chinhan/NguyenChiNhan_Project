import { Router } from 'express'
import bcrypt from 'bcryptjs'
import { q, one } from '../db.js'
import { auth, HttpError, publicUser } from '../security.js'

const ROLES = ['Admin', 'Staff', 'User']

// ---------- Người dùng (chỉ Admin) ----------
export const users = Router()
users.use(auth('Admin'))

users.get('/', async (req, res) => {
  const where = []
  const args = []
  if (ROLES.includes(req.query.role)) {
    args.push(req.query.role)
    where.push(`role = $${args.length}`)
  }
  if (req.query.q) {
    args.push(`%${String(req.query.q).trim()}%`)
    where.push(`(full_name ILIKE $${args.length} OR email ILIKE $${args.length} OR username ILIKE $${args.length})`)
  }
  const { rows } = await q(
    `SELECT * FROM users ${where.length ? 'WHERE ' + where.join(' AND ') : ''}
     ORDER BY array_position(ARRAY['Admin','Staff','User'], role), created_at`,
    args,
  )
  const counts = (await q(`SELECT role, count(*)::int AS n FROM users GROUP BY role`)).rows
  const c = Object.fromEntries(counts.map((x) => [x.role, x.n]))
  res.json({
    items: rows.map((u) => ({ ...publicUser(u), isMe: u.id === req.user.id })),
    counts: { all: (c.Admin || 0) + (c.Staff || 0) + (c.User || 0), Admin: c.Admin || 0, Staff: c.Staff || 0, User: c.User || 0 },
  })
})

users.post('/', async (req, res) => {
  const { fullName, username, email, password, role = 'User' } = req.body || {}
  if (!fullName || !username || !email || String(password || '').length < 6 || !ROLES.includes(role)) {
    throw new HttpError(400, 'Cần họ tên, tên đăng nhập, email, mật khẩu ≥ 6 ký tự và vai trò hợp lệ.', 'VALIDATION')
  }
  const uname = String(username).trim().toLowerCase()
  if (await one('SELECT 1 FROM users WHERE username = $1', [uname])) throw new HttpError(409, 'Tên đăng nhập đã được dùng.', 'USERNAME_TAKEN')
  const u = await one(
    `INSERT INTO users (username, email, full_name, password_hash, role, email_confirmed) VALUES ($1,$2,$3,$4,$5,true) RETURNING *`,
    [uname, String(email).trim().toLowerCase(), String(fullName).trim(), await bcrypt.hash(String(password), 10), role],
  )
  res.status(201).json(publicUser(u))
})

users.put('/:id', async (req, res) => {
  const id = Number(req.params.id)
  const { role, fullName, email } = req.body || {}
  if (role !== undefined && !ROLES.includes(role)) throw new HttpError(400, 'Vai trò không hợp lệ.', 'VALIDATION')
  if (id === req.user.id && role && role !== 'Admin') throw new HttpError(400, 'Không thể tự hạ quyền của chính mình.', 'SELF_DEMOTE')
  const u = await one(
    `UPDATE users SET role = COALESCE($2, role), full_name = COALESCE(NULLIF($3,''), full_name), email = COALESCE(NULLIF($4,''), email),
       token_version = token_version + CASE WHEN $2::text IS NOT NULL AND $2 <> role THEN 1 ELSE 0 END
     WHERE id = $1 RETURNING *`,
    [id, role ?? null, fullName ? String(fullName).trim() : null, email ? String(email).trim().toLowerCase() : null],
  )
  if (!u) throw new HttpError(404, 'Không tìm thấy người dùng.', 'NOT_FOUND')
  res.json(publicUser(u))
})

users.delete('/:id', async (req, res) => {
  const id = Number(req.params.id)
  if (id === req.user.id) throw new HttpError(400, 'Không thể tự xóa tài khoản đang dùng.', 'SELF_DELETE')
  const u = await one('DELETE FROM users WHERE id = $1 RETURNING full_name', [id])
  if (!u) throw new HttpError(404, 'Không tìm thấy người dùng.', 'NOT_FOUND')
  res.json({ message: `Đã xóa ${u.full_name}.` })
})

// ---------- Dashboard theo vai trò ----------
export const dashboard = Router()

dashboard.get('/admin', auth('Admin'), async (_req, res) => {
  const counts = (await q(`SELECT role, count(*)::int AS n FROM users GROUP BY role`)).rows
  const c = Object.fromEntries(counts.map((x) => [x.role, x.n]))
  const stats = await one(`SELECT (SELECT count(*)::int FROM products) AS products, (SELECT count(*)::int FROM categories) AS categories`)
  const logins = (
    await q(
      `SELECT DISTINCT ON (s.user_id) s.user_id, u.full_name AS "fullName", u.role, s.device, s.platform, s.city, s.created_at AS "createdAt"
       FROM sessions s JOIN users u ON u.id = s.user_id ORDER BY s.user_id, s.created_at DESC`,
    )
  ).rows.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt)).slice(0, 5)
  res.json({
    users: { total: (c.Admin || 0) + (c.Staff || 0) + (c.User || 0), Admin: c.Admin || 0, Staff: c.Staff || 0, User: c.User || 0 },
    products: stats.products,
    categories: stats.categories,
    recentLogins: logins,
  })
})

dashboard.get('/staff', auth('Admin', 'Staff'), async (req, res) => {
  const stats = await one(
    `SELECT (SELECT count(*)::int FROM products) AS products, (SELECT count(*)::int FROM categories) AS categories,
       (SELECT count(*)::int FROM activities WHERE user_id = $1 AND action IN ('create','update')
          AND created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Ho_Chi_Minh') AT TIME ZONE 'Asia/Ho_Chi_Minh') AS "myEditsToday"`,
    [req.user.id],
  )
  const recent = (
    await q(
      `SELECT id, action, title, detail, created_at AS "createdAt" FROM activities
       WHERE user_id = $1 AND action IN ('create','update','delete') ORDER BY created_at DESC LIMIT 5`,
      [req.user.id],
    )
  ).rows
  res.json({ ...stats, recentActivities: recent })
})
