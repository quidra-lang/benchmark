import type { LoadCase, Material, Member, Node, Section } from './model_io.ts';

export interface Geometry { length: number; c: number; s: number; dofs: [number, number, number, number]; t: [number, number, number, number] }
export interface Properties extends Geometry { area: number; inertia: number; k: number; material: Material }
export const zeros = (size: number) => Array<number>(size).fill(0);
export function geometry(nodes: Node[], members: Member[], numbering: number[]): Geometry[] {
  return members.map(member => {
    const dx = nodes[member.j].x - nodes[member.i].x, dy = nodes[member.j].y - nodes[member.i].y, length = Math.sqrt(dx * dx + dy * dy), c = dx / length, s = dy / length;
    return { length, c, s, dofs: [2 * numbering[member.i], 2 * numbering[member.i] + 1, 2 * numbering[member.j], 2 * numbering[member.j] + 1], t: [-c, -s, c, s] };
  });
}
export function properties(geometry: Geometry[], members: Member[], sections: Section[], materials: Material[], selection: number[]): Properties[] {
  return geometry.map((shape, m) => { const section = sections[selection[m]], material = materials[members[m].material]; return { ...shape, area: section.area, inertia: section.inertia, k: material.young * section.area / shape.length, material }; });
}
export function stiffness(properties: Properties[], nd: number, removed?: number): number[][] {
  const matrix = Array.from({ length: nd }, () => zeros(nd));
  properties.forEach((member, index) => {
    if (index === removed) return;
    const { k, c, s, dofs } = member, xx = k * (c * c), xy = k * (c * s), yy = k * (s * s);
    const local = [[xx, xy, -xx, -xy], [xy, yy, -xy, -yy], [-xx, -xy, xx, xy], [-xy, -yy, xy, yy]];
    for (let i = 0; i < 4; i++) for (let j = 0; j < 4; j++) matrix[dofs[i]][dofs[j]] += local[i][j];
  });
  return matrix;
}
export const memberWeight = (member: Properties) => member.material.density * 9.81 * member.area * member.length / 1000000000;
export function loadVectors(loadCase: LoadCase, properties: Properties[], nd: number, numbering: number[], removed?: number): { external: number[]; force: number[]; temperature: number[]; settlement: boolean } {
  const external = zeros(nd), thermal = zeros(nd), temperature = zeros(properties.length); let settlement = false;
  for (const load of loadCase.loads) {
    if (load.kind === 'FORCE') { external[2 * numbering[load.node]] += load.x * 1000; external[2 * numbering[load.node] + 1] += load.y * 1000; }
    else if (load.kind === 'TEMPERATURE' && load.member !== removed) {
      const member = properties[load.member], force = member.material.young * member.area * member.material.expansion * load.change; temperature[load.member] = force;
      for (let i = 0; i < 4; i++) thermal[member.dofs[i]] += force * member.t[i];
    } else if (load.kind === 'SELFWEIGHT') properties.forEach((member, m) => { if (m !== removed) { const weight = memberWeight(member); external[member.dofs[1]] -= weight / 2; external[member.dofs[3]] -= weight / 2; } });
    else if (load.kind === 'SETTLEMENT') settlement = true;
  }
  return { external, force: external.map((value, d) => value + thermal[d]), temperature, settlement };
}
