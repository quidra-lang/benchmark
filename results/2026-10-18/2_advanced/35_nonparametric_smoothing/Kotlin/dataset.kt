import java.nio.file.Files
import java.nio.file.Path
import java.nio.charset.StandardCharsets
class Dataset {
    data class Point(val x: Int, val y: Int)
    data class Test(val name: String, val position: Int)
    class Series(val name: String, val positions: IntArray, val hundredths: IntArray) {
        val n = positions.size;
        val x = DoubleArray(n) {
            positions[it] / 100.0
        };
        val y = DoubleArray(n) {
            hundredths[it] / 100.0
        }
        fun subset(group: Int, folds: Int): Series {
            val selected = positions.indices.filter {
                if (folds == 0) it != group else it % folds != group
            };
            return Series(name,selected.map {
                positions[it]
            }.toIntArray(),selected.map {
                hundredths[it]
            }.toIntArray())
        }
    }
    companion object {
        fun hundredths(value: String) = value.replace(".","").toInt()
    }
    val series = mutableListOf<Series>();
    val tests = mutableListOf<Test>();
    val settings = mutableMapOf<String,List<String>>()
    init {
        val groups = linkedMapOf<String,MutableList<Point>>()
        for (line in Files.readAllLines(Path.of("input/series.csv"),StandardCharsets.US_ASCII).drop(1)) {
            val parts = line.split(',');
            groups.getOrPut(parts[0]) {
                mutableListOf()
            }.add(Point(hundredths(parts[1]),hundredths(parts[2])))
        }
        for ((name,points) in groups) {
            val ordered = points.sortedBy {
                it.x
            };
            series.add(Series(name,ordered.map {
                it.x
            }.toIntArray(),ordered.map {
                it.y
            }.toIntArray()))
        }
        for (line in Files.readAllLines(Path.of("input/test_points.csv"),StandardCharsets.US_ASCII).drop(1)) {
            val parts = line.split(',');
            tests.add(Test(parts[0],hundredths(parts[1])))
        }
        for (line in Files.readAllLines(Path.of("input/params.txt"),StandardCharsets.US_ASCII)) {
            val parts = line.split(' ');
            settings[parts[0]] = parts.drop(1)
        }
    }
    fun integer(key: String) = settings.getValue(key)[0].toInt()
    fun number(key: String) = settings.getValue(key)[0].toDouble()
    fun values(key: String) = settings.getValue(key)
}
