data class SourceLine(val number: Int, val text: String)
data class Field(val name: String, val value: String)
data class Token(val kind: String, val text: String, val spaced: Boolean)
data class DecodedWord(val text: String, val decoded: Boolean, val error: Boolean)
data class Parameters(val type: String, val subtype: String, val values: Map<String, String>)
class Header {
    val fields = mutableListOf<Field>()
    val invalid = mutableListOf<Int>()
    fun value(name: String) = fields.firstOrNull { it.name == name.lowercase() }?.value
    fun count(name: String) = fields.count { it.name == name.lowercase() }
}
object Headers {
    private const val ADDRESS_SPECIALS = "<>:;@,."
    private const val ADDRESS_WORDS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+-/=?^_`{|}~"
    private const val MIME_SPECIALS = "/;="
    private const val MIME_EXCLUDED = "()<>@,;:\\\"/[]?="
    fun whitespace(letter: Char) = letter == ' ' || letter == '\t'
    fun rstrip(text: String) = text.trimEnd(' ', '\t')
    fun strip(text: String) = text.trim(' ', '\t')
    fun words(text: String) = text.split(' ', '\t').filter { it.isNotEmpty() }
    fun collapse(text: String) = words(text).joinToString(" ")
    fun parseFields(lines: List<SourceLine>): Header {
        val header = Header()
        val names = mutableListOf<String>()
        val values = mutableListOf<String>()
        var inField = false
        for (line in lines) {
            val text = line.text
            if (whitespace(text[0])) {
                if (inField) values[values.lastIndex] = values.last() + text else header.invalid.add(line.number)
                continue
            }
            val split = text.indexOf(':')
            val name = if (split < 0) "" else text.substring(0, split)
            inField = name.isNotEmpty() && name.all { it.code in 33..126 }
            if (inField) { names.add(name.lowercase()); values.add(text.substring(split + 1)) }
            else header.invalid.add(line.number)
        }
        for (i in names.indices) header.fields.add(Field(names[i], strip(values[i])))
        return header
    }
    fun removeComments(text: String): String? {
        val result = StringBuilder()
        var depth = 0
        var position = 0
        while (position < text.length) {
            val letter = text[position++]
            if (depth == 0) { if (letter == '(') { depth = 1; result.append(' ') } else result.append(letter) }
            else when (letter) { '\\' -> position++; '(' -> depth++; ')' -> depth-- }
        }
        return if (depth == 0) result.toString() else null
    }
    fun tokenize(text: String, mime: Boolean): List<Token>? {
        val tokens = mutableListOf<Token>()
        var position = 0
        var spaced = false
        val specials = if (mime) MIME_SPECIALS else ADDRESS_SPECIALS
        while (position < text.length) {
            val letter = text[position]
            if (whitespace(letter)) { spaced = true; position++; continue }
            if (letter == '(') {
                var depth = 1
                position++
                while (position < text.length && depth > 0) when (text[position++]) { '\\' -> position++; '(' -> depth++; ')' -> depth-- }
                if (depth != 0) return null
                spaced = true
                continue
            }
            if (letter == '"') {
                position++
                val value = StringBuilder()
                var closed = false
                while (position < text.length) {
                    var next = text[position++]
                    if (next == '"') { closed = true; break }
                    if (next == '\\') { if (position == text.length) return null; next = text[position++] }
                    value.append(next)
                }
                if (!closed) return null
                tokens.add(Token("quoted", value.toString(), spaced))
            } else if (letter in specials) { tokens.add(Token(letter.toString(), letter.toString(), spaced)); position++ }
            else if (wordCharacter(letter, mime)) {
                val start = position
                while (position < text.length && wordCharacter(text[position], mime)) position++
                tokens.add(Token("word", text.substring(start, position), spaced))
            } else return null
            spaced = false
        }
        return tokens
    }
    private fun wordCharacter(letter: Char, mime: Boolean) = if (mime) letter.code in 33..126 && letter !in MIME_EXCLUDED else letter in ADDRESS_WORDS
    private fun decodeQ(text: String): String? {
        val result = StringBuilder()
        var position = 0
        while (position < text.length) {
            val letter = text[position++]
            if (letter == '_') result.append(' ')
            else if (letter == '=') {
                if (position + 1 >= text.length) return null
                val first = Mime.hex(text[position])
                val second = Mime.hex(text[position + 1])
                if (first < 0 || second < 0) return null
                result.append((first * 16 + second).toChar())
                position += 2
            } else result.append(letter)
        }
        return result.toString()
    }
    fun decodeWord(word: String): DecodedWord {
        if (word.length < 4 || !word.startsWith("=?") || !word.endsWith("?=")) return DecodedWord(word, false, false)
        val parts = word.substring(2, word.length - 2).split('?')
        if (parts.size != 3 || parts.any { it.isEmpty() }) return DecodedWord(word, false, false)
        val decoded = if (parts[0].lowercase() != "us-ascii") null else when (parts[1]) { "Q", "q" -> decodeQ(parts[2]); "B", "b" -> Mime.strictBase64(parts[2]); else -> null }
        if (decoded == null || !decoded.all { it.code in 32..126 }) return DecodedWord(word, false, true)
        return DecodedWord(decoded, true, false)
    }
    fun unstructured(value: String): DecodedText {
        val text = StringBuilder()
        var previous = false
        var error = false
        var first = true
        for (word in words(value)) {
            val decoded = decodeWord(word)
            if (!first && !(previous && decoded.decoded)) text.append(' ')
            text.append(decoded.text)
            previous = decoded.decoded
            error = error || decoded.error
            first = false
        }
        return DecodedText(collapse(text.toString()), error)
    }
    fun parameters(value: String, withSubtype: Boolean): Parameters? {
        val tokens = tokenize(value, true) ?: return null
        if (tokens.isEmpty() || tokens[0].kind != "word") return null
        val type = tokens[0].text.lowercase()
        var subtype = ""
        var position = 1
        if (withSubtype) {
            if (tokens.size < 3 || tokens[1].kind != "/" || tokens[2].kind != "word") return null
            subtype = tokens[2].text.lowercase()
            position = 3
        }
        val values = linkedMapOf<String, String>()
        while (position < tokens.size) {
            if (position + 3 >= tokens.size || tokens[position].kind != ";" || tokens[position + 1].kind != "word" || tokens[position + 2].kind != "=" || tokens[position + 3].kind !in listOf("word", "quoted")) return null
            val name = tokens[position + 1].text.lowercase()
            if (name !in values) values[name] = tokens[position + 3].text
            position += 4
        }
        return Parameters(type, subtype, values)
    }
}
