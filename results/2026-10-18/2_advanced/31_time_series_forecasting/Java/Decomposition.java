import java.util.*;

final class Decomposition {
    final double[] trend, additive, multiplicative, residualAdd, residualMult;
    final int half, count;
    Decomposition(double[] values, int season) {
        count = values.length;
        half = season / 2;
        trend = new double[count];
        residualAdd = new double[count];
        residualMult = new double[count];
        Arrays.fill(trend, Double.NaN);
        Arrays.fill(residualAdd, Double.NaN);
        Arrays.fill(residualMult, Double.NaN);
        additive = new double[season];
        multiplicative = new double[season];
        int[] counts = new int[season];
        for (int t = half; t < count - half; t++) {
            double total = 0.5 * values[t - half];
            for (int i = t - half + 1; i < t + half; i++)
                total += values[i];
            total += 0.5 * values[t + half];
            trend[t] = total / season;
            int position = t % season;
            additive[position] += values[t] - trend[t];
            multiplicative[position] += values[t] / trend[t];
            counts[position]++;
        }
        for (int j = 0; j < season; j++) {
            additive[j] /= counts[j];
            multiplicative[j] /= counts[j];
        }
        double addMean = sum(additive) / season, multMean = sum(multiplicative) / season;
        for (int j = 0; j < season; j++) {
            additive[j] -= addMean;
            multiplicative[j] /= multMean;
        }
        for (int t = half; t < count - half; t++) {
            residualAdd[t] = values[t] - trend[t] - additive[t % season];
            residualMult[t] = values[t] / (trend[t] * multiplicative[t % season]);
        }
    }
    static double sum(double[] values) {
        double total = 0;
        for (double value : values)
            total += value;
        return total;
    }
    static double variance(double[] values) {
        double mean = sum(values) / values.length, total = 0;
        for (double value : values)
            total += (value - mean) * (value - mean);
        return total / (values.length - 1);
    }
    static double[] regression(double[] values) {
        int count = values.length;
        double center = (count + 1) / 2.0, average = sum(values) / count, numerator = 0, denominator = 0;
        for (int t = 0; t < count; t++) {
            numerator += (t + 1 - center) * (values[t] - average);
            denominator += (t + 1 - center) * (t + 1 - center);
        }
        double slope = numerator / denominator;
        return new double[] {average - slope * center, slope};
    }
}
