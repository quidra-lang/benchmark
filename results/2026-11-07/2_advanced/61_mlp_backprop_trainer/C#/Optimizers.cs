using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Optimizers {
    public sealed class State {
        public Dataset.Run run;
        public double[] first, second;
        public double pi1 = 1, pi2 = 1;
        public State(Dataset.Run run, int size) {
            this.run = run;
            first = new double[size];
            second = new double[size];
        }
        public void Update(double[] theta, double[] gradient, double eta) {
            if (run.optimizer.Equals("ADAM")) {
                pi1 *= run.beta1;
                pi2 *= run.beta2;
            }
            for (int p = 0; p < theta.Length; p++) {
                double g = gradient[p];
                if (run.optimizer.Equals("SGD"))
                    theta[p] = theta[p] - eta * g;
                else if (run.optimizer.Equals("MOMENTUM")) {
                    second[p] = run.momentum * second[p] + g;
                    theta[p] = theta[p] - eta * second[p];
                } else {
                    first[p] = run.beta1 * first[p] + (1 - run.beta1) * g;
                    second[p] = run.beta2 * second[p] + (1 - run.beta2) * g * g;
                    double m = first[p] / (1 - pi1), v = second[p] / (1 - pi2);
                    theta[p] = theta[p] - eta * m / (Math.Sqrt(v) + run.epsilon);
                }
            }
        }
    }
    public static double Rate(Dataset.Run run, Dataset.Settings settings, int epoch) {
        double eta = run.eta;
        for (int i = 0; i < (epoch - 1) / settings.decayStep; i++)
            eta *= settings.gamma;
        return eta;
    }
}
