private const val TOC = "\u0001toc\u0002"
private fun white(c: Char) = c == ' ' || c == '\n'
private fun alnum(c: Char) = c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9'
private fun label(c: Char) = alnum(c) || c == '-' || c == '_'
private fun punctuation(c: Char) = c in '!'..'/' || c in ':'..'@' || c in '['..'`' || c in '{'..'~'
private fun escape(text: String): String = buildString {
    for (c in text) append(when (c) {
        '&' -> "&amp;"
        '<' -> "&lt;"
        '>' -> "&gt;"
        '"' -> "&quot;"
        else -> c.toString()
    })
}
private fun stripTags(text: String): String = buildString {
    var at = 0
    while (at < text.length) {
        if (text[at] == '<') {
            val end = text.indexOf('>', at)
            if (end >= 0) { at = end + 1; continue }
        }
        append(text[at++])
    }
}
private fun normalize(text: String) = text.lowercase().split(' ', '\n').filter { it.isNotEmpty() }.joinToString(" ")
private fun skip(text: String, position: Int): Int {
    var at = position
    while (at < text.length && white(text[at])) at++
    return at
}
private fun escapedRead(text: String, position: Int, stops: String): Pair<String, Int> {
    var at = position
    val result = StringBuilder()
    while (at < text.length && text[at] !in stops) {
        if (text[at] == '\\' && at + 1 < text.length && punctuation(text[at + 1])) at++
        result.append(text[at++])
    }
    return result.toString() to at
}
private fun runEnd(text: String, position: Int): Int {
    var at = position
    val c = text[at]
    while (at < text.length && text[at] == c) at++
    return at
}
private fun tickCloser(text: String, position: Int, length: Int): Int? {
    var at = position
    while (at < text.length) {
        at = text.indexOf('`', at)
        if (at < 0) return null
        val end = runEnd(text, at)
        if (end - at == length) return at
        at = end
    }
    return null
}
private fun closingBracket(text: String, position: Int): Int? {
    var at = position
    var depth = 0
    while (at < text.length) {
        when (text[at]) {
            '\\' -> { at += 2; continue }
            '`' -> {
                val end = runEnd(text, at)
                at = tickCloser(text, end, end - at)?.plus(end - at) ?: end
                continue
            }
            '[' -> depth++
            ']' -> { depth--; if (depth == 0) return at }
        }
        at++
    }
    return null
}

private sealed interface Block
private data class Heading(val level: Int, val text: String) : Block
private data class Paragraph(val text: String) : Block
private data object Rule : Block
private data object Contents : Block
private data class Code(val language: String, val lines: List<String>) : Block
private data class Quote(val blocks: List<Block>) : Block
private data class Alert(val kind: String, val blocks: List<Block>) : Block
private data class ListBlock(val start: Int?, val items: List<List<Block>>) : Block
private data class Table(val align: List<String>, val header: List<String>, val rows: List<List<String>>) : Block
private data class Reference(val url: String, val title: String?)
private data class Marker(val kind: Char, val number: Int?, val content: String)
private data class Fence(val char: Char, val length: Int, val language: String)
private fun fence(text: String): Fence? {
    if (text.isEmpty() || text[0] !in "`~") return null
    val n = runEnd(text, 0)
    val info = text.substring(n).trim(' ')
    if (n < 3 || (text[0] == '`' && '`' in info)) return null
    return Fence(text[0], n, info.substringBefore(' '))
}
private fun atx(line: String): Heading? {
    val n = line.takeWhile { it == '#' }.length
    if (n !in 1..6 || (n < line.length && line[n] != ' ')) return null
    var text = line.substring(n).trim(' ')
    val unmarked = text.trimEnd('#')
    if (unmarked.isEmpty() || unmarked.endsWith(' ')) text = unmarked.trim(' ')
    return Heading(n, text)
}
private fun rule(text: String): Boolean {
    val compact = text.filter { it != ' ' }
    return compact.length >= 3 && compact[0] in "-*_" && compact.all { it == compact[0] }
}
private fun marker(text: String): Marker? {
    if (text.isEmpty() || rule(text)) return null
    val kind: Char
    val number: Int?
    var at: Int
    if (text[0] in "-*+") {
        kind = text[0]
        number = null
        at = 1
    } else {
        val n = text.takeWhile { it in '0'..'9' }.length
        if (n !in 1..9 || n == text.length || text[n] !in ".)") return null
        kind = text[n]
        number = text.substring(0, n).toInt()
        at = n + 1
    }
    if (at == text.length || text[at] != ' ') return null
    while (at < text.length && text[at] == ' ') at++
    return Marker(kind, number, text.substring(at))
}
private fun interrupt(text: String) = !text.startsWith(' ') &&
    (fence(text) != null || atx(text) != null || rule(text) || text.startsWith('>') || marker(text) != null)
private fun cells(line: String): List<String> {
    val text = line.trim(' ').removePrefix("|")
    val result = mutableListOf(StringBuilder())
    var at = 0
    var separator = false
    while (at < text.length) {
        val c = text[at++]
        separator = false
        if (c == '\\' && at < text.length) {
            if (text[at] != '|') result.last().append('\\')
            result.last().append(text[at++])
        } else if (c == '|') {
            result.add(StringBuilder())
            separator = true
        } else result.last().append(c)
    }
    if (separator) result.removeAt(result.lastIndex)
    return result.map { it.toString().trim(' ') }
}
private fun alignment(text: String): String? {
    val core = text.removePrefix(":").removeSuffix(":")
    if (core.isEmpty() || core.any { it != '-' }) return null
    return when {
        text.startsWith(':') && text.endsWith(':') -> "center"
        text.startsWith(':') -> "left"
        text.endsWith(':') -> "right"
        else -> ""
    }
}
// Definitions are collected recursively before inline conversion starts.
private class Parser {
    val references = mutableMapOf<String, Reference>()
    val footnotes = mutableMapOf<String, String>()

    private fun definition(text: String): Boolean {
        if (text.startsWith("[^")) {
            val end = text.indexOf("]:", 2)
            if (end >= 0) {
                val name = text.substring(2, end)
                val body = text.substring(end + 2).trim(' ')
                if (name.isNotEmpty() && name.all(::label) && body.isNotEmpty()) {
                    footnotes.putIfAbsent(name.lowercase(), body)
                    return true
                }
            }
        }
        if (!text.startsWith('[')) return false
        val close = text.indexOf(']')
        if (close < 0 || !text.startsWith(":", close + 1)) return false
        val name = text.substring(1, close)
        if ('[' in name || name.trim(' ').isEmpty() || name.startsWith('^')) return false
        val (url, end) = escapedRead(text, skip(text, close + 2), " ")
        if (url.isEmpty()) return false
        val at = skip(text, end)
        var title: String? = null
        if (at < text.length) {
            if (at == end || text[at] !in "\"'") return false
            val (value, stop) = escapedRead(text, at + 1, text[at].toString())
            if (stop != text.length - 1) return false
            title = value
        }
        references.putIfAbsent(normalize(name), Reference(url, title))
        return true
    }

    fun parse(lines: List<String>): List<Block> {
        val blocks = mutableListOf<Block>()
        var at = 0
        while (at < lines.size) {
            val line = lines[at]
            if (line.isEmpty()) { at++; continue }
            if (line.startsWith("    ")) {
                val start = at
                while (at < lines.size && (lines[at].isEmpty() || lines[at].startsWith("    "))) at++
                while (lines[at - 1].isEmpty()) at--
                blocks.add(Code("", lines.subList(start, at).map { if (it.isEmpty()) "" else it.substring(4) }))
                continue
            }
            if (!line.startsWith(' ')) {
                val fence = fence(line)
                if (fence != null) {
                    at++
                    val code = mutableListOf<String>()
                    while (at < lines.size) {
                        val row = lines[at++]
                        if (row.length >= fence.length && row.all { it == fence.char }) break
                        code.add(row)
                    }
                    blocks.add(Code(fence.language, code))
                    continue
                }
                val heading = atx(line)
                if (heading != null) { blocks.add(heading); at++; continue }
                if (rule(line)) { blocks.add(Rule); at++; continue }
                if (line.startsWith('>')) {
                    val content = mutableListOf<String>()
                    while (at < lines.size && lines[at].startsWith('>')) content.add(lines[at++].substring(1).removePrefix(" "))
                    val kind = content[0].removePrefix("[!").removeSuffix("]")
                    blocks.add(if (content[0] == "[!$kind]" && kind in listOf("NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"))
                        Alert(kind, parse(content.drop(1))) else Quote(parse(content)))
                    continue
                }
                val first = marker(line)
                if (first != null) {
                    var item = first
                    val items = mutableListOf<List<Block>>()
                    while (true) {
                        val content = mutableListOf(item.content)
                        at++
                        while (at < lines.size && lines[at].startsWith("  ")) content.add(lines[at++].substring(2))
                        items.add(parse(content))
                        var next = at
                        while (next < lines.size && lines[next].isEmpty()) next++
                        val following = lines.getOrNull(next)?.let(::marker)
                        if (following == null || following.kind != first.kind || (following.number != null) != (first.number != null)) break
                        item = following
                        at = next
                    }
                    blocks.add(ListBlock(first.number, items))
                    continue
                }
                if (definition(line)) { at++; continue }
                if (at + 1 < lines.size && '|' in line && '|' in lines[at + 1]) {
                    val header = cells(line)
                    val delimiters = cells(lines[at + 1])
                    val align = delimiters.map(::alignment)
                    if (header.size == delimiters.size && align.all { it != null }) {
                        at += 2
                        val rows = mutableListOf<List<String>>()
                        while (at < lines.size && '|' in lines[at]) {
                            val row = cells(lines[at++]).take(header.size).toMutableList()
                            while (row.size < header.size) row.add("")
                            rows.add(row)
                        }
                        blocks.add(Table(align.map { it!! }, header, rows))
                        continue
                    }
                }
            }
            val text = mutableListOf(line.trimStart(' '))
            at++
            var level = 0
            while (at < lines.size && lines[at].isNotEmpty()) {
                val row = lines[at]
                if (row.length >= 3 && row[0] in "=-" && row.all { it == row[0] }) {
                    level = if (row[0] == '=') 1 else 2
                    at++
                    break
                }
                if (interrupt(row)) break
                text.add(row.trimStart(' '))
                at++
            }
            val combined = text.joinToString("\n")
            blocks.add(if (level > 0) Heading(level, combined) else if (combined == "[TOC]") Contents else Paragraph(combined))
        }
        return blocks
    }
}

private data class Piece(val html: String = "", val delimiter: Char = '\u0000', val length: Int = 0, val open: Boolean = false, val close: Boolean = false)
private fun emphasis(pieces: List<Piece>, start: Int = 0, end: Int = pieces.size): String = buildString {
    var at = start
    while (at < end) {
        val piece = pieces[at]
        if (piece.delimiter == '\u0000') { append(piece.html); at++; continue }
        val close = if (piece.open) (at + 1 until end).firstOrNull {
            pieces[it].delimiter == piece.delimiter && pieces[it].length == piece.length && pieces[it].close
        } else null
        if (close == null) {
            append(piece.delimiter.toString().repeat(piece.length))
            at++
        } else {
            val tags = when {
                piece.delimiter == '~' -> "<del>" to "</del>"
                piece.length == 1 -> "<em>" to "</em>"
                piece.length == 2 -> "<strong>" to "</strong>"
                else -> "<em><strong>" to "</strong></em>"
            }
            append(tags.first).append(emphasis(pieces, at + 1, close)).append(tags.second)
            at = close + 1
        }
    }
}
private fun email(text: String): Boolean {
    val at = text.indexOf('@')
    if (at <= 0 || text.indexOf('@', at + 1) >= 0) return false
    val local = text.substring(0, at)
    val parts = text.substring(at + 1).split('.')
    return local.all { alnum(it) || it in ".+-_" } && parts.size >= 2 &&
        parts.all { part -> part.isNotEmpty() && part.all { alnum(it) || it == '-' } }
}
private data class HeadingEntry(val level: Int, val id: String, val text: String)
private class Renderer(private val references: Map<String, Reference>, private val footnotes: Map<String, String>) {
    private val usedIds = mutableSetOf<String>()
    private val headings = mutableListOf<HeadingEntry>()
    private val noteNumbers = mutableMapOf<String, Int>()
    private val noteNames = mutableListOf<String>()
    private val noteCounts = mutableListOf<Int>()

    private fun destination(text: String, at: Int, content: String): Pair<Reference, Int>? {
        if (text.startsWith("[", at)) {
            val end = text.indexOf(']', at + 1)
            if (end >= 0 && '[' !in text.substring(at + 1, end)) {
                val name = text.substring(at + 1, end).ifEmpty { content }
                // A complete reference suffix blocks shortcut fallback.
                return references[normalize(name)]?.let { it to end + 1 }
            }
        } else if (text.startsWith("(", at)) {
            val (url, end) = escapedRead(text, skip(text, at + 1), " \n)")
            var next = skip(text, end)
            var title: String? = null
            var valid = true
            if (next > end && next < text.length && text[next] in "\"'") {
                val (value, stop) = escapedRead(text, next + 1, text[next].toString())
                if (stop == text.length) valid = false else {
                    title = value
                    next = skip(text, stop + 1)
                }
            }
            if (valid && text.startsWith(")", next)) return Reference(url, title) to next + 1
        }
        return references[normalize(content)]?.let { it to at }
    }

    private fun inline(text: String, links: Boolean = true, notes: Boolean = true): String {
        val pieces = mutableListOf<Piece>()
        var at = 0
        while (at < text.length) {
            val c = text[at]
            if (c == '\\') {
                when {
                    at + 1 < text.length && punctuation(text[at + 1]) -> { pieces.add(Piece(escape(text.substring(at + 1, at + 2)))); at += 2 }
                    at + 1 < text.length && text[at + 1] == '\n' -> { pieces.add(Piece("<br />\n")); at += 2 }
                    else -> { pieces.add(Piece("\\")); at++ }
                }
                continue
            }
            if (c == '`') {
                val end = runEnd(text, at)
                val close = tickCloser(text, end, end - at)
                if (close == null) { pieces.add(Piece(text.substring(at, end))); at = end }
                else {
                    var code = text.substring(end, close).replace('\n', ' ')
                    if (code.startsWith(' ') && code.endsWith(' ') && code.any { it != ' ' }) code = code.substring(1, code.length - 1)
                    pieces.add(Piece("<code>${escape(code)}</code>"))
                    at = close + end - at
                }
                continue
            }
            if (links && c == '<') {
                val close = text.indexOf('>', at + 1)
                if (close >= 0) {
                    val target = text.substring(at + 1, close)
                    val clean = target.none { white(it) || it == '<' }
                    val href = when {
                        clean && ((target.startsWith("http://") && target.length > 7) || (target.startsWith("https://") && target.length > 8)) -> target
                        email(target) -> "mailto:$target"
                        else -> null
                    }
                    if (href != null) {
                        pieces.add(Piece("<a href=\"${escape(href)}\">${escape(target)}</a>"))
                        at = close + 1
                        continue
                    }
                }
            }
            if (links && (text.startsWith("http://", at) || text.startsWith("https://", at)) && (at == 0 || text[at - 1] in " \n*_~(")) {
                var end = at
                while (end < text.length && text[end] !in " \n<") end++
                while (end > at && text[end - 1] in ".,:;!?*_~)") end--
                val url = text.substring(at, end)
                if (url != "http://" && url != "https://") {
                    pieces.add(Piece("<a href=\"${escape(url)}\">${escape(url)}</a>"))
                    at = end
                    continue
                }
            }
            if (c == '[' || (c == '!' && text.getOrNull(at + 1) == '[')) {
                if (links && notes && text.startsWith("[^", at)) {
                    val close = text.indexOf(']', at + 2)
                    if (close >= 0) {
                        val name = text.substring(at + 2, close).lowercase()
                        if (name in footnotes) { pieces.add(Piece(noteReference(name))); at = close + 1; continue }
                    }
                }
                val image = c == '!'
                val opening = at + if (image) 1 else 0
                if (image || links) {
                    val close = closingBracket(text, opening)
                    if (close != null) {
                        val content = text.substring(opening + 1, close)
                        val dest = destination(text, close + 1, content)
                        if (dest != null) {
                            val (reference, end) = dest
                            val body = inline(content, false, false)
                            val title = reference.title?.let { " title=\"${escape(it)}\"" } ?: ""
                            val url = escape(reference.url)
                            val html = if (image) "<img src=\"$url\" alt=\"${stripTags(body)}\"$title />" else "<a href=\"$url\"$title>$body</a>"
                            pieces.add(Piece(html))
                            at = end
                            continue
                        }
                    }
                }
            }
            if (c in "*_~") {
                val end = runEnd(text, at)
                val n = end - at
                val before = text.getOrNull(at - 1) ?: ' '
                val after = text.getOrNull(end) ?: ' '
                var open = !white(after)
                var close = !white(before)
                if (c == '_' && alnum(before) && alnum(after)) { open = false; close = false }
                pieces.add(if ((c != '~' && n <= 3) || (c == '~' && n == 2)) Piece(delimiter = c, length = n, open = open, close = close) else Piece(text.substring(at, end)))
                at = end
                continue
            }
            pieces.add(Piece(escape(c.toString())))
            at++
        }
        return emphasis(pieces)
    }

    private fun blocks(blocks: List<Block>): String = buildString {
        for (block in blocks) append(render(block)).append('\n')
    }
    private fun render(block: Block): String = when (block) {
        is Heading -> heading(block.level, block.text)
        is Paragraph -> "<p>${inline(block.text)}</p>"
        Rule -> "<hr />"
        Contents -> TOC
        is Code -> {
            val attribute = if (block.language.isEmpty()) "" else " class=\"language-${escape(block.language)}\""
            "<pre><code$attribute>" + block.lines.joinToString("") { escape(it) + "\n" } + "</code></pre>"
        }
        is Quote -> "<blockquote>\n${blocks(block.blocks)}</blockquote>"
        is Alert -> {
            val name = block.kind.lowercase()
            val title = name.replaceFirstChar { it.uppercase() }
            "<div class=\"alert alert-$name\">\n<p class=\"alert-title\">$title</p>\n${blocks(block.blocks)}</div>"
        }
        is ListBlock -> {
            val tag = if (block.start == null) "ul" else "ol"
            val attribute = if (block.start != null && block.start != 1) " start=\"${block.start}\"" else ""
            "<$tag$attribute>\n" + block.items.joinToString("") { item(it) + "\n" } + "</$tag>"
        }
        is Table -> buildString {
            append("<table>\n<thead>\n<tr>\n").append(tableCells("th", block.align, block.header)).append("</tr>\n</thead>\n")
            if (block.rows.isNotEmpty()) {
                append("<tbody>\n")
                for (row in block.rows) append("<tr>\n").append(tableCells("td", block.align, row)).append("</tr>\n")
                append("</tbody>\n")
            }
            append("</table>")
        }
    }
    private fun item(blocks: List<Block>): String = buildString {
        append("<li>")
        for ((index, block) in blocks.withIndex()) {
            if (block is Paragraph) {
                val task = index == 0 && block.text.length > 4 && listOf("[ ] ", "[x] ", "[X] ").any { block.text.startsWith(it) }
                if (task) append(if (block.text[1] == ' ') "<input type=\"checkbox\" disabled=\"\" /> " else "<input type=\"checkbox\" checked=\"\" disabled=\"\" /> ")
                append(inline(if (task) block.text.substring(4) else block.text))
            } else {
                if (last() != '\n') append('\n')
                append(render(block)).append('\n')
            }
        }
        append("</li>")
    }
    private fun tableCells(tag: String, align: List<String>, cells: List<String>): String = buildString {
        for ((i, cell) in cells.withIndex()) {
            val style = if (align[i].isEmpty()) "" else " style=\"text-align:${align[i]}\""
            append("<$tag$style>${inline(cell)}</$tag>\n")
        }
    }
    private fun heading(level: Int, source: String): String {
        var text = source
        var id: String? = null
        val at = source.lastIndexOf(" {#")
        if (at >= 0 && source.endsWith('}')) {
            val candidate = source.substring(at + 3, source.length - 1)
            if (candidate.isNotEmpty() && candidate.all(::label)) {
                id = candidate
                text = source.substring(0, at).trimEnd(' ')
            }
        }
        if (id == null) {
            val base = buildString {
                for (c in source.lowercase()) {
                    if (label(c)) append(c) else if (white(c)) append('-')
                }
            }.ifEmpty { "heading" }
            id = base
            var suffix = 1
            while (id in usedIds) id = "$base-${suffix++}"
        }
        usedIds.add(id)
        val html = inline(text)
        headings.add(HeadingEntry(level, id, stripTags(html)))
        return "<h$level id=\"$id\">$html</h$level>"
    }
    private fun tocList(children: List<List<Int>>, entries: List<Int>): String = buildString {
        append("<ul>\n")
        for (i in entries) {
            val heading = headings[i]
            append("<li><a href=\"#${heading.id}\">${heading.text}</a>")
            if (children[i].isNotEmpty()) append('\n').append(tocList(children, children[i])).append('\n')
            append("</li>\n")
        }
        append("</ul>")
    }
    private fun toc(): String {
        if (headings.isEmpty()) return "<nav class=\"toc\">\n</nav>"
        val roots = mutableListOf<Int>()
        val parents = mutableListOf<Int>()
        val children = List(headings.size) { mutableListOf<Int>() }
        for ((i, heading) in headings.withIndex()) {
            while (parents.isNotEmpty() && headings[parents.last()].level >= heading.level) parents.removeAt(parents.lastIndex)
            if (parents.isEmpty()) roots.add(i) else children[parents.last()].add(i)
            parents.add(i)
        }
        return "<nav class=\"toc\">\n${tocList(children, roots)}\n</nav>"
    }
    private fun referenceId(index: Int, count: Int) = "fnref-${index + 1}" + if (count == 1) "" else "-$count"
    private fun noteReference(name: String): String {
        val index = noteNumbers.getOrPut(name) {
            noteNames.add(name)
            noteCounts.add(0)
            noteNames.lastIndex
        }
        noteCounts[index]++
        return "<sup id=\"${referenceId(index, noteCounts[index])}\"><a href=\"#fn-${index + 1}\">${index + 1}</a></sup>"
    }
    private fun noteList(): String = buildString {
        append("<section class=\"footnotes\">\n<ol>\n")
        for (i in noteNames.indices) {
            val body = inline(footnotes.getValue(noteNames[i]), notes = false)
            append("<li id=\"fn-${i + 1}\">$body")
            for (count in 1..noteCounts[i]) append(" <a href=\"#${referenceId(i, count)}\">&#8617;</a>")
            append("</li>\n")
        }
        append("</ol>\n</section>\n")
    }
    fun document(blocks: List<Block>): String {
        // Headings have all been converted before a TOC placeholder is replaced.
        val html = this.blocks(blocks).replace(TOC, toc())
        return html + if (noteNames.isEmpty()) "" else noteList()
    }
}
fun main() {
    val lines = generateSequence(::readLine).takeWhile { it != "@@END@@" }.toList()
    val parser = Parser()
    val blocks = parser.parse(lines)
    print(Renderer(parser.references, parser.footnotes).document(blocks))
}
