import java.nio.file.Files
import java.nio.file.Path
import java.nio.charset.StandardCharsets
import kotlin.math.abs
object CnfIo {
    data class Formula(val variables: Int, val clauses: List<IntArray>)
    class Invalid(reason: String): RuntimeException(reason)
    fun number(value: String) = Regex("0|[1-9][0-9]{0,5}").matches(value)
    fun read(name: String): Formula {
        val lines = Files.readAllLines(Path.of("input",name),StandardCharsets.US_ASCII);
        var header = false;
        var variables = 0;
        var declared = 0;
        val clauses = mutableListOf<IntArray>();
        var clause = mutableListOf<Int>()
        for (i in lines.indices) {
            val line = lines[i];
            if (line.startsWith("c") || line.trim(' ').isEmpty()) continue;
            val tokens = line.trim(' ').split(Regex(" +"));
            if (tokens[0] == "p") {
                if (header) throw Invalid("duplicate header at line ${i + 1}");
                if (tokens.size != 4 || tokens[1] != "cnf" || !number(tokens[2]) || !number(tokens[3])) throw Invalid("bad header at line ${i + 1}");
                header = true;
                variables = tokens[2].toInt();
                declared = tokens[3].toInt()
            }
            else {
                if (!header) throw Invalid("missing header");
                for (token in tokens) {
                    if (!Regex("0|-?[1-9][0-9]{0,5}").matches(token)) throw Invalid("bad token $token at line ${i + 1}");
                    val literal = token.toInt();
                    if (abs(literal) > variables) throw Invalid("literal out of range $token at line ${i + 1}");
                    if (literal == 0) {
                        clauses.add(clause.toIntArray());
                        clause = mutableListOf()
                    } else clause.add(literal)
                }
            }
        }
        if (!header) throw Invalid("missing header");
        if (clause.isNotEmpty()) throw Invalid("unterminated clause");
        if (clauses.size != declared) throw Invalid("clause count mismatch header=$declared found=${clauses.size}");
        return Formula(variables,clauses)
    }
    fun modelLines(model: BooleanArray): List<String> {
        val tokens = (1 until model.size).map {
            if (model[it]) it.toString() else (-it).toString()
        }
        + "0";
        return tokens.chunked(10).map {
            "v " + it.joinToString(" ")
        }
    }
}
