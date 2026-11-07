import java.io.File
class SourceFile(source: String) {
    val lines = Lexer.lex(source)
    val physicalLines = source.count {
        it == '\n'
    }
    val guardName = IncludeManager.guardName(lines)
    var entered = 0; var skipped = 0; var output = 0; var skippedLines = 0; var once = false
}
class IncludeManager {
    val files = mutableMapOf<String, SourceFile>(); val order = mutableListOf<String>()
    fun enter(path: String): SourceFile {
        val file = files.getOrPut(path) {
            order.add(path); SourceFile(File("input/$path").readText())
        }; file.entered++; return file
    }
    companion object {
        fun search(name: String, quoted: Boolean): String? {
            if (quoted && File("input/$name").isFile) return name; val path = "include/$name"; return path.takeIf {
                File("input/$it").isFile
            }
        }
        fun guardName(original: List<LogicalLine>): String? {
            val lines = original.filter {
                it.tokens.isNotEmpty()
            }; val first = lines.firstOrNull()?.tokens ?: return null; val last = lines.last().tokens
            if (first.size != 3 || first[0].text != "#" || first[1].text != "ifndef" || first[2].kind != "identifier" || last.size != 2 || last[0].text != "#" || last[1].text != "endif") return null
            var depth = 0
            for ((i, line) in lines.withIndex()) {
                val tokens = line.tokens; val directive = if (tokens.size >= 2 && tokens[0].text == "#" && tokens[1].kind == "identifier") tokens[1].text else ""; if (depth == 1 && directive in listOf("elif", "elifdef", "elifndef", "else")) return null; if (directive in listOf("if", "ifdef", "ifndef")) depth++ else if (directive == "endif") depth--; if (depth == 0 && i + 1 != lines.size) return null
            }
            return if (depth == 0) first[2].text else null
        }
    }
}
