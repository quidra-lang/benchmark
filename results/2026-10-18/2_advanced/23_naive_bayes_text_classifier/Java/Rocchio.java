import java.util.*;

final class Rocchio {
    final double[] idf;
    final double[][] centroids;
    final double[] lengths;

    Rocchio(List<int[]> sequences, int[] labels, int classes, int[] frequencies) {
        idf = new double[frequencies.length];
        for (int t = 0; t < idf.length; t++) idf[t] = Math.log((double) sequences.size() / frequencies[t]);
        centroids = new double[classes][idf.length];
        int[] documents = new int[classes];
        for (int i = 0; i < sequences.size(); i++) {
            int c = labels[i];
            documents[c]++;
            double[] vector = vector(sequences.get(i));
            double length = length(vector);
            if (length > 0) for (int t = 0; t < idf.length; t++) centroids[c][t] += vector[t] / length;
        }
        lengths = new double[classes];
        for (int c = 0; c < classes; c++) {
            for (int t = 0; t < idf.length; t++) centroids[c][t] /= documents[c];
            lengths[c] = length(centroids[c]);
        }
    }

    private double[] vector(int[] sequence) {
        int[] counts = new int[idf.length];
        for (int term : sequence) counts[term]++;
        double[] vector = new double[idf.length];
        for (int t = 0; t < idf.length; t++) vector[t] = counts[t] * idf[t];
        return vector;
    }

    private static double length(double[] values) {
        double total = 0.0;
        for (double value : values) total += value * value;
        return Math.sqrt(total);
    }

    Prediction predict(int[] sequence) {
        double[] vector = vector(sequence);
        double length = length(vector);
        double[] scores = new double[centroids.length];
        for (int c = 0; c < centroids.length; c++) {
            if (length > 0 && lengths[c] > 0) {
                double product = 0.0;
                for (int t = 0; t < idf.length; t++) product += vector[t] * centroids[c][t];
                scores[c] = product / (length * lengths[c]);
            }
        }
        return new Prediction(scores, false);
    }
}
