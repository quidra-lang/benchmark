using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class Integrator {
    public static double[] Shifted(double[] y, double[] k, double factor) {
        double[] result = new double[y.Length];
        for (int i = 0; i < y.Length; i++)
            result[i] = y[i] + factor * k[i];
        return result;
    }
    public static double[] Step(Models.Rate rate, double[] state, double multiplier) {
        double h = 0.25, half = h / 2, sixth = h / 6;
        double[] a = rate.Invoke(state, multiplier), b = rate.Invoke(Shifted(state, a, half), multiplier),
                 c = rate.Invoke(Shifted(state, b, half), multiplier),
                 d = rate.Invoke(Shifted(state, c, h), multiplier), result = new double[state.Length];
        for (int i = 0; i < result.Length; i++)
            result[i] = state[i] + sixth * (((a[i] + 2 * b[i]) + 2 * c[i]) + d[i]);
        return result;
    }
    public static List<double[]> Simulate(Models.Rate rate, double[] initial, double[] multipliers,
                                          int[] inflows) {
        double[] state = initial.ToArray();
        List<double[]> daily = new();
        foreach (double multiplier in multipliers) {
            foreach (int i in inflows)
                state[i] = 0;
            for (int k = 0; k < 4; k++)
                state = Step(rate, state, multiplier);
            daily.Add(state.ToArray());
        }
        return daily;
    }
}
