import { Router } from 'express'
import bcrypt from 'bcryptjs'
import { q, one } from '../db.js'
import { maskEmail, maskIp, pageHtml, formBtn } from '../mail.js'
import { auth, HttpError, publicUser, verifyLink } from '../security.js'
import { denySession, trustSession } from '../account.js'

export const me = Router()
me.use(auth())

me.get('/', (req, res) => res.json(publicUser(req.user)))

me.patch('/', async (req, res) => {
  const { loginAlert, fullName } = req.body || {}
  const u = await one(
    `UPDATE users SET login_alert = COALESCE($2, login_alert), full_name = COALESCE(NULLIF($3,''), full_name) WHERE id = $1 RETURNING *`,
    [req.user.id, typeof loginAlert === 'boolean' ? loginAlert : null, fullName ? String(fullName).trim() : null],
  )
  res.json(publicUser(u))
})

me.post('/password', async (req, res) => {
  const { currentPassword, newPassword } = req.body || {}
  if (!(await bcrypt.compare(String(currentPassword || ''), req.user.password_hash))) {
    throw new HttpError(400, 'Mật khẩu hiện tại không đúng.', 'BAD_PASSWORD')
  }
  if (String(newPassword || '').length < 6) throw new HttpError(400, 'Mật khẩu mới ít nhất 6 ký tự.', 'VALIDATION')
  await q('UPDATE users SET password_hash = $2 WHERE id = $1', [req.user.id, await bcrypt.hash(String(newPassword), 10)])
  res.json({ message: 'Đã đổi mật khẩu.' })
})

// Lịch sử đăng nhập (mục 6)
me.get('/sessions', async (req, res) => {
  const { rows } = await q(
    `SELECT * FROM sessions WHERE user_id = $1 ORDER BY created_at DESC LIMIT 20`,
    [req.user.id],
  )
  const currentDevice = rows.find((s) => s.id === req.sessionId)?.device
  const items = rows.map((s) => ({
    id: s.id,
    device: s.device,
    platform: s.platform,
    city: s.city,
    country: s.country,
    ip: maskIp(s.ip),
    createdAt: s.created_at,
    lastSeenAt: s.last_seen_at,
    current: s.id === req.sessionId,
    revoked: s.revoked,
    status: s.status,
    suspicious: s.is_new_device && s.status === 'normal' && s.id !== req.sessionId && !s.revoked && s.device !== currentDevice,
  }))
  res.json({
    items,
    suspiciousCount: items.filter((x) => x.suspicious).length,
    alertEmail: maskEmail(req.user.email),
    loginAlert: req.user.login_alert,
  })
})

me.post('/sessions/:id/trust', async (req, res) => {
  if (!(await trustSession(Number(req.params.id), req.user.id))) throw new HttpError(404, 'Không tìm thấy phiên.', 'NOT_FOUND')
  res.json({ message: 'Đã đánh dấu là bạn.' })
})

me.post('/sessions/:id/deny', async (req, res) => {
  const out = await denySession(Number(req.params.id), req.user.id)
  if (!out) throw new HttpError(404, 'Không tìm thấy phiên.', 'NOT_FOUND')
  res.json({ message: 'Đã bảo vệ tài khoản.', username: req.user.username, maskedEmail: maskEmail(req.user.email), ...out })
})

// Link bấm từ email cảnh báo (không cần đăng nhập, ký bằng JWT riêng).
// GET chỉ hiện trang xác nhận, POST mới thực hiện.
export const securityLinks = Router()
const checkLink = (req) => {
  const p = verifyLink(String(req.query.t || ''))
  if (p.sid !== Number(req.params.id) || p.action !== req.params.action || !['trust', 'deny'].includes(p.action)) {
    throw new HttpError(400, 'Link không hợp lệ.', 'BAD_LINK')
  }
  return p
}
securityLinks.get('/sessions/:id/:action', async (req, res) => {
  const p = checkLink(req)
  res.type('html').send(
    p.action === 'trust'
      ? pageHtml('Đúng là bạn?', 'Xác nhận lần đăng nhập này là của bạn.', formBtn('Đúng là tôi', true))
      : pageHtml(
          'Không phải bạn đăng nhập?',
          'Hệ thống sẽ đăng xuất mọi thiết bị, gửi mã đặt lại mật khẩu tới email và báo Quản trị viên.',
          formBtn('Khóa tài khoản ngay', true),
        ),
  )
})
securityLinks.post('/sessions/:id/:action', async (req, res) => {
  const p = checkLink(req)
  res.type('html')
  if (p.action === 'trust') {
    await trustSession(p.sid, p.uid)
    return res.send(pageHtml('Cảm ơn bạn đã xác nhận', 'Lần đăng nhập này đã được đánh dấu là của bạn. Bạn có thể đóng trang này.'))
  }
  const out = await denySession(p.sid, p.uid)
  if (!out) throw new HttpError(404, 'Không tìm thấy phiên.', 'NOT_FOUND')
  res.send(
    pageHtml(
      'Đã bảo vệ tài khoản',
      `Đã đăng xuất ${out.revokedSessions} thiết bị. Mã đặt lại mật khẩu đã gửi tới email của bạn, mở app và chọn “Đặt mật khẩu mới”.${out.adminsNotified ? ' Quản trị viên đã được báo.' : ''}`,
    ),
  )
})
