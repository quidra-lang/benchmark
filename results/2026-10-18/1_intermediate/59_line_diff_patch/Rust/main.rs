use std::collections::{BTreeMap, HashMap};
use std::io::{self, Read, Write};

const DATA_COMMANDS: [&str; 3] = ["FILE", "PATCH", "EDIT"];
const FORMATS_WITH_ARGUMENT: [&str; 4] = ["IFDEF", "UNIFIED", "CONTEXT", "SIDE"];
const OFFSETS: [i64; 7] = [0, 1, -1, 2, -2, 3, -3];
const GRAPH_WIDTH: usize = 20;
const SEPARATOR: &str = "=======";

type CommandResult = Result<(), String>;

fn range_r(start: usize, count: usize) -> String {
    match count {
        0 => start.to_string(),
        1 => (start + 1).to_string(),
        _ => format!("{},{}", start + 1, start + count),
    }
}

fn range_u(start: usize, count: usize) -> String {
    match count {
        0 => format!("{start},0"),
        1 => (start + 1).to_string(),
        _ => format!("{},{}", start + 1, count),
    }
}

fn range_m(start: usize, count: usize) -> String {
    format!("{},{}", start + 1, count)
}

fn collapse_spaces(line: &str) -> String {
    let mut result = String::with_capacity(line.len());
    let mut previous_space = false;
    for ch in line.chars() {
        if ch == ' ' && previous_space {
            continue;
        }
        previous_space = ch == ' ';
        result.push(ch);
    }
    result
}

fn comparison_key(line: &str, options: &[&str]) -> String {
    let mut key = line.to_string();
    if options.contains(&"ICASE") {
        key = key.to_ascii_lowercase();
    }
    if options.contains(&"IWHITE") {
        key = key.replace(' ', "");
    }
    if options.contains(&"ISPACE") {
        key = collapse_spaces(&key);
    }
    key
}

fn matched_pairs<T: PartialEq>(first: &[T], second: &[T]) -> Vec<(usize, usize)> {
    let (rows, columns) = (first.len(), second.len());
    let mut table = vec![vec![0usize; columns + 1]; rows + 1];
    for i in 1..=rows {
        for j in 1..=columns {
            table[i][j] = if first[i - 1] == second[j - 1] {
                table[i - 1][j - 1] + 1
            } else {
                table[i - 1][j].max(table[i][j - 1])
            };
        }
    }
    let mut pairs = vec![(rows + 1, columns + 1)];
    let (mut i, mut j) = (rows, columns);
    while i >= 1 && j >= 1 {
        if first[i - 1] == second[j - 1] {
            pairs.push((i, j));
            i -= 1;
            j -= 1;
        } else if table[i - 1][j] >= table[i][j - 1] {
            i -= 1;
        } else {
            j -= 1;
        }
    }
    pairs.push((0, 0));
    pairs.reverse();
    pairs
}

#[derive(Clone, Copy)]
struct ChangeBlock {
    p: usize,
    q: usize,
    x: usize,
    y: usize,
}

impl ChangeBlock {
    fn letter(&self) -> char {
        if self.x >= 1 && self.y >= 1 {
            'c'
        } else if self.y == 0 {
            'd'
        } else {
            'a'
        }
    }
}

fn change_blocks<T: PartialEq>(first: &[T], second: &[T]) -> Vec<ChangeBlock> {
    let pairs = matched_pairs(first, second);
    let mut blocks = Vec::new();
    for window in pairs.windows(2) {
        let ((i, j), (next_i, next_j)) = (window[0], window[1]);
        if next_i - i > 1 || next_j - j > 1 {
            blocks.push(ChangeBlock {
                p: i,
                q: j,
                x: next_i - i - 1,
                y: next_j - j - 1,
            });
        }
    }
    blocks
}

#[derive(Clone, Copy)]
enum Step {
    Common(usize, usize),
    Change(ChangeBlock),
}

fn walk(blocks: &[ChangeBlock], old_start: usize, new_start: usize, old_end: usize) -> Vec<Step> {
    let mut steps = Vec::new();
    let (mut old_index, mut new_index) = (old_start, new_start);
    for block in blocks {
        while old_index < block.p {
            steps.push(Step::Common(old_index, new_index));
            old_index += 1;
            new_index += 1;
        }
        steps.push(Step::Change(*block));
        old_index = block.p + block.x;
        new_index = block.q + block.y;
    }
    while old_index < old_end {
        steps.push(Step::Common(old_index, new_index));
        old_index += 1;
        new_index += 1;
    }
    steps
}

fn side_row(left: &str, symbol: &str, right: &str, width: usize) -> String {
    let left = &left[..left.len().min(width)];
    let right = &right[..right.len().min(width)];
    format!("{left:<width$} {symbol} {right}")
        .trim_end_matches(' ')
        .to_string()
}

fn stat_graph(inserted: usize, deleted: usize) -> String {
    let total = inserted + deleted;
    let (mut plus, mut minus) = (inserted, deleted);
    if total > GRAPH_WIDTH {
        plus = GRAPH_WIDTH * inserted / total;
        minus = GRAPH_WIDTH * deleted / total;
        if inserted >= 1 && plus == 0 {
            plus = 1;
        }
        if deleted >= 1 && minus == 0 {
            minus = 1;
        }
    }
    "+".repeat(plus) + &"-".repeat(minus)
}

struct Hunk {
    blocks: Vec<ChangeBlock>,
    old_start: usize,
    old_count: usize,
    new_start: usize,
    new_count: usize,
}

impl Hunk {
    fn new(blocks: Vec<ChangeBlock>, context: usize, old_total: usize) -> Self {
        let (first, last) = (blocks[0], blocks[blocks.len() - 1]);
        let before = context.min(first.p);
        let after = context.min(old_total - last.p - last.x);
        let old_start = first.p - before;
        let new_start = first.q - before;
        Hunk {
            old_start,
            old_count: last.p + last.x + after - old_start,
            new_start,
            new_count: last.q + last.y + after - new_start,
            blocks,
        }
    }

    fn steps(&self) -> Vec<Step> {
        walk(
            &self.blocks,
            self.old_start,
            self.new_start,
            self.old_start + self.old_count,
        )
    }
}

struct LineDiff<'a> {
    old: &'a [String],
    new: &'a [String],
    blocks: Vec<ChangeBlock>,
}

impl<'a> LineDiff<'a> {
    fn new(old: &'a [String], new: &'a [String], options: &[&str]) -> Self {
        let old_keys: Vec<String> = old
            .iter()
            .map(|line| comparison_key(line, options))
            .collect();
        let new_keys: Vec<String> = new
            .iter()
            .map(|line| comparison_key(line, options))
            .collect();
        LineDiff {
            old,
            new,
            blocks: change_blocks(&old_keys, &new_keys),
        }
    }

    fn deleted(&self, block: &ChangeBlock) -> &'a [String] {
        &self.old[block.p..block.p + block.x]
    }

    fn inserted(&self, block: &ChangeBlock) -> &'a [String] {
        &self.new[block.q..block.q + block.y]
    }

    fn hunks(&self, context: usize) -> Vec<Hunk> {
        let mut groups: Vec<Vec<ChangeBlock>> = Vec::new();
        for block in &self.blocks {
            if let Some(group) = groups.last_mut() {
                let previous = group[group.len() - 1];
                if block.p - (previous.p + previous.x) <= 2 * context {
                    group.push(*block);
                    continue;
                }
            }
            groups.push(vec![*block]);
        }
        groups
            .into_iter()
            .map(|group| Hunk::new(group, context, self.old.len()))
            .collect()
    }

    fn normal(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for block in &self.blocks {
            let letter = block.letter();
            lines.push(format!(
                "{}{letter}{}",
                range_r(block.p, block.x),
                range_r(block.q, block.y)
            ));
            lines.extend(self.deleted(block).iter().map(|line| format!("< {line}")));
            if letter == 'c' {
                lines.push("---".to_string());
            }
            lines.extend(self.inserted(block).iter().map(|line| format!("> {line}")));
        }
        lines
    }

    fn ed(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for block in self.blocks.iter().rev() {
            let letter = block.letter();
            lines.push(format!("{}{letter}", range_r(block.p, block.x)));
            if letter != 'd' {
                lines.extend_from_slice(self.inserted(block));
                lines.push(".".to_string());
            }
        }
        lines
    }

    fn rcs(&self) -> Vec<String> {
        let mut lines = Vec::new();
        for block in &self.blocks {
            if block.x >= 1 {
                lines.push(format!("d{} {}", block.p + 1, block.x));
            }
            if block.y >= 1 {
                lines.push(format!("a{} {}", block.p + block.x, block.y));
                lines.extend_from_slice(self.inserted(block));
            }
        }
        lines
    }

    fn ifdef(&self, macro_name: &str) -> Vec<String> {
        let mut lines = Vec::new();
        for step in walk(&self.blocks, 0, 0, self.old.len()) {
            match step {
                Step::Common(old_index, _) => lines.push(self.old[old_index].clone()),
                Step::Change(block) if block.x >= 1 && block.y >= 1 => {
                    lines.push(format!("#ifndef {macro_name}"));
                    lines.extend_from_slice(self.deleted(&block));
                    lines.push(format!("#else /* {macro_name} */"));
                    lines.extend_from_slice(self.inserted(&block));
                    lines.push(format!("#endif /* {macro_name} */"));
                }
                Step::Change(block) if block.y == 0 => {
                    lines.push(format!("#ifndef {macro_name}"));
                    lines.extend_from_slice(self.deleted(&block));
                    lines.push(format!("#endif /* ! {macro_name} */"));
                }
                Step::Change(block) => {
                    lines.push(format!("#ifdef {macro_name}"));
                    lines.extend_from_slice(self.inserted(&block));
                    lines.push(format!("#endif /* {macro_name} */"));
                }
            }
        }
        lines
    }

    fn unified(&self, context: usize, old_name: &str, new_name: &str) -> Vec<String> {
        let mut lines = vec![format!("--- {old_name}"), format!("+++ {new_name}")];
        for hunk in self.hunks(context) {
            lines.push(format!(
                "@@ -{} +{} @@",
                range_u(hunk.old_start, hunk.old_count),
                range_u(hunk.new_start, hunk.new_count)
            ));
            for step in hunk.steps() {
                match step {
                    Step::Common(old_index, _) => lines.push(format!(" {}", self.old[old_index])),
                    Step::Change(block) => {
                        lines.extend(self.deleted(&block).iter().map(|line| format!("-{line}")));
                        lines.extend(self.inserted(&block).iter().map(|line| format!("+{line}")));
                    }
                }
            }
        }
        lines
    }

    fn context(&self, context: usize, old_name: &str, new_name: &str) -> Vec<String> {
        let mut lines = vec![format!("*** {old_name}"), format!("--- {new_name}")];
        for hunk in self.hunks(context) {
            let steps = hunk.steps();
            lines.push("*".repeat(15));
            lines.push(format!(
                "*** {} ****",
                range_r(hunk.old_start, hunk.old_count)
            ));
            if hunk.blocks.iter().any(|block| block.x >= 1) {
                for &step in &steps {
                    match step {
                        Step::Common(old_index, _) => {
                            lines.push(format!("  {}", self.old[old_index]));
                        }
                        Step::Change(block) => {
                            let marker = if block.y >= 1 { "! " } else { "- " };
                            let deleted = self.deleted(&block).iter();
                            lines.extend(deleted.map(|line| format!("{marker}{line}")));
                        }
                    }
                }
            }
            lines.push(format!(
                "--- {} ----",
                range_r(hunk.new_start, hunk.new_count)
            ));
            if hunk.blocks.iter().any(|block| block.y >= 1) {
                for &step in &steps {
                    match step {
                        Step::Common(_, new_index) => {
                            lines.push(format!("  {}", self.new[new_index]));
                        }
                        Step::Change(block) => {
                            let marker = if block.x >= 1 { "! " } else { "+ " };
                            let inserted = self.inserted(&block).iter();
                            lines.extend(inserted.map(|line| format!("{marker}{line}")));
                        }
                    }
                }
            }
        }
        lines
    }

    fn side_by_side(&self, width: usize) -> Vec<String> {
        let mut lines = Vec::new();
        for step in walk(&self.blocks, 0, 0, self.old.len()) {
            match step {
                Step::Common(old_index, new_index) => {
                    lines.push(side_row(
                        &self.old[old_index],
                        " ",
                        &self.new[new_index],
                        width,
                    ));
                }
                Step::Change(block) => {
                    for row in 0..block.x.max(block.y) {
                        let (left, symbol, right) = if row < block.x && row < block.y {
                            (
                                &self.old[block.p + row][..],
                                "|",
                                &self.new[block.q + row][..],
                            )
                        } else if row < block.x {
                            (&self.old[block.p + row][..], "<", "")
                        } else {
                            ("", ">", &self.new[block.q + row][..])
                        };
                        lines.push(side_row(left, symbol, right, width));
                    }
                }
            }
        }
        lines
    }
}

#[derive(Default)]
struct TokenTotals {
    deleted: usize,
    inserted: usize,
    common: usize,
}

fn split_tokens(line: &str, by_word: bool) -> Vec<&str> {
    if by_word {
        line.split_whitespace().collect()
    } else {
        (0..line.len()).map(|index| &line[index..=index]).collect()
    }
}

fn deletion(tokens: &[&str], separator: &str) -> String {
    format!("[-{}-]", tokens.join(separator))
}

fn insertion(tokens: &[&str], separator: &str) -> String {
    format!("{{+{}+}}", tokens.join(separator))
}

fn compare_tokens(
    old_tokens: &[&str],
    new_tokens: &[&str],
    separator: &str,
    totals: &mut TokenTotals,
) -> String {
    let mut parts = Vec::new();
    let blocks = change_blocks(old_tokens, new_tokens);
    for step in walk(&blocks, 0, 0, old_tokens.len()) {
        match step {
            Step::Common(old_index, _) => {
                parts.push(old_tokens[old_index].to_string());
                totals.common += 1;
            }
            Step::Change(block) => {
                if block.x >= 1 {
                    parts.push(deletion(&old_tokens[block.p..block.p + block.x], separator));
                }
                if block.y >= 1 {
                    parts.push(insertion(
                        &new_tokens[block.q..block.q + block.y],
                        separator,
                    ));
                }
                totals.deleted += block.x;
                totals.inserted += block.y;
            }
        }
    }
    parts.join(separator)
}

struct PatchHunk {
    line_number: usize,
    old_start: usize,
    old_count: usize,
    new_start: usize,
    new_count: usize,
    body: Vec<(char, String)>,
}

impl PatchHunk {
    fn texts(&self, other_kind: char) -> Vec<&str> {
        self.body
            .iter()
            .filter(|(kind, _)| *kind == ' ' || *kind == other_kind)
            .map(|(_, text)| text.as_str())
            .collect()
    }

    fn sequences(&self, reverse: bool) -> (Vec<&str>, Vec<&str>) {
        if reverse {
            (self.texts('+'), self.texts('-'))
        } else {
            (self.texts('-'), self.texts('+'))
        }
    }

    fn start(&self, reverse: bool) -> usize {
        if reverse {
            self.new_start
        } else {
            self.old_start
        }
    }

    fn leading_context(&self) -> usize {
        self.body
            .iter()
            .take_while(|(kind, _)| *kind == ' ')
            .count()
    }

    fn trailing_context(&self) -> usize {
        self.body
            .iter()
            .rev()
            .take_while(|(kind, _)| *kind == ' ')
            .count()
    }
}

struct HunkMatch {
    fuzz: usize,
    delta: i64,
    position: usize,
    lines: Vec<String>,
}

impl HunkMatch {
    fn report(&self, number: usize) -> String {
        let mut text = format!("Hunk #{number} succeeded at {}", self.position + 1);
        if self.fuzz >= 1 {
            text += &format!(" with fuzz {}", self.fuzz);
        }
        match self.delta {
            0 => {}
            1 | -1 => text += &format!(" (offset {} line)", self.delta),
            _ => text += &format!(" (offset {} lines)", self.delta),
        }
        text
    }
}

fn parse_number(text: &str) -> Option<usize> {
    if (1..=4).contains(&text.len()) && text.bytes().all(|byte| byte.is_ascii_digit()) {
        text.parse().ok()
    } else {
        None
    }
}

fn parse_number_pair(text: &str) -> Option<(usize, Option<usize>)> {
    match text.split_once(',') {
        Some((first, second)) => Some((parse_number(first)?, Some(parse_number(second)?))),
        None => Some((parse_number(text)?, None)),
    }
}

fn parse_range(text: &str, sign: char) -> Option<(usize, usize)> {
    let (start, count) = parse_number_pair(text.strip_prefix(sign)?)?;
    let count = count.unwrap_or(1);
    if start == 0 && count != 0 {
        return None;
    }
    Some((start, count))
}

fn parse_hunk_header(line: &str, line_number: usize) -> Result<PatchHunk, String> {
    let parts: Vec<&str> = line.split(' ').collect();
    let ranges = if parts.len() == 4 && parts[0] == "@@" && parts[3] == "@@" {
        parse_range(parts[1], '-').zip(parse_range(parts[2], '+'))
    } else {
        None
    };
    let Some(((old_start, old_count), (new_start, new_count))) = ranges else {
        return Err(format!("PATCH ERROR line {line_number}: bad hunk header"));
    };
    Ok(PatchHunk {
        line_number,
        old_start,
        old_count,
        new_start,
        new_count,
        body: Vec::new(),
    })
}

fn parse_patch(patch_lines: &[String]) -> Result<Vec<PatchHunk>, String> {
    let Some(mut index) = patch_lines.iter().position(|line| line.starts_with("@@")) else {
        return Err("PATCH ERROR no hunks".to_string());
    };
    let mut hunks = Vec::new();
    while index < patch_lines.len() {
        let mut hunk = parse_hunk_header(&patch_lines[index], index + 1)?;
        index += 1;
        let (mut old_seen, mut new_seen) = (0, 0);
        while old_seen < hunk.old_count || new_seen < hunk.new_count {
            if index == patch_lines.len() {
                return Err(format!(
                    "PATCH ERROR line {}: truncated hunk",
                    hunk.line_number
                ));
            }
            let line = &patch_lines[index];
            let kind = line.as_bytes()[0] as char;
            let in_old = kind == ' ' || kind == '-';
            let in_new = kind == ' ' || kind == '+';
            if line.len() < 2
                || !(in_old || in_new)
                || (in_old && old_seen == hunk.old_count)
                || (in_new && new_seen == hunk.new_count)
            {
                return Err(format!("PATCH ERROR line {}: bad hunk line", index + 1));
            }
            hunk.body.push((kind, line[1..].to_string()));
            if in_old {
                old_seen += 1;
            }
            if in_new {
                new_seen += 1;
            }
            index += 1;
        }
        if hunk.body.iter().all(|(kind, _)| *kind == ' ') {
            return Err(format!("PATCH ERROR line {}: no changes", hunk.line_number));
        }
        hunks.push(hunk);
    }
    Ok(hunks)
}

fn search_hunk(
    hunk: &PatchHunk,
    lines: &[String],
    adjustment: i64,
    reverse: bool,
    max_fuzz: usize,
) -> Option<HunkMatch> {
    let (old, new) = hunk.sequences(reverse);
    let start = hunk.start(reverse) as i64;
    let expected = if old.is_empty() {
        start + adjustment
    } else {
        start - 1 + adjustment
    };
    let (leading, trailing) = (hunk.leading_context(), hunk.trailing_context());
    for fuzz in 0..=max_fuzz {
        let head = fuzz.min(leading);
        let tail = fuzz.min(trailing);
        let old_part = &old[head..old.len() - tail];
        let new_part = &new[head..new.len() - tail];
        for delta in OFFSETS {
            let Ok(position) = usize::try_from(expected + head as i64 + delta) else {
                continue;
            };
            let end = position + old_part.len();
            if end > lines.len() || lines[position..end] != *old_part {
                continue;
            }
            let mut result = lines[..position].to_vec();
            result.extend(new_part.iter().map(|text| text.to_string()));
            result.extend_from_slice(&lines[end..]);
            return Some(HunkMatch {
                fuzz,
                delta,
                position,
                lines: result,
            });
        }
    }
    None
}

fn parse_edit_command(line: &str) -> Option<(char, usize, usize)> {
    let instruction = line.chars().last()?;
    let (first, second) = parse_number_pair(&line[..line.len() - 1])?;
    if !matches!(instruction, 'a' | 'c' | 'd') || (instruction == 'a' && second.is_some()) {
        return None;
    }
    Some((instruction, first, second.unwrap_or(first)))
}

fn run_edit_script(lines: &[String], script: &[String]) -> Result<(Vec<String>, usize), String> {
    let mut lines = lines.to_vec();
    let mut executed = 0;
    let mut index = 0;
    while index < script.len() {
        let line_number = index + 1;
        let Some((instruction, first, last)) = parse_edit_command(&script[index]) else {
            return Err(format!("EDIT ERROR line {line_number}: bad command"));
        };
        let valid = if instruction == 'a' {
            first <= lines.len()
        } else {
            1 <= first && first <= last && last <= lines.len()
        };
        if !valid {
            return Err(format!("EDIT ERROR line {line_number}: bad range"));
        }
        index += 1;
        let mut text: &[String] = &[];
        if instruction != 'd' {
            let Some(length) = script[index..].iter().position(|line| line == ".") else {
                return Err(format!("EDIT ERROR line {line_number}: missing terminator"));
            };
            text = &script[index..index + length];
            index += length + 1;
        }
        match instruction {
            'a' => {
                lines.splice(first..first, text.iter().cloned());
            }
            'c' => {
                lines.splice(first - 1..last, text.iter().cloned());
            }
            _ => {
                lines.drain(first - 1..last);
            }
        }
        executed += 1;
    }
    Ok((lines, executed))
}

#[derive(Clone, Copy, PartialEq)]
enum ChunkKind {
    Stable,
    A,
    B,
    Both,
    Conflict,
}

impl ChunkKind {
    fn name(self) -> &'static str {
        match self {
            ChunkKind::Stable => "stable",
            ChunkKind::A => "a",
            ChunkKind::B => "b",
            ChunkKind::Both => "both",
            ChunkKind::Conflict => "conflict",
        }
    }
}

struct Chunk<'a> {
    kind: ChunkKind,
    base_start: usize,
    ours_start: usize,
    theirs_start: usize,
    base: &'a [String],
    ours: &'a [String],
    theirs: &'a [String],
}

impl Chunk<'_> {
    fn location(&self) -> String {
        format!(
            "base {} a {} b {}",
            range_m(self.base_start, self.base.len()),
            range_m(self.ours_start, self.ours.len()),
            range_m(self.theirs_start, self.theirs.len())
        )
    }
}

fn chunk_kind(base: &[String], ours: &[String], theirs: &[String]) -> ChunkKind {
    if ours == base {
        ChunkKind::B
    } else if theirs == base {
        ChunkKind::A
    } else if ours == theirs {
        ChunkKind::Both
    } else {
        ChunkKind::Conflict
    }
}

fn match_table(first: &[String], second: &[String]) -> Vec<usize> {
    let mut matches = vec![0; first.len() + 2];
    let pairs = matched_pairs(first, second);
    for &(i, j) in &pairs[1..pairs.len() - 1] {
        matches[i] = j;
    }
    matches
}

fn three_way_chunks<'a>(
    base: &'a [String],
    ours: &'a [String],
    theirs: &'a [String],
) -> Vec<Chunk<'a>> {
    let ours_match = match_table(base, ours);
    let theirs_match = match_table(base, theirs);
    let mut chunks = Vec::new();
    let (mut x, mut y, mut z) = (0, 0, 0);
    while x < base.len() || y < ours.len() || z < theirs.len() {
        if x < base.len() && ours_match[x + 1] == y + 1 && theirs_match[x + 1] == z + 1 {
            chunks.push(Chunk {
                kind: ChunkKind::Stable,
                base_start: x,
                ours_start: y,
                theirs_start: z,
                base: &base[x..x + 1],
                ours: &ours[y..y + 1],
                theirs: &theirs[z..z + 1],
            });
            x += 1;
            y += 1;
            z += 1;
            continue;
        }
        let mut anchor = x + 1;
        while anchor <= base.len() && (ours_match[anchor] == 0 || theirs_match[anchor] == 0) {
            anchor += 1;
        }
        let (next_x, next_y, next_z) = if anchor <= base.len() {
            (anchor - 1, ours_match[anchor] - 1, theirs_match[anchor] - 1)
        } else {
            (base.len(), ours.len(), theirs.len())
        };
        let (base_part, ours_part, theirs_part) =
            (&base[x..next_x], &ours[y..next_y], &theirs[z..next_z]);
        chunks.push(Chunk {
            kind: chunk_kind(base_part, ours_part, theirs_part),
            base_start: x,
            ours_start: y,
            theirs_start: z,
            base: base_part,
            ours: ours_part,
            theirs: theirs_part,
        });
        (x, y, z) = (next_x, next_y, next_z);
    }
    chunks
}

fn kind_counts(chunks: &[Chunk]) -> String {
    let count = |kind: ChunkKind| chunks.iter().filter(|chunk| chunk.kind == kind).count();
    format!(
        "a={} b={} both={} conflicts={}",
        count(ChunkKind::A),
        count(ChunkKind::B),
        count(ChunkKind::Both),
        count(ChunkKind::Conflict)
    )
}

fn common_prefix_length(first: &[String], second: &[String]) -> usize {
    first.iter().zip(second).take_while(|(a, b)| a == b).count()
}

fn common_suffix_length(first: &[String], second: &[String], limit: usize) -> usize {
    let mut length = 0;
    while length < limit && first[first.len() - 1 - length] == second[second.len() - 1 - length] {
        length += 1;
    }
    length
}

fn conflict_lines(
    chunk: &Chunk,
    mode: &str,
    base_name: &str,
    ours_name: &str,
    theirs_name: &str,
) -> Vec<String> {
    let (ours, theirs) = (chunk.ours, chunk.theirs);
    let mut lines = Vec::new();
    match mode {
        "OURS" => return ours.to_vec(),
        "THEIRS" => return theirs.to_vec(),
        "DIFF3" => {
            lines.push(format!("<<<<<<< {ours_name}"));
            lines.extend_from_slice(ours);
            lines.push(format!("||||||| {base_name}"));
            lines.extend_from_slice(chunk.base);
            lines.push(SEPARATOR.to_string());
            lines.extend_from_slice(theirs);
            lines.push(format!(">>>>>>> {theirs_name}"));
            return lines;
        }
        _ => {}
    }
    let head = common_prefix_length(ours, theirs);
    let tail = common_suffix_length(ours, theirs, ours.len().min(theirs.len()) - head);
    let ours_middle = &ours[head..ours.len() - tail];
    let theirs_middle = &theirs[head..theirs.len() - tail];
    lines.extend_from_slice(&ours[..head]);
    if mode == "UNION" {
        lines.extend_from_slice(ours_middle);
        lines.extend_from_slice(theirs_middle);
    } else {
        lines.push(format!("<<<<<<< {ours_name}"));
        lines.extend_from_slice(ours_middle);
        lines.push(SEPARATOR.to_string());
        lines.extend_from_slice(theirs_middle);
        lines.push(format!(">>>>>>> {theirs_name}"));
    }
    lines.extend_from_slice(&ours[ours.len() - tail..]);
    lines
}

#[derive(Clone, Copy, PartialEq)]
enum Marker {
    Start,
    Base,
    Separator,
    End,
}

fn marker_kind(line: &str) -> Option<Marker> {
    if line == SEPARATOR {
        return Some(Marker::Separator);
    }
    if line.len() > 7 && line.as_bytes()[7] != b' ' {
        return None;
    }
    match line.get(..7)? {
        "<<<<<<<" => Some(Marker::Start),
        "|||||||" => Some(Marker::Base),
        ">>>>>>>" => Some(Marker::End),
        _ => None,
    }
}

fn next_marker(lines: &[String], index: usize) -> usize {
    let mut index = index + 1;
    while index < lines.len() && marker_kind(&lines[index]).is_none() {
        index += 1;
    }
    index
}

fn marker_at(lines: &[String], index: usize) -> Option<Marker> {
    lines.get(index).and_then(|line| marker_kind(line))
}

struct ConflictRegion<'a> {
    start: usize,
    end: usize,
    ours: &'a [String],
    base: Option<&'a [String]>,
    theirs: &'a [String],
}

impl ConflictRegion<'_> {
    fn part(&self, side: &str) -> Vec<String> {
        match side {
            "OURS" => self.ours.to_vec(),
            "THEIRS" => self.theirs.to_vec(),
            "BASE" => self.base.unwrap_or_default().to_vec(),
            _ => [self.ours, self.theirs].concat(),
        }
    }
}

fn region_at(lines: &[String], start: usize) -> Option<ConflictRegion<'_>> {
    if marker_at(lines, start) != Some(Marker::Start) {
        return None;
    }
    let mut middle = next_marker(lines, start);
    let mut base_marker = None;
    if marker_at(lines, middle) == Some(Marker::Base) {
        base_marker = Some(middle);
        middle = next_marker(lines, middle);
    }
    if marker_at(lines, middle) != Some(Marker::Separator) {
        return None;
    }
    let end = next_marker(lines, middle);
    if marker_at(lines, end) != Some(Marker::End) {
        return None;
    }
    Some(ConflictRegion {
        start: start + 1,
        end: end + 1,
        ours: &lines[start + 1..base_marker.unwrap_or(middle)],
        base: base_marker.map(|marker| &lines[marker + 1..middle]),
        theirs: &lines[middle + 1..end],
    })
}

fn conflict_regions(lines: &[String]) -> Vec<ConflictRegion<'_>> {
    let mut regions = Vec::new();
    let mut index = 0;
    while index < lines.len() {
        match region_at(lines, index) {
            Some(region) => {
                index = region.end;
                regions.push(region);
            }
            None => index += 1,
        }
    }
    regions
}

#[derive(Default)]
struct Workspace {
    files: BTreeMap<String, Vec<String>>,
    history: HashMap<String, Vec<Option<Vec<String>>>>,
    output: Vec<String>,
}

impl Workspace {
    fn require(&self, names: &[&str]) -> CommandResult {
        for name in names {
            if !self.files.contains_key(*name) {
                return Err(format!("ERROR no such file {name}"));
            }
        }
        Ok(())
    }

    fn save(&mut self, name: &str, lines: Vec<String>) {
        let previous = self.files.insert(name.to_string(), lines);
        self.history
            .entry(name.to_string())
            .or_default()
            .push(previous);
    }

    fn load_file(&mut self, arguments: &[&str], data: &[String]) -> CommandResult {
        let name = arguments[0];
        self.save(name, data.to_vec());
        self.output
            .push(format!("FILE {name} lines={}", data.len()));
        Ok(())
    }

    fn copy(&mut self, arguments: &[&str]) -> CommandResult {
        let (source, target) = (arguments[0], arguments[1]);
        self.require(&[source])?;
        let lines = self.files[source].clone();
        self.output
            .push(format!("COPY {source} {target} lines={}", lines.len()));
        self.save(target, lines);
        Ok(())
    }

    fn print_file(&mut self, arguments: &[&str]) -> CommandResult {
        let name = arguments[0];
        self.require(&[name])?;
        let lines = &self.files[name];
        self.output
            .push(format!("PRINT {name} lines={}", lines.len()));
        for (index, line) in lines.iter().enumerate() {
            self.output.push(format!("{:>3}| {line}", index + 1));
        }
        Ok(())
    }

    fn list_files(&mut self) -> CommandResult {
        self.output
            .push(format!("FILES count={}", self.files.len()));
        for (name, lines) in &self.files {
            let undo = self.history[name].len();
            self.output
                .push(format!("{name} lines={} undo={undo}", lines.len()));
        }
        Ok(())
    }

    fn undo(&mut self, arguments: &[&str]) -> CommandResult {
        let name = arguments[0];
        match self.history.get_mut(name).and_then(|states| states.pop()) {
            None => return Err(format!("ERROR nothing to undo {name}")),
            Some(None) => {
                self.files.remove(name);
                self.output.push(format!("UNDO {name} removed"));
            }
            Some(Some(state)) => {
                self.output
                    .push(format!("UNDO {name} lines={}", state.len()));
                self.files.insert(name.to_string(), state);
            }
        }
        Ok(())
    }

    fn diff(&mut self, arguments: &[&str]) -> CommandResult {
        let (old_name, new_name, form) = (arguments[0], arguments[1], arguments[2]);
        self.require(&[old_name, new_name])?;
        let (parameter, options) = if FORMATS_WITH_ARGUMENT.contains(&form) {
            (arguments[3], &arguments[4..])
        } else {
            ("", &arguments[3..])
        };
        let diff = LineDiff::new(&self.files[old_name], &self.files[new_name], options);
        let lines = if diff.blocks.is_empty() {
            vec![format!("Files {old_name} and {new_name} are identical")]
        } else {
            match form {
                "BRIEF" => vec![format!("Files {old_name} and {new_name} differ")],
                "NORMAL" => diff.normal(),
                "ED" => diff.ed(),
                "RCS" => diff.rcs(),
                "IFDEF" => diff.ifdef(parameter),
                "UNIFIED" => diff.unified(parameter.parse().unwrap(), old_name, new_name),
                "CONTEXT" => diff.context(parameter.parse().unwrap(), old_name, new_name),
                _ => diff.side_by_side(parameter.parse().unwrap()),
            }
        };
        self.output.extend(lines);
        Ok(())
    }

    fn token_diff(&mut self, arguments: &[&str], by_word: bool) -> CommandResult {
        let (old_name, new_name) = (arguments[0], arguments[1]);
        self.require(&[old_name, new_name])?;
        let (old, new) = (&self.files[old_name], &self.files[new_name]);
        let diff = LineDiff::new(old, new, &[]);
        if diff.blocks.is_empty() {
            self.output
                .push(format!("Files {old_name} and {new_name} are identical"));
            return Ok(());
        }
        let separator = if by_word { " " } else { "" };
        let mut totals = TokenTotals::default();
        for block in &diff.blocks {
            for row in 0..block.x.max(block.y) {
                let (old_number, new_number) = (block.p + row + 1, block.q + row + 1);
                let line = if row < block.x && row < block.y {
                    let old_tokens = split_tokens(&old[old_number - 1], by_word);
                    let new_tokens = split_tokens(&new[new_number - 1], by_word);
                    let text = compare_tokens(&old_tokens, &new_tokens, separator, &mut totals);
                    format!("a{old_number} b{new_number}: {text}")
                } else if row < block.x {
                    let old_tokens = split_tokens(&old[old_number - 1], by_word);
                    totals.deleted += old_tokens.len();
                    format!("a{old_number}: {}", deletion(&old_tokens, separator))
                } else {
                    let new_tokens = split_tokens(&new[new_number - 1], by_word);
                    totals.inserted += new_tokens.len();
                    format!("b{new_number}: {}", insertion(&new_tokens, separator))
                };
                self.output.push(line);
            }
        }
        let label = if by_word { "WORDS" } else { "CHARS" };
        self.output.push(format!(
            "{label} deleted={} inserted={} common={}",
            totals.deleted, totals.inserted, totals.common
        ));
        Ok(())
    }

    fn stat(&mut self, arguments: &[&str]) -> CommandResult {
        let (old_name, new_name) = (arguments[0], arguments[1]);
        self.require(&[old_name, new_name])?;
        let (old, new) = (&self.files[old_name], &self.files[new_name]);
        let diff = LineDiff::new(old, new, &arguments[2..]);
        let deleted: usize = diff.blocks.iter().map(|block| block.x).sum();
        let inserted: usize = diff.blocks.iter().map(|block| block.y).sum();
        let total = deleted + inserted;
        let unchanged = old.len() - deleted;
        let mut summary = format!("{old_name} -> {new_name} | {total}");
        if total > 0 {
            summary += &format!(" {}", stat_graph(inserted, deleted));
        }
        self.output.push(summary);
        let line_total = old.len() + new.len();
        let similarity = if line_total > 0 {
            200 * unchanged / line_total
        } else {
            100
        };
        self.output.push(format!(
            "changes={} insertions={inserted} deletions={deleted} unchanged={unchanged} \
             similarity={similarity}%",
            diff.blocks.len()
        ));
        Ok(())
    }

    fn patch(&mut self, arguments: &[&str], data: &[String]) -> CommandResult {
        let name = arguments[0];
        self.require(&[name])?;
        let options = &arguments[2..];
        let reverse = options.contains(&"REVERSE");
        let dry_run = options.contains(&"DRYRUN");
        let max_fuzz = match options.iter().position(|&option| option == "FUZZ") {
            Some(index) => options[index + 1].parse().unwrap(),
            None => 0,
        };
        let hunks = parse_patch(data)?;
        let verb = if dry_run { "checking" } else { "patching" };
        self.output.push(format!("{verb} file {name}"));
        let mut lines = self.files[name].clone();
        let first = &hunks[0];
        if search_hunk(first, &lines, 0, reverse, max_fuzz).is_none()
            && search_hunk(first, &lines, 0, !reverse, max_fuzz).is_some()
        {
            self.output.push(
                "Reversed (or previously applied) patch detected! Skipping patch.".to_string(),
            );
            self.output.push(format!(
                "RESULT applied=0 failed=0 ignored={} lines={}",
                hunks.len(),
                lines.len()
            ));
            return Ok(());
        }
        let mut adjustment = 0;
        let (mut applied, mut failed) = (0, 0);
        for (index, hunk) in hunks.iter().enumerate() {
            let number = index + 1;
            let Some(found) = search_hunk(hunk, &lines, adjustment, reverse, max_fuzz) else {
                failed += 1;
                self.output
                    .push(format!("Hunk #{number} FAILED at {}", hunk.start(reverse)));
                continue;
            };
            let (old, new) = hunk.sequences(reverse);
            adjustment += found.delta + new.len() as i64 - old.len() as i64;
            applied += 1;
            self.output.push(found.report(number));
            lines = found.lines;
        }
        self.output.push(format!(
            "RESULT applied={applied} failed={failed} ignored=0 lines={}",
            lines.len()
        ));
        if !dry_run && applied >= 1 {
            self.save(name, lines);
        }
        Ok(())
    }

    fn edit(&mut self, arguments: &[&str], data: &[String]) -> CommandResult {
        let name = arguments[0];
        self.require(&[name])?;
        let (lines, executed) = run_edit_script(&self.files[name], data)?;
        self.output.push(format!(
            "EDIT {name} commands={executed} lines={}",
            lines.len()
        ));
        self.save(name, lines);
        Ok(())
    }

    fn diff3(&mut self, arguments: &[&str]) -> CommandResult {
        let (base_name, ours_name, theirs_name) = (arguments[0], arguments[1], arguments[2]);
        self.require(&[base_name, ours_name, theirs_name])?;
        let chunks = three_way_chunks(
            &self.files[base_name],
            &self.files[ours_name],
            &self.files[theirs_name],
        );
        let changes: Vec<&Chunk> = chunks
            .iter()
            .filter(|chunk| chunk.kind != ChunkKind::Stable)
            .collect();
        for chunk in &changes {
            self.output
                .push(format!("==== {} {}", chunk.kind.name(), chunk.location()));
            self.output
                .extend(chunk.base.iter().map(|line| format!("O {line}")));
            if chunk.kind != ChunkKind::B {
                self.output
                    .extend(chunk.ours.iter().map(|line| format!("A {line}")));
            }
            if matches!(chunk.kind, ChunkKind::B | ChunkKind::Conflict) {
                self.output
                    .extend(chunk.theirs.iter().map(|line| format!("B {line}")));
            }
        }
        self.output.push(format!(
            "DIFF3 chunks={} {}",
            changes.len(),
            kind_counts(&chunks)
        ));
        Ok(())
    }

    fn merge(&mut self, arguments: &[&str]) -> CommandResult {
        let (base_name, ours_name, theirs_name, target) =
            (arguments[0], arguments[1], arguments[2], arguments[3]);
        let mode = arguments.get(4).copied().unwrap_or("MARKERS");
        self.require(&[base_name, ours_name, theirs_name])?;
        let chunks = three_way_chunks(
            &self.files[base_name],
            &self.files[ours_name],
            &self.files[theirs_name],
        );
        let mut result = Vec::new();
        let mut conflicts = Vec::new();
        for chunk in &chunks {
            match chunk.kind {
                ChunkKind::B => result.extend_from_slice(chunk.theirs),
                ChunkKind::Conflict => {
                    result.extend(conflict_lines(
                        chunk,
                        mode,
                        base_name,
                        ours_name,
                        theirs_name,
                    ));
                    conflicts.push(chunk);
                }
                _ => result.extend_from_slice(chunk.ours),
            }
        }
        self.output.push(format!(
            "MERGE {target} lines={} {}",
            result.len(),
            kind_counts(&chunks)
        ));
        for (index, chunk) in conflicts.iter().enumerate() {
            self.output
                .push(format!("CONFLICT {} {}", index + 1, chunk.location()));
        }
        self.save(target, result);
        Ok(())
    }

    fn conflicts(&mut self, arguments: &[&str]) -> CommandResult {
        let name = arguments[0];
        self.require(&[name])?;
        let regions = conflict_regions(&self.files[name]);
        self.output
            .push(format!("CONFLICTS {name} count={}", regions.len()));
        for (index, region) in regions.iter().enumerate() {
            let base = region
                .base
                .map_or("none".to_string(), |base| base.len().to_string());
            self.output.push(format!(
                "{}: lines {}-{} ours={} base={base} theirs={}",
                index + 1,
                region.start,
                region.end,
                region.ours.len(),
                region.theirs.len()
            ));
        }
        Ok(())
    }

    fn resolve(&mut self, arguments: &[&str]) -> CommandResult {
        let (name, number_text, side) = (arguments[0], arguments[1], arguments[2]);
        self.require(&[name])?;
        let number: usize = number_text.parse().unwrap();
        let lines = &self.files[name];
        let regions = conflict_regions(lines);
        if regions.len() < number {
            return Err(format!("ERROR no conflict {number} in {name}"));
        }
        let region = &regions[number - 1];
        if side == "BASE" && region.base.is_none() {
            return Err(format!("ERROR no base section in conflict {number}"));
        }
        let mut content = lines[..region.start - 1].to_vec();
        content.extend(region.part(side));
        content.extend_from_slice(&lines[region.end..]);
        let remaining = conflict_regions(&content).len();
        self.output.push(format!(
            "RESOLVE {name} {number} {side} lines={} remaining={remaining}",
            content.len()
        ));
        self.save(name, content);
        Ok(())
    }

    fn execute(&mut self, words: &[&str], data: &[String]) {
        let arguments = &words[1..];
        let result = match words[0] {
            "FILE" => self.load_file(arguments, data),
            "COPY" => self.copy(arguments),
            "PRINT" => self.print_file(arguments),
            "FILES" => self.list_files(),
            "DIFF" => self.diff(arguments),
            "WORDDIFF" => self.token_diff(arguments, true),
            "CHARDIFF" => self.token_diff(arguments, false),
            "STAT" => self.stat(arguments),
            "PATCH" => self.patch(arguments, data),
            "EDIT" => self.edit(arguments, data),
            "DIFF3" => self.diff3(arguments),
            "MERGE" => self.merge(arguments),
            "CONFLICTS" => self.conflicts(arguments),
            "RESOLVE" => self.resolve(arguments),
            "UNDO" => self.undo(arguments),
            other => panic!("unknown command {other}"),
        };
        if let Err(message) = result {
            self.output.push(message);
        }
    }
}

fn main() {
    let mut input = String::new();
    io::stdin().read_to_string(&mut input).unwrap();
    let lines: Vec<String> = input.lines().map(String::from).collect();
    let mut workspace = Workspace::default();
    let command_count: usize = lines[0].trim().parse().unwrap();
    let mut position = 1;
    for _ in 0..command_count {
        let words: Vec<&str> = lines[position].split(' ').collect();
        position += 1;
        let mut data: &[String] = &[];
        if DATA_COMMANDS.contains(&words[0]) {
            let count: usize = words[2].parse().unwrap();
            data = &lines[position..position + count];
            position += count;
        }
        workspace.execute(&words, data);
    }
    let mut output = workspace.output.join("\n");
    output.push('\n');
    io::stdout().write_all(output.as_bytes()).unwrap();
}
