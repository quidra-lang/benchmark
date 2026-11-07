val diagnosticCodes = listOf("SYNTAX", "ORPHAN", "DUPLICATE", "KEY_NO_DECOMP", "KEY_UNREACHABLE", "SYNON_UNUSED", "PRE_CHAIN", "SYNON_UNKNOWN", "RULE_NO_REASM", "RULE_SHADOWED", "REF_UNBOUND", "TARGET_UNDEFINED", "TARGET_CYCLE")
val errorCodes = setOf("SYNTAX", "ORPHAN", "DUPLICATE", "SYNON_UNKNOWN", "REF_UNBOUND", "TARGET_UNDEFINED", "TARGET_CYCLE")

fun references(text: String): List<Int> = (0 until text.length - 2).filter { isReference(text.substring(it, it + 3)) }.map { text[it + 1] - '0' }

fun lint(script: Script): List<Diagnostic> {
    val found = script.diagnostics.toMutableList()
    fun add(line: Int, code: String, message: String) { found += Diagnostic(line, code, message) }
    val replacementWords = script.pres.flatMap { it.replacement }.toSet()
    val targets = script.items.filter { it.kind == "GOTO" || it.kind == "RESTATE" }.map { it.arguments[0] }.toSet()
    val usedGroups = script.rules.flatMap { it.pattern }.filter { it.startsWith("@") }.map { it.drop(1) }.toSet()
    val graph = script.keywords.associate { keyword -> keyword.word to keyword.decomps.flatMap { script.rules[it].items }.map { script.items[it] }.filter { (it.kind == "GOTO" || it.kind == "RESTATE") && it.arguments[0] in script.keywordMap }.map { it.arguments[0] } }
    fun reaches(start: String, goal: String): Boolean {
        val seen = mutableSetOf<String>()
        val pending = mutableListOf(start)
        while (pending.isNotEmpty()) {
            val word = pending.removeAt(pending.lastIndex)
            if (word == goal) return true
            if (seen.add(word)) pending.addAll(graph.getValue(word))
        }
        return false
    }
    fun unknown(pattern: List<String>) = pattern.filter { it.startsWith("@") && it.drop(1) !in script.groupWords }
    for (keyword in script.keywords) {
        if (keyword.decomps.isEmpty()) add(keyword.line, "KEY_NO_DECOMP", "keyword ${keyword.word} has no DECOMP")
        if (keyword.word in script.pre && keyword.word !in replacementWords && keyword.word !in targets) add(keyword.line, "KEY_UNREACHABLE", "keyword ${keyword.word} is replaced by PRE")
        for (rules in listOf(keyword.memories, keyword.decomps)) for ((position, ruleId) in rules.withIndex()) {
            val rule = script.rules[ruleId]
            for (element in unknown(rule.pattern)) add(rule.line, "SYNON_UNKNOWN", "unknown group ${element.drop(1)}")
            if (rule.items.isEmpty()) add(rule.line, "RULE_NO_REASM", "rule has no reassembly")
            if (unknown(rule.pattern).isEmpty()) {
                val shadow = rules.take(position).map { script.rules[it] }.firstOrNull { unknown(it.pattern).isEmpty() && patternCovers(it.pattern, rule.pattern, script.groupWords) }
                if (shadow != null) add(rule.line, "RULE_SHADOWED", "pattern is shadowed by line ${shadow.line}")
            }
            val wildcards = rule.pattern.count(::isWildcard)
            for (itemId in rule.items) {
                val item = script.items[itemId]
                val refs = when (item.kind) {
                    "REASM" -> references(item.text)
                    "RESTATE" -> item.arguments.drop(1).filter(::isReference).map { it[1] - '0' }
                    else -> emptyList()
                }
                for (reference in refs) if (reference == 0 || reference > wildcards) add(item.line, "REF_UNBOUND", "reference ($reference) is not bound")
                if (item.kind == "GOTO" || item.kind == "RESTATE") {
                    val target = item.arguments[0]
                    if (target !in script.keywordMap) add(item.line, "TARGET_UNDEFINED", "target $target is not a keyword")
                    else if (reaches(target, keyword.word)) add(item.line, "TARGET_CYCLE", "edge ${keyword.word} -> $target is on a cycle")
                }
            }
        }
    }
    for (group in script.groups) if (group.name !in usedGroups) add(group.line, "SYNON_UNUSED", "group ${group.name} is never used")
    for (pre in script.pres) for (word in pre.replacement) if (word in script.pre) add(pre.line, "PRE_CHAIN", "replacement $word is itself replaced by PRE")
    return found.sortedWith(compareBy<Diagnostic> { it.line }.thenBy { diagnosticCodes.indexOf(it.code) })
}

fun lintLines(diagnostics: List<Diagnostic>): List<String> {
    if (diagnostics.isEmpty()) return listOf("OK")
    val errors = diagnostics.count { it.code in errorCodes }
    return diagnostics.map { "${it.line} ${it.code} ${it.message}" } + "TOTAL ${diagnostics.size} errors=$errors warnings=${diagnostics.size - errors}"
}
