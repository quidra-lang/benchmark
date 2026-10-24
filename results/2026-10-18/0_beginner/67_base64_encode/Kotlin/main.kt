fun main() {
    val alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    for (text in listOf("Man", "Hello, World!", "", "<b>bold</b>", "a+b=c?")) {
        val encoded = StringBuilder()
        for (i in text.indices step 3) {
            val remaining = text.length - i
            var bits = text[i].code shl 16
            if (remaining > 1) bits = bits or (text[i + 1].code shl 8)
            if (remaining > 2) bits = bits or text[i + 2].code
            encoded.append(alphabet[(bits shr 18) and 63])
            encoded.append(alphabet[(bits shr 12) and 63])
            encoded.append(if (remaining > 1) alphabet[(bits shr 6) and 63] else '=')
            encoded.append(if (remaining > 2) alphabet[bits and 63] else '=')
        }
        println("\"$text\" -> \"$encoded\"")
    }
}
