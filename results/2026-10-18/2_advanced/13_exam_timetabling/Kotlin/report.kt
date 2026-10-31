import java.io.File

object Report {
    fun fixedWidthLine(label: String, cells: List<String>, labelWidth: Int, cellWidth: Int): String =
        (label.padEnd(labelWidth) + cells.joinToString("") { it.padStart(cellWidth) }).trimEnd()

    fun roundedPercent(part: Int, whole: Int): Int = (200 * part + whole) / (2 * whole)

    fun writeFiles(directory: String, files: Map<String, List<String>>) {
        File(directory).mkdirs()
        for ((name, lines) in files)
            File(directory, name).writeText(lines.joinToString("\n") + "\n", Charsets.US_ASCII)
    }
}
