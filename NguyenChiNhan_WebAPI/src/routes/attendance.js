import { Router } from 'express'
import { q, one } from '../db.js'
import { auth, HttpError } from '../security.js'
import { reverseGeocode } from './tools.js'

// Chấm công bằng GPS: mỗi ngày 1 lần Vào ca + 1 lần Tan ca, phải ở trong bán kính cửa hàng.
// Mọi luật nằm ở đây; app chỉ gửi tọa độ và hiển thị kết quả.
export const attendance = Router()
attendance.use(auth('Staff', 'Admin'))

const TZ = 'Asia/Ho_Chi_Minh'
export const SHIFT_START = '08:00' // vào sau giờ này = đi trễ
export const MAX_ACCURACY_M = 150 // GPS sai số lớn hơn thì không nhận
const today = `(now() AT TIME ZONE '${TZ}')::date`

// ---------- Vị trí ----------
export function distanceM(a, b) {
  const R = 6371000
  const rad = (d) => (d * Math.PI) / 180
  const dLat = rad(b.lat - a.lat)
  const dLng = rad(b.lng - a.lng)
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2
  return 2 * R * Math.asin(Math.sqrt(h))
}

export const distanceText = (m) =>
  m == null ? null : m < 1000 ? `${Math.round(m)} m` : `${(m / 1000).toFixed(1).replace('.', ',')} km`

const getSite = () => one('SELECT * FROM attendance_site WHERE id = 1')
const siteView = (s) => ({ name: s.name, address: s.address, lat: s.lat, lng: s.lng, radius: s.radius_m, updatedAt: s.updated_at })

function parseFix(body) {
  const lat = Number(body?.lat)
  const lng = Number(body?.lng)
  if (body?.lat == null || body?.lng == null || !Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    throw new HttpError(400, 'Cần vị trí GPS để chấm công. Bật Vị trí rồi thử lại.', 'LOCATION_REQUIRED')
  }
  const accuracy = body?.accuracy == null ? null : Number(body.accuracy)
  return { lat, lng, accuracy: Number.isFinite(accuracy) ? accuracy : null, isMocked: body?.isMocked === true }
}

/** Đánh giá vị trí so với mốc: trả về allowed + code + message để app hiển thị nguyên văn */
function evaluate(fix, site) {
  const d = distanceM(fix, site)
  const base = { distance: Math.round(d), distanceText: distanceText(d), radius: site.radius_m, accuracy: fix.accuracy }
  if (fix.isMocked) {
    return { ...base, allowed: false, code: 'MOCK_LOCATION', message: 'Phát hiện vị trí giả lập. Tắt app giả vị trí rồi thử lại.' }
  }
  if (fix.accuracy != null && fix.accuracy > MAX_ACCURACY_M) {
    return { ...base, allowed: false, code: 'GPS_INACCURATE', message: `Vị trí chưa đủ chính xác (±${Math.round(fix.accuracy)} m). Ra chỗ thoáng rồi cập nhật lại.` }
  }
  if (d > site.radius_m) {
    return { ...base, allowed: false, code: 'OUTSIDE_AREA', message: `Cách cửa hàng ${distanceText(d)}. Cần ở trong ${site.radius_m} m để chấm công.` }
  }
  return { ...base, allowed: true, code: 'INSIDE', message: `Trong khu vực cửa hàng · cách ${distanceText(d)}` }
}

async function requireInside(body) {
  const site = await getSite()
  const fix = parseFix(body)
  const ev = evaluate(fix, site)
  if (!ev.allowed) throw new HttpError(403, ev.message, ev.code, ev)
  return { fix, ev }
}

// ---------- Bản ghi ----------
// Cột chung: ngày, giờ vào/ra, trễ (vào sau SHIFT_START), số phút làm, khoảng cách lúc chấm
const colsOf = (t = '') => `${t}id, to_char(${t}work_date, 'YYYY-MM-DD') AS date, ${t}check_in, ${t}check_out,
  (${t}check_in AT TIME ZONE '${TZ}')::time > '${SHIFT_START}' AS late,
  CASE WHEN ${t}check_out IS NULL THEN NULL ELSE floor(extract(epoch FROM ${t}check_out - ${t}check_in) / 60)::int END AS minutes,
  ${t}in_distance, ${t}out_distance`
const cols = colsOf()

const view = (r) =>
  r && {
    id: r.id,
    date: r.date,
    checkIn: r.check_in,
    checkOut: r.check_out,
    late: r.late,
    minutes: r.minutes,
    inDistance: r.in_distance == null ? null : Math.round(r.in_distance),
    inDistanceText: distanceText(r.in_distance),
    outDistanceText: distanceText(r.out_distance),
  }

const todayRecord = (userId) => one(`SELECT ${cols} FROM attendances WHERE user_id = $1 AND work_date = ${today}`, [userId])

// Câu nhắc dưới nút (API sinh, app hiện nguyên văn)
async function hintFor(status) {
  if (status === 'done') return 'Hẹn gặp lại ngày mai.'
  if (status === 'working') return `Vào ca sau ${SHIFT_START} được tính là đi trễ.`
  const { mins } = await one(
    `SELECT ceil(extract(epoch FROM ((${today} + time '${SHIFT_START}')::timestamp AT TIME ZONE '${TZ}') - now()) / 60)::int AS mins`,
  )
  if (mins > 60) return `Giờ vào ca ${SHIFT_START}.`
  if (mins > 0) return `Còn ${mins} phút tới giờ vào ca ${SHIFT_START}.`
  return `Đã quá ${SHIFT_START}, vào ca bây giờ sẽ tính là đi trễ.`
}

// ---------- Nhân viên ----------
// Hôm nay của tôi + giờ máy chủ (app dùng làm đồng hồ) + mốc chấm công
attendance.get('/today', async (req, res) => {
  const r = await todayRecord(req.user.id)
  const status = !r ? 'none' : r.check_out ? 'done' : 'working'
  const { now } = await one('SELECT now() AS now')
  res.json({
    serverTime: now,
    shiftStart: SHIFT_START,
    status,
    record: view(r),
    workingMinutes: status === 'working' ? Math.floor((new Date(now) - new Date(r.check_in)) / 60000) : null,
    hint: await hintFor(status),
    site: siteView(await getSite()),
  })
})

// App gửi GPS khi mở màn / bấm "Cập nhật vị trí": chỉ đánh giá, không ghi gì
attendance.post('/check-location', async (req, res) => {
  const site = await getSite()
  res.json({ ...evaluate(parseFix(req.body), site), site: siteView(site) })
})

attendance.post('/check-in', async (req, res) => {
  const { fix, ev } = await requireInside(req.body)
  const r = await one(
    `INSERT INTO attendances (user_id, work_date, check_in, in_lat, in_lng, in_distance)
     VALUES ($1, ${today}, now(), $2, $3, $4)
     ON CONFLICT (user_id, work_date) DO NOTHING RETURNING id`,
    [req.user.id, fix.lat, fix.lng, ev.distance],
  )
  if (!r) throw new HttpError(409, 'Hôm nay bạn đã vào ca rồi.', 'ALREADY_CHECKED_IN')
  const rec = view(await one(`SELECT ${cols} FROM attendances WHERE id = $1`, [r.id]))
  res.status(201).json({ message: rec.late ? `Đã vào ca (trễ, sau ${SHIFT_START}).` : 'Đã vào ca.', record: rec })
})

attendance.post('/check-out', async (req, res) => {
  const cur = await one(`SELECT * FROM attendances WHERE user_id = $1 AND work_date = ${today}`, [req.user.id])
  if (!cur) throw new HttpError(409, 'Bạn chưa vào ca hôm nay.', 'NOT_CHECKED_IN')
  if (cur.check_out) throw new HttpError(409, 'Hôm nay bạn đã tan ca rồi.', 'ALREADY_CHECKED_OUT')
  const { fix, ev } = await requireInside(req.body)
  await q('UPDATE attendances SET check_out = now(), out_lat = $2, out_lng = $3, out_distance = $4 WHERE id = $1', [
    cur.id,
    fix.lat,
    fix.lng,
    ev.distance,
  ])
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
    totalHoursText: `${(minutes / 60).toFixed(1).replace('.', ',')}h`,
    items,
  })
})

// ---------- Mốc chấm công ----------
attendance.get('/site', async (_req, res) => res.json(siteView(await getSite())))

// Admin đổi mốc (vị trí hiện tại của Admin) và/hoặc bán kính
attendance.put('/site', auth('Admin'), async (req, res) => {
  const cur = await getSite()
  const b = req.body || {}
  const moving = b.lat != null || b.lng != null
  const pos = moving ? parseFix(b) : { lat: cur.lat, lng: cur.lng }
  if (moving && pos.isMocked) throw new HttpError(403, 'Phát hiện vị trí giả lập.', 'MOCK_LOCATION')
  const radius = b.radius == null ? cur.radius_m : Number(b.radius)
  if (!Number.isInteger(radius) || radius < 20 || radius > 1000) {
    throw new HttpError(400, 'Bán kính phải từ 20 đến 1000 m.', 'VALIDATION')
  }
  let address = cur.address
  if (moving) {
    const geo = await reverseGeocode(pos.lat, pos.lng)
    address = geo ? [geo.place, geo.address].filter(Boolean).join(', ') : `${pos.lat.toFixed(5)}, ${pos.lng.toFixed(5)}`
  }
  const name = b.name ? String(b.name).trim().slice(0, 80) : cur.name
  const s = await one(
    `UPDATE attendance_site SET name = $1, address = $2, lat = $3, lng = $4, radius_m = $5, updated_by = $6, updated_at = now()
     WHERE id = 1 RETURNING *`,
    [name, address, pos.lat, pos.lng, radius, req.user.id],
  )
  await q(`INSERT INTO activities (user_id, action, title, detail) VALUES ($1,'update','Đổi vị trí chấm công',$2)`, [
    req.user.id,
    `${address} · bán kính ${radius} m`,
  ])
  res.json({ message: 'Đã lưu vị trí chấm công.', site: siteView(s) })
})

// ---------- Admin: ai đã chấm công trong một ngày: ?date=YYYY-MM-DD ----------
attendance.get('/', auth('Admin'), async (req, res) => {
  const date = /^\d{4}-\d{2}-\d{2}$/.test(req.query.date || '') ? req.query.date : null
  const { rows } = await q(
    `SELECT u.id AS "userId", u.full_name AS "fullName", u.username, ${colsOf('a.')}
     FROM users u LEFT JOIN attendances a ON a.user_id = u.id AND a.work_date = COALESCE($1::date, ${today})
     WHERE u.role = 'Staff' ORDER BY a.check_in NULLS LAST, u.full_name`,
    [date],
  )
  const items = rows.map((r) => ({ userId: r.userId, fullName: r.fullName, username: r.username, record: r.id ? view(r) : null }))
  const day = date || (await one(`SELECT to_char(${today}, 'YYYY-MM-DD') AS d`)).d
  const isToday = day === (await one(`SELECT to_char(${today}, 'YYYY-MM-DD') AS d`)).d
  res.json({
    date: day,
    isToday,
    shiftStart: SHIFT_START,
    total: items.length,
    present: items.filter((x) => x.record).length,
    late: items.filter((x) => x.record?.late).length,
    items,
  })
})
