import java.nio.file.Files
import java.nio.file.Path
import java.nio.charset.StandardCharsets
object Report {
    fun numbers(values: List<Int>) = if (values.isEmpty()) "-" else values.joinToString(",")
    fun numbers(values: IntArray) = numbers(values.toList())
    fun frequency(values: List<Int>): String {
        val counts = values.groupingBy {
            it
        }.eachCount().toSortedMap();
        return if (counts.isEmpty()) "-" else counts.entries.joinToString(",") {
            "${it.key}:${it.value}"
        }
    }
    fun board(positions: IntArray) = positions.map {
        column -> val row = CharArray(positions.size) {
            '.'
        };
        row[column - 1] = 'Q';
        String(row)
    }
    fun search(stats: Dpll.Stats) = "decisions=${stats.decisions} propagations=${stats.propagations} conflicts=${stats.conflicts} max_depth=${stats.maxDepth}"
    fun paragraph(output: MutableList<String>, lines: List<String>) {
        if (output.isNotEmpty()) output.add("");
        output.addAll(lines)
    }
    fun write(name: String, lines: List<String>) {
        Files.writeString(Path.of("output",name),if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n",StandardCharsets.US_ASCII)
    }
}
