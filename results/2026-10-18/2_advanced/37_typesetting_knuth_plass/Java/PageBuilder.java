import java.util.*;
final class PageBuilder {
    record Boundary(int end, int next, boolean forced) {}
    static List<Main.Page> build(List<Main.LayoutBlock> blocks, Map<Integer, List<Main.Line>> footnotes,
                                 int height, int orphan, int widow) {
        List<Main.Line> lines = new ArrayList<>();
        List<Boundary> boundaries = new ArrayList<>();
        for (int i = 0; i < blocks.size(); i++) {
            Main.LayoutBlock block = blocks.get(i);
            int start = lines.size(), count = block.lines.size();
            lines.addAll(block.lines);
            if (block.kind.equals("flow"))
                for (int kept = 1; kept < count; kept++)
                    if (kept >= orphan && count - kept >= widow)
                        boundaries.add(new Boundary(start + kept, start + kept, false));
            if (i + 1 == blocks.size()) {
                boundaries.add(new Boundary(lines.size(), lines.size(), true));
                continue;
            }
            Main.LayoutBlock next = blocks.get(i + 1);
            int end = lines.size();
            if (!block.list || !next.list)
                lines.add(new Main.Line(""));
            if (next.forced || !block.kind.equals("heading"))
                boundaries.add(new Boundary(end, lines.size(), next.forced));
        }
        List<Main.Page> pages = new ArrayList<>();
        int start = 0, firstBoundary = 0;
        while (start < lines.size()) {
            SortedSet<Integer> notes = new TreeSet<>();
            int noteHeight = 0, scanned = start, chosen = -1, chosenHeight = 0;
            List<Integer> chosenNotes = new ArrayList<>();
            for (int i = firstBoundary; i < boundaries.size(); i++) {
                Boundary boundary = boundaries.get(i);
                while (scanned < boundary.end) {
                    for (int note : lines.get(scanned).footnotes)
                        if (notes.add(note))
                            noteHeight += footnotes.get(note).size();
                    scanned++;
                }
                int used = boundary.end - start + noteHeight + (notes.isEmpty() ? 0 : 1);
                if (used > height)
                    break;
                chosen = i;
                chosenHeight = used;
                chosenNotes = new ArrayList<>(notes);
                if (boundary.forced)
                    break;
            }
            Boundary boundary = boundaries.get(chosen);
            Main.Page page = new Main.Page();
            page.content = new ArrayList<>(lines.subList(start, boundary.end));
            page.notes = chosenNotes;
            page.height = chosenHeight;
            page.forced = boundary.forced;
            pages.add(page);
            start = boundary.next;
            firstBoundary = chosen + 1;
        }
        return pages;
    }
}
