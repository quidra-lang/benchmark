function hundredths(value) {
  const n = BigInt(value);
  return `${n / 100n}.${(n % 100n).toString().padStart(2, '0')}`;
}

function roundedHundredths(numerator, denominator) {
  const a = BigInt(numerator), b = BigInt(denominator);
  return Number((200n * a + b) / (2n * b));
}

function twoDecimals(numerator, denominator = 1) {
  return hundredths(roundedHundredths(numerator, denominator));
}

function depthHundredths(disparity, focal, baseline) {
  return roundedHundredths(focal * baseline, disparity);
}

function subpixel(disparity, costs, minimum, maximum, focal, baseline) {
  const d = disparity - minimum;
  let a = 0, b = 1;
  if (disparity > minimum && disparity < maximum
      && costs[d - 1] > costs[d] && costs[d + 1] >= costs[d]) {
    a = costs[d - 1] - costs[d + 1];
    b = 2 * (costs[d - 1] - 2 * costs[d] + costs[d + 1]);
  }
  const q = roundedHundredths(disparity * b + a, b);
  return [hundredths(q), twoDecimals(100 * focal * baseline, q)];
}

module.exports = { hundredths, twoDecimals, depthHundredths, subpixel };
