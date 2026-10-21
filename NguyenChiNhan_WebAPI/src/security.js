import crypto from 'node:crypto'
import jwt from 'jsonwebtoken'
import { q, one } from './db.js'
import { sendMail, otpMail, devMail } from './mail.js'

const SECRET = process.env.JWT_SECRET || 'nguyenchinhan-dev-secret-chi-dung-local-0123456789'
export const OTP_TTL_SEC = 300
export const OTP_RESEND_SEC = 45
const OTP_MAX_ATTEMPTS = 3

export class HttpError extends Error {
  constructor(status, message, code, extra) {
    super(message)
    this.status = status
    this.code = code
    this.extra = extra
  }
}

export const sha = (s) => crypto.createHash('sha256').update(s).digest('hex')

export function signAccess(user, sessionId) {
  return jwt.sign(
    { sub: String(user.id), sid: sessionId, ver: user.token_version, role: user.role, unique_name: user.username },
    SECRET,
    { expiresIn: '7d', issuer: 'NguyenChiNhan_WebAPI', audience: 'NguyenChiNhan_App' },
  )
}

// Link trong email (Đúng là tôi / Không phải tôi), hạn 3 ngày
export const signLink = (payload) => jwt.sign(payload, SECRET, { expiresIn: '3d', audience: 'email-link' })
export function verifyLink(token) {
  try {
    return jwt.verify(token, SECRET, { audience: 'email-link' })
  } catch {
    throw new HttpError(400, 'Link không hợp lệ hoặc đã hết hạn.', 'BAD_LINK')
  }
}

// Middleware: xác thực JWT, kiểm tra phiên còn hiệu lực và vai trò
export function auth(...roles) {
  return async (req, _res, next) => {
    const h = req.get('authorization') || ''
    const token = h.startsWith('Bearer ') ? h.slice(7) : null
    if (!token) throw new HttpError(401, 'Bạn cần đăng nhập.', 'UNAUTHORIZED')
    let p
    try {
      p = jwt.verify(token, SECRET, { issuer: 'NguyenChiNhan_WebAPI', audience: 'NguyenChiNhan_App' })
    } catch {
      throw new HttpError(401, 'Phiên đăng nhập đã hết hạn.', 'TOKEN_EXPIRED')
    }
    const row = await one(
      `SELECT u.*, s.revoked FROM users u JOIN sessions s ON s.id = $2 AND s.user_id = u.id WHERE u.id = $1`,
      [Number(p.sub), p.sid],
    )
    if (!row || row.revoked || row.token_version !== p.ver) {
      throw new HttpError(401, 'Phiên đăng nhập đã bị thu hồi.', 'SESSION_REVOKED')
    }
    if (roles.length && !roles.includes(row.role)) throw new HttpError(403, 'Bạn không có quyền làm việc này.', 'FORBIDDEN')
    req.user = row
    req.sessionId = p.sid
    q('UPDATE sessions SET last_seen_at = now() WHERE id = $1', [p.sid]).catch(() => {})
    next()
  }
}

// Tạo OTP 6 số, gửi email. Trả về devCode khi MAIL_DEV=1 để test.
export async function issueOtp(user, purpose, { cooldown = true } = {}) {
  const last =
    cooldown &&
    (await one(`SELECT created_at FROM otps WHERE user_id = $1 AND purpose = $2 ORDER BY created_at DESC LIMIT 1`, [
      user.id,
      purpose,
    ]))
  if (last) {
    const wait = OTP_RESEND_SEC - Math.floor((Date.now() - new Date(last.created_at).getTime()) / 1000)
    if (wait > 0) throw new HttpError(429, `Vui lòng đợi ${wait} giây để gửi lại mã.`, 'OTP_COOLDOWN', { resendAfter: wait })
  }
  const code = String(crypto.randomInt(0, 1_000_000)).padStart(6, '0')
  await q('UPDATE otps SET used = true WHERE user_id = $1 AND purpose = $2 AND used = false', [user.id, purpose])
  await q(
    `INSERT INTO otps (user_id, purpose, code_hash, expires_at) VALUES ($1,$2,$3, now() + make_interval(secs => $4))`,
    [user.id, purpose, sha(`${user.id}:${code}`), OTP_TTL_SEC],
  )
  const m = otpMail(user, code, purpose)
  await sendMail(user.email, m.subject, m.html)
  return devMail ? code : undefined
}

export async function consumeOtp(user, purpose, code) {
  const otp = await one(
    `SELECT * FROM otps WHERE user_id = $1 AND purpose = $2 AND used = false ORDER BY created_at DESC LIMIT 1`,
    [user.id, purpose],
  )
  if (!otp || new Date(otp.expires_at) < new Date()) {
    throw new HttpError(400, 'Mã đã hết hạn. Vui lòng lấy mã mới.', 'OTP_EXPIRED')
  }
  if (otp.code_hash !== sha(`${user.id}:${String(code || '').trim()}`)) {
    const attempts = otp.attempts + 1
    const left = OTP_MAX_ATTEMPTS - attempts
    await q('UPDATE otps SET attempts = $2, used = $3 WHERE id = $1', [otp.id, attempts, left <= 0])
    if (left <= 0) throw new HttpError(400, 'Sai quá 3 lần. Vui lòng lấy mã mới.', 'OTP_LOCKED', { attemptsLeft: 0 })
    throw new HttpError(400, `Mã không đúng. Còn ${left} lần thử, sau đó cần lấy mã mới.`, 'OTP_INVALID', { attemptsLeft: left })
  }
  await q('UPDATE otps SET used = true WHERE id = $1', [otp.id])
}

// Thông tin thiết bị/vị trí của request (Vercel gắn sẵn header vị trí theo IP)
export function clientInfo(req) {
  const ip = (req.get('x-forwarded-for') || req.socket?.remoteAddress || '').split(',')[0].trim()
  const dec = (v) => {
    try {
      return v ? decodeURIComponent(v) : null
    } catch {
      return v
    }
  }
  return {
    ip,
    city: dec(req.get('x-vercel-ip-city')),
    country: req.get('x-vercel-ip-country') || null,
    // App gửi tên thiết bị đã encodeURIComponent (header HTTP chỉ an toàn với ASCII)
    device: dec(req.get('x-device-name'))?.slice(0, 80) || (req.get('user-agent') || 'Không rõ thiết bị').slice(0, 80),
    platform: dec(req.get('x-device-platform'))?.slice(0, 40) || null,
  }
}

export const publicUser = (u) => ({
  id: u.id,
  username: u.username,
  fullName: u.full_name,
  email: u.email,
  role: u.role,
  emailConfirmed: u.email_confirmed,
  loginAlert: u.login_alert,
  createdAt: u.created_at,
})
