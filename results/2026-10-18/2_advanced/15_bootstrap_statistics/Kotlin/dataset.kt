import java.io.File

data class Group(val number: Int, val name: String, val values: LongArray)
data class PairedSample(val before: LongArray, val after: LongArray, val differences: LongArray)
data class Comparison(val first: Group, val second: Group)
data class Settings(val seed: Long, val bootstrap: Int, val permutations: Int, val confidence: Int,
    val pilot: Int, val powerSims: Int, val powerPerms: Int, val bins: Int)
data class Dataset(val groups: List<Group>, val paired: PairedSample, val pairs: List<Comparison>, val settings: Settings) {
    companion object {
        private fun lines(path: String): List<String> = File(path).readLines(Charsets.US_ASCII)
        private fun hundredths(text: String): Long {
            val parts = text.split('.')
            return 100 * parts[0].toLong() + if (parts.size == 1) 0L else (parts[1] + "00").take(2).toLong()
        }
        fun load(directory: String): Dataset {
            val values = linkedMapOf<String, MutableList<Long>>()
            for (line in lines("$directory/samples.csv").drop(1)) {
                val (name, value) = line.split(',')
                values.getOrPut(name) { mutableListOf() } += hundredths(value)
            }
            val groups = values.entries.mapIndexed { index, entry -> Group(index + 1, entry.key, entry.value.toLongArray()) }
            val names = groups.associateBy { it.name }
            val pairedLines = lines("$directory/paired.csv").drop(1)
            val before = LongArray(pairedLines.size)
            val after = LongArray(pairedLines.size)
            for ((index, line) in pairedLines.withIndex()) {
                val fields = line.split(',')
                before[index] = hundredths(fields[1]); after[index] = hundredths(fields[2])
            }
            val entries = mutableMapOf<String, List<Int>>()
            val pairs = mutableListOf<Comparison>()
            for (line in lines("$directory/params.txt")) {
                val fields = line.split(' ')
                if (fields[0] == "compare") pairs += Comparison(names.getValue(fields[1]), names.getValue(fields[2]))
                else entries[fields[0]] = fields.drop(1).map { it.toInt() }
            }
            fun get(key: String): Int = entries.getValue(key).first()
            val settings = Settings(get("seed").toLong(), get("bootstrap"), get("permutations"), get("confidence"),
                get("pilot"), entries.getValue("power")[0], entries.getValue("power")[1], get("bins"))
            return Dataset(groups, PairedSample(before, after, LongArray(before.size) { after[it] - before[it] }), pairs, settings)
        }
    }
}
