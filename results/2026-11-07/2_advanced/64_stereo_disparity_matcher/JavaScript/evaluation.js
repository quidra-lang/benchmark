const { twoDecimals } = require('./refinement');
const REGION_ORDER = ['nonocc', 'all', 'disc'];

function truthRegions(truth, width, height) {
  const known = truth.flatMap((value, p) => value === 0 ? [] : [p]);
  const occluded = [];
  for (const p of known) {
    const x = p % width, y = Math.floor(p / width), g = truth[p];
    let hidden = x < g;
    for (let x2 = 0; x2 < width && !hidden; x2++) {
      const other = truth[y * width + x2];
      hidden = other > g && x2 - other === x - g;
    }
    if (hidden) occluded.push(p);
  }
  const hidden = new Set(occluded);
  const nonocc = known.filter(p => !hidden.has(p));
  const disc = nonocc.filter(p => {
    const x = p % width, y = Math.floor(p / width);
    for (let yy = Math.max(0, y - 1); yy < Math.min(height, y + 2); yy++) {
      for (let xx = Math.max(0, x - 1); xx < Math.min(width, x + 2); xx++) {
        const value = truth[yy * width + xx];
        if (value !== 0 && Math.abs(value - truth[p]) >= 2) return true;
      }
    }
    return false;
  });
  return { all: known, nonocc, disc, occluded };
}

function evaluate(image, truth, region) {
  const errors = region.filter(p => image[p] !== 0).map(p => Math.abs(image[p] - truth[p]));
  const valid = errors.length;
  const missing = region.length - valid;
  const errorSum = errors.reduce((a, b) => a + b, 0);
  return {
    pixels: region.length, valid,
    bad1: missing + errors.filter(e => e > 1).length,
    bad2: missing + errors.filter(e => e > 2).length,
    errorSum, mae: valid ? twoDecimals(errorSum, valid) : '-',
    exact: errors.filter(e => e === 0).length,
  };
}

function gcd(a, b) {
  while (b !== 0) [a, b] = [b, a % b];
  return a;
}

function ratio(numerator, denominator) {
  if (denominator === 0) return '0/1 0.00';
  const divisor = gcd(numerator, denominator);
  return `${numerator / divisor}/${denominator / divisor} ${twoDecimals(100 * numerator, denominator)}`;
}

module.exports = { REGION_ORDER, truthRegions, evaluate, ratio };
