import { suite } from './journey.js';

const test = suite('smoke');
export const options = test.options;
export const setup = test.setup;
export default test.run;
