import java.io.File
class ModelError(val line: Int, val reason: String) : Exception(reason)
data class Term(val name: String, val coefficient: F)
data class Constraint(val line: Int, val name: String, val terms: List<Term>, val comparison: String, val rhs: F)
data class BoundLine(val line: Int, val name: String, val kind: String, val lower: F?, val upper: F?)
data class Declaration(val line: Int, val names: List<String>)
data class Parsed(val name: String, var maximize: Boolean = false, var objective: List<Term> = emptyList(), val constraints: MutableList<Constraint> = mutableListOf(), val bounds: MutableList<BoundLine> = mutableListOf(), val integers: MutableList<Declaration> = mutableListOf(), val binaries: MutableList<Declaration> = mutableListOf(), var error: ModelError? = null)
data class Params(val level: Int, val limit: Int, val levels: Map<String, Int>, val limits: Map<String, Int>)
object LPParser {
    fun name(word: String): Boolean = word.matches(Regex("[a-z][a-z0-9_]*")) && word !in listOf("bounds", "integer", "binary", "free", "inf")
    fun expression(words: List<String>): List<Term>? {
        val terms = mutableListOf<Term>(); var i = 0; var sign = F(1)
        if (words.firstOrNull() == "-") {
            i++; sign = F(-1)
        }
        while (i < words.size) {
            val coefficient = F.read(words[i]); val variable: String; val value: F
            if (coefficient != null) {
                if (i + 1 >= words.size || !name(words[i + 1])) return null; variable = words[i + 1]; value = coefficient; i += 2
            }
            else if (name(words[i])) {
                variable = words[i++]; value = F(1)
            } else return null
            terms.add(Term(variable, sign * value)); if (i == words.size) return terms
            if (words[i] !in listOf("+", "-")) return null; sign = F(if (words[i++] == "+") 1 else -1)
        }
        return null
    }
    fun named(words: List<String>): Pair<String, List<Term>>? {
        if (words.size < 2 || !words[0].endsWith(":")) return null
        val name = words[0].dropLast(1); if (!this.name(name)) return null
        return expression(words.drop(1))?.let {
            Pair(name, it)
        }
    }
    fun constraint(words: List<String>, line: Int): Constraint? {
        if (words.size < 4 || words[words.size - 2] !in listOf("<=", ">=", "=")) return null
        val rhs = F.read(words.last(), true) ?: return null
        val named = named(words.dropLast(2)) ?: return null
        return Constraint(line, named.first, named.second, words[words.size - 2], rhs)
    }
    fun bound(words: List<String>, line: Int): BoundLine? {
        if (words.size == 2 && name(words[0]) && words[1] == "free") return BoundLine(line, words[0], "both", null, null)
        if (words.size == 3 && name(words[0])) {
            val value = F.read(words[2], true)
            if (words[1] == ">=" && (value != null || words[2] == "-inf")) return BoundLine(line, words[0], "lower", value, null)
            if (words[1] == "<=" && (value != null || words[2] == "inf")) return BoundLine(line, words[0], "upper", null, value)
            if (words[1] == "=" && value != null) return BoundLine(line, words[0], "both", value, value)
        }
        if (words.size == 5 && words[1] == "<=" && words[3] == "<=" && name(words[2])) {
            val lower = F.read(words[0], true); val upper = F.read(words[4], true)
            if ((lower != null || words[0] == "-inf") && (upper != null || words[4] == "inf")) return BoundLine(line, words[2], "both", lower, upper)
        }
        return null
    }
    fun parse(name: String, body: List<Pair<Int, String>>, end: Int): Parsed {
        val result = Parsed(name); var state = "A"
        for ((line, text) in body) {
            val words = text.split(' '); var accepted = false
            when (state) {
                "A" -> if (text in listOf("maximize", "minimize")) {
                    result.maximize = text == "maximize"; state = "B"; accepted = true
                }
                "B" -> {
                    val value = named(words); if (value != null) {
                        result.objective = value.second; state = "C"; accepted = true
                    }
                }
                "C" -> if (text == "subject to") {
                    state = "D"; accepted = true
                }
                "D", "E" -> {
                    if (state == "E" && text in listOf("bounds", "integer", "binary")) {
                        state = when (text) {
                            "bounds" -> "F"; "integer" -> "G"; else -> "H"
                        }; accepted = true
                    }
                    else {
                        val value = constraint(words, line); if (value != null) {
                            result.constraints.add(value); state = "E"; accepted = true
                        }
                    }
                }
                "F" -> if (text in listOf("integer", "binary")) {
                    state = if (text == "integer") "G" else "H"; accepted = true
                } else {
                    val value = bound(words, line); if (value != null) {
                        result.bounds.add(value); accepted = true
                    }
                }
                "G", "H" -> if (state == "G" && text == "binary") {
                    state = "H"; accepted = true
                } else if (words.all {
                    this.name(it)
                }) {
                    (if (state == "G") result.integers else result.binaries).add(Declaration(line, words)); accepted = true
                }
            }
            if (!accepted) {
                result.error = ModelError(line, "syntax error"); return result
            }
        }
        if (state in listOf("A", "B", "C", "D")) result.error = ModelError(end, "syntax error")
        return result
    }
    fun read(): List<Parsed> {
        val result = mutableListOf<Parsed>(); var name: String? = null; val body = mutableListOf<Pair<Int, String>>()
        for ((i, text) in File("input/models.lp").readLines().withIndex()) {
            if (text.isEmpty() || text.startsWith("#")) continue
            if (name == null) {
                name = text.split(' ')[1]; body.clear()
            }
            else if (text == "end") {
                result.add(parse(name, body, i + 1)); name = null
            } else body.add(Pair(i + 1, text))
        }
        return result
    }
    fun params(): Params {
        val lines = File("input/params.txt").readLines(); val levels = mutableMapOf<String, Int>(); val limits = mutableMapOf<String, Int>()
        for (text in lines.drop(2)) if (text.isNotEmpty()) {
            val words = text.split(' '); (if (words[0] == "log") levels else limits)[words[1]] = words[2].toInt()
        }
        return Params(lines[0].split(' ')[1].toInt(), lines[1].split(' ')[1].toInt(), levels, limits)
    }
}
