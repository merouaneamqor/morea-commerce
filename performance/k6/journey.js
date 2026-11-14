import http from 'k6/http';
import { check, fail } from 'k6';
import { Rate } from 'k6/metrics';
import exec from 'k6/execution';
import { scenario, target } from './config.js';

const completed = new Rate('journey_completed');
const ordered = new Rate('checkout_completed');
const reads = ['home', 'catalog', 'collection', 'product'];

export function suite(profile) {
  const origin = target(__ENV, profile);
  const route = '/fr';
  const writes = profile === 'checkout';
  const token = __ENV.PERF_TARGET_TOKEN;
  const preflight = { headers: { 'X-Morea-Perf-Token': token }, timeout: '5s', redirects: 0 };
  const thresholds = {
    http_req_failed: ['rate<0.01', { threshold: 'rate<0.10', abortOnFail: true, delayAbortEval: '5s' }],
    journey_completed: ['rate>0.99', { threshold: 'rate>0.90', abortOnFail: true, delayAbortEval: '5s' }],
    dropped_iterations: ['count==0'],
  };
  for (const name of reads) thresholds[`http_req_duration{name:${name}}`] = ['p(95)<500'];
  if (writes) thresholds.checkout_completed = ['rate>0.99'];

  function step(response, name, good) {
    return check(response, { [name]: good });
  }

  function request(method, path, name, status, body = null, csrf = null) {
    const headers = { Accept: 'text/html' };
    if (csrf) headers['X-CSRF-Token'] = csrf;
    return http.request(method, origin + path, body, {
      timeout: '4s', redirects: 0, headers, tags: { name },
      responseCallback: http.expectedStatuses(...status),
    });
  }

  function browse() {
    const landing = request('GET', '/', 'landing', [301, 302]);
    if (!step(landing, 'localized redirect', r => [301, 302].includes(r.status) && pathIs(r, route))) return false;
    for (const [name, path, marker] of [
      ['home', route, '/fr/collections'],
      ['catalog', route + '/collections', '/fr/collections/perf-collection'],
      ['collection', route + '/collections/perf-collection', '/fr/products/perf-product'],
    ]) {
      const page = request('GET', path, name, [200]);
      if (!step(page, name, r => r.status === 200 && r.body.includes(marker))) return false;
    }
    const product = request('GET', route + '/products/perf-product', 'product', [200]);
    if (!step(product, 'variant form', r => r.status === 200 && input(r, 'product_id') && input(r, 'product_variant_id'))) return false;
    if (!writes) return true;

    const csrf = product.html().find('meta[name="csrf-token"]').attr('content');
    if (!csrf) return false;
    const add = request('POST', route + '/cart/add_item', 'cart_add', [302, 303], {
      product_id: input(product, 'product_id'),
      product_variant_id: input(product, 'product_variant_id'),
      quantity: '1',
    }, csrf);
    if (!step(add, 'added to cart', r => [302, 303].includes(r.status) && pathIs(r, route + '/cart'))) return false;

    const cart = request('GET', route + '/cart', 'cart', [200]);
    const item = cart.status === 200 && input(cart, 'item_id');
    if (!step(cart, 'cart persisted', () => item && cart.body.includes('Performance Fixture Variant'))) return false;
    const update = request('PATCH', route + '/cart/update_item', 'cart_update', [302, 303], {
      item_id: item, quantity: '2',
    }, csrf);
    if (!step(update, 'cart updated', r => [302, 303].includes(r.status) && pathIs(r, route + '/cart'))) return false;

    const checkout = request('GET', route + '/checkout', 'checkout_start', [200]);
    if (!step(checkout, 'checkout form', r => r.status === 200 && r.body.includes('name="checkout[phone]"'))) return false;
    const checkoutCsrf = checkout.html().find('meta[name="csrf-token"]').attr('content');
    if (!checkoutCsrf) return false;
    // Reserved fictional NANP 555-0100 through 555-0199 range.
    const subscriber = String(exec.scenario.iterationInTest).padStart(2, '0');
    const order = request('POST', route + '/checkout', 'checkout_submit', [303], {
      'checkout[name]': 'Synthetic Performance',
      'checkout[phone]': '+120255501' + subscriber,
      'checkout[phone_country]': 'US',
      'checkout[city]': 'Fixture City',
      'checkout[address]': '1 Synthetic Address',
      'checkout[privacy_accepted]': '1',
      'checkout[age_confirmed]': '1',
    }, checkoutCsrf);
    const location = redirectPath(order);
    if (!step(order, 'order created', r => r.status === 303 && /^\/fr\/orders\/M[0-9]{6}$/.test(location))) return false;
    const receipt = request('GET', location, 'order_show', [200]);
    return step(receipt, 'correct synthetic receipt', r => r.status === 200 &&
      r.body.includes('1 Synthetic Address') && r.body.includes('× 2'));
  }

  function redirectPath(response) {
    const location = response.headers.Location || '';
    return location.startsWith(origin + '/') ? location.slice(origin.length) : location;
  }

  function pathIs(response, path) { return redirectPath(response) === path; }

  function input(response, name) {
    return response.html().find(`input[name="${name}"]`).first().attr('value');
  }

  return {
    options: {
      scenarios: { [profile]: scenario(profile) },
      thresholds,
      summaryTrendStats: ['count', 'avg', 'p(50)', 'p(95)', 'p(99)', 'max'],
      insecureSkipTLSVerify: false,
      // Do not emit order numbers or other per-request URLs as metric tags.
      systemTags: ['status', 'method', 'name', 'scenario', 'expected_response'],
    },
    setup() {
      const result = http.get(origin + '/_performance/ready', {
        ...preflight, tags: { name: 'preflight' },
      });
      const ready = result.body === 'synthetic-orders-ready' || (!writes && result.body === 'performance-ready');
      if (result.status !== 200 || !ready) {
        fail('Isolated application preflight failed (status ' + result.status + ')');
      }
    },
    run() {
      let ok = false;
      try { ok = browse(); } finally {
        completed.add(ok);
        if (writes) ordered.add(ok);
      }
    },
  };
}
