import java.util.*;

record Accuracy(double me, double mae, double rmse, double mape, double smape, double mase) {}
final class Evaluation {
    static double scale(double[] values, int season) {
        double total = 0;
        for (int t = season; t < values.length; t++)
            total += Math.abs(values[t] - values[t - season]);
        return total / (values.length - season);
    }
    static Accuracy accuracy(double[] actual, double[] predicted, double scale) {
        double sum = 0, absolute = 0, squares = 0, percentage = 0, symmetric = 0;
        for (int i = 0; i < actual.length; i++) {
            double error = actual[i] - predicted[i];
            sum += error;
            absolute += Math.abs(error);
            squares += error * error;
            percentage += Math.abs(error) / actual[i];
            symmetric += 2 * Math.abs(error) / (Math.abs(actual[i]) + Math.abs(predicted[i]));
        }
        int count = actual.length;
        double mae = absolute / count;
        return new Accuracy(sum / count, mae, Math.sqrt(squares / count), 100 * percentage / count,
                            100 * symmetric / count, mae / scale);
    }
    static double winkler(double actual, double low, double high, double multiplier) {
        return high - low +
            (actual < low    ? multiplier * (low - actual)
             : actual > high ? multiplier * (actual - high)
                             : 0);
    }
    static List<Integer> ranking(List<Accuracy> metrics) {
        List<Integer> order = new ArrayList<>();
        for (int i = 0; i < metrics.size(); i++)
            order.add(i);
        order.sort(Comparator.<Integer>comparingDouble(i -> metrics.get(i).rmse()).thenComparingInt(i -> i));
        return order;
    }
}
