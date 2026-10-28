import java.nio.file.Files
import java.nio.file.Path

data class Point(val id: Int, val x: Int, val y: Int)
class Dataset {
    val points = Files.readAllLines(Path.of("input/points.csv")).drop(1).map {
        val fields = it.split(",");
        Point(fields[0].toInt(), fields[1].toInt(), fields[2].toInt())
    }.sortedBy {
        it.id
    }
    val settings = Files.readAllLines(Path.of("input/params.txt")).associate {
        val fields = it.split(" ");
        fields[0] to fields.drop(1)
    }
    fun value(key: String, index: Int = 0): Int = settings.getValue(key)[index].toInt()
    fun values(key: String): IntArray = settings.getValue(key).map(String::toInt).toIntArray()
}
