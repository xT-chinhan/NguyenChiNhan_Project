import nodemailer from 'nodemailer'

const BRAND = 'Chí Nhân Store'
export const devMail = process.env.MAIL_DEV === '1'

let transporter
function tx() {
  transporter ??= nodemailer.createTransport({
    service: 'gmail',
    auth: { user: process.env.GMAIL_USER, pass: (process.env.GMAIL_APP_PASSWORD || '').replace(/\s/g, '') },
  })
  return transporter
}

export const outbox = [] // MAIL_DEV=1: giữ mail cuối để test đọc

export async function sendMail(to, subject, html) {
  if (devMail) {
    outbox.push({ to, subject, html })
    if (outbox.length > 50) outbox.shift()
    return
  }
  await tx().sendMail({ from: `"${BRAND}" <${process.env.GMAIL_USER}>`, to, subject, html })
}

const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c])

// Khung email cùng style mockup: nền ngà, card trắng, chữ mực
function layout(inner, foot) {
  return `<!doctype html><html lang="vi"><body style="margin:0;background:#F7F6F3;font-family:'Be Vietnam Pro',-apple-system,Segoe UI,Roboto,sans-serif;color:#111">
<div style="max-width:480px;margin:0 auto;padding:28px 16px">
<div style="background:#fff;border:1px solid #EAEAEA;border-radius:18px;padding:26px 22px">
<div style="display:flex;align-items:center;gap:8px;font-weight:700;font-size:15px"><span style="display:inline-block;width:32px;height:32px;line-height:32px;text-align:center;border-radius:10px;background:#111;color:#fff;font-size:14px">CN</span>&nbsp;${BRAND}</div>
${inner}
</div>
<p style="font-size:12px;color:#A9A8A3;text-align:center;line-height:1.5;margin:16px 8px 0">${foot || ''}<br>Đồ án Lập trình di động · Nguyễn Chí Nhân · Email tự động, vui lòng không trả lời.</p>
</div></body></html>`
}

const btn = (href, text, primary) =>
  `<a href="${href}" style="display:block;text-align:center;text-decoration:none;font-weight:600;font-size:15px;padding:13px 16px;border-radius:999px;margin-top:10px;${
    primary ? 'background:#111;color:#fff' : 'background:#fff;color:#111;border:1px solid #EAEAEA'
  }">${text}</a>`

const TITLES = {
  verify_email: ['Mã xác thực email', 'Nhập mã này trong app để kích hoạt tài khoản.'],
  login: ['Mã đăng nhập', 'Đây là mã đăng nhập của bạn.'],
  reset: ['Mã đặt lại mật khẩu', 'Dùng mã này để đặt mật khẩu mới.'],
}

export function otpMail(user, code, purpose) {
  const [title, lead] = TITLES[purpose]
  return {
    subject: `${title} ${BRAND}: ${code}`,
    html: layout(
      `<p style="font-size:16px;font-weight:600;margin:22px 0 6px">Xin chào ${esc(user.full_name)},</p>
<p style="font-size:14px;color:#787774;line-height:1.5;margin:0">${lead} Mã có hiệu lực trong 5 phút và chỉ dùng được một lần.</p>
<div style="margin-top:18px;background:#F1F0EC;border-radius:14px;padding:14px 0;text-align:center;font-size:34px;font-weight:700;letter-spacing:10px">${code}</div>
<p style="font-size:12.5px;color:#787774;line-height:1.5;margin:16px 0 0">Không phải bạn? Bỏ qua email này, không ai đăng nhập được nếu không có mã.</p>`,
    ),
  }
}

export function loginAlertMail(user, s, links) {
  const time = new Date(s.created_at).toLocaleString('vi-VN', { timeZone: 'Asia/Ho_Chi_Minh', hour: '2-digit', minute: '2-digit', day: '2-digit', month: '2-digit', year: 'numeric' })
  const row = (k, v) => `<tr><td style="padding:10px 0;border-top:1px solid #F0EFEC;color:#787774;width:84px;font-size:14px">${k}</td><td style="padding:10px 0;border-top:1px solid #F0EFEC;font-weight:600;font-size:14px">${esc(v)}</td></tr>`
  return {
    subject: s.is_new_device ? 'Đăng nhập trên thiết bị mới vào tài khoản của bạn' : 'Đăng nhập mới vào tài khoản của bạn',
    html: layout(
      `<p style="font-size:15px;line-height:1.5;margin:20px 0 12px">Tài khoản <b>${esc(user.username)}</b> vừa đăng nhập${s.is_new_device ? ' trên một <b>thiết bị mới</b>' : ''}.</p>
<table style="width:100%;border-collapse:collapse">
${row('Lúc', time)}${row('Thiết bị', [s.device, s.platform].filter(Boolean).join(' · '))}${row('Vị trí', s.city ? `${s.city}${s.country ? ', ' + s.country : ''} (theo IP)` : 'Không xác định')}${row('IP', maskIp(s.ip))}
</table>
${btn(links.trust, 'Đúng là tôi')}${btn(links.deny, 'Không phải tôi, khóa ngay', true)}`,
      'Bạn nhận email này vì đã bật “Email cảnh báo đăng nhập” trong app.',
    ),
  }
}

export function adminNoticeMail(admin, user, s) {
  return {
    subject: `[Cảnh báo] ${user.username} báo đăng nhập lạ`,
    html: layout(
      `<p style="font-size:15px;line-height:1.5;margin:20px 0 0">Xin chào ${esc(admin.full_name)},</p>
<p style="font-size:14px;line-height:1.5;color:#787774">Người dùng <b style="color:#111">${esc(user.full_name)} (${esc(user.username)})</b> vừa bấm “Không phải tôi” cho lần đăng nhập từ <b style="color:#111">${esc(s.device)}</b>${s.city ? ` tại ${esc(s.city)}` : ''}. Hệ thống đã đăng xuất mọi thiết bị và yêu cầu đặt lại mật khẩu.</p>`,
    ),
  }
}

export function pageHtml(title, text, extra = '') {
  return layout(`<h1 style="font-size:22px;margin:22px 0 6px">${esc(title)}</h1><p style="font-size:14px;color:#787774;line-height:1.55;margin:0">${text}</p>${extra}`)
}

// Nút POST (link GET trong email chỉ mở trang xác nhận, tránh trình quét mail tự bấm)
export const formBtn = (text, primary) =>
  `<form method="post" style="margin:18px 0 0"><button type="submit" style="width:100%;font:600 15px sans-serif;padding:13px 16px;border-radius:999px;cursor:pointer;${
    primary ? 'background:#111;color:#fff;border:0' : 'background:#fff;color:#111;border:1px solid #EAEAEA'
  }">${text}</button></form>`

export function maskIp(ip) {
  if (!ip) return 'Không rõ'
  const p = ip.split('.')
  return p.length === 4 ? `${p[0]}.${p[1]}.•••.${p[3]}` : ip.replace(/:[^:]+:[^:]+$/, ':••••')
}

export function maskEmail(email) {
  const [u, d] = email.split('@')
  return `${u.slice(0, 3)}•••@${d}`
}
