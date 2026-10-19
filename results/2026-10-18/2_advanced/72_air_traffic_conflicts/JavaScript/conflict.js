"use strict";

const {position} = require("./trajectory");

function lossInterval(p, w, t1, t2, dh, dv) {
  const [px, py, pz] = p, [wx, wy, wz] = w;
  const qa = wx * wx + wy * wy;
  const qb = 2 * (px * wx + py * wy);
  const qc = px * px + py * py - dh * dh;
  let lo = t1, hi = t2;
  if (qa < 1e-12) {
    if (qc >= 0) return null;
  } else {
    const disc = qb * qb - 4 * qa * qc;
    if (disc <= 0) return null;
    const root = Math.sqrt(disc);
    lo = Math.max(lo, t1 + (-qb - root) / (2 * qa));
    hi = Math.min(hi, t1 + (-qb + root) / (2 * qa));
  }
  if (wz === 0) {
    if (Math.abs(pz) >= dv) return null;
  } else {
    const r1 = (-dv - pz) / wz, r2 = (dv - pz) / wz;
    lo = Math.max(lo, t1 + Math.min(r1, r2));
    hi = Math.min(hi, t1 + Math.max(r1, r2));
  }
  if (hi - lo <= 1e-6) return null;
  let tc = qa >= 1e-12 ? t1 + (-qb / (2 * qa)) : t1;
  tc = Math.min(Math.max(tc, lo), hi);
  const elapsed = tc - t1;
  const ex = px + wx * elapsed, ey = py + wy * elapsed;
  return {
    lo, hi, tc, distance: Math.sqrt(ex * ex + ey * ey),
    vertical: Math.abs(pz + wz * elapsed)
  };
}

function pairConflicts(aName, aTrajectory, bName, bTrajectory, dh, dv) {
  const pieces = [];
  for (const a of aTrajectory.segments) {
    for (const b of bTrajectory.segments) {
      const t1 = Math.max(a.ts, b.ts), t2 = Math.min(a.te, b.te);
      if (t1 >= t2) continue;
      const pa = position(a, t1), pb = position(b, t1);
      const relative = pa.map((v, i) => v - pb[i]);
      const velocity = a.velocity.map((v, i) => v - b.velocity[i]);
      const loss = lossInterval(relative, velocity, t1, t2, dh, dv);
      if (loss !== null) pieces.push({...loss, aSegment: a, bSegment: b});
    }
  }
  pieces.sort((a, b) => a.lo - b.lo);
  const conflicts = [];
  for (const piece of pieces) {
    const last = conflicts[conflicts.length - 1];
    if (!last || piece.lo - last.end > 1e-6) {
      conflicts.push({
        pair: [aName, bName], name: aName + "-" + bName,
        start: piece.lo, end: piece.hi, pieces: [piece], closest: piece
      });
    } else {
      last.pieces.push(piece);
      last.end = piece.hi;
      if (piece.distance < last.closest.distance - 1e-9) last.closest = piece;
    }
  }
  return conflicts;
}

function allConflicts(trajectories, dh, dv) {
  const names = Object.keys(trajectories).sort();
  const result = [];
  for (let i = 0; i < names.length; i++) {
    for (let j = i + 1; j < names.length; j++) {
      result.push(...pairConflicts(
        names[i], trajectories[names[i]],
        names[j], trajectories[names[j]], dh, dv
      ));
    }
  }
  result.sort((a, b) =>
    a.start - b.start || a.pair[0].localeCompare(b.pair[0]) ||
    a.pair[1].localeCompare(b.pair[1])
  );
  return result;
}

module.exports = {lossInterval, pairConflicts, allConflicts};
