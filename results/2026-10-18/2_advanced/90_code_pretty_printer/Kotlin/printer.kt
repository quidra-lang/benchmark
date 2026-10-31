data class Command(val indent: Int, val flat: Boolean, val document: Document)
data class Printed(val lines: List<String>, val modes: Map<Int, String>)
object Printer {
    fun fits(width: Int, first: Command, stack: List<Command>): Boolean {
        if (width < 0) return false
        var remaining = width
        val check = (stack + first).toMutableList()
        while (check.isNotEmpty()) {
            val (i, flat, document) = check.removeAt(check.lastIndex)
            when (document) {
                is Document.Text -> remaining -= document.value.length
                is Document.IfBreak -> remaining -= if (flat) document.flat.length else document.broken.length
                Document.Line -> if (flat) remaining-- else return true
                Document.Softline -> if (!flat) return true
                Document.Hardline -> return true
                is Document.Concat -> for (part in document.children.reversed()) check.add(Command(i, flat, part))
                is Document.Group -> check.add(Command(i, if (document.forced()) false else flat, document.child))
                is Document.Nest -> check.add(Command(i, flat, document.child))
                is Document.Align -> check.add(Command(i, flat, document.child))
                else -> Unit
            }
            if (remaining < 0) return false
        }
        return true
    }
    fun print(document: Document, width: Int, column: Int): Printed {
        val stack = mutableListOf(Command(0, false, document))
        val lines = mutableListOf<String>()
        val modes = mutableMapOf<Int, String>()
        var current = ""
        var col = 0
        val pending = mutableListOf<String>()
        fun finalizeLine() {
            var line = Lexer.trim(current)
            if (pending.isNotEmpty()) {
                val comment = pending.joinToString(" ")
                line += if (column > 0 && line.length < column - 1 && column - 1 + comment.length <= width) " ".repeat(column - 1 - line.length) else " "
                line += comment; pending.clear()
            }
            lines.add(line)
        }
        while (stack.isNotEmpty()) {
            val (i, flat, doc) = stack.removeAt(stack.lastIndex)
            when (doc) {
                is Document.Text -> {
                    current += doc.value; col += doc.value.length
                }
                is Document.IfBreak -> {
                    val value = if (flat) doc.flat else doc.broken; current += value; col += value.length
                }
                Document.Line, Document.Softline, Document.Hardline -> {
                    val newline = doc == Document.Hardline || !flat
                    if (newline) {
                        finalizeLine(); current = " ".repeat(i); col = i
                    }
                    else if (doc == Document.Line) {
                        current += " "; col++
                    }
                }
                is Document.Concat -> for (part in doc.children.reversed()) stack.add(Command(i, flat, part))
                is Document.Nest -> stack.add(Command(i + doc.amount, flat, doc.child))
                is Document.Align -> stack.add(Command(col, flat, doc.child))
                is Document.Suffix -> pending.add(doc.value)
                Document.BreakParent -> Unit
                is Document.Group -> {
                    val mode = if (flat) "flat" else if (doc.forced()) "forced" else if (fits(width - col, Command(i, true, doc.child), stack)) "flat" else "break"
                    modes[doc.id] = mode; stack.add(Command(i, mode == "flat", doc.child))
                }
            }
        }
        finalizeLine()
        return Printed(lines, modes)
    }
}
