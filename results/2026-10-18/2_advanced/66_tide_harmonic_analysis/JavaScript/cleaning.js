'use strict';

function median(sorted) {
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
}

function flatRuns(numeric, minimum) {
  const runs = [];
  for (let start = 0; start < numeric.length;) {
    let end = start;
    while (end + 1 < numeric.length && numeric[end + 1].time === numeric[end].time + 1 &&
      numeric[end + 1].milli === numeric[start].milli) end++;
    if (end - start + 1 >= minimum) {
      runs.push({start: numeric[start].time, end: numeric[end].time, value: numeric[start].value});
    }
    start = end + 1;
  }
  return runs;
}

function lowerBound(values, target) {
  let low = 0;
  let high = values.length;
  while (low < high) {
    const middle = Math.floor((low + high) / 2);
    if (values[middle] < target) low = middle + 1;
    else high = middle;
  }
  return low;
}

function mad(sorted, center) {
  // Distances on either side of the median are two increasing sequences.
  let right = lowerBound(sorted, center);
  let left = right - 1;
  let previous = 0;
  let current = 0;
  for (let index = 0; index <= Math.floor(sorted.length / 2); index++) {
    previous = current;
    const before = left >= 0 ? Math.abs(sorted[left] - center) : Infinity;
    const after = right < sorted.length ? Math.abs(sorted[right] - center) : Infinity;
    if (before <= after) {
      current = before;
      left--;
    } else {
      current = after;
      right++;
    }
  }
  return sorted.length % 2 === 1 ? current : (previous + current) / 2;
}

function spikeTests(candidates, settings) {
  const sorted = [];
  const spikes = [];
  let left = 0;
  let right = 0;
  let tested = 0;
  for (const row of candidates) {
    while (right < candidates.length && candidates[right].time <= row.time + settings.window) {
      const value = candidates[right++].preliminary;
      sorted.splice(lowerBound(sorted, value), 0, value);
    }
    while (left < right && candidates[left].time < row.time - settings.window) {
      const value = candidates[left++].preliminary;
      sorted.splice(lowerBound(sorted, value), 1);
    }
    if (sorted.length < settings.count) continue;
    tested++;
    const center = median(sorted);
    const deviation = mad(sorted, center);
    const limit = Math.max(settings.factor * 1.4826 * deviation, settings.minimum);
    if (Math.abs(row.preliminary - center) > limit) {
      spikes.push({time: row.time, value: row.value, residual: row.preliminary,
        median: center, mad: deviation, limit});
    }
  }
  return {tested, spikes};
}

function gaps(first, last, reasons) {
  const result = [];
  for (let time = first; time <= last;) {
    if (!reasons.has(time)) {
      time++;
      continue;
    }
    const start = time;
    let cause = reasons.get(time);
    while (time <= last && reasons.has(time)) {
      if (reasons.get(time) !== cause) cause = 'mixed';
      time++;
    }
    result.push({start, end: time - 1, cause});
  }
  return result;
}

module.exports = {median, flatRuns, spikeTests, gaps};
