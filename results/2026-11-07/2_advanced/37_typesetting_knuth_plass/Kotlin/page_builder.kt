object PageBuilder {
    data class Boundary(val end: Int, val next: Int, val forced: Boolean)
    fun build(blocks: List<LayoutBlock>, footnotes: Map<Int,List<Line>>, height: Int, orphan: Int, widow: Int): List<Page> {
        val lines = mutableListOf<Line>();
        val boundaries = mutableListOf<Boundary>()
        for (i in blocks.indices) {
            val block = blocks[i];
            val start = lines.size;
            val count = block.lines.size;
            lines.addAll(block.lines);
            if (block.kind == "flow") for (kept in 1 until count) if (kept >= orphan && count - kept >= widow) boundaries.add(Boundary(start + kept,
                start + kept,false));
            if (i + 1 == blocks.size) {
                boundaries.add(Boundary(lines.size,lines.size,true));
                continue
            };
            val next = blocks[i + 1];
            val end = lines.size;
            if (!block.list || !next.list) lines.add(Line(""));
            if (next.forced || block.kind != "heading") boundaries.add(Boundary(end,lines.size,next.forced))
        }
        val pages = mutableListOf<Page>();
        var start = 0;
        var firstBoundary = 0
        while (start < lines.size) {
            val notes = sortedSetOf<Int>();
            var noteHeight = 0;
            var scanned = start;
            var chosen = -1;
            var chosenHeight = 0;
            var chosenNotes = listOf<Int>()
            for (i in firstBoundary until boundaries.size) {
                val boundary = boundaries[i];
                while (scanned < boundary.end) {
                    for (note in lines[scanned].footnotes) if (notes.add(note)) noteHeight += footnotes.getValue(note).size;
                    scanned++
                };
                val used = boundary.end - start + noteHeight + if (notes.isEmpty()) 0 else 1;
                if (used > height) break;
                chosen = i;
                chosenHeight = used;
                chosenNotes = notes.toList();
                if (boundary.forced) break
            }
            val boundary = boundaries[chosen];
            val page = Page();
            page.content = lines.subList(start,boundary.end).toList();
            page.notes = chosenNotes;
            page.height = chosenHeight;
            page.forced = boundary.forced;
            pages.add(page);
            start = boundary.next;
            firstBoundary = chosen + 1
        }
        return pages
    }
}
