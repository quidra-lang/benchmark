final class Optimizers {
    static final class State {
        Dataset.Run run;
        double[] first, second;
        double pi1 = 1, pi2 = 1;
        State(Dataset.Run run, int size) {
            this.run = run;
            first = new double[size];
            second = new double[size];
        }
        void update(double[] theta, double[] gradient, double eta) {
            if (run.optimizer().equals("ADAM")) {
                pi1 *= run.beta1();
                pi2 *= run.beta2();
            }
            for (int p = 0; p < theta.length; p++) {
                double g = gradient[p];
                if (run.optimizer().equals("SGD"))
                    theta[p] = theta[p] - eta * g;
                else if (run.optimizer().equals("MOMENTUM")) {
                    second[p] = run.momentum() * second[p] + g;
                    theta[p] = theta[p] - eta * second[p];
                } else {
                    first[p] = run.beta1() * first[p] + (1 - run.beta1()) * g;
                    second[p] = run.beta2() * second[p] + (1 - run.beta2()) * g * g;
                    double m = first[p] / (1 - pi1), v = second[p] / (1 - pi2);
                    theta[p] = theta[p] - eta * m / (Math.sqrt(v) + run.epsilon());
                }
            }
        }
    }
    static double rate(Dataset.Run run, Dataset.Settings settings, int epoch) {
        double eta = run.eta();
        for (int i = 0; i < (epoch - 1) / settings.decayStep; i++)
            eta *= settings.gamma;
        return eta;
    }
}
