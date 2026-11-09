import java.io.File

const val MASK = "********"

fun stringNotation(text: String): String = "\"" + text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n").replace("\t", "\\t") + "\""
fun valueNotation(value: Value): String = when (value.kind) {
    "string" -> stringNotation(value.text)
    "int", "size", "duration" -> value.number.toString()
    "bool" -> value.flag.toString()
    "list" -> value.items.joinToString(", ", "[", "]", transform = ::valueNotation)
    else -> value.text
}
fun originText(origin: Origin): String = "${origin.document}:${origin.line}"
fun shownNotation(notation: String, secret: Boolean): String = if (secret) MASK else notation
fun checkedText(text: String, secret: Boolean): String = shownNotation(stringNotation(text), secret)
fun shown(output: OutputKey): String = shownNotation(output.notation, output.spec?.has("secret") == true)

private fun normalizedBlock(profile: Profile): String {
    val lines = mutableListOf("profile ${profile.name}")
    var previous = ""
    for (key in profile.outputs.keys.sortedWith(keyOrder)) {
        val section = sectionOf(key)
        if (section != previous) { lines += "[$section]"; previous = section }
        lines += "${keyName(key)} = ${shown(profile.outputs.getValue(key))}"
    }
    return lines.joinToString("\n")
}
private fun diagnosticsBlock(profile: Profile): String {
    val lines = mutableListOf("profile ${profile.name} errors ${profile.errors} warnings ${profile.warnings}")
    for (diagnostic in profile.diagnostics) lines += "${originText(diagnostic.origin)} ${diagnostic.code} ${diagnostic.message}"
    return lines.joinToString("\n")
}
private fun diffBlock(diff: ProfileDiff): String {
    val lines = mutableListOf("diff ${diff.first} -> ${diff.second}: ${diff.added} added, ${diff.removed} removed, ${diff.changed} changed")
    for (entry in diff.entries) lines += when (entry.sign) {
        "+" -> "+ ${entry.key} = ${shown(requireNotNull(entry.after))}"
        "-" -> "- ${entry.key} = ${shown(requireNotNull(entry.before))}"
        else -> "~ ${entry.key}: ${shown(requireNotNull(entry.before))} -> ${shown(requireNotNull(entry.after))}"
    }
    return lines.joinToString("\n")
}
private fun reportBlock(profile: Profile): String {
    val lines = mutableListOf("profile ${profile.name}", "includes")
    for (entry in profile.tree) lines += " ".repeat(2 + 2 * entry.depth) + entry.text
    lines += "overridden"
    for (key in profile.overridden) {
        val history = profile.outputs.getValue(key).definition.history.joinToString(" -> ", transform = ::originText)
        lines += "  $key: $history"
    }
    if (profile.overridden.isEmpty()) lines += "  (none)"
    lines += "keys ${profile.outputs.size} documents ${profile.documentKeys} manifest ${profile.manifestKeys} defaults ${profile.defaultKeys}"
    lines += "dropped ${profile.dropped}"
    lines += "errors ${profile.errors} warnings ${profile.warnings}"
    return lines.joinToString("\n")
}
fun writeOutputs(profiles: List<Profile>, diffs: List<ProfileDiff>) {
    File("output").mkdirs()
    val blocks = mapOf(
        "normalized.txt" to profiles.map(::normalizedBlock),
        "diagnostics.txt" to profiles.map(::diagnosticsBlock),
        "report.txt" to profiles.map(::reportBlock),
        "diff.txt" to diffs.map(::diffBlock)
    )
    for ((name, content) in blocks) File("output", name).writeText(content.joinToString("\n\n") + "\n", Charsets.US_ASCII)
}
