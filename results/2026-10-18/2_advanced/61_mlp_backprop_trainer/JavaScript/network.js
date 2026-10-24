'use strict';

const layers = require('./layers');

class Network {
    constructor(definition, inputSize, initial) {
        this.name = definition.name;
        this.initial = initial.slice();
        this.layers = [];
        this.weightIndices = [];
        let offset = 0;
        let inputs = inputSize;
        for (const definitionLayer of definition.layers) {
            const biasOffset = offset + definitionLayer.units * inputs;
            const end = biasOffset + definitionLayer.units;
            this.layers.push({...definitionLayer, inputs, offset, biasOffset, end});
            for (let p = offset; p < biasOffset; p++) this.weightIndices.push(p);
            offset = end;
            inputs = definitionLayer.units;
        }
        this.parameterCount = offset;
        this.classes = this.layers.at(-1).units;
        this.outputType = this.layers.at(-1).activation;
    }

    forward(theta, image) {
        const activations = [image.vector];
        const preactivations = [];
        let result;
        for (let l = 0; l < this.layers.length; l++) {
            const layer = this.layers[l];
            const values = layers.preactivate(theta, layer, activations[l]);
            preactivations.push(values);
            if (l + 1 < this.layers.length) {
                activations.push(values.map(value => layers.activate(layer.activation, value)));
            } else {
                result = layers.output(layer.activation, values, image.label);
                activations.push(result.scores);
            }
        }
        return {...result, activations, preactivations};
    }

    backward(theta, forward) {
        const deltas = Array(this.layers.length);
        deltas[deltas.length - 1] = forward.errors;
        for (let l = this.layers.length - 2; l >= 0; l--) {
            const propagated = layers.propagate(theta, this.layers[l + 1], deltas[l + 1]);
            deltas[l] = propagated.map((value, j) => value * layers.derivative(
                this.layers[l].activation, forward.preactivations[l][j], forward.activations[l + 1][j]));
        }
        const gradient = Array(this.parameterCount).fill(0);
        for (let l = 0; l < this.layers.length; l++) {
            const layer = this.layers[l];
            for (let j = 0; j < layer.units; j++) {
                for (let i = 0; i < layer.inputs; i++) {
                    gradient[layer.offset + j * layer.inputs + i] = deltas[l][j] * forward.activations[l][i];
                }
                gradient[layer.biasOffset + j] = deltas[l][j];
            }
        }
        const inputGradient = layers.propagate(theta, this.layers[0], deltas[0]);
        return {gradient, inputGradient};
    }
}

module.exports = {Network};
