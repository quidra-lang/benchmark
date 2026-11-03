private val namePattern = Regex("[a-z][a-z0-9_]*")
private val sectionPattern = Regex("[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*")
fun isSectionName(text: String): Boolean = sectionPattern.matches(text)

data class Statement(val kind: String, val line: Int, val target: String, val value: String = "")
data class Document(val statements: List<Statement>, val diagnostics: List<Diagnostic>)

private fun trimmed(source: List<String>): MutableList<String> = source.toMutableList().apply {
    this[0] = first().trimStart(' ')
    this[lastIndex] = last().trimEnd(' ')
}

class IniParser(private val name: String) {
    private var section = ""
    private var base = ""
    private val statements = mutableListOf<Statement>()
    private val diagnostics = mutableListOf<Diagnostic>()
    private val assigned = mutableMapOf<String, Int>()

    private fun report(line: Int, code: String, message: String) {
        diagnostics += Diagnostic(Origin(name, line), code, message)
    }
    private fun add(kind: String, line: Int, target: String, value: String = "") {
        statements += Statement(kind, line, target, value)
    }
    fun parse(physical: List<String>): Document {
        for (line in logicalLines(physical)) interpret(line)
        return Document(statements, diagnostics)
    }
    private fun interpret(line: LogicalLine) {
        if (line.code.isNotEmpty()) { report(line.number, line.code, line.message); return }
        val segments = trimmed(line.segments)
        val first = segments.first()
        when {
            segments.size == 1 && first.isEmpty() -> return
            first.startsWith('[') -> header(line.number, segments)
            first.startsWith('@') -> directive(line.number, segments)
            else -> assignment(line.number, segments)
        }
    }
    private fun header(line: Int, segments: List<String>) {
        val text = segments.first()
        val inside = if (text.length >= 2) text.substring(1, text.lastIndex) else ""
        val colon = inside.indexOf(':')
        val name = (if (colon < 0) inside else inside.substring(0, colon)).trim(' ')
        val parent = if (colon < 0) "" else inside.substring(colon + 1).trim(' ')
        val relative = name.startsWith('.') && isSectionName(name.substring(1))
        val error = when {
            segments.size != 1 || !text.endsWith(']') || (colon >= 0 && !isSectionName(parent)) || (!relative && !isSectionName(name)) -> "invalid section header"
            relative && base.isEmpty() -> "relative section without base"
            else -> ""
        }
        if (error.isNotEmpty()) { report(line, "E_SECTION", error); section = ""; return }
        if (relative) section = base + name else { section = name; base = name }
        if (colon >= 0) add("inherit", line, section, parent)
    }
    private fun directive(line: Int, segments: List<String>) {
        val words = segments.first().split(Regex(" +"))
        if (segments.size != 1 || words.size != 2 || words[0] !in listOf("@include", "@unset") || !namePattern.matches(words[1])) {
            report(line, "E_SYNTAX", "invalid directive")
        } else if (words[0] == "@include") add("include", line, words[1])
        else if (section.isEmpty()) report(line, "E_NO_SECTION", "no current section")
        else add("unset", line, "$section.${words[1]}")
    }
    private fun assignment(line: Int, source: List<String>) {
        if (source.indices.step(2).none { '=' in source[it] }) { report(line, "E_SYNTAX", "invalid line"); return }
        val equals = source.first().indexOf('=')
        if (equals < 0) { report(line, "E_SYNTAX", "invalid key"); return }
        var key = source.first().substring(0, equals).trim(' ')
        val append = key.endsWith('+')
        if (append) key = key.dropLast(1).trimEnd(' ')
        if (!namePattern.matches(key)) { report(line, "E_SYNTAX", "invalid key"); return }
        val segments = trimmed(listOf(source.first().substring(equals + 1)) + source.drop(1))
        val value = when {
            segments.size == 1 -> segments.first()
            segments.size == 3 && segments.first().isEmpty() && segments.last().isEmpty() -> segments[1]
            else -> { report(line, "E_SYNTAX", "invalid value"); return }
        }
        if (section.isEmpty()) { report(line, "E_NO_SECTION", "no current section"); return }
        val fullKey = "$section.$key"
        if (!append) {
            assigned.put(fullKey, line)?.let { report(line, "W_DUPLICATE", "$fullKey already set at line $it") }
        }
        add(if (append) "append" else "assign", line, fullKey, value)
    }
}
