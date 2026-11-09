use crate::{LayoutBlock, LayoutLine};
use std::collections::BTreeSet;

pub struct Page {
    pub lines: Vec<usize>,
    pub footnotes: Vec<usize>,
    pub height: usize,
    pub forced: bool,
    pub blank: bool,
}

struct Boundary {
    end: usize,
    next: usize,
    forced: bool,
}

pub fn build(blocks: &[LayoutBlock], footnotes: &[Vec<String>], height: usize, orphan: usize, widow: usize) -> (Vec<LayoutLine>, Vec<Page>) {
    let mut lines = Vec::new();
    let mut boundaries = Vec::new();
    for (index, block) in blocks.iter().enumerate() {
        if index > 0 {
            let end = lines.len();
            if !(blocks[index - 1].list && block.list) { lines.push(LayoutLine::empty()); }
            if block.page_break || blocks[index - 1].kind != "heading" { boundaries.push(Boundary { end, next: lines.len(), forced: block.page_break }); }
        }
        let begin = lines.len();
        lines.extend(block.lines.iter().cloned());
        if block.kind == "flow" {
            for k in 1..block.lines.len() {
                if k >= orphan && block.lines.len() - k >= widow { boundaries.push(Boundary { end: begin + k, next: begin + k, forced: false }); }
            }
        }
    }
    if lines.is_empty() { return (lines, Vec::new()); }
    boundaries.push(Boundary { end: lines.len(), next: lines.len(), forced: true });
    boundaries.sort_by_key(|boundary| boundary.end);
    let mut pages = Vec::new();
    let mut start = 0;
    while start < lines.len() {
        let mut selected = None;
        for (i, boundary) in boundaries.iter().enumerate().filter(|(_, b)| b.end > start) {
            let notes: BTreeSet<_> = lines[start..boundary.end].iter().flat_map(|line| line.footnotes.iter().copied()).collect();
            let note_height = if notes.is_empty() { 0 } else { 1 + notes.iter().map(|&id| footnotes[id].len()).sum::<usize>() };
            let page_height = boundary.end - start + note_height;
            if page_height <= height { selected = Some((i, notes.into_iter().collect::<Vec<_>>(), page_height)); }
            if boundary.forced { break; }
        }
        let (index, notes, page_height) = selected.unwrap();
        let boundary = &boundaries[index];
        pages.push(Page { lines: (start..boundary.end).collect(), footnotes: notes, height: page_height, forced: boundary.forced, blank: false });
        start = boundary.next;
    }
    (lines, pages)
}
