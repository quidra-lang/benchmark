import java.nio.file.Files
import java.nio.file.Path
import kotlin.math.sqrt

data class Example(val id: String, val values: DoubleArray, val label: Int)
data class Statistics(val means: DoubleArray, val deviations: DoubleArray)
class Dataset {
    val train: List<Example>
    val test: List<Example>
    val names: List<String>
    val settings: Map<String, List<String>>
    val tuples = mutableListOf<IntArray>()
    val features: List<String>
    init {
        val trainingLines = lines("train.csv");
        names = trainingLines[0].split(",").drop(1).dropLast(1);
        train = examples(trainingLines);
        test = examples(lines("test.csv"))
        settings = lines("params.txt").associate {
            val fields = it.split(" ");
            fields[0] to fields.drop(1)
        }
        for (degree in 1..integer("DEGREE", 0)) expand(IntArray(degree), 0, 0)
        features = tuples.map {
            tuple -> tuple.joinToString("*") {
                names[it]
            }
        }
    }
    fun integer(key: String, index: Int): Int = settings.getValue(key)[index].toInt()
    fun number(key: String, index: Int): Double = settings.getValue(key)[index].toDouble()
    private fun expand(tuple: IntArray, position: Int, minimum: Int) {
        if (position == tuple.size) {
            tuples.add(tuple.copyOf());
            return
        }
        for (index in minimum until names.size) {
            tuple[position] = index;
            expand(tuple, position + 1, index)
        }
    }
    fun expanded(values: DoubleArray): DoubleArray = tuples.map {
        tuple -> var product = values[tuple[0]];
        for (k in 1 until tuple.size) product *= values[tuple[k]];
        product
    }.toDoubleArray()
    fun expanded(rows: List<Example>): Array<DoubleArray> = rows.map {
        expanded(it.values)
    }.toTypedArray()
    companion object {
        fun lines(name: String): List<String> = Files.readAllLines(Path.of("input", name))
        fun examples(lines: List<String>): List<Example> = lines.drop(1).map {
            val fields = it.split(",");
            Example(fields[0], fields.drop(1).dropLast(1).map(String::toDouble).toDoubleArray(), fields.last().toInt())
        }
        fun statistics(rows: Array<DoubleArray>, count: Int): Statistics {
            val means = DoubleArray(count);
            val deviations = DoubleArray(count)
            for (j in 0 until count) {
                var total = 0.0;
                for (row in rows) total += row[j];
                val mean = total / rows.size;
                means[j] = mean;
                var squares = 0.0;
                for (row in rows) {
                    val delta = row[j] - mean;
                    squares += delta * delta
                };
                deviations[j] = sqrt(squares / (rows.size - 1))
            }
            return Statistics(means, deviations)
        }
        fun standardize(values: DoubleArray, statistics: Statistics, count: Int): DoubleArray = DoubleArray(count + 1) {
            if (it == 0) 1.0 else (values[it - 1] - statistics.means[it - 1]) / statistics.deviations[it - 1]
        }
        fun standardize(rows: Array<DoubleArray>, statistics: Statistics, count: Int): Array<DoubleArray> = rows.map {
            standardize(it, statistics, count)
        }.toTypedArray()
    }
}
