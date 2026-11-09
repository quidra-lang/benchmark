import java.util.TreeMap

private data class Entry(val key: Int, val value: String) {
    override fun toString() = "$key=$value"
}

private data class Node(
    val entries: MutableList<Entry> = mutableListOf(),
    val children: MutableList<Int> = mutableListOf()
) {
    fun deepCopy() = Node(entries.toMutableList(), children.toMutableList())
    fun notation() = entries.joinToString(" ", "[", "]") { it.key.toString() }
    fun position(key: Int) = entries.indexOfFirst { key <= it.key }.let { if (it < 0) entries.size else it }
}

private data class Search(val page: Int?, val position: Int, val path: List<String>)
private data class Changes(val writes: Int, val frees: Int)
private data class Scan(val entries: List<Entry>, val visited: Int)
private class CommandError(message: String) : RuntimeException(message)

private class Trace(val enabled: Boolean) {
    val lines = mutableListOf<String>()
    val cases = mutableListOf<String>()
    fun emit(line: String) { if (enabled) lines.add(line) }
}

private class Tree(val degree: Int) {
    var root = 0
    val pages = TreeMap<Int, Node>().also { it[0] = Node() }
    var splits = 0
    var merges = 0
    var borrows = 0

    fun copyPages(): Map<Int, Node> = pages.mapValues { it.value.deepCopy() }

    fun deepCopy(): Tree {
        val result = Tree(degree)
        result.root = root
        result.pages.clear()
        result.pages.putAll(copyPages())
        result.splits = splits
        result.merges = merges
        result.borrows = borrows
        return result
    }

    fun allocate(node: Node): Int {
        var page = 0
        while (page in pages) page++
        pages[page] = node
        return page
    }

    fun entries(): List<Entry> {
        val result = mutableListOf<Entry>()
        fun visit(page: Int) {
            val node = pages.getValue(page)
            for (j in 0..node.entries.size) {
                if (node.children.isNotEmpty()) visit(node.children[j])
                if (j < node.entries.size) result.add(node.entries[j])
            }
        }
        visit(root)
        return result
    }

    fun search(key: Int): Search {
        var page = root
        val path = mutableListOf<String>()
        while (true) {
            val node = pages.getValue(page)
            path.add(node.notation())
            val position = node.position(key)
            if (node.entries.getOrNull(position)?.key == key) return Search(page, position, path)
            if (node.children.isEmpty()) return Search(null, position, path)
            page = node.children[position]
        }
    }

    fun violation(): String? {
        var reference: Int? = null
        fun visit(page: Int, location: String, depth: Int, low: Int?, high: Int?): String? {
            val node = pages.getValue(page)
            val count = node.entries.size
            val minimum = if (page == root) { if (node.children.isEmpty()) 0 else 1 } else degree - 1
            val maximum = 2 * degree - 1
            val details = "at=$location node=${node.notation()}"
            if (count !in minimum..maximum) return "COUNT $details keys=$count allowed=$minimum..$maximum"
            for (j in 0 until count - 1) {
                if (node.entries[j].key >= node.entries[j + 1].key) return "ORDER $details ${node.entries[j].key}>=${node.entries[j + 1].key}"
            }
            for (entry in node.entries) {
                if (low != null && entry.key <= low || high != null && entry.key >= high)
                    return "RANGE $details key=${entry.key} low=${low ?: "-inf"} high=${high ?: "+inf"}"
            }
            if (node.children.isEmpty()) {
                if (reference == null) reference = depth
                else if (depth != reference) return "DEPTH $details depth=$depth expected=$reference"
            }
            for ((j, child) in node.children.withIndex()) {
                val lower = if (j == 0) low else node.entries[j - 1].key
                val upper = if (j == count) high else node.entries[j].key
                visit(child, "$location.$j", depth + 1, lower, upper)?.let { return it }
            }
            return null
        }
        return visit(root, "root", 0, null, null)
    }

    fun status() = if (violation() == null) "OK" else "DAMAGED"

    fun height(): Int {
        var page = root
        var depth = 0
        while (pages.getValue(page).children.isNotEmpty()) {
            page = pages.getValue(page).children.first()
            depth++
        }
        return depth
    }

    fun changes(before: Map<Int, Node>) = Changes(
        pages.count { (page, node) -> before[page] != node },
        before.keys.count { it !in pages }
    )

    private fun split(parentPage: Int, position: Int, trace: Trace) {
        val parent = pages.getValue(parentPage)
        val childPage = parent.children[position]
        val child = pages.getValue(childPage)
        val old = child.notation()
        val middle = child.entries[degree - 1]
        val right = Node(child.entries.drop(degree).toMutableList(), child.children.drop(degree).toMutableList())
        val rightPage = allocate(right)
        child.entries.subList(degree - 1, child.entries.size).clear()
        if (child.children.isNotEmpty()) child.children.subList(degree, child.children.size).clear()
        parent.entries.add(position, middle)
        parent.children.add(position + 1, rightPage)
        splits++
        trace.emit("STEP split page=$childPage keys=$old up=${middle.key} new=$rightPage")
    }

    fun upsert(entry: Entry, trace: Trace): String? {
        val found = search(entry.key)
        found.page?.let { page ->
            val node = pages.getValue(page)
            return node.entries.set(found.position, entry).value
        }
        if (pages.getValue(root).entries.size == 2 * degree - 1) {
            root = allocate(Node(children = mutableListOf(root)))
            trace.emit("STEP grow page=$root")
            split(root, 0, trace)
        }
        var page = root
        while (pages.getValue(page).children.isNotEmpty()) {
            val node = pages.getValue(page)
            var position = node.position(entry.key)
            if (pages.getValue(node.children[position]).entries.size == 2 * degree - 1) {
                split(page, position, trace)
                if (entry.key > node.entries[position].key) position++
            }
            page = node.children[position]
        }
        val node = pages.getValue(page)
        node.entries.add(node.position(entry.key), entry)
        trace.emit("STEP place page=$page keys=${node.notation()}")
        return null
    }

    private fun extreme(start: Int, last: Boolean): Entry {
        var page = start
        while (true) {
            val node = pages.getValue(page)
            if (node.children.isEmpty()) return if (last) node.entries.last() else node.entries.first()
            page = if (last) node.children.last() else node.children.first()
        }
    }

    private fun merge(parentPage: Int, position: Int, case: String, trace: Trace): Int {
        val parent = pages.getValue(parentPage)
        val leftPage = parent.children[position]
        val rightPage = parent.children[position + 1]
        val left = pages.getValue(leftPage)
        val right = pages.remove(rightPage)!!
        left.entries.add(parent.entries.removeAt(position))
        left.entries.addAll(right.entries)
        left.children.addAll(right.children)
        parent.children.removeAt(position + 1)
        merges++
        trace.emit("STEP $case page=$parentPage merge=$leftPage+$rightPage keys=${left.notation()}")
        if (parentPage == root && parent.entries.isEmpty()) {
            root = leftPage
            pages.remove(parentPage)
            trace.emit("STEP shrink page=$root")
        }
        return leftPage
    }

    private fun removeAt(page: Int, key: Int, trace: Trace) {
        val node = pages.getValue(page)
        val position = node.position(key)
        if (node.entries.getOrNull(position)?.key == key) {
            if (node.children.isEmpty()) {
                trace.cases.add("1")
                node.entries.removeAt(position)
                trace.emit("STEP 1 page=$page keys=${node.notation()}")
                return
            }
            val left = node.children[position]
            val right = node.children[position + 1]
            when {
                pages.getValue(left).entries.size >= degree -> {
                    val predecessor = extreme(left, true)
                    trace.cases.add("2a")
                    trace.emit("STEP 2a page=$page pred=${predecessor.key}")
                    removeAt(left, predecessor.key, trace)
                    node.entries[position] = predecessor
                }
                pages.getValue(right).entries.size >= degree -> {
                    val successor = extreme(right, false)
                    trace.cases.add("2b")
                    trace.emit("STEP 2b page=$page succ=${successor.key}")
                    removeAt(right, successor.key, trace)
                    node.entries[position] = successor
                }
                else -> {
                    trace.cases.add("2c")
                    val child = merge(page, position, "2c", trace)
                    removeAt(child, key, trace)
                }
            }
            return
        }
        var childPage = node.children[position]
        val child = pages.getValue(childPage)
        if (child.entries.size == degree - 1) {
            val left = node.children.getOrNull(position - 1)
            val right = node.children.getOrNull(position + 1)
            when {
                left != null && pages.getValue(left).entries.size >= degree -> {
                    val sibling = pages.getValue(left)
                    trace.cases.add("3a-left")
                    child.entries.add(0, node.entries[position - 1])
                    node.entries[position - 1] = sibling.entries.removeLast()
                    if (sibling.children.isNotEmpty()) child.children.add(0, sibling.children.removeLast())
                    borrows++
                    trace.emit("STEP 3a-left page=$page child=$childPage from=$left keys=${child.notation()}")
                }
                right != null && pages.getValue(right).entries.size >= degree -> {
                    val sibling = pages.getValue(right)
                    trace.cases.add("3a-right")
                    child.entries.add(node.entries[position])
                    node.entries[position] = sibling.entries.removeAt(0)
                    if (sibling.children.isNotEmpty()) child.children.add(sibling.children.removeAt(0))
                    borrows++
                    trace.emit("STEP 3a-right page=$page child=$childPage from=$right keys=${child.notation()}")
                }
                left != null -> {
                    trace.cases.add("3b-left")
                    childPage = merge(page, position - 1, "3b-left", trace)
                }
                else -> {
                    trace.cases.add("3b-right")
                    childPage = merge(page, position, "3b-right", trace)
                }
            }
        }
        removeAt(childPage, key, trace)
    }

    fun remove(key: Int, trace: Trace) {
        trace.cases.clear()
        removeAt(root, key, trace)
    }

    fun scan(low: Int, high: Int): Scan {
        val entries = mutableListOf<Entry>()
        var visits = 0
        fun visit(page: Int) {
            visits++
            val node = pages.getValue(page)
            for (j in 0..node.entries.size) {
                if (node.children.isNotEmpty() && (j == 0 || node.entries[j - 1].key < high)
                    && (j == node.entries.size || node.entries[j].key > low)) visit(node.children[j])
                if (j < node.entries.size && node.entries[j].key in low..high) entries.add(node.entries[j])
            }
        }
        visit(root)
        return Scan(entries, visits)
    }

    fun dump(): String {
        val tokens = mutableListOf<String>()
        fun visit(page: Int) {
            val node = pages.getValue(page)
            tokens.add("(")
            for (j in 0..node.entries.size) {
                if (node.children.isNotEmpty()) visit(node.children[j])
                if (j < node.entries.size) tokens.add(node.entries[j].toString())
            }
            tokens.add(")")
        }
        visit(root)
        return tokens.joinToString(" ")
    }

    fun compact() {
        var source = entries()
        var children = emptyList<Int>()
        val built = mutableListOf<Node>()
        var oldRoot: Int
        while (true) {
            val groups = (source.size + 2 * degree) / (2 * degree)
            val keys = source.size - (groups - 1)
            val base = keys / groups
            val extra = keys % groups
            var position = 0
            var childPosition = 0
            val separators = mutableListOf<Entry>()
            val level = mutableListOf<Int>()
            repeat(groups) { j ->
                val count = base + if (j < extra) 1 else 0
                val node = Node(source.subList(position, position + count).toMutableList(),
                    if (children.isEmpty()) mutableListOf() else children.subList(childPosition, childPosition + count + 1).toMutableList())
                position += count
                childPosition += count + 1
                level.add(built.size)
                built.add(node)
                if (j + 1 < groups) separators.add(source[position++])
            }
            if (groups == 1) { oldRoot = level.first(); break }
            source = separators
            children = level
        }
        pages.clear()
        fun renumber(old: Int): Int {
            val sourceNode = built[old]
            val node = Node(sourceNode.entries.toMutableList())
            val page = allocate(node)
            for (child in sourceNode.children) node.children.add(renumber(child))
            return page
        }
        root = renumber(oldRoot)
        splits = 0
        merges = 0
        borrows = 0
    }
}

private class Parser(degree: Int, val tokens: List<String>) {
    val tree = Tree(degree).also { it.pages.clear() }
    var position = 0
    private fun peek() = tokens.getOrNull(position)
    private fun entry(): Entry {
        val token = peek() ?: throw CommandError("SYNTAX ${position + 1}")
        val split = token.indexOf('=')
        if (split < 0) throw CommandError("SYNTAX ${position + 1}")
        position++
        return Entry(token.substring(0, split).toInt(), token.substring(split + 1))
    }
    private fun node(): Int {
        if (peek() != "(") throw CommandError("SYNTAX ${position + 1}")
        position++
        val item = Node()
        val page = tree.allocate(item)
        val internal = peek() == "("
        if (internal) item.children.add(node())
        while (peek() != ")") {
            item.entries.add(entry())
            if (internal) item.children.add(node())
        }
        position++
        return page
    }
    fun load(): Tree {
        tree.root = node()
        if (position != tokens.size) throw CommandError("SYNTAX ${position + 1}")
        return tree
    }
}

private enum class CursorKind { UNSET, KEY, BEGIN, END }
private data class Cursor(val kind: CursorKind, val key: Int = 0)

private fun findEntry(entries: List<Entry>, last: Boolean = false, accepts: (Entry) -> Boolean): Entry? =
    if (last) entries.findLast(accepts) else entries.find(accepts)

private class Workbench {
    var index: Tree? = null
    var saved: Tree? = null
    var cursor = Cursor(CursorKind.UNSET)
    var trace = false

    fun process(line: String): List<String> {
        val words = line.split(' ')
        val command = words[0]
        if (command == "TRACE") {
            trace = words[1] == "ON"
            return listOf("TRACE ${words[1]}")
        }
        val first = words.getOrNull(1)?.toInt() ?: 0
        val ranged = command in setOf("DELRANGE", "RANGE", "COUNT")
        val second = if (ranged) words[2].toInt() else 0
        if (command == "CREATE" || command == "LOAD") {
            if (first !in 2..5) throw CommandError("BAD DEGREE $first")
            val replacement = if (command == "CREATE") Tree(first) else Parser(first, words.drop(2)).load()
            val result = if (command == "CREATE") "CREATE t=$first"
                else "LOAD t=$first nodes=${replacement.pages.size} keys=${replacement.entries().size} ${replacement.status()}"
            index = replacement
            cursor = Cursor(CursorKind.UNSET)
            return listOf(result)
        }
        var tree = index ?: throw CommandError("NO INDEX")
        val needsValid = command in setOf("INSERT", "BULKLOAD", "DELETE", "DELRANGE", "RANGE", "COUNT", "MIN", "MAX",
            "FLOOR", "CEIL", "RANK", "SELECT", "SEEK", "NEXT", "PREV", "HEIGHT", "COMPACT")
        if (needsValid && tree.violation() != null) throw CommandError("DAMAGED")
        val entries = tree.entries()
        if (ranged && first > second) throw CommandError("BAD RANGE $first $second")
        if (command == "SELECT" && first !in 1..entries.size) throw CommandError("BAD POSITION $first")
        if ((command == "NEXT" || command == "PREV") && cursor.kind == CursorKind.UNSET) throw CommandError("NO CURSOR")
        if (command == "RESTORE" && saved == null) throw CommandError("NO SAVE")
        val output = mutableListOf<String>()
        val steps = Trace(trace && (command == "INSERT" || command == "DELETE"))
        when (command) {
            "INSERT" -> {
                val before = tree.copyPages()
                val splits = tree.splits
                val old = tree.upsert(Entry(first, words[2]), steps)
                val writes = tree.changes(before).writes
                output.addAll(steps.lines)
                output.add(if (old != null) "INSERT $first UPDATED old=$old writes=$writes"
                    else "INSERT $first NEW splits=${tree.splits - splits} height=${tree.height()} writes=$writes")
            }
            "BULKLOAD" -> {
                val before = tree.copyPages()
                val splits = tree.splits
                var added = 0
                var updated = 0
                for (i in 1 until words.size step 2) {
                    if (tree.upsert(Entry(words[i].toInt(), words[i + 1]), steps) == null) added++ else updated++
                }
                output.add("BULKLOAD pairs=${(words.size - 1) / 2} new=$added updated=$updated splits=${tree.splits - splits} height=${tree.height()} writes=${tree.changes(before).writes}")
            }
            "DELETE" -> {
                val found = tree.search(first)
                if (found.page == null) output.add("DELETE $first NOT FOUND")
                else {
                    val value = tree.pages.getValue(found.page).entries[found.position].value
                    val before = tree.copyPages()
                    tree.remove(first, steps)
                    val changes = tree.changes(before)
                    output.addAll(steps.lines)
                    output.add("DELETE $first REMOVED value=$value cases=${steps.cases.joinToString(",")} height=${tree.height()} writes=${changes.writes} frees=${changes.frees}")
                }
            }
            "DELRANGE" -> {
                val before = tree.copyPages()
                val merges = tree.merges
                val borrows = tree.borrows
                var removed = 0
                for (entry in entries) if (entry.key in first..second) {
                    tree.remove(entry.key, steps)
                    removed++
                }
                val changes = tree.changes(before)
                output.add("DELRANGE $first $second removed=$removed merges=${tree.merges - merges} borrows=${tree.borrows - borrows} height=${tree.height()} writes=${changes.writes} frees=${changes.frees}")
            }
            "GET" -> {
                val found = tree.search(first)
                val result = if (found.page == null) "NOT FOUND" else "FOUND value=${tree.pages.getValue(found.page).entries[found.position].value}"
                output.add("GET $first $result path=${found.path.joinToString(" -> ")}")
            }
            "RANGE", "COUNT" -> {
                val result = tree.scan(first, second)
                val suffix = if (command == "RANGE") result.entries.joinToString("") { " $it" } else ""
                output.add("$command $first $second count=${result.entries.size} visited=${result.visited}$suffix")
            }
            "MIN", "MAX" -> {
                val entry = if (command == "MIN") entries.firstOrNull() else entries.lastOrNull()
                output.add("$command ${entry ?: "EMPTY"}")
            }
            "FLOOR", "CEIL" -> {
                val floor = command == "FLOOR"
                val entry = findEntry(entries, floor) { if (floor) it.key <= first else it.key >= first }
                output.add("$command $first ${entry ?: "NONE"}")
            }
            "RANK" -> output.add("RANK $first ${entries.count { it.key < first }}")
            "SELECT" -> output.add("SELECT $first ${entries[first - 1]}")
            "SEEK" -> {
                val entry = findEntry(entries) { it.key >= first }
                cursor = if (entry == null) Cursor(CursorKind.END) else Cursor(CursorKind.KEY, entry.key)
                output.add("SEEK $first ${entry ?: "END"}")
            }
            "NEXT", "PREV" -> {
                val next = command == "NEXT"
                val entry = when (cursor.kind) {
                    CursorKind.KEY -> findEntry(entries, !next) { if (next) it.key > cursor.key else it.key < cursor.key }
                    CursorKind.BEGIN -> if (next) entries.firstOrNull() else null
                    CursorKind.END -> if (next) null else entries.lastOrNull()
                    CursorKind.UNSET -> error("unreachable")
                }
                val boundary = if (next) CursorKind.END else CursorKind.BEGIN
                cursor = if (entry == null) Cursor(boundary) else Cursor(CursorKind.KEY, entry.key)
                output.add("$command ${entry ?: boundary.name}")
            }
            "PRINT" -> {
                var level = listOf(tree.root)
                var depth = 0
                while (level.isNotEmpty()) {
                    output.add("LEVEL ${depth++} " + level.joinToString(" ") { tree.pages.getValue(it).notation() })
                    level = level.flatMap { tree.pages.getValue(it).children }
                }
            }
            "PAGES" -> {
                for ((page, node) in tree.pages) {
                    val kids = if (node.children.isEmpty()) "-" else node.children.joinToString(",")
                    output.add("PAGE $page ${node.notation()} kids=$kids")
                }
            }
            "DUMP" -> output.add("DUMP ${tree.degree} ${tree.dump()}")
            "HEIGHT" -> output.add("HEIGHT ${tree.height()}")
            "STATS" -> {
                val nodes = tree.pages.size
                val leaves = tree.pages.values.count { it.children.isEmpty() }
                val fill = 100 * entries.size / ((2 * tree.degree - 1) * nodes)
                output.add("STATS t=${tree.degree} nodes=$nodes leaves=$leaves keys=${entries.size} fill=$fill% splits=${tree.splits} merges=${tree.merges} borrows=${tree.borrows}")
            }
            "VERIFY" -> output.add(tree.violation()?.let { "VERIFY FAIL $it" } ?: "VERIFY OK")
            "REBUILD" -> {
                tree = Tree(tree.degree)
                for (entry in entries) tree.upsert(entry, steps)
                output.add("REBUILD entries=${entries.size} keys=${tree.entries().size} nodes=${tree.pages.size} splits=${tree.splits} height=${tree.height()}")
            }
            "COMPACT" -> {
                val nodes = tree.pages.size
                tree.compact()
                output.add("COMPACT nodes=$nodes->${tree.pages.size} height=${tree.height()}")
            }
            "SAVE" -> {
                saved = tree.deepCopy()
                output.add("SAVE nodes=${tree.pages.size} keys=${entries.size} ${tree.status()}")
            }
            "RESTORE" -> {
                tree = saved!!.deepCopy()
                output.add("RESTORE nodes=${tree.pages.size} keys=${tree.entries().size} ${tree.status()}")
            }
        }
        index = tree
        return output
    }
}

fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val count = input.readLine().toInt()
    val workbench = Workbench()
    repeat(count) {
        try {
            for (line in workbench.process(input.readLine())) output.write("$line\n")
        } catch (error: CommandError) {
            output.write("ERROR ${error.message}\n")
        }
    }
    output.flush()
}
