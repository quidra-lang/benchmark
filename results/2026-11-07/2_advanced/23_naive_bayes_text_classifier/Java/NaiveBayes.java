import java.util.*;

final class TrainingCounts {
    final int classCount;
    final int vocabularySize;
    final int documentTotal;
    final long[] documents;
    final long[][] occurrences;
    final long[][] containing;
    final long[] totals;
    final long[] termTotals;
    final long total;

    TrainingCounts(List<int[]> sequences, int[] labels, int classes, int size) {
        classCount = classes;
        vocabularySize = size;
        documentTotal = sequences.size();
        documents = new long[classes];
        occurrences = new long[classes][size];
        containing = new long[classes][size];
        for (int i = 0; i < sequences.size(); i++) {
            int c = labels[i];
            documents[c]++;
            for (int term : sequences.get(i)) occurrences[c][term]++;
            for (int term : Vocabulary.firstOccurrences(sequences.get(i))) containing[c][term]++;
        }
        totals = new long[classes];
        termTotals = new long[size];
        long sum = 0;
        for (int c = 0; c < classes; c++) {
            for (int t = 0; t < size; t++) { totals[c] += occurrences[c][t]; termTotals[t] += occurrences[c][t]; }
            sum += totals[c];
        }
        total = sum;
    }
}

final class Prediction {
    final int label;
    final double score;
    final int[] ranking;
    final double[] scores;
    final double[] probabilities;
    final double normalizer;
    final double margin;

    Prediction(double[] values, boolean posterior) {
        scores = values;
        Integer[] order = new Integer[values.length];
        for (int i = 0; i < order.length; i++) order[i] = i;
        Arrays.sort(order, Comparator.<Integer>comparingDouble(i -> values[i]).reversed().thenComparingInt(i -> i));
        ranking = Arrays.stream(order).mapToInt(Integer::intValue).toArray();
        label = ranking[0];
        margin = values[label] - values[ranking[1]];
        probabilities = new double[values.length];
        double sum = 0.0;
        if (posterior) {
            for (int c = 0; c < values.length; c++) { probabilities[c] = Math.exp(values[c] - values[label]); sum += probabilities[c]; }
            for (int c = 0; c < values.length; c++) probabilities[c] /= sum;
        }
        normalizer = sum;
        score = posterior ? probabilities[label] : values[label];
    }

    Prediction(int winner, double value) {
        label = winner;
        score = value;
        ranking = new int[0];
        scores = probabilities = new double[0];
        normalizer = margin = 0.0;
    }
}

final class NaiveBayes {
    final int kind;
    final double[] priors;
    final double[] base;
    final double[][] weights;

    NaiveBayes(int kind, double[] priors, double[] base, double[][] weights) {
        this.kind = kind;
        this.priors = priors;
        this.base = base;
        this.weights = weights;
    }

    static double smoothedLog(long count, long total, int alpha, int outcomes) {
        return Math.log((double) (100 * count + alpha) / (100 * total + (long) alpha * outcomes));
    }

    static double smoothedLog(double count, double total, int alpha, int outcomes) {
        return Math.log((100 * count + alpha) / (100 * total + (double) alpha * outcomes));
    }

    static NaiveBayes train(int kind, TrainingCounts counts, int alpha) {
        int size = counts.vocabularySize;
        double[] priors = new double[counts.classCount];
        double[] base = new double[counts.classCount];
        double[][] weights = new double[counts.classCount][size];
        for (int c = 0; c < counts.classCount; c++) {
            priors[c] = Math.log((double) counts.documents[c] / counts.documentTotal);
            for (int t = 0; t < size; t++) {
                if (kind == 0) weights[c][t] = smoothedLog(counts.occurrences[c][t], counts.totals[c], alpha, size);
                else if (kind == 1) {
                    double present = smoothedLog(counts.containing[c][t], counts.documents[c], alpha, 2);
                    double absent = smoothedLog(counts.documents[c] - counts.containing[c][t], counts.documents[c], alpha, 2);
                    base[c] += absent;
                    weights[c][t] = present - absent;
                } else weights[c][t] = -smoothedLog(counts.termTotals[t] - counts.occurrences[c][t], counts.total - counts.totals[c], alpha, size);
            }
        }
        return new NaiveBayes(kind, priors, base, weights);
    }

    Prediction predict(int[] sequence) {
        int[] terms = kind == 1 ? Vocabulary.firstOccurrences(sequence) : sequence;
        double[] scores = new double[weights.length];
        for (int c = 0; c < weights.length; c++) {
            double score = base[c];
            for (int term : terms) score += weights[c][term];
            scores[c] = score + priors[c];
        }
        return new Prediction(scores, true);
    }
}
