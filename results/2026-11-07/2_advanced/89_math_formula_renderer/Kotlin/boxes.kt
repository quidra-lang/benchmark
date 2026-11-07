data class Child(val role: String, val x: Int, val y: Int, val node: Box)
data class Ink(val x: Int, val y: Int, val text: String)
class Box(val width: Int, val height: Int, val baseline: Int, val description: String) {
    val children = mutableListOf<Child>()
    val strings = mutableListOf<Ink>()
    fun child(node: Box, x: Int, y: Int, role: String = "") {
        children.add(Child(role, x, y, node))
    }
    fun string(x: Int, y: Int, text: String) {
        strings.add(Ink(x, y, text))
    }
    fun delimiter(text: String, x: Int) {
        for ((y, line) in Boxes.delimiter(text, height).withIndex()) string(x, y, line)
    }
    companion object {
        fun text(display: String, description: String): Box {
            val node = Box(display.length, 1, 0, description); node.string(0, 0, display); return node
        }
    }
}
object Boxes {
    fun delimiter(text: String, height: Int): List<String> {
        if (text == ".") return emptyList()
        val plain = if (text == "\\{") "{" else if (text == "\\}") "}" else text
        if (height == 1) return listOf(plain)
        val glyph = MutableList(height) {
            plain
        }
        if (text in listOf("(", "\\{")) {
            glyph.fill("|"); glyph[0] = "/"; glyph[height - 1] = "\\"
            if (text == "\\{" && height >= 3) glyph[(height - 1) / 2] = "<"
        } else if (text in listOf(")", "\\}")) {
            glyph.fill("|"); glyph[0] = "\\"; glyph[height - 1] = "/"
            if (text == "\\}" && height >= 3) glyph[(height - 1) / 2] = ">"
        }
        return glyph
    }
    fun large(name: String): List<String> = if (name == "sum") listOf("\\--", " > ", "/--") else if (name == "prod") listOf("___", "| |", "| |") else listOf(" /", " |", "/ ")
    fun atomType(kind: String, value: String): Int {
        if (kind == "command") return Lexer.symbol(value.drop(1))!!.second
        if (kind != "symbol") return 0
        return when (value) {
            "+", "-", "*" -> 2; "=", "<", ">", ":" -> 3; "(", "[" -> 4; ")", "]", "!" -> 5; ",", ";" -> 6; else -> 0
        }
    }
}
