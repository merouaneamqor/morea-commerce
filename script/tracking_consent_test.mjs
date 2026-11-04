import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
import test from 'node:test'
const source = readFileSync(new URL('../app/javascript/controllers/tracking_consent_controller.js', import.meta.url), 'utf8')
  .replace(/import .*\n/, '').replace('export default class', 'globalThis.Notice = class')
test('notice follows resized height and clears its offset on Turbo removal', async () => {
  const properties = new Map()
  let resize, disconnected = false, removed = false
  const context = vm.createContext({ Controller: class {}, ResizeObserver: class {
    constructor(callback) { resize = callback }
    observe() {} disconnect() { disconnected = true }
  }, document: { body: { style: { setProperty: (k,v) => properties.set(k,v), removeProperty: k => properties.delete(k) }, classList: { remove: () => {} } }, querySelector: () => ({content:'synthetic-token'}) }, fetch: async () => ({ ok: false }) })
  vm.runInContext(source, context)
  const notice = new context.Notice()
  let height = 120
  notice.element = { getBoundingClientRect: () => ({height}), remove: () => { removed = true } }
  notice.connect(); resize()
  assert.equal(properties.get('--cookie-notice-height'), '120px')
  height = 180; resize()
  assert.equal(properties.get('--cookie-notice-height'), '180px')
  await notice.accept()
  assert.equal(removed, false, 'failed save keeps the notice visible')
  context.fetch = async () => ({ok: true})
  await notice.accept()
  assert.equal(removed, true)
  notice.disconnect()
  assert.equal(disconnected, true)
  assert.equal(properties.size, 0)
})
