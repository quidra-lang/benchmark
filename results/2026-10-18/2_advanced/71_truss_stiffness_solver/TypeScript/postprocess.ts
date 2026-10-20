import type { Properties } from './assembly.ts';
import type { Combination } from './model_io.ts';

export interface Result {
  name: string;
  displacement: number[];
  axial: number[];
  reaction: number[];
  external: number[];
}
export function axialForces(
  properties: Properties[],
  displacement: number[],
  temperature: number[],
  removed?: number,
): number[] {
  return properties.map((member, m) => {
    if (m === removed) return 0;
    const [ix, iy, jx, jy] = member.dofs;
    const extension =
      (displacement[jx] - displacement[ix]) * member.c +
      (displacement[jy] - displacement[iy]) * member.s;
    return member.k * extension - temperature[m];
  });
}
export function reactions(
  matrix: number[][],
  displacement: number[],
  force: number[],
  restrained: number[],
): number[] {
  const reaction = Array<number>(force.length).fill(0);
  for (const r of restrained) {
    let value = 0;
    for (let d = 0; d < force.length; d++) value += matrix[r][d] * displacement[d];
    reaction[r] = value - force[r];
  }
  return reaction;
}
export function superpose(combination: Combination, cases: Result[]): Result {
  const combine = (field: 'displacement' | 'axial' | 'reaction' | 'external') =>
    cases[0][field].map((_, d) => {
      let value = 0;
      for (const term of combination.terms) value += term.factor * cases[term.case][field][d];
      return value;
    });
  return {
    name: combination.name,
    displacement: combine('displacement'),
    axial: combine('axial'),
    reaction: combine('reaction'),
    external: combine('external'),
  };
}
export function equilibriumResidual(result: Result, properties: Properties[]): number {
  const residual = result.external.map((value, d) => value + result.reaction[d]);
  properties.forEach((member, m) => {
    const force = result.axial[m];
    const direction = [member.c, member.s, -member.c, -member.s];
    for (let i = 0; i < 4; i++) residual[member.dofs[i]] += force * direction[i];
  });
  return Math.max(...residual.map(Math.abs));
}
