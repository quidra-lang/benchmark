'use strict';

const { at } = require('./filters');
const { neighbors } = require('./canny');

function detect(gx, gy, width, height, window, threshold, maximum) {
  const half = (window - 1) / 2, response = Array(width * height).fill(0);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let xx = 0, yy = 0, xy = 0;
      for (let j = -half; j <= half; j++) {
        for (let i = -half; i <= half; i++) {
          const dx = at(gx, x + i, y + j, width, height), dy = at(gy, x + i, y + j, width, height);
          xx += dx * dx;
          yy += dy * dy;
          xy += dx * dy;
        }
      }
      // Every integer intermediate, including these products, is below 2^53.
      response[y * width + x] = xx * yy - xy * xy - Math.floor((xx + yy) * (xx + yy) / 25);
    }
  }
  const candidates = [];
  for (let index = 0; index < response.length; index++) {
    const value = response[index];
    if (value < threshold) continue;
    if (neighbors(index, width, height).some(next => response[next] > value ||
        (response[next] === value && next < index))) continue;
    candidates.push({ x: index % width, y: Math.floor(index / width), response: value });
  }
  candidates.sort((a, b) => a.response !== b.response ? (a.response > b.response ? -1 : 1) : a.y - b.y || a.x - b.x);
  const corners = candidates.slice(0, maximum).map((corner, i) => ({ ...corner, number: i + 1 }));
  return { response, candidates, corners };
}

module.exports = { detect };
