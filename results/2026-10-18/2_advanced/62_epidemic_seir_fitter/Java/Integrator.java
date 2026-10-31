import java.util.*;

final class Integrator {
    static double[] shifted(double[] y, double[] k, double factor) {
        double[] result = new double[y.length];
        for (int i = 0; i < y.length; i++)
            result[i] = y[i] + factor * k[i];
        return result;
    }
    static double[] step(Models.Rate rate, double[] state, double multiplier) {
        double h = 0.25, half = h / 2, sixth = h / 6;
        double[] a = rate.value(state, multiplier), b = rate.value(shifted(state, a, half), multiplier),
                 c = rate.value(shifted(state, b, half), multiplier),
                 d = rate.value(shifted(state, c, h), multiplier), result = new double[state.length];
        for (int i = 0; i < result.length; i++)
            result[i] = state[i] + sixth * (((a[i] + 2 * b[i]) + 2 * c[i]) + d[i]);
        return result;
    }
    static List<double[]> simulate(Models.Rate rate, double[] initial, double[] multipliers, int[] inflows) {
        double[] state = initial.clone();
        List<double[]> daily = new ArrayList<>();
        for (double multiplier : multipliers) {
            for (int i : inflows)
                state[i] = 0;
            for (int k = 0; k < 4; k++)
                state = step(rate, state, multiplier);
            daily.add(state.clone());
        }
        return daily;
    }
}
