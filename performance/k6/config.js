export const profiles = {
  smoke: [1, 1, '10s'],
  baseline: [20, 3, '60s'],
  moderate: [50, 8, '90s'],
  high: [100, 15, '90s'],
  stress: [250, 30, '90s'],
  extreme: [500, 60, '90s'],
  spike: [200, 30, '20s'],
  checkout: [5, 1, '15s'],
};

export function target(env, profile) {
  const origin = env.BASE_URL || '';
  const match = /^(https?):\/\/([a-zA-Z0-9.-]+)(?::[0-9]{1,5})?$/.exec(origin);
  if (!match) throw new Error('BASE_URL must be an HTTP(S) origin without a path or credentials');
  const host = match[2].toLowerCase().replace(/\.+$/, '');
  const mode = env.TARGET_ENV;
  if (/(^|\.)((seallo|ollazen)\.(ma|com)|morea\.onrender\.com)$/.test(host)) {
    throw new Error('Known production hosts are denied');
  }
  if (mode === 'local') {
    if (!['127.0.0.1', 'localhost'].includes(host)) throw new Error('Local mode requires loopback');
  } else if (mode === 'staging') {
    if (match[1] !== 'https' || env.APPROVED_STAGING_ORIGIN !== origin ||
        env.ISOLATION_CONFIRMED !== 'yes') throw new Error('Staging requires an approved HTTPS origin and isolation attestation');
  } else {
    throw new Error('TARGET_ENV must be local or staging');
  }
  if (!['smoke', 'baseline', 'checkout'].includes(profile) && env.BASELINE_PASSED !== 'yes') {
    throw new Error('Pass baseline against this environment before running this profile');
  }
  if (profile === 'checkout' && env.ALLOW_SYNTHETIC_ORDERS !== 'yes') {
    throw new Error('Checkout requires ALLOW_SYNTHETIC_ORDERS=yes');
  }
  if (!/^[a-zA-Z0-9_-]{24,128}$/.test(env.PERF_TARGET_TOKEN || '')) {
    throw new Error('PERF_TARGET_TOKEN must match the isolated application token');
  }
  return origin;
}

export function scenario(profile) {
  const [maxVUs, target, duration] = profiles[profile];
  const pool = { maxVUs, preAllocatedVUs: maxVUs, timeUnit: '1s', gracefulStop: '15s' };
  if (profile === 'smoke' || profile === 'checkout') {
    return { ...pool, executor: 'constant-arrival-rate', rate: target, duration };
  }
  return {
    ...pool,
    executor: 'ramping-arrival-rate',
    startRate: profile === 'spike' ? 0 : 1,
    stages: [
      { target, duration: profile === 'spike' ? '2s' : '20s' },
      { target, duration },
      { target: 0, duration: '10s' },
    ],
  };
}
