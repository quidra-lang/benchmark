import java.io.File

data class Origin(val document: String, val line: Int)
data class Diagnostic(val origin: Origin, val code: String, val message: String)
data class Definition(val value: String, val origin: Origin, val number: Long, val history: List<Origin>)
data class Value(val kind: String, val text: String = "", val number: Long = 0, val flag: Boolean = false, val items: List<Value> = emptyList())
data class OutputKey(val definition: Definition, val spec: Spec?, val value: Value, val notation: String)
data class Parent(val section: String, val origin: Origin)
data class TreeEntry(val depth: Int, val text: String)
data class DiffEntry(val sign: String, val key: String, val before: OutputKey?, val after: OutputKey?)
data class ProfileDiff(val first: String, val second: String, val added: Int, val removed: Int, val changed: Int, val entries: List<DiffEntry>)
class CheckError(val code: String, message: String) : Exception(message)

val keyOrder: Comparator<String> = compareBy<String> { sectionOf(it) }.thenBy { keyName(it) }
fun sectionOf(key: String): String = key.substringBeforeLast('.')
fun keyName(key: String): String = key.substringAfterLast('.')
fun readLines(path: String): List<String> = File(path).readLines(Charsets.US_ASCII)

private val integerPattern = Regex("([+-]?)(?:0[xX]([0-9a-fA-F]{1,10})|([0-9](?:_?[0-9])*))")
private val sizePattern = Regex("([0-9]{1,6})(?:\\.([0-9]{1,3}))?([A-Za-z]*)")
private val secondsPattern = Regex("[0-9]{1,6}")
private val durationPattern = Regex("(?:([0-9]{1,6})h)?(?:([0-9]{1,6})m)?(?:([0-9]{1,6})s)?")
private val ipCharacters = Regex("[0-9.]*")
private val ipPart = Regex("0|[1-9][0-9]{0,2}")
private val hostLabel = Regex("[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?")
private val schemePattern = Regex("[A-Za-z][A-Za-z0-9+.-]*")
private val portPattern = Regex("[1-9][0-9]{0,4}")
private val datePattern = Regex("[0-9]{4}-[0-9]{2}-[0-9]{2}")
private val sizeFactors = mapOf("" to 1L, "b" to 1L, "kb" to 1024L, "mb" to 1048576L, "gb" to 1073741824L)

fun scalar(kind: String, text: String, values: List<String> = emptyList()): Value? {
    return when (kind) {
        "string" -> Value(kind, text = text)
        "int" -> {
            val match = integerPattern.matchEntire(text) ?: return null
            val digits = match.groupValues[3].replace("_", "")
            val number = if (match.groupValues[2].isNotEmpty()) match.groupValues[2].toLong(16) else {
                if (digits.length > 12) return null
                digits.toLong()
            }
            Value(kind, number = if (match.groupValues[1] == "-") -number else number)
        }
        "bool" -> when (text.lowercase()) {
            "true", "yes", "on", "1" -> Value(kind, flag = true)
            "false", "no", "off", "0" -> Value(kind, flag = false)
            else -> null
        }
        "enum" -> values.firstOrNull { it.equals(text, ignoreCase = true) }?.let { Value(kind, text = it) }
        "size" -> {
            val match = sizePattern.matchEntire(text) ?: return null
            val factor = sizeFactors[match.groupValues[3].lowercase()] ?: return null
            var number = match.groupValues[1].toLong() * factor
            val fraction = match.groupValues[2]
            if (fraction.isNotEmpty()) {
                var divisor = 1L
                repeat(fraction.length) { divisor *= 10 }
                val scaled = fraction.toLong() * factor
                if (scaled % divisor != 0L) return null
                number += scaled / divisor
            }
            Value(kind, number = number)
        }
        "duration" -> {
            if (secondsPattern.matches(text)) return Value(kind, number = text.toLong())
            val match = durationPattern.matchEntire(text) ?: return null
            if (text.isEmpty()) return null
            val numbers = match.groupValues.drop(1).map { if (it.isEmpty()) 0L else it.toLong() }
            Value(kind, number = numbers[0] * 3600 + numbers[1] * 60 + numbers[2])
        }
        "host" -> {
            val parts = text.split('.')
            if (ipCharacters.matches(text)) {
                if (parts.size != 4 || parts.any { !ipPart.matches(it) || it.toLong() > 255 }) return null
                Value(kind, text = text)
            } else {
                if (text.length > 253 || parts.any { !hostLabel.matches(it) }) return null
                Value(kind, text = text.lowercase())
            }
        }
        "path" -> {
            if (text.isEmpty() || text.any { it == ' ' || it == '\n' || it == '\t' }) return null
            val absolute = text.startsWith('/')
            val parts = mutableListOf<String>()
            for (part in text.split('/')) {
                if (part.isEmpty() || part == ".") continue
                when {
                    part != ".." -> parts += part
                    parts.isNotEmpty() && parts.last() != ".." -> parts.removeAt(parts.lastIndex)
                    absolute -> return null
                    else -> parts += part
                }
            }
            val path = parts.joinToString("/")
            Value(kind, text = if (absolute) "/$path" else path.ifEmpty { "." })
        }
        "url" -> {
            val delimiter = text.indexOf("://")
            if (delimiter < 0) return null
            val scheme = text.substring(0, delimiter).lowercase()
            val rest = text.substring(delimiter + 3)
            if (!schemePattern.matches(scheme) || '?' in rest || '#' in rest) return null
            val authority = rest.substringBefore('/')
            val path = scalar("path", "/" + rest.substringAfter('/', "")) ?: return null
            val host = scalar("host", authority.substringBefore(':')) ?: return null
            var result = "$scheme://${host.text}"
            if (':' in authority) {
                val port = authority.substringAfter(':')
                if (!portPattern.matches(port) || port.toLong() > 65535) return null
                val defaultPort = when (scheme) { "http" -> 80L; "https" -> 443L; else -> -1L }
                if (port.toLong() != defaultPort) result += ":$port"
            }
            Value(kind, text = result + path.text)
        }
        "date" -> {
            if (!datePattern.matches(text)) return null
            val year = text.substring(0, 4).toInt()
            val month = text.substring(5, 7).toInt()
            val day = text.substring(8).toInt()
            if (year < 1 || month !in 1..12) return null
            val days = intArrayOf(31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)
            if (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)) days[1] = 29
            if (day in 1..days[month - 1]) Value(kind, text = text) else null
        }
        else -> error("Unknown type $kind")
    }
}

class DocumentLibrary {
    private val cache = mutableMapOf<String, Document?>()
    fun find(name: String): Document? {
        if (name !in cache) {
            val file = File("input/conf/$name.ini")
            cache[name] = if (file.exists()) IniParser(name).parse(file.readLines(Charsets.US_ASCII)) else null
        }
        return cache[name]
    }
}

class Profile(val name: String, val root: String) {
    val configuration = mutableMapOf<String, Definition>()
    private val parents = mutableMapOf<String, Parent>()
    val tree = mutableListOf<TreeEntry>()
    private val reported = mutableSetOf<Diagnostic>()
    val outputs = mutableMapOf<String, OutputKey>()
    private var definitionCount = 0L
    var diagnostics: List<Diagnostic> = emptyList()
        private set
    val overridden = mutableListOf<String>()
    var errors = 0
        private set
    var warnings = 0
        private set
    var documentKeys = 0
        private set
    var manifestKeys = 0
        private set
    var defaultKeys = 0
        private set
    var dropped = 0
        private set

    fun report(origin: Origin, code: String, message: String) { reported += Diagnostic(origin, code, message) }
    fun define(key: String, value: String, origin: Origin) {
        val history = configuration[key]?.history.orEmpty().toMutableList()
        if (history.lastOrNull() != origin) history += origin
        configuration[key] = Definition(value, origin, ++definitionCount, history.toList())
    }
    fun apply(library: DocumentLibrary, documentName: String, chain: List<String>) {
        val document = requireNotNull(library.find(documentName))
        tree += TreeEntry(chain.size - 1, documentName)
        reported.addAll(document.diagnostics)
        for (statement in document.statements) {
            val origin = Origin(documentName, statement.line)
            val key = statement.target
            val value = statement.value
            when (statement.kind) {
                "assign" -> define(key, value, origin)
                "append" -> {
                    val previous = configuration[key]?.value
                    define(key, if (previous.isNullOrEmpty()) value else "$previous,$value", origin)
                }
                "unset" -> if (configuration.remove(key) == null) report(origin, "W_UNSET", "$key is not set")
                "inherit" -> parents[key] = Parent(value, origin)
                "include" -> {
                    val cycle = chain.indexOf(key)
                    if (cycle >= 0) {
                        report(origin, "E_INCLUDE_CYCLE", "include cycle " + (chain.drop(cycle) + key).joinToString(" -> "))
                        tree += TreeEntry(chain.size, "$key (cycle)")
                    } else if (library.find(key) == null) {
                        report(origin, "E_INCLUDE_MISSING", "missing document $key")
                        tree += TreeEntry(chain.size, "$key (missing)")
                    } else apply(library, key, chain + key)
                }
            }
        }
    }
    fun inheritSections() {
        val own = configuration.entries.groupBy { sectionOf(it.key) }.mapValues { (_, entries) ->
            entries.associate { keyName(it.key) to it.value }
        }
        for ((section, declaration) in parents) {
            val chain = mutableListOf(section)
            while (chain.last() in parents) {
                val parent = parents.getValue(chain.last()).section
                if (parent in chain) break
                chain += parent
            }
            if (chain.last() in parents) {
                chain += parents.getValue(chain.last()).section
                report(declaration.origin, "E_INHERIT_CYCLE", "inheritance cycle " + chain.joinToString(" -> "))
                continue
            }
            if (declaration.section !in parents && declaration.section !in own) {
                report(declaration.origin, "W_PARENT_EMPTY", "section $section inherits from empty section ${declaration.section}")
            }
            for (ancestor in chain.drop(1)) for ((key, definition) in own[ancestor].orEmpty()) {
                configuration.putIfAbsent("$section.$key", definition)
            }
        }
    }
    fun resolveAliases(schema: Schema) {
        for (spec in schema.specs) {
            if (!spec.has("alias")) continue
            val aliases = spec["alias"].split(',')
            if (aliases.none { it in configuration }) continue
            val candidates = (listOf(spec.pattern) + aliases).filter { it in configuration }
            var winner = candidates.first()
            for (key in candidates) if (configuration.getValue(key).number > configuration.getValue(winner).number) winner = key
            val chosen = configuration.getValue(winner)
            for (key in candidates) {
                val origin = configuration.getValue(key).origin
                if (key != spec.pattern) report(origin, "W_DEPRECATED", "$key is deprecated, use ${spec.pattern}")
                if (key != winner) report(origin, "W_SHADOWED", "$key is superseded by $winner at ${originText(chosen.origin)}")
            }
            configuration[spec.pattern] = chosen
            aliases.forEach { configuration.remove(it) }
        }
    }
    fun fillDefaults(schema: Schema): Set<String> {
        val sections = configuration.keys.map(::sectionOf).toSet()
        for (spec in schema.specs) if (spec.has("default")) {
            for (key in schema.targets(spec, sections)) if (key !in configuration) define(key, spec["default"], Origin("schema", spec.line))
        }
        return sections
    }
    private fun typeError(key: String, kind: String, text: String, spec: Spec, item: Boolean): CheckError {
        val display = (if (item) "item " else "") + checkedText(text, spec.has("secret"))
        return if (kind == "enum") CheckError("E_ENUM", "$key: $display is not one of ${spec["values"]}")
        else CheckError("E_TYPE", "$key: $display is not a valid $kind")
    }
    private fun normalize(key: String, text: String, spec: Spec, origin: Origin): Value {
        val value = if (spec.kind == "list") {
            var items = mutableListOf<Value>()
            if (text.trim(' ').isNotEmpty()) {
                val parts = text.split(',').map { it.trim(' ') }
                if ("" in parts) report(origin, "W_EMPTY_ITEM", "$key: empty list item ignored")
                for (part in parts) {
                    if (part.isEmpty()) continue
                    items += scalar(spec.item, part, spec.values) ?: throw typeError(key, spec.item, part, spec, true)
                }
            }
            if (spec.has("unique")) {
                val unique = items.distinctBy(::valueNotation)
                if (unique.size < items.size) report(origin, "W_DUPLICATE_ITEM", "$key: duplicate items removed")
                items = unique.toMutableList()
            }
            Value("list", items = items)
        } else scalar(spec.kind, text, spec.values) ?: throw typeError(key, spec.kind, text, spec, false)
        if (spec.has("range")) checkRange(key, value, spec)
        return value
    }
    private fun checkRange(key: String, value: Value, spec: Spec) {
        val bounds = spec["range"].split("..").toMutableList()
        val count = spec.kind == "string" || spec.kind == "list"
        val measure = when (spec.kind) {
            "string" -> value.text.length.toLong()
            "list" -> value.items.size.toLong()
            else -> value.number
        }
        val display = when {
            spec.kind == "string" -> "length $measure"
            spec.kind == "list" -> "count $measure"
            else -> shownNotation(valueNotation(value), spec.has("secret"))
        }
        var outside = false
        for (i in bounds.indices) {
            if (bounds[i].isEmpty()) continue
            if (spec.kind == "date") {
                outside = outside || if (i == 0) value.text < bounds[i] else value.text > bounds[i]
            } else {
                val bound = if (count) bounds[i].toLong() else requireNotNull(scalar(spec.kind, bounds[i])).number
                outside = outside || if (i == 0) measure < bound else measure > bound
                bounds[i] = bound.toString()
            }
        }
        if (outside) throw CheckError("E_RANGE", "$key: $display is out of range ${bounds.joinToString("..")}")
    }
    fun validate(schema: Schema) {
        val expanded = Expander(this).expandAll()
        for (key in configuration.keys.sortedWith(keyOrder)) {
            val text = expanded[key] ?: continue
            val definition = configuration.getValue(key)
            val spec = schema.find(key)
            val value = if (spec == null) {
                report(definition.origin, "W_UNKNOWN", "$key is not in the schema")
                Value("string", text = text)
            } else try { normalize(key, text, spec, definition.origin) }
            catch (error: CheckError) { report(definition.origin, error.code, requireNotNull(error.message)); continue }
            outputs[key] = OutputKey(definition, spec, value, valueNotation(value))
        }
    }
    fun checkOrder() {
        val removed = mutableListOf<String>()
        for (key in outputs.keys.sortedWith(keyOrder)) {
            val output = outputs.getValue(key)
            val spec = output.spec ?: continue
            if (!spec.has("le")) continue
            val limitKey = "${sectionOf(key)}.${spec["le"]}"
            val limit = outputs[limitKey] ?: continue
            if (limit.value.kind in listOf("int", "size", "duration") && output.value.number > limit.value.number) {
                report(output.definition.origin, "E_ORDER", "$key: ${shown(output)} is greater than $limitKey (${shown(limit)})")
                removed += key
            }
        }
        removed.forEach { outputs.remove(it) }
    }
    fun checkRequired(schema: Schema, sections: Set<String>) {
        for (spec in schema.specs) if (spec.has("required")) {
            for (key in schema.targets(spec, sections)) {
                if (key in configuration) continue
                var message = "$key is required"
                if (spec.has("when")) {
                    val conditionKey = "${sectionOf(key)}.${spec["when"]}"
                    val condition = outputs[conditionKey] ?: continue
                    if (condition.value.kind != "bool" || !condition.value.flag) continue
                    message += " when $conditionKey is true"
                }
                report(Origin(root, 0), "E_REQUIRED", message)
            }
        }
    }
    fun checkFixed(earlier: List<Profile>) {
        for (key in outputs.keys.sortedWith(keyOrder)) {
            val output = outputs.getValue(key)
            if (output.spec?.has("fixed") != true) continue
            val reference = earlier.firstOrNull { key in it.outputs } ?: continue
            if (reference.outputs.getValue(key).notation != output.notation) {
                report(output.definition.origin, "E_FIXED", "$key: value differs from profile ${reference.name}")
                outputs.remove(key)
            }
        }
    }
    fun finish() {
        diagnostics = reported.sortedWith(compareBy<Diagnostic> { it.origin.document }.thenBy { it.origin.line }.thenBy { it.code }.thenBy { it.message })
        errors = diagnostics.count { it.code.startsWith("E_") }
        warnings = diagnostics.size - errors
        for (key in outputs.keys.sortedWith(keyOrder)) {
            val definition = outputs.getValue(key).definition
            if (definition.history.size >= 2) overridden += key
            when (definition.origin.document) {
                "manifest" -> manifestKeys++
                "schema" -> defaultKeys++
                else -> documentKeys++
            }
        }
        dropped = configuration.size - outputs.size
    }
}

fun differences(first: Profile, second: Profile): ProfileDiff {
    val entries = mutableListOf<DiffEntry>()
    var added = 0
    var removed = 0
    var changed = 0
    for (key in (first.outputs.keys + second.outputs.keys).sortedWith(keyOrder)) {
        val before = first.outputs[key]
        val after = second.outputs[key]
        val sign = when {
            before == null -> { added++; "+" }
            after == null -> { removed++; "-" }
            before.notation != after.notation -> { changed++; "~" }
            else -> continue
        }
        entries += DiffEntry(sign, key, before, after)
    }
    return ProfileDiff(first.name, second.name, added, removed, changed, entries)
}

fun main() {
    val schema = Schema("input/schema.txt")
    val library = DocumentLibrary()
    val profiles = mutableListOf<Profile>()
    for ((index, line) in readLines("input/manifest.txt").withIndex()) {
        val words = line.split(' ')
        val profile = Profile(words[0], words[1])
        profile.apply(library, profile.root, listOf(profile.root))
        for (overrideText in words.drop(2)) profile.define(overrideText.substringBefore('='), overrideText.substringAfter('='), Origin("manifest", index + 1))
        profile.inheritSections()
        profile.resolveAliases(schema)
        val sections = profile.fillDefaults(schema)
        profile.validate(schema)
        profile.checkOrder()
        profile.checkRequired(schema, sections)
        profile.checkFixed(profiles)
        profile.finish()
        profiles += profile
    }
    writeOutputs(profiles, profiles.zipWithNext(::differences))
}
