import { readFileSync } from 'node:fs';
import { neg, norm, triple, type Vec3 } from './vector3.ts';

export type Color = Vec3;
export interface Material { name: string; color: Color; kd: number; ks: number; exponent: number; kr: number; kt: number; ior: number; checker?: { color: Color; size: number } }
interface ObjectBase { number: number; label: string; material: Material }
export type BoundedObject = ObjectBase & ({ kind: 'sphere'; center: Vec3; radius: number } | { kind: 'box'; lo: Vec3; hi: Vec3 });
export type SceneObject = BoundedObject | (ObjectBase & { kind: 'plane'; point: Vec3; normal: Vec3 });
interface LightBase { number: number; intensity: number }
export type Light = LightBase & (
  { kind: 'point'; position: Vec3 } | { kind: 'spot'; position: Vec3; direction: Vec3; outer: number; inner: number } |
  { kind: 'sun'; direction: Vec3 } | { kind: 'area'; position: Vec3; u: Vec3; v: Vec3; divisions: number }
);
export interface Scene { eye: Vec3; forward: Vec3; right: Vec3; up: Vec3; halfWidth: number; halfHeight: number; background: Color; ambient: number;
  fog?: { color: Color; start: number; end: number }; materials: Map<string, Material>; lights: Light[]; objects: SceneObject[] }
export function readScene(): Scene {
  const scene: Scene = { eye: [0, 0, 0], forward: [0, 0, 0], right: [0, 0, 0], up: [0, 0, 0], halfWidth: 0, halfHeight: 0, background: [0, 0, 0], ambient: 0, materials: new Map(), lights: [], objects: [] };
  for (const line of readFileSync('input/scene.txt', 'ascii').split('\n')) {
    if (!line || line.startsWith('#')) continue;
    const [kind, ...tokens] = line.split(' '), values = tokens.map(token => /^-?[0-9]+$/.test(token) ? +token : 0);
    const material = (name: string): Material => { const result = scene.materials.get(name); if (!result) throw new Error('Unknown material'); return result; };
    if (kind === 'eye' || kind === 'forward' || kind === 'right' || kind === 'up') scene[kind] = triple(values);
    else if (kind === 'view') { scene.halfWidth = values[0]; scene.halfHeight = values[1]; }
    else if (kind === 'background') scene.background = triple(values);
    else if (kind === 'ambient') scene.ambient = values[0];
    else if (kind === 'fog') scene.fog = { color: triple(values), start: values[3], end: values[4] };
    else if (kind === 'material') scene.materials.set(tokens[0], { name: tokens[0], color: triple(values, 1), kd: values[4], ks: values[5], exponent: values[6], kr: values[7], kt: values[8], ior: values[9] });
    else if (kind === 'checker') material(tokens[0]).checker = { color: triple(values, 1), size: values[4] };
    else if (kind === 'point') scene.lights.push({ kind, number: scene.lights.length + 1, position: triple(values), intensity: values[3] });
    else if (kind === 'spot') scene.lights.push({ kind, number: scene.lights.length + 1, position: triple(values), direction: norm(triple(values, 3)), outer: values[6], inner: values[7], intensity: values[8] });
    else if (kind === 'sun') scene.lights.push({ kind, number: scene.lights.length + 1, direction: norm(neg(triple(values))), intensity: values[3] });
    else if (kind === 'area') scene.lights.push({ kind, number: scene.lights.length + 1, position: triple(values), u: triple(values, 3), v: triple(values, 6), divisions: values[9], intensity: values[10] });
    else {
      const base = { number: scene.objects.length + 1, label: tokens[0], material: material(tokens[1]) };
      if (kind === 'sphere') scene.objects.push({ ...base, kind, center: triple(values, 2), radius: values[5] });
      else if (kind === 'plane') scene.objects.push({ ...base, kind, point: triple(values, 2), normal: norm(triple(values, 5)) });
      else if (kind === 'box') scene.objects.push({ ...base, kind, lo: triple(values, 2), hi: triple(values, 5) });
    }
  }
  return scene;
}
