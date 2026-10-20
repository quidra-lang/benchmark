'use strict';

const log10 = value => Math.log(value) / 2.302585092994046;

function median(values) {
  if (values.length === 0) return null;
  const sorted = values.slice().sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function localMagnitude(amplitude, distanceKm, coefficients) {
  const [a, b, c] = coefficients;
  return log10(amplitude) + a * log10(distanceKm / 100) + b * (distanceKm - 100) + c;
}

function durationMagnitude(duration, distanceKm, coefficients) {
  const [a, b, c] = coefficients;
  return a + b * log10(duration / 100) + c * distanceKm;
}

const magnitudeClass = hundredths => Math.floor((hundredths + 5) / 10);

function frequencyStatistics(classes) {
  const frequencies = new Map();
  for (const value of classes) frequencies.set(value, (frequencies.get(value) ?? 0) + 1);
  const ordered = [...frequencies.keys()].sort((a, b) => a - b);
  let completeness = ordered[0];
  for (const value of ordered) {
    if (frequencies.get(value) > frequencies.get(completeness)) completeness = value;
  }
  let count = 0;
  let total = 0;
  for (const value of classes) {
    if (value >= completeness) { count++; total += value; }
  }
  const mc = completeness / 10;
  const mean = total / (10 * count);
  const b = 0.4342944819032518 / (mean - (mc - 0.05));
  const sigma = b / Math.sqrt(count);
  const a = log10(count) + b * mc;
  return { frequencies, minimum: ordered[0], maximum: ordered.at(-1), completeness, count, b, sigma, a };
}

module.exports = { log10, median, localMagnitude, durationMagnitude, magnitudeClass, frequencyStatistics };
