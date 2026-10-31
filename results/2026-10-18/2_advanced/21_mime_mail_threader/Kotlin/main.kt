import java.io.File

private val CHECKED_FIELDS = listOf("From", "To", "Cc", "Subject", "Date", "Message-ID", "In-Reply-To", "References", "MIME-Version", "Content-Type", "Content-Transfer-Encoding", "Content-Disposition")
private val HIDDEN_TAGS = setOf("head", "style", "script")
private val PARAGRAPH_TAGS = setOf("p", "div", "ul", "ol", "table", "tr", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6")
private val CHARACTER_REFERENCES = mapOf("amp" to "&", "lt" to "<", "gt" to ">", "quot" to "\"", "apos" to "'", "nbsp" to " ")
data class Sections(val header: List<SourceLine>, val body: List<SourceLine>)
data class SortKey(val invalidDate: Int, val seconds: Long, val id: String, val number: Int) : Comparable<SortKey> {
    override fun compareTo(other: SortKey): Int {
        var result = invalidDate.compareTo(other.invalidDate)
        if (result == 0) result = seconds.compareTo(other.seconds)
        if (result == 0) result = id.compareTo(other.id)
        return if (result == 0) number.compareTo(other.number) else result
    }
}
class Entity(val number: String) {
    var type = "text"
    var subtype = "plain"
    var disposition: String? = null
    var filename: String? = null
    var content = ""
    var parameters: Map<String, String> = emptyMap()
    var children: MutableList<Entity>? = null
    fun parameter(name: String) = parameters[name] ?: ""
}
class Message(val number: Int) {
    val problems = mutableListOf<String>()
    var sender: Mailbox? = null
    var to = emptyList<String>()
    var cc = emptyList<String>()
    var references = mutableListOf<String>()
    var subject = ""
    var baseSubject = ""
    var id = ""
    var reply = false
    var date: Long? = null
    lateinit var body: Entity
    lateinit var sortKey: SortKey
    var thread = 0
    var depth = 0
    var parent: Message? = null
    fun problem(text: String) { problems.add(text) }
    fun process(lines: List<SourceLine>, knownIds: MutableMap<String, Int>) {
        val sections = sections(lines)
        val header = Headers.parseFields(sections.header)
        for (line in header.invalid) problem("bad header line $line")
        for (name in CHECKED_FIELDS) if (header.count(name) > 1) problem("duplicate $name")
        readSender(header.value("From"))
        to = readRecipients(header.value("To"), "To")
        cc = readRecipients(header.value("Cc"), "Cc")
        readSubject(header.value("Subject"))
        readDate(header.value("Date"))
        readId(header.value("Message-ID"), knownIds)
        references = extractIds(header.value("References") ?: "").toMutableList()
        val replies = extractIds(header.value("In-Reply-To") ?: "")
        if (replies.isNotEmpty() && (references.isEmpty() || references.last() != replies.first())) references.add(replies.first())
        val mime = mimeEnabled(header.value("MIME-Version"))
        body = parseEntity("1", header, sections.body, mime)
        sortKey = SortKey(if (date == null) 1 else 0, date ?: 0L, id, number)
    }
    private fun readSender(value: String?) {
        if (value == null) { problem("missing From"); return }
        val parsed = Addresses.parse(value)
        if (parsed == null || parsed.addresses.size != 1 || parsed.addresses[0] !is Mailbox) { problem("bad From"); return }
        sender = parsed.addresses[0] as Mailbox
        if (parsed.encodingError) problem("bad encoded word in From")
    }
    private fun readRecipients(value: String?, name: String): List<String> {
        if (value == null) return emptyList()
        val parsed = Addresses.parse(value)
        if (parsed == null) { problem("bad $name"); return emptyList() }
        val recipients = mutableListOf<String>()
        for (address in parsed.addresses) when (address) {
            is Mailbox -> recipients.add(address.address)
            is AddressGroup -> recipients.addAll(address.mailboxes.map { (it as Mailbox).address })
        }
        if (parsed.encodingError) problem("bad encoded word in $name")
        return recipients
    }
    private fun readSubject(value: String?) {
        val decoded = Headers.unstructured(value ?: "")
        subject = decoded.text
        if (decoded.error) problem("bad encoded word in Subject")
        baseSubject = subject
        while (baseSubject.length >= 3 && baseSubject.substring(0, 3).lowercase() == "re:") { baseSubject = baseSubject.substring(3).trimStart(' '); reply = true }
    }
    private fun readDate(value: String?) {
        if (value == null) { problem("missing Date"); return }
        val parsed = Dates.parse(value)
        if (parsed.error == null) date = parsed.seconds else problem(parsed.error)
    }
    private fun readId(value: String?, known: MutableMap<String, Int>) {
        when {
            value == null -> problem("missing Message-ID")
            !messageId(value) -> problem("bad Message-ID")
            value in known -> problem("Message-ID already used by message ${known.getValue(value)}")
            else -> { id = value; known[value] = number }
        }
    }
    private fun mimeEnabled(value: String?): Boolean {
        if (value == null) return false
        val text = Headers.removeComments(value)
        if (text != null && text.replace(" ", "").replace("\t", "") == "1.0") return true
        problem("bad MIME-Version")
        return false
    }
    private fun parseEntity(number: String, header: Header, lines: List<SourceLine>, mime: Boolean): Entity {
        val entity = Entity(number)
        val contentType = header.value("Content-Type")
        if (mime && contentType != null) {
            val parsed = Headers.parameters(contentType, true)
            if (parsed == null) problem("bad Content-Type in part $number")
            else { entity.type = parsed.type; entity.subtype = parsed.subtype; entity.parameters = parsed.values }
        }
        val disposition = header.value("Content-Disposition")
        if (mime && disposition != null) {
            val parsed = Headers.parameters(disposition, false)
            if (parsed == null) problem("bad Content-Disposition in part $number")
            else { entity.disposition = parsed.type; entity.filename = parsed.values["filename"] }
        }
        if (entity.filename.isNullOrEmpty()) entity.filename = entity.parameters["name"]
        val charset = entity.parameters["charset"]
        if (entity.type == "text" && charset != null && charset.lowercase() != "us-ascii") problem("unsupported charset \"${charset.lowercase()}\" in part $number")
        if (mime && entity.type == "multipart") {
            val boundary = entity.parameter("boundary")
            if (boundary.isNotEmpty()) { splitMultipart(entity, lines, boundary); return entity }
            problem("missing boundary in part $number")
        }
        decodeLeaf(entity, header, lines, mime)
        return entity
    }
    private fun splitMultipart(entity: Entity, lines: List<SourceLine>, boundary: String) {
        val parts = mutableListOf<MutableList<SourceLine>>()
        var closed = false
        for (line in lines) {
            val text = Headers.rstrip(line.text)
            if (text == "--$boundary--") { closed = true; break }
            if (text == "--$boundary") parts.add(mutableListOf()) else if (parts.isNotEmpty()) parts.last().add(line)
        }
        if (parts.isEmpty()) problem("no parts in part ${entity.number}")
        else if (!closed) problem("unterminated multipart in part ${entity.number}")
        val children = mutableListOf<Entity>()
        entity.children = children
        for ((i, part) in parts.withIndex()) {
            val sections = sections(part)
            val header = Headers.parseFields(sections.header)
            for (line in header.invalid) problem("bad header line $line")
            children.add(parseEntity("${entity.number}.${i + 1}", header, sections.body, true))
        }
    }
    private fun decodeLeaf(entity: Entity, header: Header, lines: List<SourceLine>, mime: Boolean) {
        val original = lines.joinToString("\n") { it.text }
        val transfer = header.value("Content-Transfer-Encoding")
        val encoding = if (mime && transfer != null) transfer.lowercase() else "7bit"
        when (encoding) {
            "base64" -> {
                val content = Mime.base64Body(original)
                if (content == null) problem("bad base64 in part ${entity.number}")
                entity.content = content ?: ""
            }
            "quoted-printable" -> {
                val decoded = Mime.quotedPrintable(original)
                entity.content = decoded.text
                if (decoded.error) problem("bad quoted-printable in part ${entity.number}")
            }
            else -> {
                entity.content = original
                if (encoding !in listOf("7bit", "8bit", "binary")) problem("unknown encoding \"$encoding\" in part ${entity.number}")
            }
        }
    }
}
private class LogicalLine(val depth: Int, var text: String, var flowing: Boolean = false)
private data class Displayed(val format: String, val lines: List<String>)
private data class ThreadEntry(val container: Container, val prefix: String, val depth: Int)
private class MailThread(val number: Int, private val root: Container) {
    private val entries = mutableListOf<ThreadEntry>()
    private val messages: List<Message>
    init { walk(root, "", "", 0); messages = entries.mapNotNull { it.container.message } }
    private fun walk(container: Container, prefix: String, stem: String, depth: Int) {
        entries.add(ThreadEntry(container, prefix, depth))
        for ((i, child) in container.children.withIndex()) {
            val last = i + 1 == container.children.size
            walk(child, stem + (if (last) "`- " else "+- "), stem + (if (last) "   " else "|  "), depth + 1)
        }
    }
    fun placeMessages() {
        for (entry in entries) entry.container.message?.let { message ->
            message.thread = number
            message.depth = entry.depth
            message.parent = entry.container.parent?.message
        }
    }
    fun report(): List<String> {
        val depth = entries.maxOf { it.depth }
        val senders = messages.mapNotNull { it.sender?.address }.toSet()
        val dates = messages.mapNotNull { it.date }
        val lines = mutableListOf("thread $number messages ${messages.size} depth $depth senders ${senders.size}")
        lines.add(if (dates.isEmpty()) "span -" else "span ${Dates.format(dates.min())} .. ${Dates.format(dates.max())}")
        lines.add("subject " + subjectNotation(root.subject ?: Threader.rootSubject(root)))
        for (entry in entries) lines.add(entry.prefix + containerNotation(entry.container))
        return lines
    }
}
private class SenderStats(val address: String) {
    var count = 0
    val threads = mutableSetOf<Int>()
    var first: Long? = null
    var last: Long? = null
    var name = ""
    fun add(message: Message) {
        count++
        threads.add(message.thread)
        val date = message.date
        if (date != null) {
            if (first == null || date < first!!) first = date
            if (last == null || date > last!!) last = date
        }
        val sender = message.sender!!
        if (sender.name.isNotEmpty()) name = sender.name
    }
}
private fun read(name: String) = File("input", name).readLines(Charsets.US_ASCII)
private fun mailbox(lines: List<String>): List<List<SourceLine>> {
    val messages = mutableListOf<MutableList<SourceLine>>()
    for ((i, line) in lines.withIndex()) {
        if (line.startsWith("From ")) messages.add(mutableListOf())
        else if (messages.isNotEmpty()) {
            val unquoted = line.trimStart('>')
            val text = if (unquoted.length != line.length && unquoted.startsWith("From ")) line.substring(1) else line
            messages.last().add(SourceLine(i + 1, text))
        }
    }
    for (message in messages) if (message.isNotEmpty() && message.last().text.isEmpty()) message.removeAt(message.lastIndex)
    return messages
}
private fun sections(lines: List<SourceLine>): Sections {
    val split = lines.indexOfFirst { it.text.isEmpty() }
    return if (split < 0) Sections(lines, emptyList()) else Sections(lines.take(split), lines.drop(split + 1))
}
private fun messageId(text: String): Boolean {
    if (text.length < 3 || !text.startsWith('<') || !text.endsWith('>')) return false
    val inside = text.substring(1, text.length - 1)
    if (inside.count { it == '@' } != 1 || inside.startsWith('@') || inside.endsWith('@')) return false
    return inside.all { it.code in 33..126 && it !in "<>()\"\\" }
}
private fun extractIds(value: String): List<String> {
    val ids = mutableListOf<String>()
    var start = value.indexOf('<')
    while (start >= 0) {
        val end = value.indexOf('>', start + 1)
        if (end < 0) break
        val id = value.substring(start, end + 1)
        if (messageId(id)) ids.add(id)
        start = value.indexOf('<', end + 1)
    }
    return ids
}
private fun dateNotation(seconds: Long?) = seconds?.let { Dates.format(it) } ?: "invalid"
private fun subjectNotation(subject: String) = subject.ifEmpty { "(no subject)" }
private fun collect(entity: Entity, allowHtml: Boolean): List<Entity> {
    val children = entity.children
    if (children == null) return if (entity.disposition != "attachment" && entity.type == "text" && (entity.subtype == "plain" || entity.subtype == "html" && allowHtml)) listOf(entity) else emptyList()
    if (entity.subtype == "alternative") {
        for (html in listOf(false, true)) for (child in children) { val parts = collect(child, html); if (parts.isNotEmpty()) return parts }
        return emptyList()
    }
    return children.flatMap { collect(it, allowHtml) }
}
private fun quotePrefix(depth: Int) = if (depth > 0) ">".repeat(depth) + " " else ""
private fun wrap(text: String, prefix: String): List<String> {
    val lines = mutableListOf<String>()
    var current = ""
    for (word in Headers.words(text)) {
        if (current.isNotEmpty() && current.length + 1 + word.length > 72) { lines.add(prefix + current); current = word }
        else current = if (current.isEmpty()) word else "$current $word"
    }
    lines.add(prefix + current)
    return lines
}
private fun flowed(content: String, deleteSpace: Boolean): List<String> {
    if (content.isEmpty()) return emptyList()
    val logical = mutableListOf<LogicalLine>()
    for (line in content.split('\n')) {
        var text = line.trimStart('>')
        val depth = line.length - text.length
        if (text.startsWith(' ')) text = text.substring(1)
        val flowing = text.endsWith(' ') && text != "-- "
        val previous = logical.lastOrNull()
        if (previous != null && previous.flowing && previous.depth == depth) {
            if (deleteSpace) previous.text = previous.text.dropLast(1)
            previous.text += text
            previous.flowing = flowing
        } else logical.add(LogicalLine(depth, text, flowing))
    }
    return logical.flatMap { wrap(it.text, quotePrefix(it.depth)) }
}
private fun tagCharacter(letter: Char) = letter in 'A'..'Z' || letter in 'a'..'z' || letter in '0'..'9'
private fun tagName(text: String) = text.takeWhile { tagCharacter(it) }.lowercase()
private fun reference(name: String): String? {
    CHARACTER_REFERENCES[name]?.let { return it }
    if (name.startsWith('#') && Dates.digits(name.substring(1), 1, 2, 3)) {
        val value = name.substring(1).toInt()
        if (value in 32..126) return value.toChar().toString()
    }
    return null
}
private fun replaceReferences(text: String): String {
    val result = StringBuilder()
    var position = 0
    while (position < text.length) {
        val end = if (text[position] == '&') text.indexOf(';', position + 1) else -1
        val replacement = if (end < 0) null else reference(text.substring(position + 1, end))
        if (replacement == null) result.append(text[position++])
        else { result.append(replacement); position = end + 1 }
    }
    return result.toString()
}
private fun htmlBlocks(content: String): List<LogicalLine> {
    val blocks = mutableListOf<LogicalLine>()
    var depth = 0
    var position = 0
    var text = StringBuilder()
    var hide: String? = null
    while (position < content.length) {
        val letter = content[position]
        val close = if (letter == '<') content.indexOf('>', position + 1) else -1
        if (close < 0) { if (hide == null) text.append(letter); position++; continue }
        val inside = content.substring(position + 1, close)
        position = close + 1
        val endTag = inside.startsWith('/')
        val name = tagName(if (endTag) inside.substring(1) else inside)
        if (hide != null) { if (endTag && name == hide) hide = null }
        else if (!endTag && name in HIDDEN_TAGS) hide = name
        else if (name == "br" || name == "li" && !endTag) {
            blocks.add(LogicalLine(depth, text.toString()))
            text = StringBuilder(if (name == "li") "* " else "")
        } else if (name in PARAGRAPH_TAGS) {
            blocks.add(LogicalLine(depth, text.toString()))
            blocks.add(LogicalLine(depth, ""))
            text = StringBuilder()
            if (name == "blockquote") depth = if (endTag) maxOf(0, depth - 1) else depth + 1
        }
    }
    blocks.add(LogicalLine(depth, text.toString()))
    return blocks
}
private fun html(content: String): List<String> {
    val lines = mutableListOf<String>()
    for (block in htmlBlocks(content)) {
        val text = replaceReferences(Headers.collapse(block.text.replace('\n', ' '))).trim(' ')
        if (text.isNotEmpty()) lines.addAll(wrap(text, quotePrefix(block.depth)))
        else if (lines.isNotEmpty() && lines.last().isNotEmpty()) lines.add("")
    }
    while (lines.isNotEmpty() && lines.last().isEmpty()) lines.removeAt(lines.lastIndex)
    return lines
}
private fun display(entity: Entity): Displayed {
    if (entity.subtype == "html") return Displayed("html", html(entity.content))
    if (entity.parameter("format").lowercase() == "flowed") return Displayed("flowed", flowed(entity.content, entity.parameter("delsp").lowercase() == "yes"))
    return Displayed("plain", if (entity.content.isEmpty()) emptyList() else entity.content.split('\n'))
}
private fun lineCounts(lines: List<String>): Pair<Int, Int> {
    var quoted = 0
    var signature = 0
    for ((i, original) in lines.withIndex()) {
        val line = Headers.rstrip(original)
        if (line.startsWith('>')) quoted++
        if (line == "--") signature = lines.size - i - 1
    }
    return quoted to signature
}
private fun containerNotation(container: Container): String {
    val message = container.message
    if (message != null) return "[${message.number}] ${dateNotation(message.date)} ${message.sender?.address ?: "-"} ${subjectNotation(message.subject)}"
    return if (container.subject == null) "[missing] ${container.id}" else "[subject] ${container.subject}"
}
private fun checkParentDates(messages: List<Message>) {
    for (message in messages) {
        val parent = message.parent ?: continue
        val date = message.date ?: continue
        val parentDate = parent.date ?: continue
        if (date < parentDate) message.problem("dated before parent message ${parent.number}")
    }
}
private fun senderNotation(sender: Mailbox?) = when { sender == null -> "-"; sender.name.isEmpty() -> sender.address; else -> "${sender.name} <${sender.address}>" }
private fun entityLines(entity: Entity, lines: MutableList<String>) {
    var line = "part ${entity.number} ${entity.type}/${entity.subtype}"
    val children = entity.children
    if (children != null) { lines.add(line); for (child in children) entityLines(child, lines) }
    else {
        line += " ${entity.content.length}"
        entity.disposition?.let { line += " $it" }
        entity.filename?.takeIf { it.isNotEmpty() }?.let { line += " \"$it\"" }
        lines.add(line)
    }
}
private fun messageReport(message: Message): List<String> {
    val lines = mutableListOf("message ${message.number}", "id ${message.id.ifEmpty { "-" }}", "date ${dateNotation(message.date)}", "from ${senderNotation(message.sender)}",
        "to ${message.to.joinToString(", ").ifEmpty { "-" }}", "cc ${message.cc.joinToString(", ").ifEmpty { "-" }}", "subject ${subjectNotation(message.subject)}",
        "refs ${message.references.joinToString(" ").ifEmpty { "-" }}", "thread ${message.thread} depth ${message.depth} parent ${message.parent?.number ?: "-"}")
    entityLines(message.body, lines)
    return lines
}
private fun bodyReport(request: String, byId: Map<String, Message>): List<String> {
    val lines = mutableListOf("request $request")
    val message = byId[request]
    if (message == null) { lines.add("not found"); return lines }
    val parts = collect(message.body, true)
    lines.add("message ${message.number} text parts ${parts.size}")
    for (part in parts) {
        val display = display(part)
        val (quoted, signature) = lineCounts(display.lines)
        lines.add("part ${part.number} ${display.format} lines ${display.lines.size} quoted $quoted signature $signature")
        for (line in display.lines) {
            val stripped = Headers.rstrip(line)
            lines.add(if (stripped.isEmpty()) "|" else "| $stripped")
        }
    }
    return lines
}
private fun csv(text: String) = if (',' in text || '"' in text) "\"" + text.replace("\"", "\"\"") + "\"" else text
private fun sendersReport(messages: List<Message>): List<String> {
    val stats = mutableMapOf<String, SenderStats>()
    for (message in messages) message.sender?.let { sender -> stats.getOrPut(sender.address) { SenderStats(sender.address) }.add(message) }
    val lines = mutableListOf("address,name,messages,threads,first,last")
    for (entry in stats.values.sortedWith(compareByDescending<SenderStats> { it.count }.thenBy { it.address })) {
        val first = entry.first?.let { Dates.format(it) } ?: "-"
        val last = entry.last?.let { Dates.format(it) } ?: "-"
        lines.add("${entry.address},${csv(entry.name)},${entry.count},${entry.threads.size},$first,$last")
    }
    return lines
}
private fun malformed(messages: List<Message>): List<String> {
    val flagged = messages.count { it.problems.isNotEmpty() }
    val count = messages.sumOf { it.problems.size }
    val lines = mutableListOf("messages ${messages.size} malformed $flagged problems $count")
    for (message in messages) for (problem in message.problems) lines.add("message ${message.number}: $problem")
    return lines
}
private fun blocks(blocks: List<List<String>>): List<String> {
    val lines = mutableListOf<String>()
    for (block in blocks) { if (lines.isNotEmpty()) lines.add(""); lines.addAll(block) }
    return lines
}
fun main() {
    val messages = mutableListOf<Message>()
    val knownIds = mutableMapOf<String, Int>()
    for (lines in mailbox(read("mailbox.mbox"))) {
        val message = Message(messages.size + 1)
        message.process(lines, knownIds)
        messages.add(message)
    }
    val threads = Threader.build(messages).mapIndexed { i, root -> MailThread(i + 1, root) }
    for (thread in threads) thread.placeMessages()
    checkParentDates(messages)
    val byId = messages.filter { it.id.isNotEmpty() }.associateBy { it.id }
    val requests = read("requests.txt")
    val files = linkedMapOf("threads.txt" to blocks(threads.map { it.report() }), "messages.txt" to blocks(messages.map { messageReport(it) }),
        "bodies.txt" to blocks(requests.map { bodyReport(it, byId) }), "senders.csv" to sendersReport(messages), "malformed.txt" to malformed(messages))
    File("output").mkdirs()
    for ((name, lines) in files) File("output", name).writeText(lines.joinToString("\n") + "\n", Charsets.US_ASCII)
}
