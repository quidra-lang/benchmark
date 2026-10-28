import java.nio.file.Files
import java.nio.file.Path
import java.nio.charset.StandardCharsets
import java.util.Locale
import kotlin.math.abs
object Report {
    fun fixed(value: Long): String {
        val n = abs(value);
        return (if (value < 0) "-" else "") + (n / 10000) + "." + String.format(Locale.ROOT,"%04d",n % 10000)
    }
    fun average(total: Long, count: Long) = fixed(DynamicProgramming.floor(total * 10000,count))
    fun cell(world: Environment, x: Int) = "${x / world.width},${x % world.width}"
    fun grid(world: Environment, separated: Boolean, content: (Int) -> String): List<String> = (0 until world.height).map {
        r -> (0 until world.width).joinToString(if (separated) " " else "") {
            c -> val x = r * world.width + c;
            if (world.cells[x] == '#' || world.terminal(x)) world.cells[x].toString() else content(x)
        }
    }
    fun qRows(output: MutableList<String>, method: String, world: Environment, values: Array<LongArray>, visits: Array<LongArray>?) {
        for (x in world.states) for (a in 0..3) output.add("$method,${cell(world,x)},${"NESW"[a]},${fixed(values[x][a])},${visits?.get(x)?.get(a) ?: "-"}")
    }
    fun write(name: String, lines: List<String>) {
        Files.writeString(Path.of("output",name),lines.joinToString("\n") + "\n",StandardCharsets.US_ASCII)
    }
}
