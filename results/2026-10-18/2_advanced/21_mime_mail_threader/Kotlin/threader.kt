class Container(val id: String) {
    var message: Message? = null
    var parent: Container? = null
    var children = mutableListOf<Container>()
    var subject: String? = null
    fun ancestorOrSelf(other: Container?): Boolean {
        var current = other
        while (current != null) { if (current === this) return true; current = current.parent }
        return false
    }
}
class Threader private constructor() {
    private val table = linkedMapOf<String, Container>()
    private val containers = mutableListOf<Container>()
    private fun containerOf(id: String) = table.getOrPut(id) { Container(id).also { containers.add(it) } }
    private fun add(message: Message) {
        val container = if (message.id.isNotEmpty()) containerOf(message.id) else Container("").also { containers.add(it) }
        container.message = message
        val references = message.references.map { containerOf(it) }
        for (i in 0 until references.size - 1) {
            val current = references[i]
            val following = references[i + 1]
            if (following.parent == null && !following.ancestorOrSelf(current)) adopt(current, following)
        }
        container.parent?.children?.remove(container)
        container.parent = null
        if (references.isNotEmpty() && !container.ancestorOrSelf(references.last())) adopt(references.last(), container)
    }
    companion object {
        private fun adopt(parent: Container, child: Container) { child.parent = parent; parent.children.add(child) }
        private fun prune(containers: List<Container>, atRoot: Boolean): MutableList<Container> {
            val result = mutableListOf<Container>()
            for (container in containers) {
                container.children = prune(container.children, false)
                if (container.message != null || atRoot && container.children.size >= 2) result.add(container)
                else {
                    for (child in container.children) child.parent = if (atRoot) null else container.parent
                    result.addAll(container.children)
                }
            }
            return result
        }
        private fun key(container: Container): SortKey = container.message?.sortKey ?: container.children.minOf { key(it) }
        private fun sort(containers: MutableList<Container>) {
            for (container in containers) sort(container.children)
            containers.sortWith(compareBy { key(it) })
        }
        fun rootSubject(root: Container) = root.message?.baseSubject ?: root.children.first().message!!.baseSubject
        private fun mergeGroup(subject: String, group: List<Container>): Container {
            val missing = group.firstOrNull { it.message == null }
            val originals = group.filter { it.message != null && !it.message!!.reply }
            val target = missing ?: if (originals.size == 1) originals.first() else Container("").also { it.subject = subject }
            for (root in group) if (root !== target) {
                if (root.message != null) adopt(target, root)
                else for (child in root.children) adopt(target, child)
            }
            return target
        }
        private fun merge(roots: List<Container>): MutableList<Container> {
            val groups = linkedMapOf<String, MutableList<Container>>()
            for (root in roots) { val subject = rootSubject(root); if (subject.isNotEmpty()) groups.getOrPut(subject) { mutableListOf() }.add(root) }
            val result = roots.filter { val subject = rootSubject(it); subject.isEmpty() || groups.getValue(subject).size == 1 }.toMutableList()
            for ((subject, group) in groups) if (group.size >= 2) result.add(mergeGroup(subject, group))
            return result
        }
        fun build(messages: List<Message>): List<Container> {
            val threader = Threader()
            for (message in messages) threader.add(message)
            var roots = prune(threader.containers.filter { it.parent == null }, true)
            sort(roots)
            roots = merge(roots)
            sort(roots)
            return roots
        }
    }
}
