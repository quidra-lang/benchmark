'use strict';

const S = 4096;
const div = (a, b) => Math.floor(a / b);
const mul = (a, b) => div(a * b, S);

function isqrt(n) {
  let low = 0, high = 1;
  while (high * high <= n) high *= 2;
  while (high - low > 1) {
    const middle = div(low + high, 2);
    if (middle * middle <= n) low = middle;
    else high = middle;
  }
  return low;
}

module.exports = { S, div, mul, isqrt };
