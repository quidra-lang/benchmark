import type { Definition, Image, LayerDefinition } from './dataset.ts';
import * as layers from './layers.ts';
import type { Layout, Output } from './layers.ts';
export interface Layer extends LayerDefinition, Layout {}
export interface Forward extends Output {
  activations: number[][];
  preactivations: number[][];
}
export class Network {
  name: string;
  initial: number[];
  layers: Layer[] = [];
  weightIndices: number[] = [];
  parameterCount: number;
  classes: number;
  outputType: 'SOFTMAX' | 'SIGMOID';
  constructor(definition: Definition, inputSize: number, initial: number[]) {
    this.name = definition.name;
    this.initial = initial.slice();
    let offset = 0;
    let inputs = inputSize;
    for (const layer of definition.layers) {
      const biasOffset = offset + layer.units * inputs;
      const end = biasOffset + layer.units;
      this.layers.push({ ...layer, inputs, offset, biasOffset, end });
      for (let p = offset; p < biasOffset; p++) this.weightIndices.push(p);
      offset = end;
      inputs = layer.units;
    }
    this.parameterCount = offset;
    const last = this.layers[this.layers.length - 1];
    this.classes = last.units;
    this.outputType = last.activation === 'SOFTMAX' ? 'SOFTMAX' : 'SIGMOID';
  }
  forward(theta: number[], image: Pick<Image, 'vector' | 'label'>): Forward {
    const activations = [image.vector];
    const preactivations: number[][] = [];
    const last = this.layers.length - 1;
    for (let l = 0; l < last; l++) {
      const layer = this.layers[l];
      const z = layers.preactivate(theta, layer, activations[l]);
      preactivations.push(z);
      activations.push(z.map((v) => layers.activate(layer.activation, v)));
    }
    const z = layers.preactivate(theta, this.layers[last], activations[last]);
    const result = layers.output(this.outputType, z, image.label);
    preactivations.push(z);
    activations.push(result.scores);
    return { ...result, activations, preactivations };
  }
  backward(theta: number[], forward: Forward) {
    const deltas: number[][] = Array.from({ length: this.layers.length }, () => []);
    deltas[deltas.length - 1] = forward.errors;
    for (let l = this.layers.length - 2; l >= 0; l--) {
      deltas[l] = layers
        .propagate(theta, this.layers[l + 1], deltas[l + 1])
        .map(
          (v, j) =>
            v *
            layers.derivative(
              this.layers[l].activation,
              forward.preactivations[l][j],
              forward.activations[l + 1][j],
            ),
        );
    }
    const gradient: number[] = Array(this.parameterCount).fill(0);
    for (let l = 0; l < this.layers.length; l++) {
      const layer = this.layers[l];
      for (let j = 0; j < layer.units; j++) {
        for (let i = 0; i < layer.inputs; i++) {
          gradient[layer.offset + j * layer.inputs + i] = deltas[l][j] * forward.activations[l][i];
        }
        gradient[layer.biasOffset + j] = deltas[l][j];
      }
    }
    return { gradient, inputGradient: layers.propagate(theta, this.layers[0], deltas[0]) };
  }
}
