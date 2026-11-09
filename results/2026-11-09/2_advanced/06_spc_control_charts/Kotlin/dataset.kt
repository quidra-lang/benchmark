import java.io.File

class Settings(fields: Map<String, String>, val rules: Map<String, List<Int>>) {
    val characteristic = fields.getValue("characteristic")
    val lsl = fields.getValue("lsl").toLong()
    val usl = fields.getValue("usl").toLong()
    val target = fields.getValue("target").toLong()
    val size = fields.getValue("subgroup_size").toInt()
    val phase1 = fields.getValue("phase1_subgroups").toInt()
    val passes = fields.getValue("max_passes").toInt()
    val cusumK = fields.getValue("cusum_k").toDouble()
    val cusumH = fields.getValue("cusum_h").toDouble()
    val lambda = fields.getValue("ewma_lambda").toDouble()
    val ewmaL = fields.getValue("ewma_l").toDouble()
    val maSpan = fields.getValue("ma_span").toInt()
    val eventGap = fields.getValue("event_gap").toInt()
    val ciZ = fields.getValue("ci_z").toDouble()
    val bin = fields.getValue("histogram_bin").toLong()
    val rollingWindow = fields.getValue("rolling_window").toInt()
    val rollingStep = fields.getValue("rolling_step").toInt()
}

data class Lot(val number: Int, val inspected: Long, val defectives: Long, val defects: Long)
class ControlConstants(val values: List<Double>) {
    val a2 get() = values[0]
    val a3 get() = values[1]
    val b3 get() = values[2]
    val b4 get() = values[3]
    val d3 get() = values[4]
    val d4 get() = values[5]
    val d2 get() = values[6]
    val c4 get() = values[7]
}

fun controlConstants(size: Int) = ControlConstants(listOf(
    listOf(1.880, 2.659, 0.0, 3.267, 0.0, 3.267, 1.128, 0.7979),
    listOf(1.023, 1.954, 0.0, 2.568, 0.0, 2.574, 1.693, 0.8862),
    listOf(0.729, 1.628, 0.0, 2.266, 0.0, 2.282, 2.059, 0.9213),
    listOf(0.577, 1.427, 0.0, 2.089, 0.0, 2.114, 2.326, 0.9400),
    listOf(0.483, 1.287, 0.030, 1.970, 0.0, 2.004, 2.534, 0.9515),
    listOf(0.419, 1.182, 0.118, 1.882, 0.076, 1.924, 2.704, 0.9594),
    listOf(0.373, 1.099, 0.185, 1.815, 0.136, 1.864, 2.847, 0.9650),
    listOf(0.337, 1.032, 0.239, 1.761, 0.184, 1.816, 2.970, 0.9693),
    listOf(0.308, 0.975, 0.284, 1.716, 0.223, 1.777, 3.078, 0.9727)
)[size - 2])

fun readSettings(): Settings {
    val fields = mutableMapOf<String, String>()
    val rules = mutableMapOf<String, List<Int>>()
    for (line in File("input/spec.txt").readLines()) {
        val words = line.split(' ')
        if (words[0] == "rules") rules[words[1]] = words.drop(2).map(String::toInt)
        else fields[words[0]] = words[1]
    }
    return Settings(fields, rules)
}
fun readMeasurements() = File("input/measurements.csv").readLines().drop(1).map { it.split(',')[2].toLong() }
fun readLots() = File("input/attributes.csv").readLines().drop(1).map { line -> val values = line.split(','); Lot(values[0].toInt(), values[1].toLong(), values[2].toLong(), values[3].toLong()) }
