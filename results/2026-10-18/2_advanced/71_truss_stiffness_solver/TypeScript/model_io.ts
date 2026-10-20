import { readFileSync } from 'node:fs';

export interface Node { id: number; x: number; y: number }
export interface Section { name: string; area: number; inertia: number }
export interface Material { name: string; young: number; yield: number; density: number; expansion: number }
export interface Member { id: number; i: number; j: number; section: number; material: number; group: string }
export interface Support { node: number; fixed: [boolean, boolean]; prescribed: [number, number] }
export type Load = { kind: 'FORCE'; node: number; x: number; y: number } | { kind: 'TEMPERATURE'; member: number; change: number } | { kind: 'SELFWEIGHT' | 'SETTLEMENT' };
export interface LoadCase { name: string; loads: Load[] }
export interface Combination { name: string; terms: { case: number; factor: number }[] }
export interface Drawing { name: string; magnification: number; wc: number; hc: number }
export interface Settings {
  deck: number[]; influences: number[]; step: number; axles: { offset: number; load: number }[];
  rating: { name: string; dead: number; live: number }; compressionLimit: number; tensionLimit: number;
  deflection: { name: string; ratio: number }; vibration: { name: string; modes: number; iterations: number };
  removal: string; drawings: Drawing[]; map: { wc: number; hc: number };
}
const lines = (name: string) => readFileSync(`input/${name}`, 'ascii').slice(0, -1).split('\n');
const csv = (name: string) => lines(name).slice(1).map(line => line.split(','));
export function readModel(): { nodes: Node[]; members: Member[]; sections: Section[]; materials: Material[]; supports: Support[]; cases: LoadCase[]; combinations: Combination[]; settings: Settings } {
  const nodes = csv('nodes.csv').map(([id, x, y]) => ({ id: +id, x: +x, y: +y }));
  const sections = csv('sections.csv').map(([name, area, inertia]) => ({ name, area: +area, inertia: +inertia }));
  const materials = csv('materials.csv').map(([name, young, yieldStress, density, expansion]) => ({ name, young: +young, yield: +yieldStress, density: +density, expansion: +expansion }));
  const nodeIndex = (id: string) => nodes.findIndex(node => node.id === +id);
  const members = csv('members.csv').map(([id, i, j, section, material, group]) => ({ id: +id, i: nodeIndex(i), j: nodeIndex(j), section: sections.findIndex(item => item.name === section), material: materials.findIndex(item => item.name === material), group }));
  const memberIndex = (id: string) => members.findIndex(member => member.id === +id);
  const supports = csv('supports.csv').map(([node, fixX, fixY, dx, dy]): Support => ({ node: nodeIndex(node), fixed: [fixX === '1', fixY === '1'], prescribed: [+dx, +dy] }));
  const cases: LoadCase[] = [], combinations: Combination[] = [];
  for (const line of lines('loads.txt')) {
    const [kind, ...t] = line.split(' ');
    if (kind === 'LOADCASE') cases.push({ name: t[0], loads: [] });
    else if (kind === 'COMBINATION') { const terms: Combination['terms'] = []; for (let i = 1; i < t.length; i += 2) terms.push({ case: cases.findIndex(item => item.name === t[i]), factor: +t[i + 1] }); combinations.push({ name: t[0], terms }); }
    else if (kind === 'FORCE') cases.at(-1)!.loads.push({ kind, node: nodeIndex(t[0]), x: +t[1], y: +t[2] });
    else if (kind === 'TEMPERATURE') cases.at(-1)!.loads.push({ kind, member: memberIndex(t[0]), change: +t[1] });
    else if (kind === 'SELFWEIGHT' || kind === 'SETTLEMENT') cases.at(-1)!.loads.push({ kind });
  }
  const settings: Settings = { deck: [], influences: [], step: 0, axles: [], rating: { name: '', dead: 0, live: 0 }, compressionLimit: 0, tensionLimit: 0, deflection: { name: '', ratio: 0 }, vibration: { name: '', modes: 0, iterations: 0 }, removal: '', drawings: [], map: { wc: 0, hc: 0 } };
  for (const line of lines('params.txt')) {
    const [kind, ...t] = line.split(' ');
    if (kind === 'deck') settings.deck = t.map(nodeIndex);
    else if (kind === 'influence') settings.influences.push(memberIndex(t[0]));
    else if (kind === 'vehicle') { settings.step = +t[0]; for (let i = 1; i < t.length; i += 2) settings.axles.push({ offset: +t[i], load: +t[i + 1] }); }
    else if (kind === 'rating') settings.rating = { name: t[0], dead: +t[1], live: +t[2] };
    else if (kind === 'slenderness') { settings.compressionLimit = +t[0]; settings.tensionLimit = +t[1]; }
    else if (kind === 'deflection') settings.deflection = { name: t[0], ratio: +t[1] };
    else if (kind === 'vibration') settings.vibration = { name: t[0], modes: +t[1], iterations: +t[2] };
    else if (kind === 'removal') settings.removal = t[0];
    else if (kind === 'drawing') settings.drawings.push({ name: t[0], magnification: +t[1], wc: +t[2], hc: +t[3] });
    else if (kind === 'utilization_map') settings.map = { wc: +t[0], hc: +t[1] };
  }
  return { nodes, members, sections, materials, supports, cases, combinations, settings };
}
