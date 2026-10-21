import pg from 'pg'
import bcrypt from 'bcryptjs'

pg.types.setTypeParser(1700, (v) => (v === null ? null : Number(v))) // numeric -> number
pg.types.setTypeParser(20, (v) => Number(v)) // bigint (count) -> number

const url = process.env.DATABASE_URL || 'postgres://tracker:tracker@127.0.0.1:5433/nguyenchinhan_db'
const local = /@(localhost|127\.0\.0\.1)[:/]/.test(url)

export const pool = new pg.Pool({
  connectionString: url,
  ssl: local ? false : { rejectUnauthorized: false },
  max: 3,
})

export const q = (text, params) => pool.query(text, params)
export const one = async (text, params) => (await pool.query(text, params)).rows[0] || null

const SCHEMA = `
CREATE TABLE IF NOT EXISTS users (
  id SERIAL PRIMARY KEY,
  username TEXT UNIQUE NOT NULL,
  email TEXT NOT NULL,
  full_name TEXT NOT NULL,
  password_hash TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'User' CHECK (role IN ('Admin','Staff','User')),
  email_confirmed BOOLEAN NOT NULL DEFAULT false,
  login_alert BOOLEAN NOT NULL DEFAULT true,
  must_reset BOOLEAN NOT NULL DEFAULT false,
  token_version INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS otps (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  purpose TEXT NOT NULL CHECK (purpose IN ('verify_email','login','reset')),
  code_hash TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  attempts INT NOT NULL DEFAULT 0,
  used BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS otps_user_purpose ON otps(user_id, purpose, created_at DESC);
CREATE TABLE IF NOT EXISTS sessions (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device TEXT NOT NULL DEFAULT 'Không rõ thiết bị',
  platform TEXT,
  ip TEXT,
  city TEXT,
  country TEXT,
  is_new_device BOOLEAN NOT NULL DEFAULT false,
  status TEXT NOT NULL DEFAULT 'normal' CHECK (status IN ('normal','trusted','denied')),
  revoked BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS categories (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  icon TEXT NOT NULL DEFAULT 'shapes'
);
CREATE TABLE IF NOT EXISTS products (
  id SERIAL PRIMARY KEY,
  name TEXT NOT NULL,
  price NUMERIC(14,0) NOT NULL DEFAULT 0 CHECK (price >= 0),
  description TEXT,
  icon TEXT,
  category_id INT REFERENCES categories(id) ON DELETE SET NULL,
  updated_by INT REFERENCES users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS activities (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id) ON DELETE CASCADE,
  action TEXT NOT NULL,
  title TEXT NOT NULL,
  detail TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS noise_records (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  avg_db REAL NOT NULL,
  max_db REAL NOT NULL,
  duration_sec INT NOT NULL,
  level TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS location_shares (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  accuracy REAL,
  place TEXT,
  address TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS translations (
  id SERIAL PRIMARY KEY,
  user_id INT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source_lang TEXT NOT NULL,
  target_lang TEXT NOT NULL,
  source_text TEXT NOT NULL,
  translated_text TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
`

async function seed() {
  const { rows } = await q('SELECT count(*)::int AS n FROM users')
  if (rows[0].n > 0) return
  const email = process.env.SEED_EMAIL || 'hutech.vn.online@gmail.com'
  const users = [
    ['chinhan', 'Nguyễn Chí Nhân', 'Admin', 'Admin@123'],
    ['phuc', 'Lê Hoàng Phúc', 'Staff', 'Staff@123'],
    ['baongoc', 'Trần Bảo Ngọc', 'User', 'User@123'],
  ]
  for (const [username, name, role, pass] of users) {
    await q(
      `INSERT INTO users (username, email, full_name, password_hash, role, email_confirmed)
       VALUES ($1,$2,$3,$4,$5,true)`,
      [username, email, name, await bcrypt.hash(pass, 10), role],
    )
  }
  const cats = [
    ['Điện tử', 'Thiết bị điện tử, công nghệ và phụ kiện', 'laptop'],
    ['Thời trang', 'Quần áo, giày dép và phụ kiện thời trang', 'shirt'],
    ['Gia dụng', 'Đồ dùng gia đình, nhà bếp và tiện ích', 'cooking-pot'],
  ]
  const ids = []
  for (const c of cats) {
    ids.push((await one('INSERT INTO categories (name, description, icon) VALUES ($1,$2,$3) RETURNING id', c)).id)
  }
  const products = [
    ['Laptop Dell XPS 15', 35000000, 'Laptop cao cấp cho lập trình viên', 'laptop', 0],
    ['Bàn phím cơ không dây', 1850000, 'Bàn phím cơ Bluetooth switch Red', 'keyboard', 0],
    ['Chuột Logitech MX Master 3S', 2490000, 'Chuột công thái học cao cấp', 'mouse', 0],
    ['Áo thun thể thao nam', 250000, 'Chất liệu thun lạnh thoáng khí', 'shirt', 1],
    ['Áo khoác gió chống nước', 450000, 'Áo khoác đi mưa 2 lớp', 'shirt', 1],
    ['Nồi chiên không dầu 5L', 1200000, 'Công nghệ Rapid Air giảm 80% dầu mỡ', 'cooking-pot', 2],
    ['Máy lọc không khí thông minh', 3200000, 'Lọc bụi mịn PM2.5 kết nối Wifi', 'air-vent', 2],
  ]
  for (const [name, price, desc, icon, ci] of products) {
    await q('INSERT INTO products (name, price, description, icon, category_id) VALUES ($1,$2,$3,$4,$5)', [name, price, desc, icon, ids[ci]])
  }
}

let ready
export function ensureDb() {
  ready ??= (async () => {
    // Khóa để 2 instance serverless khởi động cùng lúc không seed trùng
    const c = await pool.connect()
    try {
      await c.query('SELECT pg_advisory_lock(20261021)')
      await c.query(SCHEMA)
      await seed()
    } finally {
      await c.query('SELECT pg_advisory_unlock(20261021)').catch(() => {})
      c.release()
    }
  })().catch((e) => {
    ready = undefined
    throw e
  })
  return ready
}
