private val fields = "author editor title journal booktitle edition volume number pages publisher institution school address howpublished month year doi note".split(' ')
private val types = "article book inproceedings incollection techreport phdthesis misc".split(' ')
private val required = listOf(
    "author title journal year", "author title publisher year", "author title booktitle year",
    "author title booktitle publisher year", "author title institution year", "author title school year", "author title year"
).map { it.split(' ') }
private val months = "January February March April May June July August September October November December".split(' ')
private val monthMacros = "jan feb mar apr may jun jul aug sep oct nov dec".split(' ')
private val monthShort = "Jan. Feb. Mar. Apr. May June July Aug. Sep. Oct. Nov. Dec.".split(' ')
private val smallWords = "a an and as at but by for from in into nor of on or over per so the to up via with yet".split(' ').toSet()

private fun lower(c: Char) = c in 'a'..'z'
private fun upper(c: Char) = c in 'A'..'Z'
private fun letter(c: Char) = lower(c) || upper(c)
private fun digit(c: Char) = c in '0'..'9'
private fun lowercase(c: Char) = if (upper(c)) c + 32 else c
private fun uppercase(c: Char) = if (lower(c)) c - 32 else c
private fun lowerText(text: String) = text.map(::lowercase).joinToString("")
private fun plain(text: String) = text.replace("{", "").replace("}", "")
private fun letters(text: String) = lowerText(text.filter(::letter))
private fun digits(text: String) = text.isNotEmpty() && text.all(::digit)

private fun splitDepth(text: String, separator: String): MutableList<String> {
    val result = mutableListOf<String>()
    var start = 0
    var i = 0
    var depth = 0
    while (i < text.length) {
        if (depth == 0 && text.startsWith(separator, i)) {
            result += text.substring(start, i)
            i += separator.length
            start = i
        } else {
            if (text[i] == '{') depth++
            if (text[i] == '}') depth--
            i++
        }
    }
    result += text.substring(start)
    return result
}

private class Problem(message: String) : RuntimeException(message)
private class LoadProblem(val line: Int, message: String) : RuntimeException(message)

private fun evaluate(expression: String, macros: Map<String, String>, line: Int): String {
    var depth = 0
    for (c in expression) {
        if (c == '{') depth++
        if (c == '}') depth--
        if (depth < 0) throw LoadProblem(line, "unbalanced braces")
    }
    if (depth != 0) throw LoadProblem(line, "unbalanced braces")
    return buildString {
        for (term in expression.split(" # ")) when {
            term[0] == '{' || term[0] == '"' -> append(term.substring(1, term.length - 1))
            digit(term[0]) -> append(term)
            else -> append(macros[term] ?: throw LoadProblem(line, "unknown macro '$term'"))
        }
    }
}

private data class Accent(val value: Char, val width: Int)
private fun accent(text: String, at: Int): Accent? {
    if (at + 1 >= text.length || text[at] != '\\') return null
    val command = text[at + 1]
    if (command == '&') return Accent('&', 2)
    val symbol = command in "'\"`^~=."
    if (symbol && at + 2 < text.length && letter(text[at + 2])) return Accent(text[at + 2], 3)
    if ((symbol || command in "cuvH") && at + 4 < text.length && text[at + 2] == '{' && letter(text[at + 3]) && text[at + 4] == '}') return Accent(text[at + 3], 5)
    return null
}

private fun normalize(text: String): String {
    val result = buildString {
        var i = 0
        while (i < text.length) {
            val wrapped = if (text[i] == '{') accent(text, i + 1) else null
            if (wrapped != null && i + wrapped.width + 1 < text.length && text[i + wrapped.width + 1] == '}') {
                append(wrapped.value)
                i += wrapped.width + 2
            } else {
                val current = accent(text, i)
                if (current == null) append(text[i++]) else {
                    append(current.value)
                    i += current.width
                }
            }
        }
    }
    return result.replace('~', ' ').split(' ').filter { it.isNotEmpty() }.joinToString(" ")
}

private data class Name(val first: String, val von: String, val last: String, val jr: String) {
    companion object {
        fun parse(text: String): Name {
            val parts = splitDepth(text, ",").map { it.trim() }
            val words = splitDepth(parts.first(), " ")
            val lowerWords = (0 until words.lastIndex).filter { lower(words[it][0]) }
            val firstLower = lowerWords.firstOrNull() ?: -1
            val lastLower = lowerWords.lastOrNull() ?: -1
            fun joined(from: Int, until: Int) = words.subList(from, until).joinToString(" ")
            if (parts.size == 1) {
                if (firstLower < 0) return Name(joined(0, words.lastIndex), "", words.last(), "")
                return Name(joined(0, firstLower), joined(firstLower, lastLower + 1), joined(lastLower + 1, words.size), "")
            }
            return Name(parts.last(), if (lastLower < 0) "" else joined(0, lastLower + 1), joined(lastLower + 1, words.size), if (parts.size == 3) parts[1] else "")
        }
    }
    fun surname() = plain(if (von.isEmpty()) last else "$von $last")
    fun initials() = plain(first).split(' ').filter { it.isNotEmpty() }.joinToString(" ") { word ->
        word.split('-').joinToString("-") { piece -> "${uppercase(piece.first(::letter))}." }
    }
    fun text(inverted: Boolean, abbreviated: Boolean): String {
        val given = if (abbreviated) initials() else plain(first)
        var result = surname()
        if (first.isNotEmpty()) result = if (inverted) "$result, $given" else "$given $result"
        if (jr.isNotEmpty()) result += ", ${plain(jr)}"
        return result
    }
}

private data class NameList(val names: List<Name>, val etAl: Boolean) {
    companion object {
        fun parse(text: String): NameList {
            val parts = splitDepth(text, " and ")
            val etAl = parts.last() == "others"
            return NameList((if (etAl) parts.dropLast(1) else parts).map(Name::parse), etAl)
        }
    }
    fun single() = names.size == 1 && !etAl
}

private enum class Style { APA, IEEE, CHICAGO, MLA }
private fun titleCase(title: String, style: Style): String {
    if (style == Style.IEEE) return title
    if (style == Style.APA) {
        val result = title.toCharArray()
        var depth = 0
        for (i in result.indices) {
            val c = result[i]
            when {
                c == '{' -> depth++
                c == '}' -> depth--
                depth == 0 && letter(c) -> result[i] = if (i == 0 || i >= 2 && title.substring(i - 2, i) == ": ") uppercase(c) else lowercase(c)
            }
        }
        return result.concatToString()
    }
    val words = splitDepth(title, " ")
    for (i in words.indices) {
        val word = words[i]
        if (word.startsWith('{')) continue
        val makeLower = i > 0 && i < words.lastIndex && !words[i - 1].endsWith(':') && letters(word) in smallWords
        val result = word.toCharArray()
        var depth = 0
        var firstLetter = true
        for (j in result.indices) {
            val c = result[j]
            when {
                c == '{' -> depth++
                c == '}' -> depth--
                letter(c) -> {
                    if (depth == 0 && makeLower) result[j] = lowercase(c)
                    else if (depth == 0 && firstLetter) result[j] = uppercase(c)
                    firstLetter = false
                }
            }
        }
        words[i] = result.concatToString()
    }
    return words.joinToString(" ")
}

private fun listed(names: List<String>, conjunction: String, listB: Boolean): String = when {
    names.size == 1 -> names.first()
    listB && names.size == 2 -> "${names.first()} $conjunction ${names.last()}"
    else -> "${names.dropLast(1).joinToString(", ")}, $conjunction ${names.last()}"
}

private fun renderNames(list: NameList, style: Style, editor: Boolean): String {
    val names = list.names.mapIndexed { i, name -> name.text(!editor && (style == Style.APA || style != Style.IEEE && i == 0), style == Style.APA || style == Style.IEEE) }
    if (editor) return if (list.etAl) "${names.first()} et al." else listed(names, if (style == Style.APA) "&" else "and", true)
    return when (style) {
        Style.APA -> when {
            list.etAl -> "${names.joinToString(", ")}, et al."
            names.size >= 21 -> "${names.take(19).joinToString(", ")}, . . . ${names.last()}"
            else -> listed(names, "&", false)
        }
        Style.IEEE -> if (list.etAl || names.size >= 7) "${names.first()} et al." else listed(names, "and", true)
        Style.CHICAGO -> if (list.etAl || names.size >= 11) "${names.take(7).joinToString(", ")}, et al." else listed(names, "and", false)
        Style.MLA -> if (list.etAl || names.size >= 3) "${names.first()}, et al." else listed(names, "and", false)
    }
}

private class Entry(val key: String, val kind: Int, source: Map<String, String>) {
    val values = source.toMap()
    val authors = values["author"]?.let(NameList::parse)
    val editors = values["editor"]?.let(NameList::parse)
    val primary get() = authors ?: editors!!
    val sortLast = lowerText(plain(primary.names.first().last))
    val year = plain(values.getValue("year"))
    val plainTitle = plain(values.getValue("title"))
    val lowerTitle = lowerText(plainTitle)
    val sortTitle = listOf("a ", "an ", "the ").firstOrNull { lowerTitle.startsWith(it) }?.let { lowerTitle.removePrefix(it) } ?: lowerTitle
    val baseKey = letters(plain(primary.names.first().last)) + values.getValue("year").filter(::digit) +
        (plainTitle.split(' ').asSequence().map(::letters).firstOrNull { it.isNotEmpty() && it !in smallWords } ?: "")
    var suffix = ""
    fun yearLabel(style: Style) = year + if (style == Style.APA || style == Style.CHICAGO) suffix else ""
    fun shortName(style: Style, parenthetical: Boolean): String {
        if (primary.etAl || primary.names.size >= if (style == Style.CHICAGO) 4 else 3) return "${primary.names.first().surname()} et al."
        return listed(primary.names.map(Name::surname), if (style == Style.APA && parenthetical) "&" else "and", true)
    }
    fun unknownFields() = values.keys.filter { it !in fields }.sorted()
}

private val bibliography = compareBy<Entry>({ it.sortLast }, { it.year }, { it.sortTitle }, { it.key })
private val templates = listOf(
    listOf(
        "{author}. ({year}). {title}. {journal}<, {volume}<({number})>><, {pages}>.< https://doi.org/{doi}>",
        "{author}. ({year}). {title}< ({edition})>. {publisher}.",
        "{author}. ({year}). {title}. In <{editor} ({eds}), >{booktitle}< ({pp})>.< {publisher}.>",
        "{author}. ({year}). {title}< (Report No. {number})>. {institution}.",
        "{author}. ({year}). {title} [Doctoral dissertation, {school}].",
        "{author}. ({year}<, {month}>). {title}.< {howpublished}.>< {note}.>"
    ), listOf(
        "{author}, \"{title},\" {journal}<, vol. {volume}><, no. {number}><, {pp}>, <{mon} >{year}<, doi: {doi}>.",
        "{author}, {title}<, {edition}>. <{address}: >{publisher}, {year}.",
        "{author}, \"{title},\" in {booktitle}<, {editor}, {eds}><, {address}><, {publisher}>, {year}<, {pp}>.",
        "{author}, \"{title},\" {institution}<, {address}>, Tech. Rep.< {number}>, {year}.",
        "{author}, \"{title},\" Ph.D. dissertation, {school}<, {address}>, {year}.",
        "{author}, \"{title},\"< {howpublished},> <{mon} >{year}.< {note}.>"
    ), listOf(
        "{author}. {year}. \"{title}.\" {journal}< {volume}>< ({number})><: {pages}>.< https://doi.org/{doi}.>",
        "{author}. {year}. {title}.< {edition}.> <{address}: >{publisher}.",
        "{author}. {year}. \"{title}.\" In {booktitle}<, edited by {editor}><, {pages}>.< <{address}: >{publisher}.>",
        "{author}. {year}. {title}. Technical Report< {number}>. <{address}: >{institution}.",
        "{author}. {year}. \"{title}.\" PhD diss., {school}.",
        "{author}. {year}. {title}.< {howpublished}.>< {note}.>"
    ), listOf(
        "{author}. \"{title}.\" {journal}<, vol. {volume}><, no. {number}>, <{mon} >{year}<, {pp}>.< https://doi.org/{doi}.>",
        "{author}. {title}.< {edition},> {publisher}, {year}.",
        "{author}. \"{title}.\" {booktitle},< edited by {editor},>< {publisher},> {year}<, {pp}>.",
        "{author}. {title}. {institution}, {year}.< Technical Report {number}.>",
        "{author}. {title}. {year}. {school}, PhD dissertation.",
        "{author}. {title}.< {howpublished},> <{mon} >{year}.< {note}.>"
    )
)

private fun optionalEnd(pattern: String, start: Int): Int {
    var depth = 1
    var i = start
    while (depth > 0) {
        i++
        if (pattern[i] == '<') depth++
        if (pattern[i] == '>') depth--
    }
    return i
}

private fun optionalPresent(pattern: String, start: Int, end: Int, values: Map<String, String>): Boolean {
    var i = start
    while (i < end) {
        when (pattern[i]) {
            '<' -> i = optionalEnd(pattern, i)
            '{' -> {
                val close = pattern.indexOf('}', i)
                if (values[pattern.substring(i + 1, close)].isNullOrEmpty()) return false
                i = close
            }
        }
        i++
    }
    return true
}

private fun renderTemplate(pattern: String, start: Int, end: Int, values: Map<String, String>, result: StringBuilder) {
    var i = start
    while (i < end) {
        val c = pattern[i]
        when (c) {
            '<' -> {
                val close = optionalEnd(pattern, i)
                if (optionalPresent(pattern, i + 1, close, values)) renderTemplate(pattern, i + 1, close, values, result)
                i = close
            }
            '{' -> {
                val close = pattern.indexOf('}', i)
                result.append(values[pattern.substring(i + 1, close)] ?: "")
                i = close
            }
            else -> if (c != '.' || result.isEmpty() || result.last() !in ".?!") result.append(c)
        }
        i++
    }
}

private fun reference(entry: Entry, style: Style, number: Int, repeated: Boolean): String {
    val values = fields.associateWith { plain(entry.values[it] ?: "") }.toMutableMap()
    var author = if (repeated) "---" else renderNames(entry.primary, style, false)
    if (entry.authors == null) {
        val annotations = listOf(listOf(" (Ed.)", " (Eds.)"), listOf(", Ed.", ", Eds."), listOf(", ed.", ", eds."), listOf(", editor", ", editors"))
        author += annotations[style.ordinal][if (entry.primary.single()) 0 else 1]
    }
    values["author"] = author
    entry.editors?.let {
        values["editor"] = renderNames(it, style, true)
        values["eds"] = if (it.single()) "Ed." else "Eds."
    }
    values["title"] = plain(titleCase(entry.values.getValue("title"), style))
    values["year"] = entry.yearLabel(style)
    entry.values["pages"]?.let {
        val pages = plain(it).replace("--", "-")
        values["pages"] = pages
        values["pp"] = (if ('-' in pages) "pp. " else "p. ") + pages
    }
    entry.values["edition"]?.let {
        var edition = plain(it)
        if (digits(edition)) {
            val n = edition.toInt()
            val suffix = if (n % 100 in 11..13) "th" else when (n % 10) { 1 -> "st"; 2 -> "nd"; 3 -> "rd"; else -> "th" }
            edition = "$n$suffix"
        }
        values["edition"] = "$edition ed."
    }
    entry.values["month"]?.let {
        val month = plain(it)
        val index = months.indexOf(month)
        values["mon"] = if (index < 0) month else monthShort[index]
    }
    val kind = when { entry.kind == 3 -> 2; entry.kind > 3 -> entry.kind - 1; else -> entry.kind }
    val pattern = templates[style.ordinal][kind]
    val result = StringBuilder(if (style == Style.IEEE) "[$number] " else "")
    renderTemplate(pattern, 0, pattern.length, values, result)
    return result.toString()
}

private data class Numbering(val order: List<Entry>, val numbers: Map<Entry, Int>)
private enum class CitationKind { PARENTHETICAL, NARRATIVE, AUTHOR, YEAR }
private data class Citation(val start: Int, val end: Int, val kind: CitationKind, val entries: List<Entry>)

private class Database(lines: List<String>) {
    val entries = mutableListOf<Entry>()
    val record = mutableListOf<Entry>()
    val lookup = sortedMapOf<String, Entry>()
    val macros = monthMacros.zip(months).toMap().toMutableMap()
    val output = mutableListOf<String>()
    var macroCount = 0

    init {
        var i = 0
        while (i < lines.size) {
            val line = lines[i]
            when {
                line.isEmpty() || line.startsWith('%') -> Unit
                line.startsWith("@string{") -> {
                    val equals = line.indexOf(" = ")
                    val name = line.substring(8, equals)
                    try {
                        val value = evaluate(line.substring(equals + 3, line.length - 1), macros, i + 1)
                        if (name in macros) throw LoadProblem(i + 1, "duplicate macro")
                        macros[name] = value
                        macroCount++
                    } catch (error: LoadProblem) { report(name, error) }
                }
                else -> {
                    var end = i + 1
                    while (lines[end] != "}") end++
                    val brace = line.indexOf('{')
                    val kind = line.substring(1, brace)
                    val key = line.substring(brace + 1, line.length - 1)
                    try { readEntry(lines, i, end, kind, key) } catch (error: LoadProblem) { report(key, error) }
                    i = end
                }
            }
            i++
        }
        output += "LOADED entries=${entries.size} macros=$macroCount errors=${output.size}"
        val assigned = mutableSetOf<Entry>()
        for (entry in entries) {
            if (entry in assigned) continue
            val group = entries.filter { it.primary == entry.primary && it.values["year"] == entry.values["year"] }
                .sortedWith(compareBy({ it.sortTitle }, { it.key }))
            assigned.addAll(group)
            if (group.size >= 2) group.forEachIndexed { index, item -> item.suffix = ('a' + index).toString() }
        }
    }
    private fun report(name: String, error: LoadProblem) { output += "ERROR line ${error.line}: $name: ${error.message}" }
    private fun readEntry(lines: List<String>, start: Int, end: Int, kindName: String, key: String) {
        val kind = types.indexOf(kindName)
        if (kind < 0) throw LoadProblem(start + 1, "unknown type '$kindName'")
        if (key in lookup) throw LoadProblem(start + 1, "duplicate key")
        val values = mutableMapOf<String, String>()
        for (i in start + 1 until end) {
            val equals = lines[i].indexOf(" = ")
            val name = lines[i].substring(2, equals)
            val expression = lines[i].substring(equals + 3).removeSuffix(",")
            val value = evaluate(expression, macros, i + 1)
            if (name in values) throw LoadProblem(i + 1, "duplicate field '$name'")
            values[name] = normalize(value)
        }
        for (name in required[kind]) if (name !in values && !(kind == 1 && name == "author" && "editor" in values)) throw LoadProblem(end + 1, "missing field '$name'")
        val entry = Entry(key, kind, values)
        entries += entry
        lookup[key] = entry
    }
    private fun numbering(): Numbering {
        val cited = record.toSet()
        val order = record + lookup.values.filter { it !in cited }
        return Numbering(order, order.mapIndexed { index, entry -> entry to index + 1 }.toMap())
    }
    private fun citationText(citation: Citation, style: Style, numbers: Map<Entry, Int>): String {
        val parenthetical = citation.kind == CitationKind.PARENTHETICAL
        if (citation.kind == CitationKind.AUTHOR || citation.kind == CitationKind.YEAR || style == Style.MLA || style == Style.IEEE && !parenthetical) {
            val text = citation.entries.joinToString(if (citation.kind == CitationKind.YEAR) ", " else "; ") { entry ->
                if (citation.kind == CitationKind.YEAR) entry.yearLabel(style)
                else entry.shortName(style, false) + if (style == Style.IEEE && citation.kind == CitationKind.NARRATIVE) " [${numbers.getValue(entry)}]" else ""
            }
            return if (style == Style.MLA && parenthetical) "($text)" else text
        }
        val parts = mutableListOf<String>()
        if (style == Style.IEEE) {
            val sorted = citation.entries.map { numbers.getValue(it) }.sorted()
            var i = 0
            while (i < sorted.size) {
                var end = i + 1
                while (end < sorted.size && sorted[end] == sorted[end - 1] + 1) end++
                if (end - i >= 3) parts += "[${sorted[i]}]-[${sorted[end - 1]}]"
                else for (j in i until end) parts += "[${sorted[j]}]"
                i = end
            }
            return parts.joinToString(", ")
        }
        val entries = if (parenthetical) citation.entries.sortedWith(bibliography) else citation.entries
        var i = 0
        while (i < entries.size) {
            val name = entries[i].shortName(style, parenthetical)
            var end = i + 1
            while (end < entries.size && entries[end].shortName(style, parenthetical) == name) end++
            val years = entries.subList(i, end).joinToString(", ") { it.yearLabel(style) }
            parts += if (parenthetical) name + (if (style == Style.APA) ", " else " ") + years else "$name ($years)"
            i = end
        }
        val text = parts.joinToString("; ")
        return if (parenthetical) "($text)" else text
    }
    private fun cite(style: Style, text: String): String {
        val citations = mutableListOf<Citation>()
        var start = text.indexOf('\\')
        while (start >= 0) {
            val brace = text.indexOf('{', start)
            val end = text.indexOf('}', brace)
            val kind = when (text.substring(start + 1, brace)) {
                "citet" -> CitationKind.NARRATIVE
                "citeauthor" -> CitationKind.AUTHOR
                "citeyear" -> CitationKind.YEAR
                else -> CitationKind.PARENTHETICAL
            }
            val seen = linkedSetOf<Entry>()
            for (key in text.substring(brace + 1, end).split(',')) seen += lookup[key] ?: throw Problem("unknown key '$key'")
            citations += Citation(start, end + 1, kind, seen.toList())
            start = text.indexOf('\\', end + 1)
        }
        val recorded = record.toMutableSet()
        for (citation in citations) for (entry in citation.entries) if (recorded.add(entry)) record += entry
        val numbers = numbering().numbers
        return buildString {
            var position = 0
            for (citation in citations) {
                append(text, position, citation.start)
                append(citationText(citation, style, numbers))
                position = citation.end
            }
            append(text, position, text.length)
        }
    }
    private fun keygen(): List<String> {
        val counts = entries.groupingBy { it.baseKey }.eachCount()
        val used = mutableMapOf<String, Int>()
        return entries.map {
            var key = it.baseKey
            if (counts.getValue(key) >= 2) {
                val index = used[key] ?: 0
                used[key] = index + 1
                key += 'a' + index
            }
            "${it.key} -> $key"
        }
    }
    private fun check(): List<String> {
        val result = mutableListOf<String>()
        val titles = mutableMapOf<String, String>()
        for (entry in entries) {
            val warnings = mutableListOf<String>()
            entry.values["pages"]?.let {
                val pages = plain(it)
                if ('-' in pages && "--" !in pages) warnings += "pages use a single hyphen"
                val parts = pages.split('-').filter(String::isNotEmpty)
                if (parts.size == 2 && parts.all(::digits) && parts[0].toInt() > parts[1].toInt()) warnings += "pages are reversed"
            }
            if (entry.year.length != 4 || !digits(entry.year)) warnings += "year is not 4 digits"
            if (entry.plainTitle.none(::lower) && entry.plainTitle.count(::upper) >= 2) warnings += "title is all caps"
            if (entry.kind == 0 && "doi" !in entry.values) warnings += "article has no doi"
            val earlier = titles[entry.lowerTitle]
            if (earlier != null) warnings += "same title as $earlier" else titles[entry.lowerTitle] = entry.key
            for (field in entry.unknownFields()) warnings += "unknown field '$field'"
            result += warnings.map { "WARN ${entry.key}: $it" }
        }
        result += "CHECK warnings=${result.size}"
        return result
    }
    private fun export(key: String): List<String> {
        val entry = lookup[key] ?: throw Problem("unknown key '$key'")
        val names = fields.filter { it in entry.values } + entry.unknownFields()
        return listOf("@${types[entry.kind]}{$key,") + names.mapIndexed { index, name ->
            "  $name = {${entry.values.getValue(name)}}" + if (index == names.lastIndex) "" else ","
        } + "}"
    }
    private fun stats(): List<String> {
        val typeCounts = entries.groupingBy { types[it.kind] }.eachCount().toSortedMap()
        val yearCounts = entries.groupingBy { it.year }.eachCount().toSortedMap()
        val authors = mutableSetOf<String>()
        val pairs = sortedMapOf<Pair<String, String>, Int>(compareBy({ it.first }, { it.second }))
        for (entry in entries) entry.authors?.let { list ->
            val names = list.names.map { it.text(false, false) }.distinct().sorted()
            authors.addAll(names)
            for (a in names.indices) for (b in a + 1 until names.size) {
                val pair = names[a] to names[b]
                pairs[pair] = (pairs[pair] ?: 0) + 1
            }
        }
        val result = mutableListOf("ENTRIES ${entries.size}")
        result += typeCounts.map { (type, count) -> "TYPE $type $count" }
        result += yearCounts.map { (year, count) -> "YEAR $year $count" }
        result += "AUTHORS ${authors.size}"
        val best = pairs.entries.maxByOrNull { it.value }
        result += if (best == null) "PAIR none" else "PAIR ${best.key.first} & ${best.key.second} ${best.value}"
        return result
    }
    fun command(line: String): List<String> {
        val command = line.substringBefore(' ')
        val words = line.split(' ', limit = if (command == "CITE" || command == "SEARCH") 3 else 0)
        val arity = when (command) {
            "FORMAT" -> -1
            "BIBLIOGRAPHY", "EXPORT" -> 1
            "CITE", "SEARCH" -> 2
            "KEYGEN", "CHECK", "STATS" -> 0
            else -> throw Problem("unknown command '$command'")
        }
        if (if (arity == -1) words.size < 3 else words.size != arity + 1) throw Problem("wrong number of arguments")
        val style = if (command in listOf("FORMAT", "BIBLIOGRAPHY", "CITE"))
            Style.entries.firstOrNull { it.name == words[1] } ?: throw Problem("unknown style '${words[1]}'") else Style.APA
        return when (command) {
            "FORMAT" -> {
                val numbers = numbering().numbers
                words.drop(2).map { key -> lookup[key]?.let { reference(it, style, numbers.getValue(it), false) } ?: "ERROR unknown key '$key'" }
            }
            "BIBLIOGRAPHY" -> {
                val numbering = numbering()
                val order = if (style == Style.IEEE) numbering.order else numbering.order.sortedWith(bibliography)
                listOf(if (style == Style.MLA) "Works Cited" else "References") + order.mapIndexed { index, entry ->
                    val repeated = index > 0 && (style == Style.CHICAGO || style == Style.MLA) && entry.primary == order[index - 1].primary
                    reference(entry, style, numbering.numbers.getValue(entry), repeated)
                }
            }
            "CITE" -> listOf(cite(style, words[2]))
            "KEYGEN" -> keygen()
            "CHECK" -> check()
            "EXPORT" -> export(words[1])
            "STATS" -> stats()
            else -> {
                val needle = lowerText(words[2])
                val matches = entries.filter { words[1] in it.values && needle in lowerText(plain(it.values.getValue(words[1]))) }.map { it.key }
                listOf(if (matches.isEmpty()) "MATCHES 0" else "MATCHES ${matches.size}: ${matches.joinToString(" ")}")
            }
        }
    }
}

fun main() {
    val reader = System.`in`.bufferedReader(Charsets.US_ASCII)
    val lines = mutableListOf<String>()
    while (true) {
        val line = reader.readLine()
        if (line == "%%") break
        lines += line
    }
    val database = Database(lines)
    val writer = System.out.bufferedWriter(Charsets.UTF_8)
    fun write(line: String) { writer.write(line); writer.write("\n") }
    database.output.forEach(::write)
    repeat(reader.readLine().toInt()) {
        try { database.command(reader.readLine()).forEach(::write) }
        catch (error: Problem) { write("ERROR ${error.message}") }
    }
    writer.flush()
}
