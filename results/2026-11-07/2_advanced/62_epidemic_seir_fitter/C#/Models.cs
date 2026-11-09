using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Models {
    public delegate double[] Rate(double[] state, double multiplier);
    public static Rate Seird(int population, double sigma, double fatality, double beta, double gamma) {
        return (y, m) => {
            double flow = beta * m * y[0] * y[2] / population, progression = sigma * y[1],
                   removal = gamma * y[2];
            return new double[] { -flow,
                                  flow - progression,
                                  progression - removal,
                                  (1 - fatality) * gamma * y[2],
                                  fatality * gamma * y[2],
                                  progression };
        };
    }
    public static Rate Sir(int population, double beta, double gamma) {
        return (y, m) => {
            double flow = beta * m * y[0] * y[1] / population, removal = gamma * y[1];
            return new double[] { -flow, flow - removal, removal, flow };
        };
    }
    public static Rate Age(int[] populations, double[] fatalities, double sigma, double beta, double gamma,
                           double[][] contacts) {
        return (y, m) => {
            double[] result = new double[y.Length];
            for (int g = 0; g < populations.Length; g++) {
                int p = 6 * g;
                double pressure = 0;
                for (int h = 0; h < populations.Length; h++)
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
    public static Rate Generation(double sigma, double gamma) {
        return (y, m) => {
            double progression = sigma * y[0], removal = gamma * y[1];
            return new double[] { -progression, progression - removal, removal };
        };
    }
}
