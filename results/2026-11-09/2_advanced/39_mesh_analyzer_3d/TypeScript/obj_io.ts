import { readFileSync, writeFileSync } from 'node:fs';

export type Triple = [number, number, number];
export interface Polygon {
  number: number;
  line: number;
  group: string;
  vertices: number[];
  nonplanar: boolean;
}
export interface Face {
  number: number;
  vertices: Triple;
  group: string;
  polygon: Polygon | null;
  initial?: Triple;
}
export const integerWord = (text: string): boolean => /^-?[0-9]+$/.test(text);
export function readModel() {
  const lines = readFileSync('input/model.obj', 'ascii').split('\n').slice(0, -1);
  const vertices: Triple[] = [[0, 0, 0]];
  const polygons: Polygon[] = [];
  const errors: { line: number; kind: string }[] = [];
  const groups: string[] = [];
  const seen = new Set<string>();
  const ignoredKeywords = new Set(['vt', 'vn', 's', 'o', 'usemtl', 'mtllib']);
  let group = 'default';
  let ignored = 0;
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line === '' || line.startsWith('#')) continue;
    const [keyword, ...args] = line.split(' ');
    let error: string | null = null;
    if (keyword === 'v') {
      if (args.length !== 3 || !args.every(integerWord)) error = 'bad_vertex';
      else vertices.push([Number(args[0]), Number(args[1]), Number(args[2])]);
    } else if (keyword === 'f') {
      const references: number[] = [];
      if (args.length < 3) error = 'short_face';
      else {
        for (const reference of args) {
          const part = reference.split('/')[0];
          const value = Number(part);
          if (!integerWord(part) || value === 0) {
            error = 'bad_index';
            break;
          }
          const index = value > 0 ? value : vertices.length + value;
          if (index < 1 || index >= vertices.length) {
            error = 'out_of_range';
            break;
          }
          references.push(index);
        }
      }
      if (error === null) {
        polygons.push({
          number: polygons.length + 1,
          line: i + 1,
          group,
          vertices: references,
          nonplanar: false,
        });
        if (!seen.has(group)) {
          seen.add(group);
          groups.push(group);
        }
      }
    } else if (keyword === 'g') group = args.length ? args[0] : 'default';
    else if (ignoredKeywords.has(keyword)) ignored++;
    else error = 'unknown_keyword';
    if (error !== null) errors.push({ line: i + 1, kind: error });
  }
  return { vertices, polygons, errors, groups, ignored, lines: lines.length };
}
export function writeModel(vertices: Triple[], faces: Face[]): void {
  const lines = [`# vertices ${vertices.length - 1} faces ${faces.length}`];
  for (let v = 1; v < vertices.length; v++) lines.push('v ' + vertices[v].join(' '));
  let group: string | null = null;
  for (const face of faces) {
    if (face.group !== group) {
      group = face.group;
      lines.push('g ' + group);
    }
    lines.push('f ' + face.vertices.join(' '));
  }
  writeFileSync('output/repaired.obj', lines.join('\n') + '\n', 'ascii');
}
