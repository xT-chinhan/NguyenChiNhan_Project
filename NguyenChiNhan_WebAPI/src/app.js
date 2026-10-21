import express from 'express'
import cors from 'cors'
import { ensureDb } from './db.js'
import { HttpError } from './security.js'
import { devMail, outbox } from './mail.js'
import authRoutes from './routes/auth.js'
import { me, securityLinks } from './routes/me.js'
import { categories, products } from './routes/catalog.js'
import { users, dashboard } from './routes/admin.js'
import { tools } from './routes/tools.js'
import { attendance } from './routes/attendance.js'
import { openapi, swaggerHtml } from './openapi.js'

const app = express()
app.set('trust proxy', true)
app.use(cors())
app.use(express.json({ limit: '200kb' }))
app.use(express.urlencoded({ extended: false }))

app.get('/', (_req, res) => res.redirect('/swagger'))
app.get('/swagger', (_req, res) => res.type('html').send(swaggerHtml))
app.get('/openapi.json', (_req, res) => res.json(openapi))
app.get('/api', (_req, res) =>
  res.json({ name: 'NguyenChiNhan_WebAPI', author: 'Nguyễn Chí Nhân', database: 'nguyenchinhan_db', docs: '/swagger' }),
)

// Tạo bảng + seed lần đầu (serverless: chạy một lần mỗi instance)
app.use('/api', async (_req, _res, next) => {
  await ensureDb()
  next()
})

app.use('/api/auth', authRoutes)
app.use('/api/me', me)
app.use('/api/security', securityLinks)
app.use('/api/categories', categories)
app.use('/api/products', products)
app.use('/api/users', users)
app.use('/api/dashboard', dashboard)
app.use('/api/tools', tools)
app.use('/api/attendance', attendance)

if (devMail) app.get('/api/dev/outbox', (_req, res) => res.json(outbox.slice(-10)))

app.use('/api', (_req, _res) => {
  throw new HttpError(404, 'Không tìm thấy API.', 'NOT_FOUND')
})

// eslint-disable-next-line no-unused-vars
app.use((err, _req, res, _next) => {
  if (err instanceof HttpError) {
    return res.status(err.status).json({ message: err.message, code: err.code, ...(err.extra || {}) })
  }
  if (err?.type === 'entity.parse.failed') return res.status(400).json({ message: 'JSON không hợp lệ.', code: 'BAD_JSON' })
  console.error(err)
  res.status(500).json({ message: 'Lỗi máy chủ, thử lại sau.', code: 'SERVER_ERROR' })
})

export default app
