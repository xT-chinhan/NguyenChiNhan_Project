import { Router } from 'express'
import { q } from '../db.js'
import { auth, HttpError } from '../security.js'

export const tools = Router()
tools.use(auth())

const withTimeout = (ms) => AbortSignal.timeout(ms)

// ---------- f. Dịch: app đọc chữ bằng camera/ảnh, API dịch ----------
const LANGS = { auto: 'Tự nhận diện', en: 'Tiếng Anh', vi: 'Tiếng Việt', ja: 'Tiếng Nhật', ko: 'Tiếng Hàn', 'zh-CN': 'Tiếng Trung', fr: 'Tiếng Pháp' }

// Google (gtx) -> thử lại 1 lần -> dự phòng MyMemory
async function translateText(text, source, target) {
  for (let i = 0; i < 2; i++) {
    try {
      const r = await fetch(
        `https://translate.googleapis.com/translate_a/single?client=gtx&dt=t&sl=${source}&tl=${target}&q=${encodeURIComponent(text)}`,
        { signal: withTimeout(6000) },
      )
      if (!r.ok) throw new Error(`HTTP ${r.status}`)
      const data = await r.json()
      return { translated: (data[0] || []).map((x) => x[0]).join(''), detected: data[2] || source }
    } catch {
      // thử lại / dự phòng
    }
  }
  const lines = text.split('\n')
  const res = []
  for (const line of lines) {
    const r = await fetch(
      `https://api.mymemory.translated.net/get?q=${encodeURIComponent(line)}&langpair=${source === 'auto' ? 'en' : source}|${target}`,
      { signal: withTimeout(6000) },
    )
    const d = await r.json()
    if (!d?.responseData?.translatedText) throw new Error('fallback failed')
    res.push(d.responseData.translatedText)
  }
  return { translated: res.join('\n'), detected: source === 'auto' ? 'en' : source }
}

tools.get('/translate/languages', (_req, res) => res.json(Object.entries(LANGS).map(([code, name]) => ({ code, name }))))

tools.post('/translate', async (req, res) => {
  const text = String(req.body?.text || '').trim()
  const source = LANGS[req.body?.source] ? req.body.source : 'auto'
  const target = LANGS[req.body?.target] && req.body.target !== 'auto' ? req.body.target : 'vi'
  if (!text) throw new HttpError(400, 'Không có chữ để dịch.', 'VALIDATION')
  if (text.length > 4000) throw new HttpError(400, 'Đoạn chữ quá dài (tối đa 4000 ký tự).', 'VALIDATION')
  const t0 = Date.now()
  let out
  try {
    out = await translateText(text, source, target)
  } catch (e) {
    throw new HttpError(502, 'Dịch vụ dịch đang bận, thử lại sau.', 'TRANSLATE_FAILED', { reason: e.message })
  }
  const { translated, detected } = out
  await q(
    'INSERT INTO translations (user_id, source_lang, target_lang, source_text, translated_text) VALUES ($1,$2,$3,$4,$5)',
    [req.user.id, detected, target, text, translated],
  )
  res.json({
    text,
    translated,
    source: detected,
    sourceName: LANGS[detected] || detected,
    target,
    targetName: LANGS[target],
    lines: translated.split('\n').length,
    ms: Date.now() - t0,
  })
})

// ---------- d. Đo tiếng ồn: app đo dB bằng micro, API phân loại + lưu ----------
const LEVELS = [
  { key: 'quiet', min: 0, max: 40, label: 'Yên tĩnh', example: 'Như thư viện, phòng ngủ', tone: 'normal' },
  { key: 'normal', min: 40, max: 60, label: 'Bình thường', example: 'Như trò chuyện bình thường', tone: 'normal' },
  { key: 'moderate', min: 60, max: 75, label: 'Hơi ồn', example: 'Như văn phòng đông người', tone: 'normal' },
  { key: 'loud', min: 75, max: 85, label: 'Ồn', example: 'Như đường phố đông xe', tone: 'warn' },
  { key: 'very_loud', min: 85, max: 200, label: 'Quá ồn', example: 'Như đường phố giờ cao điểm', tone: 'danger' },
]
const levelOf = (db) => LEVELS.find((l) => db < l.max) || LEVELS.at(-1)
// Chuẩn NIOSH: 85 dB nghe tối đa 8 giờ, mỗi +3 dB giảm một nửa
const safeMinutes = (db) => (db < 85 ? null : Math.round(480 / 2 ** ((db - 85) / 3)))
const fmtMinutes = (m) => (m >= 60 ? `${Math.round((m / 60) * 10) / 10} giờ`.replace('.', ',') : `${m} phút`)

tools.get('/noise/levels', (_req, res) =>
  res.json({ levels: LEVELS, scale: { min: 30, max: 120, warn: 85 }, warnText: 'Trên 85 dB nghe lâu có thể hại tai.' }),
)

tools.post('/noise/records', async (req, res) => {
  const avg = Number(req.body?.avgDb)
  const max = Number(req.body?.maxDb)
  const dur = Math.round(Number(req.body?.durationSec))
  if (![avg, max, dur].every(Number.isFinite) || dur <= 0 || avg < 0 || max < avg) {
    throw new HttpError(400, 'Số đo không hợp lệ.', 'VALIDATION')
  }
  const lv = levelOf(max)
  const safe = safeMinutes(max)
  await q('INSERT INTO noise_records (user_id, avg_db, max_db, duration_sec, level) VALUES ($1,$2,$3,$4,$5)', [req.user.id, avg, max, dur, lv.key])
  res.status(201).json({
    avgDb: Math.round(avg),
    maxDb: Math.round(max),
    durationSec: dur,
    level: lv,
    safeMinutes: safe,
    advice: safe ? `Mức cao nhất ${Math.round(max)} dB: chỉ nên nghe tối đa ${fmtMinutes(safe)} mỗi ngày.` : 'Mức ồn an toàn cho tai.',
  })
})

tools.get('/noise/records', async (req, res) => {
  const { rows } = await q(
    `SELECT id, avg_db AS "avgDb", max_db AS "maxDb", duration_sec AS "durationSec", level, created_at AS "createdAt"
     FROM noise_records WHERE user_id = $1 ORDER BY created_at DESC LIMIT 20`,
    [req.user.id],
  )
  res.json(rows)
})

// ---------- b. Chia sẻ vị trí: app gửi tọa độ GPS, API tìm địa chỉ + tạo nội dung chia sẻ ----------
async function reverseGeocode(lat, lng) {
  try {
    const r = await fetch(
      `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${lat}&lon=${lng}&accept-language=vi&zoom=18`,
      { headers: { 'User-Agent': 'NguyenChiNhan_WebAPI/1.0 (do an LTDD HUTECH)' }, signal: withTimeout(5000) },
    )
    if (!r.ok) return null
    const d = await r.json()
    const a = d.address || {}
    const parts = [
      ...new Set(
        [a.house_number && a.road ? `${a.house_number} ${a.road}` : a.road, a.quarter || a.suburb, a.city_district, a.city || a.state].filter(Boolean),
      ),
    ]
    const place = d.name || a.amenity || a.building || parts[0] || null
    const address = parts.filter((x) => x !== place).join(', ') || d.display_name
    return { place, address }
  } catch {
    return null
  }
}

async function placeOf(body) {
  const lat = Number(body?.lat)
  const lng = Number(body?.lng)
  const accuracy = body?.accuracy != null ? Number(body.accuracy) : null
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    throw new HttpError(400, 'Tọa độ không hợp lệ.', 'VALIDATION')
  }
  const geo = await reverseGeocode(lat, lng)
  const coords = `${lat.toFixed(5)}, ${lng.toFixed(5)}`
  const mapsUrl = `https://maps.google.com/?q=${lat.toFixed(5)},${lng.toFixed(5)}`
  const where = geo ? [geo.place, geo.address].filter(Boolean).join(', ') : coords
  return {
    lat,
    lng,
    coords,
    accuracy,
    accuracyText: accuracy != null ? `Chính xác ±${Math.round(accuracy)} m` : null,
    accurate: accuracy != null && accuracy <= 30,
    place: geo?.place || 'Vị trí hiện tại',
    address: geo?.address || coords,
    mapsUrl,
    shareText: `📍 Mình đang ở ${where}\n${mapsUrl}`,
    _geo: geo,
  }
}

// Mở màn: chỉ tra địa chỉ, không lưu
tools.post('/location/resolve', async (req, res) => {
  const { _geo, ...out } = await placeOf(req.body)
  res.json(out)
})

// Bấm Chia sẻ: lưu lịch sử + trả nội dung chia sẻ
tools.post('/location/share', async (req, res) => {
  const { _geo, ...out } = await placeOf(req.body)
  await q('INSERT INTO location_shares (user_id, lat, lng, accuracy, place, address) VALUES ($1,$2,$3,$4,$5,$6)', [
    req.user.id,
    out.lat,
    out.lng,
    out.accuracy,
    _geo?.place ?? null,
    _geo?.address ?? null,
  ])
  res.status(201).json(out)
})

tools.get('/location/history', async (req, res) => {
  const { rows } = await q(
    `SELECT id, lat, lng, place, address, created_at AS "createdAt" FROM location_shares WHERE user_id = $1 ORDER BY created_at DESC LIMIT 20`,
    [req.user.id],
  )
  res.json(rows)
})
