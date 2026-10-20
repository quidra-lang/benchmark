import { readFileSync } from 'node:fs';

export interface Attribute {
    name: string;
    kind: 'INT' | 'CAT';
    values: string[];
}
export interface Row { id: string; values: (number | null)[]; label: number }
export interface Settings {
    maxDepth: number;
    minSamplesSplit: number;
    minSamplesLeaf: number;
    maxSurrogates: number;
    folds: number;
    curve: number[];
    bagTrees: number;
    bagSeed: number;
    permutationRepeats: number;
    permutationSeed: number;
}
export interface Dataset {
    attributes: Attribute[];
    target: string;
    classes: string[];
    settings: Settings;
    train: Row[];
    validation: Row[];
    test: Row[];
}

function lines(path: string): string[] {
    return readFileSync(path, 'ascii').slice(0, -1).split('\n');
}

export function readDataset(): Dataset {
    const schema = lines('input/schema.txt').map(line => line.split(' '));
    const attributes: Attribute[] = schema.slice(0, -1).map(fields => ({
        name: fields[1], kind: fields[2] === 'INT' ? 'INT' : 'CAT', values: fields.slice(3),
    }));
    const last = schema[schema.length - 1];
    const classes = last.slice(2);
    function readRows(path: string): Row[] {
        return lines(path).slice(1).map(line => {
            const fields = line.split(',');
            const values = attributes.map((attribute, index) => {
                const text = fields[index + 1];
                return text === '?' ? null : attribute.kind === 'INT'
                    ? Number(text) : attribute.values.indexOf(text);
            });
            return { id: fields[0], values, label: classes.indexOf(fields[fields.length - 1]) };
        });
    }
    const params = lines('input/params.txt').map(line => line.split(' ').slice(1).map(Number));
    const settings: Settings = {
        maxDepth: params[0][0], minSamplesSplit: params[1][0], minSamplesLeaf: params[2][0],
        maxSurrogates: params[3][0], folds: params[4][0], curve: params[5],
        bagTrees: params[6][0], bagSeed: params[7][0],
        permutationRepeats: params[8][0], permutationSeed: params[9][0],
    };
    return { attributes, classes, target: last[1], settings,
        train: readRows('input/train.csv'), validation: readRows('input/validation.csv'),
        test: readRows('input/test.csv') };
}
