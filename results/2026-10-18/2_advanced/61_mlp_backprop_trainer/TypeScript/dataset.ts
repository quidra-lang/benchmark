import { readFileSync } from 'node:fs';
export interface Image { id: string; label: number; pixels: string; vector: number[] }
export type Activation = 'TANH' | 'SIGMOID' | 'RELU' | 'SOFTMAX';
export interface LayerDefinition { units: number; activation: Activation }
export interface Definition { name: string; layers: LayerDefinition[] }
interface RunSettings { name: string; network: string; eta: number; decay: number; order: number }
export type Run = RunSettings & ({ optimizer: 'SGD' } | { optimizer: 'MOMENTUM'; mu: number } | { optimizer: 'ADAM'; beta1: number; beta2: number; epsilon: number });
export interface Settings { seed: number; batchSize: number; maxEpochs: number; patience: number; step: number; gamma: number; stride: number; bins: number; prune: number[]; noise: number[]; runs: Run[] }
const lines = (file: string) => readFileSync(`input/${file}`, 'ascii').slice(0, -1).split('\n');
const images = (file: string): Image[] => lines(file).slice(1).map(line => { const [id, label, pixels] = line.split(','); return { id, label: Number(label), pixels, vector: Array.from(pixels, Number) }; });
export function readInputs() {
    const source = lines('network.txt'), [, width, height] = source[0].split(' ').map(Number), networks: Definition[] = [];
    for (const line of source.slice(2)) { if (!line) continue; const [kind, first, second] = line.split(' '); if (kind === 'NETWORK') networks.push({ name: first, layers: [] }); else { const activation = second === 'TANH' ? second : second === 'RELU' ? second : second === 'SOFTMAX' ? second : 'SIGMOID'; networks[networks.length - 1].layers.push({ units: Number(first), activation }); } }
    const weights = new Map<string, number[]>(); let current: number[] = [];
    for (const line of lines('weights.txt')) { if (!line) continue; const [kind, ...values] = line.split(' '); if (kind === 'NETWORK') { current = []; weights.set(values[0], current); } else if (kind === 'W' || kind === 'B') for (const value of values) current.push(Number(value)); }
    const rows = lines('params.txt').map(line => line.split(' ').slice(1)), n = rows.map(row => row.map(Number));
    const runs = rows.slice(9).map((values, order): Run => { const [name, network, optimizer, eta, decay, ...extra] = values, base = { name, network, eta: Number(eta), decay: Number(decay), order }; if (optimizer === 'SGD') return { ...base, optimizer }; if (optimizer === 'MOMENTUM') return { ...base, optimizer, mu: Number(extra[0]) }; return { ...base, optimizer: 'ADAM', beta1: Number(extra[0]), beta2: Number(extra[1]), epsilon: Number(extra[2]) }; });
    const settings: Settings = { seed: n[0][0], batchSize: n[1][0], maxEpochs: n[2][0], patience: n[3][0], step: n[4][0], gamma: n[4][1], stride: n[5][0], bins: n[6][0], prune: n[7], noise: n[8], runs };
    return { width, height, networks, weights, settings, train: images('train.csv'), test: images('test.csv') };
}
export class Minstd {
    constructor(private state: number) {}
    next() { this.state = (48271 * this.state) % 2147483647; return this.state; }
    shuffle<T>(values: T[]) { for (let i = values.length - 1; i > 0; i--) { const j = this.next() % (i + 1); [values[i], values[j]] = [values[j], values[i]]; } return values; }
}
