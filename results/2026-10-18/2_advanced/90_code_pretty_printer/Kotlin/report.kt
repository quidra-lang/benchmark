object Report {
    fun tree(document: Document, depth: Int, modes: Map<Int, String>, out: MutableList<String>) {
        val prefix = " ".repeat(depth * 2)
        when (document) {
            is Document.Concat -> for (part in document.children) tree(part, depth, modes, out)
            is Document.Text -> out.add(prefix + "text \"${document.value}\"")
            is Document.Suffix -> out.add(prefix + "suffix \"${document.value}\"")
            is Document.IfBreak -> out.add(prefix + "if_break \"${document.broken}\" \"${document.flat}\"")
            is Document.Group -> {
                out.add(prefix + "group ${modes.getValue(document.id)}"); tree(document.child, depth + 1, modes, out)
            }
            is Document.Nest -> {
                out.add(prefix + "nest ${document.amount}"); tree(document.child, depth + 1, modes, out)
            }
            is Document.Align -> {
                out.add(prefix + "align"); tree(document.child, depth + 1, modes, out)
            }
            Document.Line -> out.add(prefix + "line")
            Document.Softline -> out.add(prefix + "softline")
            Document.Hardline -> out.add(prefix + "hardline")
            Document.BreakParent -> out.add(prefix + "break_parent")
        }
    }
    fun diff(a: List<String>, b: List<String>): List<String> {
        val n = a.size
        val m = b.size
        val lcs = Array(n + 1) {
            IntArray(m + 1)
        }
        for (i in n - 1 downTo 0) for (j in m - 1 downTo 0) lcs[i][j] = if (a[i] == b[j]) lcs[i + 1][j + 1] + 1 else maxOf(lcs[i + 1][j], lcs[i][j + 1])
        var i = 0
        var j = 0
        var deleted = 0
        var inserted = 0
        val hunks = mutableListOf<List<String>>()
        while (i < n || j < m) {
            if (i < n && j < m && a[i] == b[j]) {
                i++; j++; continue
            }
            val i0 = i
            val j0 = j
            var d = 0
            var e = 0
            val lines = mutableListOf<String>()
            while (i < n || j < m) {
                if (i < n && j < m && a[i] == b[j]) break
                if (j == m || i < n && lcs[i + 1][j] >= lcs[i][j + 1]) {
                    lines.add("-" + a[i]); i++; d++
                } else {
                    lines.add("+" + b[j]); j++; e++
                }
            }
            deleted += d; inserted += e
            hunks.add(listOf("@@ -${if (d > 0) i0 + 1 else i0},$d +${if (e > 0) j0 + 1 else j0},$e @@") + lines)
        }
        return listOf("hunks=${hunks.size} deleted=$deleted inserted=$inserted") + hunks.flatten()
    }
}
