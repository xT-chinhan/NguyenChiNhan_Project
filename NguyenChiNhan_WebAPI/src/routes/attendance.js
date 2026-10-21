import { Router } from 'express'
import { q, one } from '../db.js'
import { auth, HttpError } from '../security.js'

// Chấm công đơn giản: mỗi ngày 1 lần Vào ca + 1 lần Tan ca. Giờ tính theo Việt Nam.
export const attendance = Router()
attendance.use(auth('Staff', 'Admin'))

const TZ = 'Asia/Ho_Chi_Minh'
export const SHIFT_START = '08:00' // vào sau giờ này = đi trễ
const today = `(now() AT TIME ZONE '${TZ}')::date`

const view = (r) =>
  r && {
    id: r.id,
    date: r.date,
    checkIn: r.check_in,
    checkOut: r.check_out,
    late: r.late,
    minutes: r.minutes,
  }
// Cột chung: ngày, giờ vào/ra, trễ (vào sau SHIFT_START), số phút làm
const colsOf = (t = '') => `${t}id, to_char(${t}work_date, 'YYYY-MM-DD') AS date, ${t}check_in, ${t}check_out,
  (${t}check_in AT TIME ZONE '${TZ}')::time > '${SHIFT_START}' AS late,
  CASE WHEN ${t}check_out IS NULL THEN NULL ELSE floor(extract(epoch FROM ${t}check_out - ${t}check_in) / 60)::int END AS minutes`
const cols = colsOf()

// Hôm nay của người đang đăng nhập
attendance.get('/today', async (req, res) => {
  const r = await one(`SELECT ${cols} FROM attendances WHERE user_id = $1 AND work_date = ${today}`, [req.user.id])
  res.json({ shiftStart: SHIFT_START, record: view(r), status: !r ? 'none' : r.check_out ? 'done' : 'working' })
})

attendance.post('/check-in', async (req, res) => {
  const r = await one(
    `INSERT INTO attendances (user_id, work_date, check_in) VALUES ($1, ${today}, now())
     ON CONFLICT (user_id, work_date) DO NOTHING RETURNING id`,
    [req.user.id],
  )
  if (!r) throw new HttpError(409, 'Hôm nay bạn đã vào ca rồi.', 'ALREADY_CHECKED_IN')
  const rec = view(await one(`SELECT ${cols} FROM attendances WHERE id = $1`, [r.id]))
  res.status(201).json({ message: rec.late ? `Đã vào ca (trễ, sau ${SHIFT_START}).` : 'Đã vào ca.', record: rec })
})

attendance.post('/check-out', async (req, res) => {
  const cur = await one(`SELECT * FROM attendances WHERE user_id = $1 AND work_date = ${today}`, [req.user.id])
  if (!cur) throw new HttpError(409, 'Bạn chưa vào ca hôm nay.', 'NOT_CHECKED_IN')
  if (cur.check_out) throw new HttpError(409, 'Hôm nay bạn đã tan ca rồi.', 'ALREADY_CHECKED_OUT')
  await q('UPDATE attendances SET check_out = now() WHERE id = $1', [cur.id])
  const rec = view(await one(`SELECT ${cols} FROM attendances WHERE id = $1`, [cur.id]))
  res.json({ message: 'Đã tan ca.', record: rec })
})

// Bảng công tháng của tôi: ?month=YYYY-MM (mặc định tháng này)
attendance.get('/me', async (req, res) => {
  const month = /^\d{4}-\d{2}$/.test(req.query.month || '') ? req.query.month : null
  const { rows } = await q(
    `SELECT ${cols} FROM attendances WHERE user_id = $1
       AND date_trunc('month', work_date) = date_trunc('month', COALESCE($2::date, ${today}))
     ORDER BY work_date DESC`,
    [req.user.id, month ? `${month}-01` : null],
  )
  const items = rows.map(view)
  const minutes = items.reduce((s, x) => s + (x.minutes || 0), 0)
  res.json({
    month: month || (await one(`SELECT to_char(${today}, 'YYYY-MM') AS m`)).m,
    days: items.length,
    lateDays: items.filter((x) => x.late).length,
    totalMinutes: minutes,
    items,
  })
})

// Admin: ai đã chấm công trong một ngày: ?date=YYYY-MM-DD (mặc định hôm nay)
attendance.get('/', auth('Admin'), async (req, res) => {
  const date = /^\d{4}-\d{2}-\d{2}$/.test(req.query.date || '') ? req.query.date : null
  const { rows } = await q(
    `SELECT u.id AS "userId", u.full_name AS "fullName", u.username, ${colsOf('a.')}
     FROM users u LEFT JOIN attendances a ON a.user_id = u.id AND a.work_date = COALESCE($1::date, ${today})
     WHERE u.role = 'Staff' ORDER BY a.check_in NULLS LAST, u.full_name`,
    [date],
  )
  const items = rows.map((r) => ({ userId: r.userId, fullName: r.fullName, username: r.username, record: r.id ? view(r) : null }))
  res.json({
    date: date || (await one(`SELECT to_char(${today}, 'YYYY-MM-DD') AS d`)).d,
    shiftStart: SHIFT_START,
    total: items.length,
    present: items.filter((x) => x.record).length,
    late: items.filter((x) => x.record?.late).length,
    items,
  })
})
