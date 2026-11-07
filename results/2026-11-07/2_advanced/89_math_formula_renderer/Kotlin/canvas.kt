data class Description(val lines: List<String>, val kinds: Map<String, Int>, val depth: Int)
object Canvas {
    fun paint(box: Box, x: Int, y: Int, grid: Array<CharArray>) {
        for ((dx, dy, text) in box.strings) for ((i, c) in text.withIndex()) if (c != ' ') grid[y + dy][x + dx + i] = c
        for (child in box.children) paint(child.node, x + child.x, y + child.y, grid)
    }
    fun describe(roots: List<Child>): Description {
        val lines = mutableListOf<String>()
        val kinds = mutableMapOf<String, Int>()
        var depth = 0
        fun visit(box: Box, x: Int, y: Int, level: Int, role: String) {
            lines.add(" ".repeat(level * 2) + role + box.description + " x=$x y=$y w=${box.width} h=${box.height} b=${box.baseline}")
            val kind = box.description.substringBefore(' ')
            kinds[kind] = kinds.getOrDefault(kind, 0) + 1
            depth = maxOf(depth, level + 1)
            for (child in box.children) visit(child.node, x + child.x, y + child.y, level + 1, child.role)
        }
        for (root in roots) visit(root.node, root.x, root.y, 0, "")
        return Description(lines, kinds, depth)
    }
    fun lines(grid: Array<CharArray>): List<String> = grid.map {
        String(it).trimEnd(' ')
    }
}
