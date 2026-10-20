import type { Group, Parameters } from './data_io.ts';
export interface ModelData { N: number; fatality: number; params: Parameters; groups: Group[] }
export interface CompartmentModel { initial: number[]; inflows: number[]; rate(state: number[], multiplier: number): number[] }
export function seird(data: ModelData, beta: number, gamma: number, sigma = data.params.sigma): CompartmentModel {
  const { N, fatality: f, params: p } = data;
  return { initial: [N - p.exposed - p.infectious, p.exposed, p.infectious, 0, 0, 0], inflows: [5],
    rate(state, multiplier) {
      const [S, E, I] = state, flow = beta * multiplier * S * I / N;
      return [-flow, flow - sigma * E, sigma * E - gamma * I, (1 - f) * gamma * I, f * gamma * I, sigma * E];
    } };
}
export function sir(data: ModelData, beta: number, gamma: number): CompartmentModel {
  const { N, params: p } = data;
  return { initial: [N - p.exposed - p.infectious, p.exposed + p.infectious, 0, 0], inflows: [3],
    rate(state, multiplier) { const [S, I] = state, flow = beta * multiplier * S * I / N; return [-flow, flow - gamma * I, gamma * I, flow]; } };
}
export function ageSeird(data: ModelData, beta: number, gamma: number, matrix: number[][]): CompartmentModel {
  const { groups, N, params: p } = data, initial: number[] = [], inflows: number[] = [];
  groups.forEach((g, i) => {
    const exposed = p.exposed * g.population / N, infectious = p.infectious * g.population / N;
    initial.push(g.population - exposed - infectious, exposed, infectious, 0, 0, 0); inflows.push(6 * i + 5);
  });
  return { initial, inflows, rate(state, multiplier) {
    const rates: number[] = [];
    for (let g = 0; g < groups.length; g++) {
      let contacts = 0;
      for (let h = 0; h < groups.length; h++) contacts += matrix[g][h] * state[6 * h + 2] / groups[h].population;
      const lambda = beta * multiplier * contacts, flow = lambda * state[6 * g], E = state[6 * g + 1], I = state[6 * g + 2], f = groups[g].fatality;
      rates.push(-flow, flow - p.sigma * E, p.sigma * E - gamma * I, (1 - f) * gamma * I, f * gamma * I, p.sigma * E);
    }
    return rates;
  } };
}
export function generation(sigma: number, gamma: number): CompartmentModel {
  return { initial: [1, 0, 0], inflows: [2], rate(state) { const [E, I] = state; return [-sigma * E, sigma * E - gamma * I, gamma * I]; } };
}
