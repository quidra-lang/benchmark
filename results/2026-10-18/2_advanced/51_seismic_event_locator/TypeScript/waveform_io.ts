import { readFileSync } from 'node:fs';
export interface Station { index: number; code: string; x: number; y: number; elevation: number; start: number; samples: number[] }
export interface Parameters { staWindow: number; ltaWindow: number; triggerOn: number[]; triggerOff: number[]; minDuration: number; noiseLevel: number; amplitudeWindow: number; clipLevel: number; associationWindow: number; minStations: number; velocity: number; gridX: number[]; gridY: number[]; gridZ: number[]; residualLimit: number; qualityA: number[]; qualityB: number[]; cluster: number[]; localMagnitude: number[]; durationMagnitude: number[]; mapArea: number[]; mapSize: number[]; section: number[]; timeline: number[] }
const readLines = (name: string) => readFileSync('input/' + name, 'ascii').trimEnd().split('\n');
export function readInput() {
    const stations: Station[] = readLines('stations.csv').slice(1).map((line, index) => { const [code, x, y, elevation] = line.split(','); return { index, code, x: Number(x), y: Number(y), elevation: Number(elevation), start: 0, samples: [] }; });
    const lines = readLines('waveforms.txt'); let position = 0;
    for (const s of stations) { const h = lines[position++].split(' '); s.start = Number(h[2]); const n = Number(h[3]); while (s.samples.length < n) s.samples.push(...lines[position++].split(' ').map(Number)); }
    const f = readLines('params.txt').map(line => line.split(' ').slice(1).map(Number));
    const params: Parameters = { staWindow: f[0][0], ltaWindow: f[1][0], triggerOn: f[2], triggerOff: f[3], minDuration: f[4][0], noiseLevel: f[5][0], amplitudeWindow: f[6][0], clipLevel: f[7][0], associationWindow: f[8][0], minStations: f[9][0], velocity: f[10][0], gridX: f[11], gridY: f[12], gridZ: f[13], residualLimit: f[14][0], qualityA: f[15], qualityB: f[16], cluster: f[17], localMagnitude: f[18], durationMagnitude: f[19], mapArea: f[20], mapSize: f[21], section: f[22], timeline: f[23] };
    return { stations, params };
}
