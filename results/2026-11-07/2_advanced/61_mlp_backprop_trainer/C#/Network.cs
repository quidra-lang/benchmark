using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public sealed class Network {
    public string name;
    public int inputs, layers, classes, parameters, weights;
    public int[] units, starts, biases;
    public string[] activations;
    public bool[] weight;
    public double[] initial;
    public Network(string name, int inputs, int[] units, string[] activations) {
        this.name = name;
        this.inputs = inputs;
        this.units = units;
        this.activations = activations;
        layers = units.Length;
        classes = units[layers - 1];
        starts = new int[layers];
        biases = new int[layers];
        int previous = inputs;
        for (int l = 0; l < layers; l++) {
            starts[l] = parameters;
            int count = units[l] * previous;
            weights += count;
            parameters += count;
            biases[l] = parameters;
            parameters += units[l];
            previous = units[l];
        }
        weight = new bool[parameters];
        initial = new double[parameters];
        for (int l = 0; l < layers; l++)
            for (int p = starts[l]; p < biases[l]; p++)
                weight[p] = true;
    }
    public record Pass(double[][] z, double[][] a, double[] scores, double[] delta, double loss) {
    }
    public record GradientResult(double[] gradient, double[] input) {
    }
    public Pass Forward(double[] theta, Dataset.Image image) {
        double[][] z = new double [layers][], a = new double [layers + 1][];
        a[0] = image.values;
        Layers.Output output = null;
        for (int l = 0; l < layers; l++) {
            int previous = l == 0 ? inputs : units[l - 1];
            z[l] = Layers.Linear(theta, starts[l], biases[l], previous, units[l], a[l]);
            if (l + 1 == layers) {
                output = Layers.ComputeOutput(activations[l], z[l], image.label);
                a[l + 1] = output.scores;
            } else {
                a[l + 1] = new double[units[l]];
                for (int j = 0; j < units[l]; j++)
                    a[l + 1][j] = Layers.Activation(activations[l], z[l][j]);
            }
        }
        return new Pass(z, a, output.scores, output.delta, output.loss);
    }
    public GradientResult Backward(double[] theta, Pass pass) {
        double[][] delta = new double [layers][];
        delta[layers - 1] = pass.delta;
        for (int l = layers - 2; l >= 0; l--) {
            delta[l] = new double[units[l]];
            for (int j = 0; j < units[l]; j++) {
                double value = Layers.Backward(theta, starts[l + 1], units[l], units[l + 1], j, delta[l + 1]);
                delta[l][j] = value * Layers.Derivative(activations[l], pass.z[l][j], pass.a[l + 1][j]);
            }
        }
        double[] gradient = new double[parameters], input = new double[inputs];
        for (int l = 0; l < layers; l++) {
            int previous = l == 0 ? inputs : units[l - 1];
            for (int j = 0; j < units[l]; j++) {
                for (int i = 0; i < previous; i++)
                    gradient[starts[l] + j * previous + i] = delta[l][j] * pass.a[l][i];
                gradient[biases[l] + j] = delta[l][j];
            }
        }
        for (int i = 0; i < inputs; i++)
            input[i] = Layers.Backward(theta, starts[0], inputs, units[0], i, delta[0]);
        return new GradientResult(gradient, input);
    }
}
