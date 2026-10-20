import type { Parameters } from './data_io.ts';
export function goldenSearch(objective: (x: number) => number, lower: number, upper: number, iterations: number) {
  const phi = 0.6180339887498949;
  let a = lower, b = upper, c = b - phi * (b - a), d = a + phi * (b - a), fc = objective(c), fd = objective(d);
  const records = [{ a, b, c, d, fc, fd }];
  for (let i = 0; i < iterations; i++) {
    if (fc < fd) { b = d; d = c; fd = fc; c = b - phi * (b - a); fc = objective(c); }
    else { a = c; c = d; fc = fd; d = a + phi * (b - a); fd = objective(d); }
    records.push({ a, b, c, d, fc, fd });
  }
  return fc < fd ? { point: c, value: fc, records } : { point: d, value: fd, records };
}
type Point = [number, number];
interface Candidate { point: Point; value: number }
export interface Vertex extends Candidate { number: number }
type Operation = 'expand' | 'reflect' | 'contract_out' | 'contract_in' | 'shrink';
const vertexOrder = (a: Vertex, b: Vertex) => a.value - b.value || a.number - b.number;
export function nelderMead(objective: (beta: number, gamma: number) => number, beta: number, gamma: number, p: Parameters) {
  let nextNumber = 0;
  const evaluate = (point: Point): Candidate => ({ point, value: objective(point[0], point[1]) });
  const number = (candidate: Candidate): Vertex => ({ ...candidate, number: nextNumber++ });
  const move = (u: Point, v: Point, t: number): Point => [u[0] + t * (v[0] - u[0]), u[1] + t * (v[1] - u[1])];
  const initial = [number(evaluate([beta, gamma])), number(evaluate([beta + p.deltaBeta, gamma])), number(evaluate([beta, gamma + p.deltaGamma]))];
  let vertices = initial.slice();
  const records: { iteration: number; operation: Operation; best: Vertex }[] = [];
  for (let iteration = 1; iteration <= p.iterations; iteration++) {
    vertices.sort(vertexOrder);
    const [first, second, third] = vertices, center: Point = [(first.point[0] + second.point[0]) / 2, (first.point[1] + second.point[1]) / 2];
    const reflected = evaluate([center[0] + p.alpha * (center[0] - third.point[0]), center[1] + p.alpha * (center[1] - third.point[1])]);
    let accepted: Candidate | null = null, operation: Operation = 'shrink';
    if (reflected.value < first.value) {
      const expanded = evaluate(move(center, reflected.point, p.chi));
      accepted = expanded.value < reflected.value ? expanded : reflected; operation = expanded.value < reflected.value ? 'expand' : 'reflect';
    } else if (reflected.value < second.value) { accepted = reflected; operation = 'reflect'; }
    else if (reflected.value < third.value) {
      const contracted = evaluate(move(center, reflected.point, p.psi));
      if (contracted.value <= reflected.value) { accepted = contracted; operation = 'contract_out'; }
    } else {
      const contracted = evaluate(move(center, third.point, p.psi));
      if (contracted.value < third.value) { accepted = contracted; operation = 'contract_in'; }
    }
    if (accepted !== null) vertices = [first, second, number(accepted)];
    else vertices = [first, number(evaluate(move(first.point, second.point, p.omega))), number(evaluate(move(first.point, third.point, p.omega)))];
    vertices.sort(vertexOrder); records.push({ iteration, operation, best: vertices[0] });
  }
  return { initial, records, vertices };
}
