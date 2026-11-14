import { suite } from './journey.js';

const test = suite('baseline');
export const options = test.options;
export const setup = test.setup;
export default test.run;
