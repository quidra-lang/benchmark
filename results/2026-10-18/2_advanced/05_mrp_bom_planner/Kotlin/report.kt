import java.io.File

fun money(cents: Long) = "${cents / 100}.${(cents % 100).toString().padStart(2, '0')}"
fun percent(part: Long, whole: Long) = (200L * part + whole) / (2L * whole)
fun tableRow(label: String, values: List<Long>, width: Int) = label.padEnd(10) + values.joinToString("") { it.toString().padStart(width) }
fun writeReport(name: String, lines: List<String>) { File("output").mkdirs(); File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n", postfix = "\n")) }
