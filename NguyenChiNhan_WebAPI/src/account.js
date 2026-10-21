import { q, one } from './db.js'
import { sendMail, loginAlertMail, adminNoticeMail } from './mail.js'
import { signAccess, signLink, issueOtp } from './security.js'

const publicUrl = (req) => process.env.PUBLIC_URL || `${req.protocol}://${req.get('host')}`

// Tạo phiên đăng nhập + gửi email cảnh báo (mục 6) nếu người dùng bật
export async function startSession(req, user, info) {
  const seen = await one('SELECT 1 FROM sessions WHERE user_id = $1 AND device = $2 AND status <> $3 LIMIT 1', [user.id, info.device, 'denied'])
  const s = await one(
    `INSERT INTO sessions (user_id, device, platform, ip, city, country, is_new_device)
     VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING *`,
    [user.id, info.device, info.platform, info.ip, info.city, info.country, !seen],
  )
  if (user.login_alert) {
    const base = publicUrl(req)
    const link = (action) => `${base}/api/security/sessions/${s.id}/${action}?t=${signLink({ sid: s.id, uid: user.id, action })}`
    const m = loginAlertMail(user, s, { trust: link('trust'), deny: link('deny') })
    await sendMail(user.email, m.subject, m.html).catch((e) => console.error('login alert mail', e.message))
  }
  return { token: signAccess(user, s.id), session: s }
}

// "Không phải tôi": thu hồi mọi phiên, bắt đặt lại mật khẩu, gửi mã reset, báo Admin
export async function denySession(sessionId, userId) {
  const s = await one('SELECT * FROM sessions WHERE id = $1 AND user_id = $2', [sessionId, userId])
  if (!s) return null
  await q(`UPDATE sessions SET status = 'denied' WHERE id = $1`, [s.id])
  const { rowCount } = await q('UPDATE sessions SET revoked = true WHERE user_id = $1 AND revoked = false', [userId])
  const user = await one(
    'UPDATE users SET token_version = token_version + 1, must_reset = true WHERE id = $1 RETURNING *',
    [userId],
  )
  let resetSent = true
  // Thao tác bảo mật: luôn gửi mã mới, không áp thời gian chờ 45s
  await issueOtp(user, 'reset', { cooldown: false }).catch(() => (resetSent = false))
  const admins = (await q(`SELECT * FROM users WHERE role = 'Admin' AND id <> $1`, [userId])).rows
  for (const a of admins) {
    const m = adminNoticeMail(a, user, s)
    await sendMail(a.email, m.subject, m.html).catch(() => {})
  }
  await q(`INSERT INTO activities (user_id, action, title, detail) VALUES ($1,'security',$2,$3)`, [
    userId,
    'Báo đăng nhập lạ',
    `${s.device}${s.city ? ' · ' + s.city : ''}`,
  ])
  return { revokedSessions: rowCount, resetCodeSent: resetSent, adminsNotified: admins.length }
}

export async function trustSession(sessionId, userId) {
  const r = await q(`UPDATE sessions SET status = 'trusted' WHERE id = $1 AND user_id = $2 AND status <> 'denied'`, [sessionId, userId])
  return r.rowCount > 0
}
