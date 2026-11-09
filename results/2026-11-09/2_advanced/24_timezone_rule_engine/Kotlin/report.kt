import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.util.Locale
import kotlin.math.abs

object Report {
    fun local(time: Long): String {
        val parts = DayRules.splitTime(time)
        return String.format(Locale.ROOT, "%04d-%02d-%02dT%02d:%02d:%02d", parts[0], parts[1], parts[2], parts[3], parts[4], parts[5])
    }
    fun ut(time: Long): String = local(time) + "Z"
    fun offset(value: Long): String {
        val absolute = abs(value)
        val text = String.format(Locale.ROOT, "%s%02d:%02d", if (value < 0) "-" else "+", absolute / 3600, absolute / 60 % 60)
        return if (absolute % 60 == 0L) text else text + String.format(Locale.ROOT, ":%02d", absolute % 60)
    }
    fun duration(value: Long): String {
        val absolute = abs(value)
        return String.format(Locale.ROOT, "%s%d:%02d:%02d", if (value < 0) "-" else "", absolute / 3600, absolute / 60 % 60, absolute % 60)
    }
    fun clock(value: Long): String {
        val text = String.format(Locale.ROOT, "%d:%02d", value / 3600, value / 60 % 60)
        return if (value % 60 == 0L) text else text + String.format(Locale.ROOT, ":%02d", value % 60)
    }
    fun state(period: Resolver.Period): String = "${offset(period.offset)} ${if (period.dst) "DST" else "STD"} ${period.abbreviation}"
    fun change(time: Long, before: Resolver.Period, after: Resolver.Period): String = "${ut(time)} ${state(before)} -> ${state(after)}"

    fun writeLines(name: String, lines: List<String>) {
        Files.writeString(Path.of("output", name), if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n", StandardCharsets.US_ASCII)
    }
    fun writeBlocks(name: String, blocks: List<List<String>>) {
        val lines = mutableListOf<String>()
        for (block in blocks) { if (lines.isNotEmpty()) lines.add(""); lines.addAll(block) }
        writeLines(name, lines)
    }
}
