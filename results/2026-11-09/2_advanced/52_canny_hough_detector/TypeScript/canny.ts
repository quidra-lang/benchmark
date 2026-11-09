export function neighbors(index: number, width: number, height: number) {
  const x = index % width;
  const y = Math.floor(index / width);
  const result: number[] = [];
  for (let j = -1; j <= 1; j++) {
    for (let i = -1; i <= 1; i++) {
      if (!i && !j) continue;
      const nx = x + i;
      const ny = y + j;
      if (nx >= 0 && nx < width && ny >= 0 && ny < height) result.push(ny * width + nx);
    }
  }
  return result;
}
export function directions(gx: number[], gy: number[]) {
  return gx.map((v, i) => {
    const ax = Math.abs(v);
    const ay = Math.abs(gy[i]);
    return 29 * ay <= 12 * ax ? 0 : 29 * ay >= 70 * ax ? 90 : v * gy[i] < 0 ? 45 : 135;
  });
}
export function suppress(m: number[], dir: number[], w: number, h: number) {
  const result: number[] = Array(w * h).fill(0);
  const offsets: Record<number, number> = { 0: -1, 45: 1 - w, 90: -w, 135: -1 - w };
  for (let y = 1; y < h - 1; y++) {
    for (let x = 1; x < w - 1; x++) {
      const i = y * w + x;
      const d = offsets[dir[i]];
      if (m[i] > m[i + d] && m[i] >= m[i - d]) result[i] = m[i];
    }
  }
  return result;
}
export function hysteresis(nms: number[], w: number, h: number, low: number, high: number) {
  const edges = new Uint8Array(nms.length);
  const strong = new Uint8Array(nms.length);
  const weak = new Uint8Array(nms.length);
  const queue: number[] = [];
  for (let i = 0; i < nms.length; i++) {
    if (nms[i] >= high) {
      strong[i] = edges[i] = 1;
      queue.push(i);
    } else if (nms[i] >= low) weak[i] = 1;
  }
  for (let k = 0; k < queue.length; k++) {
    for (const next of neighbors(queue[k], w, h)) {
      if (!edges[next] && nms[next] >= low) {
        edges[next] = 1;
        queue.push(next);
      }
    }
  }
  return { edges, strong, weak };
}
export function components(edges: Uint8Array, w: number, h: number) {
  const visited = new Uint8Array(edges.length);
  const groups: number[][] = [];
  for (let i = 0; i < edges.length; i++) {
    if (!edges[i] || visited[i]) continue;
    const group = [i];
    visited[i] = 1;
    for (let k = 0; k < group.length; k++) {
      for (const next of neighbors(group[k], w, h)) {
        if (edges[next] && !visited[next]) {
          visited[next] = 1;
          group.push(next);
        }
      }
    }
    groups.push(group);
  }
  return groups;
}
