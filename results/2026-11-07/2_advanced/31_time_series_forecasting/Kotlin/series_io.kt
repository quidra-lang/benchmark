import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path
import java.util.Locale

class SeriesData(val name: String) {
    val periods = mutableListOf<String>();
    val raw = mutableListOf<Int>();
    val events = mutableMapOf<String, String>()
    var onHand = 0;
    var lead = 0;
    var review = 0;
    var service = 0.0
}
class SeriesIo {
    val series = mutableListOf<SeriesData>()
    val settings = mutableMapOf<String, List<String>>()
    init {
        val named = mutableMapOf<String, SeriesData>()
        for (line in read("series.csv").drop(1)) {
            val fields = line.split(",");
            val data = named.getOrPut(fields[0]) {
                SeriesData(fields[0]).also {
                    series.add(it)
                }
            };
            data.periods.add(fields[1]);
            data.raw.add(if (fields[2] == "NA") -1 else fields[2].toInt())
        }
        for (line in read("events.csv").drop(1)) {
            val fields = line.split(",");
            named.getValue(fields[0]).events[fields[1]] = fields[2]
        }
        for (line in read("inventory.csv").drop(1)) {
            val fields = line.split(",");
            val data = named.getValue(fields[0]);
            data.onHand = fields[1].toInt();
            data.lead = fields[2].toInt();
            data.review = fields[3].toInt();
            data.service = fields[4].toDouble()
        }
        for (line in read("params.txt")) {
            val fields = line.split(" ");
            settings[fields[0]] = fields.drop(1)
        }
    }
    fun integer(key: String): Int = settings.getValue(key)[0].toInt()
    fun number(key: String): Double = settings.getValue(key)[0].toDouble()
    fun candidates(key: String): DoubleArray = settings.getValue(key).map(String::toDouble).toDoubleArray()
    companion object {
        fun read(name: String): List<String> = Files.readAllLines(Path.of("input", name), StandardCharsets.US_ASCII)
        fun nextMonth(period: String): String {
            val fields = period.split("-");
            var year = fields[0].toInt();
            var month = fields[1].toInt();
            if (month == 12) {
                year++;
                month = 1
            } else month++;
            return year.toString().padStart(4, '0') + "-" + month.toString().padStart(2, '0')
        }
        fun real(value: Double): String {
            if (value.isNaN()) return "NA";
            val text = String.format(Locale.ROOT, "%.4f", value);
            return if (text == "-0.0000") "0.0000" else text
        }
        fun write(name: String, lines: List<String>) {
            Files.writeString(Path.of("output", name), lines.joinToString("\n", postfix = "\n"), StandardCharsets.US_ASCII)
        }
    }
}
