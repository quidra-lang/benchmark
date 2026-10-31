import { position } from './trajectory.ts';
import type { Vector, Segment, Trajectory } from './trajectory.ts';
export interface Loss {
  lo: number;
  hi: number;
  tc: number;
  distance: number;
  vertical: number;
}
export interface Piece extends Loss {
  aSegment: Segment;
  bSegment: Segment;
}
export interface Conflict {
  pair: [string, string];
  name: string;
  start: number;
  end: number;
  pieces: Piece[];
  closest: Piece;
}
export const asciiCompare = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);
export const conflictOrder = (a: Conflict, b: Conflict) =>
  a.start - b.start || asciiCompare(a.pair[0], b.pair[0]) || asciiCompare(a.pair[1], b.pair[1]);
export const subtract = (a: Vector, b: Vector): Vector => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
export function lossInterval(
  p: Vector,
  w: Vector,
  t1: number,
  t2: number,
  dh: number,
  dv: number,
): Loss | null {
  const [px, py, pz] = p;
  const [wx, wy, wz] = w;
  const qa = wx * wx + wy * wy;
  const qb = 2 * (px * wx + py * wy);
  const qc = px * px + py * py - dh * dh;
  let lo = t1;
  let hi = t2;
  if (qa < 1e-12) {
    if (qc >= 0) return null;
  } else {
    const D = qb * qb - 4 * qa * qc;
    if (D <= 0) return null;
    const s = Math.sqrt(D);
    lo = Math.max(lo, t1 + (-qb - s) / (2 * qa));
    hi = Math.min(hi, t1 + (-qb + s) / (2 * qa));
  }
  if (wz === 0) {
    if (Math.abs(pz) >= dv) return null;
  } else {
    const r1 = (-dv - pz) / wz;
    const r2 = (dv - pz) / wz;
    lo = Math.max(lo, t1 + Math.min(r1, r2));
    hi = Math.min(hi, t1 + Math.max(r1, r2));
  }
  if (hi - lo <= 1e-6) return null;
  let tc = qa >= 1e-12 ? t1 + -qb / (2 * qa) : t1;
  tc = Math.min(Math.max(tc, lo), hi);
  const tau = tc - t1;
  const ex = px + wx * tau;
  const ey = py + wy * tau;
  return { lo, hi, tc, distance: Math.sqrt(ex * ex + ey * ey), vertical: Math.abs(pz + wz * tau) };
}
export function pairConflicts(
  aName: string,
  aPath: Trajectory,
  bName: string,
  bPath: Trajectory,
  dh: number,
  dv: number,
) {
  const pieces: Piece[] = [];
  for (const a of aPath.segments) {
    for (const b of bPath.segments) {
      const t1 = Math.max(a.ts, b.ts);
      const t2 = Math.min(a.te, b.te);
      if (t1 >= t2) continue;
      const loss = lossInterval(
        subtract(position(a, t1), position(b, t1)),
        subtract(a.velocity, b.velocity),
        t1,
        t2,
        dh,
        dv,
      );
      if (loss) pieces.push({ ...loss, aSegment: a, bSegment: b });
    }
  }
  pieces.sort((a, b) => a.lo - b.lo);
  const conflicts: Conflict[] = [];
  for (const piece of pieces) {
    const last = conflicts[conflicts.length - 1];
    if (!last || piece.lo - last.end > 1e-6) {
      conflicts.push({
        pair: [aName, bName],
        name: `${aName}-${bName}`,
        start: piece.lo,
        end: piece.hi,
        pieces: [piece],
        closest: piece,
      });
    } else {
      last.pieces.push(piece);
      last.end = piece.hi;
      if (piece.distance < last.closest.distance - 1e-9) last.closest = piece;
    }
  }
  return conflicts;
}
export function allConflicts(paths: Record<string, Trajectory>, dh: number, dv: number) {
  const names = Object.keys(paths).sort();
  const result: Conflict[] = [];
  for (let i = 0; i < names.length; i++) {
    for (let j = i + 1; j < names.length; j++) {
      result.push(...pairConflicts(names[i], paths[names[i]], names[j], paths[names[j]], dh, dv));
    }
  }
  return result.sort(conflictOrder);
}
