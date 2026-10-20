import { floorDiv, type Point, type Rectangle, type Segment, type FillRule, type Layer, type Pixel } from './canvas.ts';
import { contains } from './clipping.ts';

export function fillPolygon(sequences: Point[][], rule: FillRule, clip: Rectangle, width: number): Set<number> {
  const edges: Segment[] = [], pixels = new Set<number>();
  for (const points of sequences) for (let i = 0; i < points.length; i++) {
    const a = points[i], b = points[(i+1)%points.length];
    if (a[1] !== b[1]) edges.push([a,b]);
  }
  for (let y = clip[1]; y <= clip[3]; y++) {
    const events = new Map<number, [number,number]>();
    let count = 0, winding = 0;
    for (const [[xa,ya],[xb,yb]] of edges) {
      if (y < Math.min(ya,yb) || y >= Math.max(ya,yb)) continue;
      let d = yb - ya, n = 2 * xa * d + (2*y+1-2*ya)*(xb-xa);
      const direction = d > 0 ? 1 : -1;
      if (d < 0) { d = -d; n = -n; }
      const first = floorDiv(n-d, 2*d)+1;
      if (first <= clip[0]) { count++; winding += direction; }
      else { const event = events.get(first) ?? [0,0]; event[0]++; event[1] += direction; events.set(first,event); }
    }
    for (let x = clip[0]; x <= clip[2]; x++) {
      const event = events.get(x);
      if (event) { count += event[0]; winding += event[1]; }
      if (rule === 'evenodd' ? count % 2 !== 0 : winding !== 0) pixels.add(y*width+x);
    }
  }
  return pixels;
}
export function fillShape(points: Point[], [cx,cy]: Point, clip: Rectangle, width: number): Set<number> {
  const spans = new Map<number,number>(), pixels = new Set<number>();
  for (const [x,y] of points) spans.set(y, Math.max(spans.get(y) ?? 0, Math.abs(x)));
  for (const [dy,extent] of spans) {
    const y = cy + dy;
    if (y < clip[1] || y > clip[3]) continue;
    for (let x = Math.max(cx-extent,clip[0]); x <= Math.min(cx+extent,clip[2]); x++) pixels.add(y*width+x);
  }
  return pixels;
}
export function floodFill(layer: Layer, seed: Point, clip: Rectangle, width: number): Set<number> {
  const first = seed[1]*width+seed[0], value = layer.pixels[first];
  const pixels = new Set([first]), queue = [seed];
  const equal = (p: Pixel | null) => value === null ? p === null : p !== null && value.color.every((v,i) => v === p.color[i]);
  for (let head = 0; head < queue.length; head++) {
    const [x,y] = queue[head], neighbors: Point[] = [[x+1,y],[x-1,y],[x,y+1],[x,y-1]];
    for (const p of neighbors) {
      if (!contains(clip,p)) continue;
      const i = p[1]*width+p[0];
      if (!pixels.has(i) && equal(layer.pixels[i])) { pixels.add(i); queue.push(p); }
    }
  }
  return pixels;
}
