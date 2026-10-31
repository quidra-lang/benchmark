import java.io.File

data class Row(val id: String, val values: List<Double>, val label: String?, val target: Double?)
class Settings(entries: Map<String, List<String>>) {
    val scalings = entries.getValue("SCALINGS")
    val ks = entries.getValue("K_VALUES").map(String::toInt)
    val metrics = entries.getValue("METRICS")
    val weightings = entries.getValue("WEIGHTINGS")
    val folds = entries.getValue("FOLDS")[0].toInt()
    val editK = entries.getValue("EDIT_K")[0].toInt()
    val curve = entries.getValue("CURVE").map(String::toInt)
    val bins = entries.getValue("BINS").map(String::toDouble)
    val top = entries.getValue("TOP")[0].toInt()
}
data class Dataset(val features: List<String>, val train: List<Row>, val test: List<Row>, val settings: Settings)
fun readRows(name: String): Pair<List<String>, List<Row>> {
    val lines = File("input/$name").readLines()
    val header = lines[0].split(',')
    val rows = lines.drop(1).map { line -> val fields = line.split(',', limit = Int.MAX_VALUE); Row(fields[0], fields.subList(1, fields.size - 2).map(String::toDouble), fields[fields.size - 2].ifEmpty { null }, fields.last().takeIf { it.isNotEmpty() }?.toDouble()) }
    return header.subList(1, header.size - 2) to rows
}
fun readDataset(): Dataset {
    val (features, train) = readRows("train.csv")
    val test = readRows("test.csv").second
    val settings = Settings(File("input/params.txt").readLines().associate { line -> val words = line.split(' '); words[0] to words.drop(1) })
    return Dataset(features, train, test, settings)
}
