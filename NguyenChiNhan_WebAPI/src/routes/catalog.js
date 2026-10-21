import { Router } from 'express'
import { q, one } from '../db.js'
import { auth, HttpError } from '../security.js'

const vnd = (n) => `${Number(n).toLocaleString('vi-VN')}đ`
const log = (userId, action, title, detail) =>
  q('INSERT INTO activities (user_id, action, title, detail) VALUES ($1,$2,$3,$4)', [userId, action, title, detail ?? null])

// ---------- Danh mục: ai đăng nhập cũng xem; Admin thêm/sửa/xóa ----------
export const categories = Router()
categories.use(auth())

const catSelect = `SELECT c.id, c.name, c.description, c.icon, count(p.id)::int AS "productCount"
  FROM categories c LEFT JOIN products p ON p.category_id = c.id`

categories.get('/', async (_req, res) => {
  res.json((await q(`${catSelect} GROUP BY c.id ORDER BY c.id`)).rows)
})

categories.get('/:id', async (req, res) => {
  const c = await one(`${catSelect} WHERE c.id = $1 GROUP BY c.id`, [Number(req.params.id)])
  if (!c) throw new HttpError(404, 'Không tìm thấy danh mục.', 'NOT_FOUND')
  res.json(c)
})

const catBody = (b) => {
  const name = String(b?.name || '').trim()
  if (!name) throw new HttpError(400, 'Tên danh mục không được trống.', 'VALIDATION')
  return [name, b?.description ? String(b.description).trim() : null, b?.icon ? String(b.icon) : 'shapes']
}

categories.post('/', auth('Admin'), async (req, res) => {
  const c = await one('INSERT INTO categories (name, description, icon) VALUES ($1,$2,$3) RETURNING id', catBody(req.body))
  await log(req.user.id, 'create', `Thêm danh mục ${req.body.name}`)
  res.status(201).json(await one(`${catSelect} WHERE c.id = $1 GROUP BY c.id`, [c.id]))
})

categories.put('/:id', auth('Admin'), async (req, res) => {
  const [name, description, icon] = catBody(req.body)
  const c = await one(
    'UPDATE categories SET name=$2, description=$3, icon=COALESCE($4, icon) WHERE id=$1 RETURNING id',
    [Number(req.params.id), name, description, req.body?.icon ? icon : null],
  )
  if (!c) throw new HttpError(404, 'Không tìm thấy danh mục.', 'NOT_FOUND')
  await log(req.user.id, 'update', `Sửa danh mục ${name}`)
  res.json(await one(`${catSelect} WHERE c.id = $1 GROUP BY c.id`, [c.id]))
})

// Xóa danh mục: sản phẩm giữ lại, chỉ không còn thuộc danh mục (ON DELETE SET NULL)
categories.delete('/:id', auth('Admin'), async (req, res) => {
  const c = await one(`${catSelect} WHERE c.id = $1 GROUP BY c.id`, [Number(req.params.id)])
  if (!c) throw new HttpError(404, 'Không tìm thấy danh mục.', 'NOT_FOUND')
  await q('DELETE FROM categories WHERE id = $1', [c.id])
  await log(req.user.id, 'delete', `Xóa danh mục ${c.name}`, `${c.productCount} sản phẩm không còn danh mục`)
  res.json({ message: `Đã xóa danh mục ${c.name}.`, unassignedProducts: c.productCount })
})

// ---------- Sản phẩm: ai đăng nhập cũng xem; Nhân viên + Admin thêm/sửa; Admin xóa ----------
export const products = Router()
products.use(auth())

const prodSelect = `SELECT p.id, p.name, p.price, p.description, COALESCE(p.icon, c.icon, 'package') AS icon,
  p.category_id AS "categoryId", c.name AS "categoryName", p.updated_at AS "updatedAt", u.full_name AS "updatedBy"
  FROM products p LEFT JOIN categories c ON c.id = p.category_id LEFT JOIN users u ON u.id = p.updated_by`
const SORTS = { price_asc: 'p.price ASC, p.id', price_desc: 'p.price DESC, p.id', name: 'p.name, p.id', newest: 'p.id DESC' }

products.get('/', async (req, res) => {
  const where = []
  const args = []
  if (req.query.categoryId) {
    args.push(Number(req.query.categoryId))
    where.push(`p.category_id = $${args.length}`)
  }
  if (req.query.q) {
    args.push(`%${String(req.query.q).trim()}%`)
    where.push(`(p.name ILIKE $${args.length} OR p.description ILIKE $${args.length})`)
  }
  const order = SORTS[req.query.sort] || SORTS.price_asc
  const { rows } = await q(`${prodSelect} ${where.length ? 'WHERE ' + where.join(' AND ') : ''} ORDER BY ${order}`, args)
  res.json(rows)
})

products.get('/:id', async (req, res) => {
  const p = await one(`${prodSelect} WHERE p.id = $1`, [Number(req.params.id)])
  if (!p) throw new HttpError(404, 'Không tìm thấy sản phẩm.', 'NOT_FOUND')
  res.json(p)
})

const prodBody = async (b) => {
  const name = String(b?.name || '').trim()
  const price = Number(b?.price)
  if (!name) throw new HttpError(400, 'Tên sản phẩm không được trống.', 'VALIDATION')
  if (!Number.isFinite(price) || price < 0) throw new HttpError(400, 'Giá bán không hợp lệ.', 'VALIDATION')
  const categoryId = b?.categoryId ? Number(b.categoryId) : null
  if (categoryId && !(await one('SELECT 1 FROM categories WHERE id = $1', [categoryId]))) {
    throw new HttpError(400, 'Danh mục không tồn tại.', 'VALIDATION')
  }
  return { name, price: Math.round(price), description: b?.description ? String(b.description).trim() : null, categoryId, icon: b?.icon || null }
}

products.post('/', auth('Admin', 'Staff'), async (req, res) => {
  const b = await prodBody(req.body)
  const p = await one(
    `INSERT INTO products (name, price, description, category_id, icon, updated_by) VALUES ($1,$2,$3,$4,$5,$6) RETURNING id`,
    [b.name, b.price, b.description, b.categoryId, b.icon, req.user.id],
  )
  const full = await one(`${prodSelect} WHERE p.id = $1`, [p.id])
  await log(req.user.id, 'create', `Thêm ${b.name}`, full.categoryName || 'Chưa có danh mục')
  res.status(201).json(full)
})

products.put('/:id', auth('Admin', 'Staff'), async (req, res) => {
  const old = await one('SELECT * FROM products WHERE id = $1', [Number(req.params.id)])
  if (!old) throw new HttpError(404, 'Không tìm thấy sản phẩm.', 'NOT_FOUND')
  const b = await prodBody(req.body)
  await q(
    `UPDATE products SET name=$2, price=$3, description=$4, category_id=$5, icon=COALESCE($6, icon), updated_by=$7, updated_at=now() WHERE id=$1`,
    [old.id, b.name, b.price, b.description, b.categoryId, b.icon, req.user.id],
  )
  const changes = []
  if (Number(old.price) !== b.price) changes.push(`${vnd(old.price)} → ${vnd(b.price)}`)
  if (old.name !== b.name) changes.push(`Tên: ${old.name} → ${b.name}`)
  if ((old.description || '') !== (b.description || '')) changes.push('Sửa mô tả')
  if ((old.category_id || null) !== b.categoryId) changes.push('Đổi danh mục')
  const title = Number(old.price) !== b.price ? `Sửa giá ${b.name}` : `Sửa ${b.name}`
  await log(req.user.id, 'update', title, changes.join(' · ') || 'Không đổi gì')
  res.json(await one(`${prodSelect} WHERE p.id = $1`, [old.id]))
})

products.delete('/:id', auth('Admin'), async (req, res) => {
  const p = await one('DELETE FROM products WHERE id = $1 RETURNING name', [Number(req.params.id)])
  if (!p) throw new HttpError(404, 'Không tìm thấy sản phẩm.', 'NOT_FOUND')
  await log(req.user.id, 'delete', `Xóa ${p.name}`)
  res.json({ message: `Đã xóa ${p.name}.` })
})
