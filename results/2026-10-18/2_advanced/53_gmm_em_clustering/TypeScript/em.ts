import type { Position, Component, CovarianceType } from './dataset.ts';
import { logWeighted } from './gaussian.ts';
export function adjust(initial: Component[], type: CovarianceType): Component[] {
  const components = initial.map(c => ({ ...c }));
  if (type === 'TIED') {
    let a = 0, b = 0, c = 0; for (const s of components) { a += s.w * s.a; b += s.w * s.b; c += s.w * s.c; }
    for (const s of components) Object.assign(s, { a, b, c });
  } else if (type === 'DIAG') for (const s of components) s.b = 0;
  else if (type === 'SPHERICAL') for (const s of components) { const v = (s.a + s.c) / 2; s.a = s.c = v; s.b = 0; }
  return components;
}
export function expectation(points: Position[], components: Component[]) {
  const responsibilities: number[][] = [], logDensities: number[] = []; let loglik = 0;
  for (const point of points) {
    const logs = components.map(c => logWeighted(point, c)), maximum = Math.max(...logs), exponents = logs.map(v => Math.exp(v - maximum)); let total = 0;
    for (const e of exponents) total += e;
    responsibilities.push(exponents.map(e => e / total)); const lp = maximum + Math.log(total); logDensities.push(lp); loglik += lp;
  }
  return { responsibilities, logDensities, loglik };
}
export function maximization(points: Position[], r: number[][], type: CovarianceType, eps: number): Component[] {
  const components: Component[] = [], moments: { a: number; b: number; c: number }[] = [];
  for (let k = 0; k < r[0].length; k++) {
    let count = 0, sx = 0, sy = 0;
    points.forEach((p, i) => { count += r[i][k]; sx += r[i][k] * p.x; sy += r[i][k] * p.y; });
    const mx = sx / count, my = sy / count; let a = 0, b = 0, c = 0;
    points.forEach((p, i) => { const dx = p.x - mx, dy = p.y - my; a += r[i][k] * dx * dx; b += r[i][k] * dx * dy; c += r[i][k] * dy * dy; });
    moments.push({ a, b, c });
    const s = { w: count / points.length, mx, my, a: a / count + eps, b: type === 'FULL' ? b / count : 0, c: c / count + eps };
    if (type === 'SPHERICAL') s.a = s.c = (a / count + c / count) / 2 + eps;
    components.push(s);
  }
  if (type === 'TIED') {
    let a = 0, b = 0, c = 0; for (const m of moments) { a += m.a; b += m.b; c += m.c; }
    for (const s of components) Object.assign(s, { a: a / points.length + eps, b: b / points.length, c: c / points.length + eps });
  }
  return components;
}
export function fit(points: Position[], initial: Component[], type: CovarianceType, iterations: number, eps: number) {
  let components = adjust(initial, type), step = expectation(points, components); const trace = [step.loglik];
  for (let t = 1; t <= iterations; t++) { components = maximization(points, step.responsibilities, type, eps); step = expectation(points, components); trace.push(step.loglik); }
  return { components, trace, ...step };
}
