data class Position(val file: String, val line: Int) {
    override fun toString(): String = "$file:$line"
}
data class Diagnostic(val position: Position, val kind: String, val message: String)
class PPError(val reason: String) : Exception(reason)
fun builtin(name: String): Boolean = name in listOf("__LINE__", "__FILE__", "__COUNTER__")
class Macro(val name: String, val parameters: List<String>?, val variadic: Boolean, val replacement: List<Token>, val position: Position, val main: Boolean) {
    var expanded = 0
    var tested = 0
    val signature: String get() = if (parameters == null) name else name + parameters.mapIndexed {
        i, parameter -> if (variadic && i == parameters.lastIndex) "..." else parameter
    }.joinToString(", ", "(", ")")
    val definition: String get() = "#define " + signature + if (replacement.isEmpty()) "" else " " + Lexer.render(replacement)
    fun identical(other: Macro): Boolean = parameters == other.parameters && variadic == other.variadic && replacement.size == other.replacement.size && replacement.zip(other.replacement).all {
        (a, b) -> a.text == b.text && a.space == b.space
    }
}
object Definitions {
    fun name(tokens: List<Token>, directive: String): String {
        val token = tokens.firstOrNull() ?: throw PPError("no macro name given in #$directive directive")
        if (token.kind != "identifier") throw PPError("macro names must be identifiers")
        if (token.text == "defined") throw PPError("\"defined\" cannot be used as a macro name")
        if (builtin(token.text)) throw PPError("cannot ${if (directive == "define") "redefine" else "undefine"} builtin macro \"${token.text}\"")
        return token.text
    }
    fun parse(tokens: List<Token>, position: Position, main: Boolean): Macro {
        val name = name(tokens, "define")
        val vaError = "\"__VA_ARGS__\" can only appear in the expansion of a variadic macro"
        if (name == "__VA_ARGS__") throw PPError(vaError)
        var i = 1
        var parameters: List<String>? = null
        var variadic = false
        if (tokens.size > 1 && tokens[1].text == "(" && !tokens[1].space) {
            i = 2
            val names = mutableListOf<String>()
            if (i < tokens.size && tokens[i].text == ")") i++
            else while (true) {
                if (i == tokens.size) throw PPError("missing ')' in macro parameter list")
                val token = tokens[i]
                if (token.text == "...") {
                    variadic = true
                    names.add("__VA_ARGS__")
                }
                else if (token.kind == "identifier") {
                    if (token.text == "__VA_ARGS__") throw PPError(vaError)
                    if (token.text in names) throw PPError("duplicate macro parameter \"${token.text}\"")
                    names.add(token.text)
                }
                else throw PPError("expected parameter name, found \"${token.text}\"")
                i++
                if (i == tokens.size) throw PPError("missing ')' in macro parameter list")
                if (tokens[i].text == ")") {
                    i++
                    break
                }
                if (variadic) throw PPError("expected ')' after \"...\", found \"${tokens[i].text}\"")
                if (tokens[i].text != ",") throw PPError("expected ',' or ')', found \"${tokens[i].text}\"")
                i++
            }
            parameters = names
        }
        val replacement = tokens.drop(i).mapIndexed {
            k, token -> if (k == 0) token.copy(space = false) else token
        }
        if (replacement.firstOrNull()?.text == "##" || replacement.lastOrNull()?.text == "##") throw PPError("'##' cannot appear at either end of a macro expansion")
        for ((k, token) in replacement.withIndex()) {
            if (token.kind == "identifier" && token.text == "__VA_ARGS__" && !variadic) throw PPError(vaError)
            if (token.text == "#" && parameters != null && (k + 1 == replacement.size || replacement[k + 1].kind != "identifier" || replacement[k + 1].text !in parameters)) throw PPError("'#' is not followed by a macro parameter")
        }
        return Macro(name, parameters, variadic, replacement, position, main)
    }
}
