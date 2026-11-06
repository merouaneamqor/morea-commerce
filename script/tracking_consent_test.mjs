import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
import test from 'node:test'
const source = readFileSync(new URL('../app/javascript/controllers/tracking_consent_controller.js', import.meta.url), 'utf8')
  .replace(/import .*\n/, '').replace('export default class', 'globalThis.Notice = class')

test('accept posts granted and reloads; reject posts denied without reload', async () => {
  const properties = new Map()
  let resize, disconnected = false, removed = false, reloaded = false, lastBody
  const context = vm.createContext({
    Controller: class {},
    ResizeObserver: class {
      constructor(callback) { resize = callback }
      observe() {}
      disconnect() { disconnected = true }
    },
    document: {
      body: {
        style: { setProperty: (k, v) => properties.set(k, v), removeProperty: k => properties.delete(k) },
        classList: { remove: () => {} }
      },
      querySelector: () => ({ content: 'synthetic-token' })
    },
    window: { location: { reload: () => { reloaded = true } } },
    URLSearchParams,
    fetch: async (_url, options) => {
      lastBody = options.body.toString()
      return { ok: false }
    }
  })
  vm.runInContext(source, context)
  const notice = new context.Notice()
  let height = 120
  notice.urlValue = '/consent/tracking'
  notice.element = { getBoundingClientRect: () => ({ height }), remove: () => { removed = true } }
  notice.connect(); resize()
  assert.equal(properties.get('--cookie-notice-height'), '120px')

  await notice.accept({ preventDefault() {} })
  assert.equal(removed, false, 'failed save keeps the notice visible')
  assert.equal(lastBody, 'choice=granted')
  assert.equal(reloaded, false)

  context.fetch = async (_url, options) => {
    lastBody = options.body.toString()
    return { ok: true }
  }
  await notice.accept({ preventDefault() {} })
  assert.equal(removed, true)
  assert.equal(lastBody, 'choice=granted')
  assert.equal(reloaded, true)

  removed = false
  reloaded = false
  notice.element = { getBoundingClientRect: () => ({ height }), remove: () => { removed = true } }
  await notice.reject({ preventDefault() {} })
  assert.equal(lastBody, 'choice=denied')
  assert.equal(removed, true)
  assert.equal(reloaded, false)

  notice.disconnect()
  assert.equal(disconnected, true)
  assert.equal(properties.size, 0)
})
