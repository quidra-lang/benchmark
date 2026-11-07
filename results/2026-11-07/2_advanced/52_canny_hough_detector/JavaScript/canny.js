'use strict';

function neighbors(index, width, height) {
  const x = index % width, y = Math.floor(index / width), result = [];
  for (let dy = -1; dy <= 1; dy++) {
    for (let dx = -1; dx <= 1; dx++) {
      if (dx === 0 && dy === 0) continue;
      const nx = x + dx, ny = y + dy;
      if (nx >= 0 && nx < width && ny >= 0 && ny < height) result.push(ny * width + nx);
    }
  }
  return result;
}

function directions(gx, gy) {
  return Uint8Array.from(gx, (value, index) => {
    const ax = Math.abs(value), ay = Math.abs(gy[index]);
    if (29 * ay <= 12 * ax) return 0;
    if (29 * ay >= 70 * ax) return 90;
    return value * gy[index] < 0 ? 45 : 135;
  });
}

function suppress(magnitude, direction, width, height) {
  const result = new Int32Array(width * height);
  const offset = { 0: -1, 45: 1 - width, 90: -width, 135: -1 - width };
  for (let y = 1; y < height - 1; y++) {
    for (let x = 1; x < width - 1; x++) {
      const index = y * width + x, delta = offset[direction[index]], m = magnitude[index];
      if (m > magnitude[index + delta] && m >= magnitude[index - delta]) result[index] = m;
    }
  }
  return result;
}

function hysteresis(nms, width, height, low, high) {
  const edges = new Uint8Array(nms.length), strong = new Uint8Array(nms.length);
  const weak = new Uint8Array(nms.length), queue = [];
  for (let i = 0; i < nms.length; i++) {
    if (nms[i] >= high) { strong[i] = 1; edges[i] = 1; queue.push(i); }
    else if (nms[i] >= low) weak[i] = 1;
  }
  for (let head = 0; head < queue.length; head++) {
    for (const next of neighbors(queue[head], width, height)) {
      if (!edges[next] && nms[next] >= low) { edges[next] = 1; queue.push(next); }
    }
  }
  return { edges, strong, weak };
}

function components(edges, width, height) {
  const visited = new Uint8Array(edges.length), groups = [];
  for (let i = 0; i < edges.length; i++) {
    if (!edges[i] || visited[i]) continue;
    const group = [i];
    visited[i] = 1;
    for (let head = 0; head < group.length; head++) {
      for (const next of neighbors(group[head], width, height)) {
        if (edges[next] && !visited[next]) { visited[next] = 1; group.push(next); }
      }
    }
    groups.push(group);
  }
  return groups;
}

module.exports = { neighbors, directions, suppress, hysteresis, components };
