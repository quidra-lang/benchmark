data class DecodedText(val text: String, val error: Boolean)
object Mime {
    private const val ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    fun hex(letter: Char) = when (letter) { in '0'..'9' -> letter - '0'; in 'A'..'F' -> letter - 'A' + 10; in 'a'..'f' -> letter - 'a' + 10; else -> -1 }
    fun strictBase64(text: String): String? {
        if (text.length % 4 != 0) return null
        val end = text.trimEnd('=').length
        if (text.length - end >= 3) return null
        val result = StringBuilder()
        var buffer = 0
        var bits = 0
        for (i in 0 until end) {
            val value = ALPHABET.indexOf(text[i])
            if (value < 0) return null
            buffer = (buffer shl 6) or value
            bits += 6
            if (bits >= 8) { bits -= 8; result.append((buffer shr bits).toChar()); buffer = buffer and ((1 shl bits) - 1) }
        }
        return result.toString()
    }
    fun base64Body(text: String): String? {
        val data = strictBase64(text.replace(" ", "").replace("\t", "").replace("\n", ""))?.replace("\r\n", "\n") ?: return null
        return if (data.all { it == '\t' || it == '\n' || it.code in 32..126 }) data else null
    }
    fun quotedPrintable(text: String): DecodedText {
        val lines = text.split('\n')
        val output = StringBuilder()
        var error = false
        for ((i, original) in lines.withIndex()) {
            var line = Headers.rstrip(original)
            val soft = line.endsWith('=')
            if (soft) line = line.dropLast(1)
            var position = 0
            while (position < line.length) {
                val letter = line[position]
                var value = -1
                if (letter == '=' && position + 2 < line.length) {
                    val first = hex(line[position + 1])
                    val second = hex(line[position + 2])
                    if (first >= 0 && second >= 0) { val candidate = first * 16 + second; if (candidate == 9 || candidate in 32..126) value = candidate }
                }
                if (value >= 0) { output.append(value.toChar()); position += 3 }
                else { output.append(letter); error = error || letter == '='; position++ }
            }
            if (!soft && i + 1 < lines.size) output.append('\n')
        }
        return DecodedText(output.toString(), error)
    }
}
