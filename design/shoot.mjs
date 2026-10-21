// Chụp ảnh mockup: node design/shoot.mjs [tiền tố data-shot]. 1 trình duyệt, tuần tự, 2x.
import { createRequire } from 'node:module'
import { fileURLToPath } from 'node:url'
import path from 'node:path'
const here = path.dirname(fileURLToPath(import.meta.url))
const { chromium } = createRequire('/home/chinhan/Downloads/app-tracker/admin/package.json')('playwright')
const prefix = process.argv[2] || ''
const b = await chromium.launch()
const p = await b.newPage({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 2 })
await p.goto('file://' + path.join(here, 'mockup', 'index.html'))
await p.evaluate(() => document.fonts.ready)
await p.waitForTimeout(800)
for (const el of await p.$$('.phone[data-shot]')) {
  const name = await el.getAttribute('data-shot')
  if (!name.startsWith(prefix)) continue
  await el.scrollIntoViewIfNeeded()
  await el.screenshot({ path: path.join(here, 'mockup', 'shots', name + '.png'), animations: 'disabled' })
  console.log(name)
}
await p.setViewportSize({ width: 1600, height: 1000 })
await p.screenshot({ path: path.join(here, 'mockup', 'shots', 'overview.png'), fullPage: true, scale: 'css' })
await b.close()
