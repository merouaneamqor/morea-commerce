import { suite } from './journey.js';

const profile = __ENV.PERF_PROFILE || 'stress';
if (!['moderate', 'high', 'stress', 'extreme'].includes(profile)) throw new Error('Invalid stress profile');
const test = suite(profile);
export const options = test.options;
export const setup = test.setup;
export default test.run;
