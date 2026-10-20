import { readFileSync } from 'node:fs';

export interface Table { names: string[]; ids: string[]; base: number[][]; labels: number[] }
export interface Settings {
    positive: number; degree: number; threshold: number; lambdas: number[];
    gd: [number, number]; sgd: [number, number, number, number]; softmax: [number, number, number];
    bootstrap: [number, number]; permutation: [number, number]; map: [number, number]; cost: [number, number];
}
export interface Feature { tuple: number[]; degree: number; name: string }
export interface Statistics { means: number[]; deviations: number[] }

function lines(path: string): string[] { return readFileSync(path, 'ascii').trimEnd().split('\n'); }
function readTable(path: string): Table {
    const records = lines(path).map(line => line.split(',')), rows = records.slice(1);
    return { names: records[0].slice(1, -1), ids: rows.map(row => row[0]),
        base: rows.map(row => row.slice(1, -1).map(Number)), labels: rows.map(row => Number(row[row.length - 1])) };
}
export function readInputs() {
    const train = readTable('input/train.csv'), test = readTable('input/test.csv');
    const parameters = new Map(lines('input/params.txt').map((line): [string, number[]] => {
        const [name, ...values] = line.split(' '); return [name, values.map(Number)];
    }));
    const get = (name: string) => parameters.get(name)!;
    const pair = (name: string): [number, number] => { const [a, b] = get(name); return [a, b]; };
    const [sgdRate, batch, epochs, seed] = get('SGD'), [softRate, iterations, lambda] = get('SOFTMAX');
    const settings: Settings = { positive: get('POSITIVE')[0], degree: get('DEGREE')[0], threshold: get('THRESHOLD')[0],
        lambdas: get('LAMBDAS'), gd: pair('GD'), sgd: [sgdRate, batch, epochs, seed], softmax: [softRate, iterations, lambda],
        bootstrap: pair('BOOTSTRAP'), permutation: pair('PERMUTATION'), map: pair('MAP'), cost: pair('COST') };
    return { names: train.names, train, test, settings };
}
export function expandedFeatures(names: string[], maximumDegree: number): Feature[] {
    const features: Feature[] = [];
    function visit(tuple: number[], start: number, remaining: number): void {
        if (remaining === 0) {
            features.push({ tuple: tuple.slice(), degree: tuple.length, name: tuple.map(i => names[i]).join('*') }); return;
        }
        for (let index = start; index < names.length; index++) {
            tuple.push(index); visit(tuple, index, remaining - 1); tuple.pop();
        }
    }
    for (let degree = 1; degree <= maximumDegree; degree++) visit([], 0, degree);
    return features;
}
export function expand(base: number[], features: Feature[]): number[] {
    return features.map(feature => {
        let value = base[feature.tuple[0]];
        for (let i = 1; i < feature.tuple.length; i++) value *= base[feature.tuple[i]];
        return value;
    });
}
export function statistics(values: number[][], width = values[0].length): Statistics {
    const means: number[] = [], deviations: number[] = [];
    for (let j = 0; j < width; j++) {
        let total = 0;
        for (const row of values) total += row[j];
        const mean = total / values.length;
        let squared = 0;
        for (const row of values) squared += (row[j] - mean) * (row[j] - mean);
        means[j] = mean; deviations[j] = Math.sqrt(squared / (values.length - 1));
    }
    return { means, deviations };
}
export function standardizeOne(values: number[], stats: Statistics): number[] {
    return [1, ...stats.means.map((mean, j) => (values[j] - mean) / stats.deviations[j])];
}
export function standardize(values: number[][], stats: Statistics): number[][] {
    return values.map(row => standardizeOne(row, stats));
}
