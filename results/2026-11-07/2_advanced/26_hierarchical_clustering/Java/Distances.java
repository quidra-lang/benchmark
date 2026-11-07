final class Distances {
    static final String[] TYPES = {"euclidean", "manhattan", "correlation"};
    record Statistics(double[] means, double[] deviations) {}

    static double sum(double[] values) { double total = 0.0; for (double value : values) total += value; return total; }
    static double squared(double[] first, double[] second) {
        double total = 0.0;
        for (int f = 0; f < first.length; f++) { double difference = first[f] - second[f]; total += difference * difference; }
        return total;
    }

    static Statistics statistics(double[][] rows) {
        double[] means = new double[rows[0].length], deviations = new double[rows[0].length];
        for (int f = 0; f < means.length; f++) {
            double total = 0.0;
            for (double[] row : rows) total += row[f];
            means[f] = total / rows.length;
            double squares = 0.0;
            for (double[] row : rows) { double difference = row[f] - means[f]; squares += difference * difference; }
            deviations[f] = Math.sqrt(squares / (rows.length - 1));
        }
        return new Statistics(means, deviations);
    }

    static double[][] standardize(double[][] rows, Statistics statistics) {
        double[][] result = new double[rows.length][statistics.means.length];
        for (int i = 0; i < rows.length; i++) for (int f = 0; f < result[i].length; f++) result[i][f] = (rows[i][f] - statistics.means[f]) / statistics.deviations[f];
        return result;
    }

    static double distance(double[] first, double[] second, String type) {
        if (type.equals("euclidean")) return Math.sqrt(squared(first, second));
        if (type.equals("manhattan")) { double total = 0.0; for (int f = 0; f < first.length; f++) total += Math.abs(first[f] - second[f]); return total; }
        double firstMean = sum(first) / first.length, secondMean = sum(second) / second.length;
        double cross = 0.0, firstSquares = 0.0, secondSquares = 0.0;
        for (int f = 0; f < first.length; f++) {
            double a = first[f] - firstMean, b = second[f] - secondMean;
            cross += a * b; firstSquares += a * a; secondSquares += b * b;
        }
        return 1 - cross / Math.sqrt(firstSquares * secondSquares);
    }

    static double[][] matrix(double[][] vectors, String type) {
        double[][] matrix = new double[vectors.length][vectors.length];
        for (int i = 0; i < vectors.length; i++) for (int j = i + 1; j < vectors.length; j++) matrix[i][j] = matrix[j][i] = distance(vectors[i], vectors[j], type);
        return matrix;
    }
}
