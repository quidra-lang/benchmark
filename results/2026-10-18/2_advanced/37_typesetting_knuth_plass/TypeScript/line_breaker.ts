import type { Parameters, LineProblem, LineMetrics } from './main.ts';

function lineClass(line: LineMetrics): number {
  if (line.last) return 1;
  return line.slack <= 1 ? 0 : line.slack <= 3 ? 1 : line.slack <= 6 ? 2 : 3;
}
function lineCost(
  problem: LineProblem,
  line: LineMetrics,
  previousClass: number,
  parameters: Parameters,
): number {
  let cost = parameters.line_penalty;
  cost += line.slack < 0 ? parameters.overfull_penalty : line.last ? 0 : line.slack * line.slack;
  if (problem.points[line.b].mid) {
    cost += parameters.hyphen_penalty;
    if (problem.points[line.a].mid) cost += parameters.double_hyphen_demerit;
  }
  if (line.last && problem.points[line.a].mid) cost += parameters.final_hyphen_demerit;
  if (Math.abs(lineClass(line) - previousClass) >= 2) cost += parameters.fitness_demerit;
  return cost;
}
export function breakingCost(
  problem: LineProblem,
  breaks: number[],
  parameters: Parameters,
): number {
  let total = 0;
  let previous = 0;
  let previousClass = 1;
  for (const end of breaks) {
    const line = problem.measure(previous, end);
    total += lineCost(problem, line, previousClass, parameters);
    previousClass = lineClass(line);
    previous = end;
  }
  return total;
}
interface State {
  cost: number;
  a: number;
  previousClass: number;
}
export function optimal(problem: LineProblem, parameters: Parameters) {
  const end = problem.points.length - 1;
  const table = Array.from({ length: end + 1 }, () => Array<State | null>(4).fill(null));
  table[0][1] = { cost: 0, a: 0, previousClass: 1 };
  for (let b = 1; b <= end; b++) {
    const consider = (a: number, line: LineMetrics) => {
      if (line.slack < 0 && b !== a + 1) return;
      const currentClass = lineClass(line);
      for (let previousClass = 0; previousClass < 4; previousClass++) {
        const earlier = table[a][previousClass];
        if (!earlier) continue;
        const cost = earlier.cost + lineCost(problem, line, previousClass, parameters);
        const best = table[b][currentClass];
        if (
          !best ||
          cost < best.cost ||
          (cost === best.cost &&
            (a < best.a || (a === best.a && previousClass < best.previousClass)))
        ) {
          table[b][currentClass] = { cost, a, previousClass };
        }
      }
    };
    consider(0, problem.measure(0, b));
    for (let a = b - 1; a >= 1; a--) {
      const line = problem.measure(a, b);
      // Positive starts share a capacity, and earlier starts only increase length.
      if (line.slack < 0 && b !== a + 1) break;
      consider(a, line);
    }
  }
  const breaks: number[] = [];
  let position = end;
  let currentClass = 1;
  while (position > 0) {
    breaks.push(position);
    const previous = table[position][currentClass]!;
    position = previous.a;
    currentClass = previous.previousClass;
  }
  return { breaks: breaks.reverse(), cost: table[end][1]!.cost };
}
export function greedy(problem: LineProblem, parameters: Parameters) {
  const end = problem.points.length - 1;
  const breaks: number[] = [];
  let start = 0;
  while (start < end) {
    let selected = start + 1;
    if (problem.measure(start, selected).slack >= 0) {
      for (let b = selected + 1; b <= end; b++) {
        if (problem.measure(start, b).slack < 0) break;
        selected = b;
      }
    }
    breaks.push(selected);
    start = selected;
  }
  return { breaks, cost: breakingCost(problem, breaks, parameters) };
}
