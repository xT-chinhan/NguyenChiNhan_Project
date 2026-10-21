import { Router } from 'express'
import bcrypt from 'bcryptjs'
import { q, one } from '../db.js'
import { maskEmail } from '../mail.js'
import { HttpError, issueOtp, consumeOtp, clientInfo, publicUser, auth, OTP_TTL_SEC, OTP_RESEND_SEC } from '../security.js'
import { startSession } from '../account.js'

const r = Router()
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/
const USER_RE = /^[a-z0-9._]{3,30}$/

const need = (body, ...keys) => {
  for (const k of keys) {
    if (body?.[k] === undefined || body[k] === null || String(body[k]).trim() === '') {
      throw new HttpError(400, `Thiếu trường "${k}".`, 'VALIDATION')
    }
  }
}
const findUser = (username) => one('SELECT * FROM users WHERE username = $1', [String(username || '').trim().toLowerCase()])
const otpInfo = (user, devCode) => ({
  username: user.username,
  maskedEmail: maskEmail(user.email),
  expiresIn: OTP_TTL_SEC,
  resendAfter: OTP_RESEND_SEC,
  ...(devCode ? { devCode } : {}),
})

// 1. Đăng ký qua email: tạo tài khoản Khách hàng chưa kích hoạt + gửi OTP
r.post('/register', async (req, res) => {
  need(req.body, 'fullName', 'username', 'email', 'password')
  const username = String(req.body.username).trim().toLowerCase()
  const email = String(req.body.email).trim().toLowerCase()
  const fullName = String(req.body.fullName).trim()
  if (!USER_RE.test(username)) throw new HttpError(400, 'Tên đăng nhập 3–30 ký tự: chữ thường, số, dấu chấm, gạch dưới.', 'VALIDATION')
  if (!EMAIL_RE.test(email)) throw new HttpError(400, 'Email không hợp lệ.', 'VALIDATION')
  if (String(req.body.password).length < 6) throw new HttpError(400, 'Mật khẩu ít nhất 6 ký tự.', 'VALIDATION')
  const hash = await bcrypt.hash(String(req.body.password), 10)
  const exist = await findUser(username)
  if (exist?.email_confirmed) throw new HttpError(409, 'Tên đăng nhập đã được dùng.', 'USERNAME_TAKEN')
  const user = exist
    ? await one('UPDATE users SET email=$2, full_name=$3, password_hash=$4 WHERE id=$1 RETURNING *', [exist.id, email, fullName, hash])
    : await one(
        `INSERT INTO users (username, email, full_name, password_hash, role) VALUES ($1,$2,$3,$4,'User') RETURNING *`,
        [username, email, fullName, hash],
      )
  const devCode = await issueOtp(user, 'verify_email')
  res.status(201).json({ message: 'Đã gửi mã xác thực tới email.', ...otpInfo(user, devCode) })
})

r.post('/verify-email', async (req, res) => {
  need(req.body, 'username', 'code')
  const user = await findUser(req.body.username)
  if (!user) throw new HttpError(404, 'Không tìm thấy tài khoản.', 'NOT_FOUND')
  if (user.email_confirmed) return res.json({ message: 'Email đã được xác thực.' })
  await consumeOtp(user, 'verify_email', req.body.code)
  await q('UPDATE users SET email_confirmed = true WHERE id = $1', [user.id])
  res.json({ message: 'Đã kích hoạt tài khoản. Mời bạn đăng nhập.' })
})

// 2. Đăng nhập bước 1: tên đăng nhập + mật khẩu -> gửi OTP
r.post('/login', async (req, res) => {
  need(req.body, 'username', 'password')
  const user = await findUser(req.body.username)
  if (!user || !(await bcrypt.compare(String(req.body.password), user.password_hash))) {
    throw new HttpError(401, 'Tên đăng nhập hoặc mật khẩu không đúng.', 'BAD_CREDENTIALS')
  }
  if (!user.email_confirmed) {
    const devCode = await issueOtp(user, 'verify_email').catch(() => undefined)
    throw new HttpError(403, 'Email chưa được xác thực. Mã mới đã được gửi.', 'EMAIL_NOT_VERIFIED', otpInfo(user, devCode))
  }
  if (user.must_reset) throw new HttpError(403, 'Tài khoản đang bị khóa sau báo đăng nhập lạ. Hãy đặt mật khẩu mới.', 'MUST_RESET', { username: user.username })
  const devCode = await issueOtp(user, 'login', { cooldown: false }) // đúng mật khẩu mới tới đây
  res.json({ message: 'Đã gửi mã đăng nhập tới email.', otpRequired: true, ...otpInfo(user, devCode) })
})

// Đăng nhập bước 2: OTP -> JWT + vai trò (app tự chuyển trang theo role)
r.post('/login/verify', async (req, res) => {
  need(req.body, 'username', 'code')
  const user = await findUser(req.body.username)
  if (!user) throw new HttpError(404, 'Không tìm thấy tài khoản.', 'NOT_FOUND')
  if (user.must_reset) throw new HttpError(403, 'Hãy đặt mật khẩu mới trước.', 'MUST_RESET', { username: user.username })
  await consumeOtp(user, 'login', req.body.code)
  const { token, session } = await startSession(req, user, clientInfo(req))
  res.json({ message: 'Đăng nhập thành công.', token, role: user.role, sessionId: session.id, user: publicUser(user) })
})

r.post('/resend', async (req, res) => {
  need(req.body, 'username', 'purpose')
  if (!['verify_email', 'login', 'reset'].includes(req.body.purpose)) throw new HttpError(400, 'purpose không hợp lệ.', 'VALIDATION')
  const user = await findUser(req.body.username)
  if (!user) throw new HttpError(404, 'Không tìm thấy tài khoản.', 'NOT_FOUND')
  const devCode = await issueOtp(user, req.body.purpose)
  res.json({ message: 'Đã gửi mã mới.', ...otpInfo(user, devCode) })
})

// Quên mật khẩu / đặt lại sau khi khóa
r.post('/forgot', async (req, res) => {
  need(req.body, 'username')
  const user = await findUser(req.body.username)
  if (!user) return res.json({ message: 'Nếu tài khoản tồn tại, mã đã được gửi tới email.' })
  const devCode = await issueOtp(user, 'reset')
  res.json({ message: 'Đã gửi mã đặt lại mật khẩu.', ...otpInfo(user, devCode) })
})

r.post('/reset', async (req, res) => {
  need(req.body, 'username', 'code', 'newPassword')
  if (String(req.body.newPassword).length < 6) throw new HttpError(400, 'Mật khẩu ít nhất 6 ký tự.', 'VALIDATION')
  const user = await findUser(req.body.username)
  if (!user) throw new HttpError(404, 'Không tìm thấy tài khoản.', 'NOT_FOUND')
  await consumeOtp(user, 'reset', req.body.code)
  await q(
    `UPDATE users SET password_hash = $2, must_reset = false, email_confirmed = true, token_version = token_version + 1 WHERE id = $1`,
    [user.id, await bcrypt.hash(String(req.body.newPassword), 10)],
  )
  await q('UPDATE sessions SET revoked = true WHERE user_id = $1', [user.id])
  res.json({ message: 'Đã đặt mật khẩu mới. Mời bạn đăng nhập.' })
})

r.post('/logout', auth(), async (req, res) => {
  await q('UPDATE sessions SET revoked = true WHERE id = $1', [req.sessionId])
  res.json({ message: 'Đã đăng xuất.' })
})

export default r
