sealed interface Document {
    data class Text(val value: String) : Document
    data object Line : Document
    data object Softline : Document
    data object Hardline : Document
    data object BreakParent : Document
    data class Suffix(val value: String) : Document
    data class IfBreak(val broken: String, val flat: String) : Document
    data class Group(val id: Int, val child: Document) : Document
    data class Nest(val amount: Int, val child: Document) : Document
    data class Align(val child: Document) : Document
    data class Concat(val children: List<Document>) : Document
}
fun Document.forced(): Boolean = when (this) {
    Document.Hardline, Document.BreakParent -> true
    is Document.Concat -> children.any {
        it.forced()
    }
    is Document.Group -> child.forced()
    is Document.Nest -> child.forced()
    is Document.Align -> child.forced()
    else -> false
}
fun Document.groupCount(): Int = when (this) {
    is Document.Group -> 1 + child.groupCount()
    is Document.Nest -> child.groupCount()
    is Document.Align -> child.groupCount()
    is Document.Concat -> children.sumOf {
        it.groupCount()
    }
    else -> 0
}
fun text(value: String): Document = Document.Text(value)
fun concat(parts: List<Document>): Document {
    val result = mutableListOf<Document>()
    fun flatten(document: Document) {
        if (document is Document.Concat) for (child in document.children) flatten(child)
        else if (document is Document.Text) {
            if (document.value.isEmpty()) return
            val previous = result.lastOrNull()
            if (previous is Document.Text) result[result.lastIndex] = Document.Text(previous.value + document.value) else result.add(document)
        } else result.add(document)
    }
    for (part in parts) flatten(part)
    return if (result.isEmpty()) text("") else if (result.size == 1) result[0] else Document.Concat(result)
}
fun nest(n: Int, child: Document): Document = Document.Nest(n, child)
fun align(child: Document): Document = Document.Align(child)
fun line(): Document = Document.Line
fun softline(): Document = Document.Softline
fun hardline(): Document = Document.Hardline
fun suffix(value: String): Document = Document.Suffix(value)
fun breakParent(): Document = Document.BreakParent
fun ifBreak(broken: String, flat: String): Document = Document.IfBreak(broken, flat)
class DocBuilder {
    var next = 0
    fun group(child: Document): Document = Document.Group(next++, child)
}
