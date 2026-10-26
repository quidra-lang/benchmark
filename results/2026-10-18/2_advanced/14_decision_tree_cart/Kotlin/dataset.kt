import java.io.File

data class Attribute(val index: Int, val name: String, val integer: Boolean, val values: List<String>) {
    fun parse(text: String): Int = if (text == "?") -1 else if (integer) text.toInt() else values.indexOf(text)
}
data class Row(val id: String, val values: IntArray, val label: Int) {
    fun value(attribute: Attribute): Int = values[attribute.index]
    fun missingCount(): Int = values.count { it < 0 }
    fun withValue(attribute: Attribute, value: Int): Row = Row(id, values.copyOf().also { it[attribute.index] = value }, label)
}
data class Settings(
    val maxDepth: Int, val minSplit: Int, val minLeaf: Int, val maxSurrogates: Int, val folds: Int,
    val curve: List<Int>, val bagTrees: Int, val bagSeed: Long, val repeats: Int, val permutationSeed: Long
)
data class Dataset(
    val attributes: List<Attribute>, val target: String, val classes: List<String>,
    val train: List<Row>, val validation: List<Row>, val test: List<Row>, val settings: Settings
) {
    companion object {
        private fun lines(path: String): List<String> = File(path).readLines(Charsets.US_ASCII)
        private fun rows(path: String, attributes: List<Attribute>, classes: List<String>): List<Row> =
            lines(path).drop(1).map { line ->
                val fields = line.split(',')
                Row(fields[0], attributes.map { it.parse(fields[it.index + 1]) }.toIntArray(), classes.indexOf(fields.last()))
            }
        fun load(directory: String): Dataset {
            val schema = lines("$directory/schema.txt").map { it.split(' ') }
            val attributes = schema.dropLast(1).mapIndexed { index, fields ->
                Attribute(index, fields[1], fields[2] == "INT", fields.drop(3))
            }
            val target = schema.last()[1]
            val classes = schema.last().drop(2)
            val entries = lines("$directory/params.txt").associate { line ->
                val fields = line.split(' ')
                fields[0] to fields.drop(1).map { it.toInt() }
            }
            fun get(key: String): Int = entries.getValue(key).first()
            val settings = Settings(get("MAX_DEPTH"), get("MIN_SAMPLES_SPLIT"), get("MIN_SAMPLES_LEAF"),
                get("MAX_SURROGATES"), get("FOLDS"), entries.getValue("CURVE"), get("BAG_TREES"),
                get("BAG_SEED").toLong(), get("PERMUTATION_REPEATS"), get("PERMUTATION_SEED").toLong())
            return Dataset(attributes, target, classes, rows("$directory/train.csv", attributes, classes),
                rows("$directory/validation.csv", attributes, classes), rows("$directory/test.csv", attributes, classes), settings)
        }
    }
}
