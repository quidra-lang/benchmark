import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
export interface Image { width: number; height: number; pixels: number[] }
export type CostKind = 'sad' | 'ssd' | 'census';
export interface Parameters {
  min: number; max: number; windows: Record<CostKind, number[]>; textureWindow: number; textureThreshold: number; uniqueness: number; lr: number;
  wta: CostKind; sgm: CostKind; sgmWindow: number; paths: number; p1: number; p2: number; gamma: number; speckleSize: number; speckleRange: number;
  fusionVotes: number; objectRange: number; objectSize: number; focal: number; baseline: number; samples: number[][];
}
const lines = (name: string) => readFileSync('input/' + name, 'ascii').trimEnd().split('\n');
export function readImage(name: string): Image { const rows = lines(name), [width, height] = rows[1].split(' ').map(Number); return { width, height, pixels: rows.slice(3).flatMap(row => row.split(' ').map(Number)) }; }
export function readParameters(): Parameters {
  const rows = lines('params.txt').map(row => row.split(' ')), map = new Map(rows.map((r): [string, string[]] => [r[0], r.slice(1)]));
  const vals = (key: string) => map.get(key) ?? [], n = (key: string) => Number(vals(key)[0]);
  const kind = (key: string): CostKind => vals(key)[0] === 'sad' ? 'sad' : vals(key)[0] === 'ssd' ? 'ssd' : 'census';
  return { min: n('disparity_min'), max: n('disparity_max'), windows: { sad: vals('sad_windows').map(Number), ssd: vals('ssd_windows').map(Number), census: vals('census_windows').map(Number) },
    textureWindow: n('texture_window'), textureThreshold: n('texture_threshold'), uniqueness: n('uniqueness'), lr: n('lr_max_diff'), wta: kind('wta_cost'), sgm: kind('sgm_cost'),
    sgmWindow: n('sgm_window'), paths: n('sgm_paths'), p1: n('p1'), p2: n('p2'), gamma: n('p2_gamma'), speckleSize: n('speckle_size'), speckleRange: n('speckle_range'),
    fusionVotes: n('fusion_min_votes'), objectRange: n('object_range'), objectSize: n('object_min_size'), focal: n('focal_length'), baseline: n('baseline'), samples: rows.filter(r => r[0] === 'sample').map(r => r.slice(1).map(Number)) };
}
export function writeLines(name: string, rows: string[]): void { mkdirSync('output', { recursive: true }); writeFileSync('output/' + name, rows.join('\n') + '\n', 'ascii'); }
export function writeImage(name: string, image: Image): void { writeLines(name, ['P2', `${image.width} ${image.height}`, '255', ...Array.from({ length: image.height }, (_, y) => image.pixels.slice(y * image.width, (y + 1) * image.width).join(' '))]); }
