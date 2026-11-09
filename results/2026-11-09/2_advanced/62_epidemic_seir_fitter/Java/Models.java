final class Models {
    interface Rate {
        double[] value(double[] state, double multiplier);
    }
    static Rate seird(int population, double sigma, double fatality, double beta, double gamma) {
        return (y, m) -> {
            double flow = beta * m * y[0] * y[2] / population, progression = sigma * y[1],
                   removal = gamma * y[2];
            return new double[] {-flow,
                                 flow - progression,
                                 progression - removal,
                                 (1 - fatality) * gamma * y[2],
                                 fatality * gamma * y[2],
                                 progression};
        };
    }
    static Rate sir(int population, double beta, double gamma) {
        return (y, m) -> {
            double flow = beta * m * y[0] * y[1] / population, removal = gamma * y[1];
            return new double[] {-flow, flow - removal, removal, flow};
        };
    }
    static Rate age(int[] populations, double[] fatalities, double sigma, double beta, double gamma,
                    double[][] contacts) {
        return (y, m) -> {
            double[] result = new double[y.length];
            for (int g = 0; g < populations.length; g++) {
                int p = 6 * g;
                double pressure = 0;
                for (int h = 0; h < populations.length; h++)
                    pressure += contacts[g][h] * y[6 * h + 2] / populations[h];
                double force = beta * m * pressure, flow = force * y[p], progression = sigma * y[p + 1],
                       removal = gamma * y[p + 2];
                result[p] = -flow;
                result[p + 1] = flow - progression;
                result[p + 2] = progression - removal;
                result[p + 3] = (1 - fatalities[g]) * gamma * y[p + 2];
                result[p + 4] = fatalities[g] * gamma * y[p + 2];
                result[p + 5] = progression;
            }
            return result;
        };
    }
    static Rate generation(double sigma, double gamma) {
        return (y, m) -> {
            double progression = sigma * y[0], removal = gamma * y[1];
            return new double[] {-progression, progression - removal, removal};
        };
    }
}
