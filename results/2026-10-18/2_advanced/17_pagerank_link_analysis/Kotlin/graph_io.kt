import java.io.File

data class Page(val id: Int, val host: String, val title: String, val words: List<String>)
data class LinkRecord(val line: Int, val source: Int, val target: Int)
data class Query(val number: Int, val words: List<String>, val seeds: IntArray)
data class Settings(val damping: Double, val iterations: Int, val tolerance: Double, val sweep: DoubleArray, val trusted: IntArray,
    val spamTop: Int, val spamThreshold: Double, val hitsIterations: Int, val topK: Int, val rootLimit: Int, val neighborLimit: Int)
data class InputData(val pages: List<Page>, val records: List<LinkRecord>, val queries: List<Query>, val settings: Settings)
object GraphIO {
    fun lines(path: String) = File(path).readLines(Charsets.US_ASCII)
    fun read(directory: String): InputData {
        val pages = lines("$directory/pages.csv").drop(1).map { text ->
            val fields = text.split(',')
            Page(fields[0].toInt(), fields[1], fields[2], fields[2].split(' '))
        }
        val records = lines("$directory/links.csv").drop(1).mapIndexed { index, text ->
            val fields = text.split(',')
            LinkRecord(index + 2, fields[0].toInt(), fields[1].toInt())
        }
        val queries = lines("$directory/queries.txt").mapIndexed { index, text ->
            val sides = text.split(" | ")
            Query(index + 1, sides[0].split(' '), sides[1].split(' ').map(String::toInt).toIntArray())
        }
        val entries = lines("$directory/params.txt").associate { text ->
            val fields = text.split(' ')
            fields[0] to fields.drop(1)
        }
        fun integer(key: String) = entries.getValue(key)[0].toInt()
        fun real(key: String) = entries.getValue(key)[0].toDouble()
        val settings = Settings(real("DAMPING"), integer("PAGERANK_ITERATIONS"), real("TOLERANCE"),
            entries.getValue("DAMPING_SWEEP").map(String::toDouble).toDoubleArray(), entries.getValue("TRUSTED").map(String::toInt).toIntArray(),
            integer("SPAM_TOP"), real("SPAM_THRESHOLD"), integer("HITS_ITERATIONS"), integer("TOP_K"), integer("ROOT_LIMIT"), integer("NEIGHBOR_LIMIT"))
        return InputData(pages, records, queries, settings)
    }
}
