import kotlin.math.abs
import kotlin.math.sqrt

data class Accuracy(val me: Double, val mae: Double, val rmse: Double, val mape: Double, val smape: Double, val mase: Double)
object Evaluation {
    fun scale(values: DoubleArray, season: Int): Double {
        var total = 0.0;
        for (t in season until values.size) total += abs(values[t] - values[t - season]);
        return total / (values.size - season)
    }
    fun accuracy(actual: DoubleArray, predicted: DoubleArray, scale: Double): Accuracy {
        var sum = 0.0;
        var absolute = 0.0;
        var squares = 0.0;
        var percentage = 0.0;
        var symmetric = 0.0
        for (i in actual.indices) {
            val error = actual[i] - predicted[i];
            sum += error;
            absolute += abs(error);
            squares += error * error;
            percentage += abs(error) / actual[i];
            symmetric += 2 * abs(error) / (abs(actual[i]) + abs(predicted[i]))
        }
        val count = actual.size;
        val mae = absolute / count
        return Accuracy(sum / count, mae, sqrt(squares / count), 100 * percentage / count, 100 * symmetric / count, mae / scale)
    }
    fun winkler(actual: Double, low: Double, high: Double, multiplier: Double): Double = high - low + if (actual < low) multiplier * (low - actual) else if (actual > high) multiplier * (actual - high) else 0.0
    fun ranking(metrics: List<Accuracy>): List<Int> = metrics.indices.sortedWith(compareBy<Int> {
        metrics[it].rmse
    }.thenBy {
        it
    })
}
