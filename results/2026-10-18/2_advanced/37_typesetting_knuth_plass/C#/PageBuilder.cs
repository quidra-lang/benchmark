using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;

public static class PageBuilder {
    public sealed record Boundary(int end, int next, bool forced);
    public static List<Program.Page> Build(List<Program.LayoutBlock> blocks,
                                           Dictionary<int, List<Program.Line>> footnotes, int height,
                                           int orphan, int widow) {
        List<Program.Line> lines = new();
        List<Boundary> boundaries = new();
        for (int i = 0; i < blocks.Count; i++) {
            Program.LayoutBlock block = blocks[i];
            int start = lines.Count, count = block.lines.Count;
            lines.AddRange(block.lines);
            if (block.kind.Equals("flow"))
                for (int kept = 1; kept < count; kept++)
                    if (kept >= orphan && count - kept >= widow)
                        boundaries.Add(new Boundary(start + kept, start + kept, false));
            if (i + 1 == blocks.Count) {
                boundaries.Add(new Boundary(lines.Count, lines.Count, true));
                continue;
            }
            Program.LayoutBlock next = blocks[i + 1];
            int end = lines.Count;
            if (!block.list || !next.list)
                lines.Add(new Program.Line(""));
            if (next.forced || !block.kind.Equals("heading"))
                boundaries.Add(new Boundary(end, lines.Count, next.forced));
        }
        List<Program.Page> pages = new();
        int start = 0, firstBoundary = 0;
        while (start < lines.Count) {
            SortedSet<int> notes = new();
            int noteHeight = 0, scanned = start, chosen = -1, chosenHeight = 0;
            List<int> chosenNotes = new();
            for (int i = firstBoundary; i < boundaries.Count; i++) {
                Boundary boundary = boundaries[i];
                while (scanned < boundary.end) {
                    foreach (int note in lines[scanned].footnotes)
                        if (notes.Add(note))
                            noteHeight += footnotes[note].Count;
                    scanned++;
                }
                int used = boundary.end - start + noteHeight + (notes.Count == 0 ? 0 : 1);
                if (used > height)
                    break;
                chosen = i;
                chosenHeight = used;
                chosenNotes = new(notes);
                if (boundary.forced)
                    break;
            }
            Boundary boundary = boundaries[chosen];
            Program.Page page = new Program.Page();
            page.content = new(lines.GetRange(start, boundary.end - (start)));
            page.notes = chosenNotes;
            page.height = chosenHeight;
            page.forced = boundary.forced;
            pages.Add(page);
            start = boundary.next;
            firstBoundary = chosen + 1;
        }
        return pages;
    }
}
