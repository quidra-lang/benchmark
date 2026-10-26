import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.Path

data class Observation(val ident: String, val label: String, val values: DoubleArray)
data class InputData(val features: List<String>, val observations: List<Observation>, val settings: Map<String, List<String>>)

object Dataset {
    fun read(): InputData {
        val lines = Files.readAllLines(Path.of("input", "data.csv"), StandardCharsets.US_ASCII)
        val features = lines.first().split(',').drop(2)
        val observations = lines.drop(1).map { line ->
            val fields = line.split(',')
            Observation(fields[0], fields[1], fields.drop(2).map(String::toDouble).toDoubleArray())
        }
        val settings = Files.readAllLines(Path.of("input", "params.txt"), StandardCharsets.US_ASCII).associate { line ->
            val fields = line.split(' ')
            fields.first() to fields.drop(1)
        }
        return InputData(features, observations, settings)
    }

    fun write(name: String, lines: List<String>) {
        Files.writeString(Path.of("output", name), if (lines.isEmpty()) "" else lines.joinToString("\n", postfix = "\n"), StandardCharsets.US_ASCII)
    }
}
