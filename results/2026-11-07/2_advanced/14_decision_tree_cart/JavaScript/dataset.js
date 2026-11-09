'use strict';

const fs = require('node:fs');

function readLines(path) {
    return fs.readFileSync(path, 'ascii').slice(0, -1).split('\n');
}

function readDataset() {
    const schema = readLines('input/schema.txt').map(line => line.split(' '));
    const attributes = schema.slice(0, -1).map(fields => ({
        name: fields[1],
        kind: fields[2],
        values: fields.slice(3),
    }));
    const classFields = schema.at(-1);
    const target = classFields[1];
    const classes = classFields.slice(2);
    const classNumbers = new Map(classes.map((name, index) => [name, index]));
    const valueNumbers = attributes.map(attribute => new Map(
        attribute.values.map((name, index) => [name, index])
    ));

    function readRows(path) {
        return readLines(path).slice(1).map(line => {
            const fields = line.split(',');
            const values = attributes.map((attribute, index) => {
                const text = fields[index + 1];
                if (text === '?') return null;
                return attribute.kind === 'INT' ? Number(text) : valueNumbers[index].get(text);
            });
            return { id: fields[0], values, label: classNumbers.get(fields.at(-1)) };
        });
    }

    const params = new Map(readLines('input/params.txt').map(line => {
        const [name, ...values] = line.split(' ');
        return [name, values.map(Number)];
    }));
    const settings = {
        maxDepth: params.get('MAX_DEPTH')[0],
        minSamplesSplit: params.get('MIN_SAMPLES_SPLIT')[0],
        minSamplesLeaf: params.get('MIN_SAMPLES_LEAF')[0],
        maxSurrogates: params.get('MAX_SURROGATES')[0],
        folds: params.get('FOLDS')[0],
        curve: params.get('CURVE'),
        bagTrees: params.get('BAG_TREES')[0],
        bagSeed: params.get('BAG_SEED')[0],
        permutationRepeats: params.get('PERMUTATION_REPEATS')[0],
        permutationSeed: params.get('PERMUTATION_SEED')[0],
    };
    return {
        attributes, classes, target, settings,
        train: readRows('input/train.csv'),
        validation: readRows('input/validation.csv'),
        test: readRows('input/test.csv'),
    };
}

module.exports = { readDataset };
