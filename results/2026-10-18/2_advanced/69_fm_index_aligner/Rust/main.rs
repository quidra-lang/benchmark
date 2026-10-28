mod sequence_io;
mod suffix_array;
mod fm_index;
mod search;
mod sam_writer;

use std::collections::{BTreeMap, BTreeSet};
use sequence_io::{Reference, Read, Params};
use fm_index::Index;
use sam_writer::ratio;

fn text_position(position: usize, references: &[Reference], offsets: &[usize]) -> Option<(usize, usize)> {
    let r = offsets.partition_point(|&offset| offset <= position).checked_sub(1)?;
    if position < offsets[r]+references[r].sequence.len() { Some((r, position-offsets[r])) } else { None }
}
fn position_name(position: usize, references: &[Reference], offsets: &[usize]) -> String {
    text_position(position, references, offsets).map_or_else(|| "*".to_owned(), |(r, p)| format!("{}:{}", references[r].name, p+1))
}
fn bytes(sequence: &[u8]) -> String { String::from_utf8(sequence.to_vec()).unwrap() }
fn base_index(base: u8) -> usize { match base { b'A' => 0, b'C' => 1, b'G' => 2, b'T' => 3, _ => 4 } }

#[derive(Clone)]
struct Alignment { reference: usize, position: usize, reverse: bool, operations: Vec<u8>, score: i64, mismatches: usize }
struct Mapping { length: usize, trimmed: usize, method: &'static str, primary: Option<Alignment>, others: Vec<Alignment>, mapq: usize, x0: usize, x1: usize, best_references: BTreeSet<usize> }
#[derive(Default)]
struct SearchTotals { calls: usize, nodes: usize, leaves: usize, positions: usize, seed_reads: usize, seeds: usize, with_n: usize, repetitive: usize, no_seed_hit: usize, candidates: usize, passing: usize }

const UNREACHABLE: i64 = -1000000;
#[derive(Clone, Copy)]
struct Cell { h: i64, e: i64, f: i64 }
fn add(value: i64, delta: i64) -> i64 { if value == UNREACHABLE { UNREACHABLE } else { value+delta } }
fn cell(rows: &[BTreeMap<usize, Cell>], i: usize, j: usize) -> Cell {
    rows[i].get(&j).copied().unwrap_or(Cell { h: UNREACHABLE, e: UNREACHABLE, f: UNREACHABLE })
}

fn affine(sequence: &[u8], reference: &[u8], center: i64, p: &Params) -> Option<(usize, i64, Vec<u8>)> {
    let length = sequence.len(); let m = reference.len(); let [matched, mismatch, open, extend] = p.scores;
    let mut rows = vec![BTreeMap::new(); length+1];
    for i in 0..=length {
        let lower = (i as i64+center-p.band).max(0);
        let upper = (i as i64+center+p.band).min(m as i64);
        if lower > upper { continue; }
        for j in lower as usize..=upper as usize {
            if i == 0 { rows[0].insert(j, Cell { h: 0, e: UNREACHABLE, f: UNREACHABLE }); continue; }
            let above = cell(&rows, i-1, j);
            let f = add(above.h, -open-extend).max(add(above.f, -extend));
            let e = if j == 0 { UNREACHABLE } else { let left = cell(&rows, i, j-1); add(left.h, -open-extend).max(add(left.e, -extend)) };
            let diagonal = if j == 0 { UNREACHABLE } else { add(cell(&rows, i-1, j-1).h, if sequence[i-1] == reference[j-1] { matched } else { -mismatch }) };
            rows[i].insert(j, Cell { h: diagonal.max(e).max(f), e, f });
        }
    }
    let (&endpoint, best) = rows[length].iter().filter(|(_, c)| c.h != UNREACHABLE).min_by_key(|&(j, c)| (std::cmp::Reverse(c.h), *j))?;
    let score = best.h;
    let (mut i, mut j, mut state) = (length, endpoint, b'H'); let mut operations = Vec::new();
    loop {
        let current = cell(&rows, i, j);
        if state == b'H' {
            if i == 0 { break; }
            let diagonal = if j == 0 { UNREACHABLE } else { add(cell(&rows, i-1, j-1).h, if sequence[i-1] == reference[j-1] { matched } else { -mismatch }) };
            if j > 0 && diagonal != UNREACHABLE && current.h == diagonal { operations.push(b'M'); i -= 1; j -= 1; }
            else if current.f != UNREACHABLE && current.h == current.f { state = b'I'; }
            else { state = b'D'; }
        } else if state == b'I' {
            operations.push(b'I');
            let previous = cell(&rows, i-1, j).f;
            state = if previous != UNREACHABLE && current.f == previous-extend { b'I' } else { b'H' }; i -= 1;
        } else {
            operations.push(b'D');
            let previous = cell(&rows, i, j-1).e;
            state = if previous != UNREACHABLE && current.e == previous-extend { b'D' } else { b'H' }; j -= 1;
        }
    }
    operations.reverse(); Some((j, score, operations))
}

fn map(read: &Read, p: &Params, references: &[Reference], offsets: &[usize], forward: &Index, reverse: &Index, totals: &mut SearchTotals) -> Mapping {
    let mut length = read.sequence.len();
    while length > 0 && read.quality[length-1]-33 < p.trim { length -= 1; }
    let mut result = Mapping { length, trimmed: read.sequence.len()-length, method: "SHORT", primary: None, others: Vec::new(), mapq: 0, x0: 0, x1: 0, best_references: BTreeSet::new() };
    if length < p.minimum { return result; }
    result.method = "NOHIT";
    let oriented = [read.sequence[..length].to_vec(), sequence_io::reverse_complement(&read.sequence[..length])];
    let exact = oriented.iter().any(|sequence| { let interval = forward.exact(sequence); interval.0 < interval.1 });
    let maximum = if exact { 1 } else { p.mismatches };
    let mut hits = Vec::new();
    for strand in 0..2 {
        let search = search::backtrack(&oriented[strand], maximum, forward, reverse);
        totals.calls += 1; totals.nodes += search.nodes; totals.leaves += search.leaves; totals.positions += search.hits.len();
        for (position, mismatches) in search.hits {
            if let Some((reference, position)) = text_position(position, references, offsets) {
                hits.push(Alignment { reference, position, reverse: strand == 1, operations: vec![b'M'; length], score: 0, mismatches });
            }
        }
    }
    if !hits.is_empty() {
        hits.sort_by_key(|h| (h.mismatches, h.reference, h.position, h.reverse));
        let best = hits[0].mismatches;
        result.method = if best == 0 { "EXACT" } else { "MISMATCH" };
        result.x0 = hits.iter().filter(|h| h.mismatches == best).count(); result.x1 = hits.iter().filter(|h| h.mismatches == best+1).count();
        result.best_references = hits.iter().filter(|h| h.mismatches == best).map(|h| h.reference).collect();
        result.mapq = if result.x0 >= 2 { 0 } else if result.x1 == 0 { 60-12*best }
            else { (30i64-12*best as i64-3*result.x1 as i64).max(1) as usize };
        hits[0].score = (length-best) as i64*p.scores[0]-best as i64*p.scores[1];
        result.primary = Some(hits.remove(0)); result.others = hits.into_iter().filter(|h| h.mismatches <= best+1).collect(); return result;
    }
    if length < p.seed { return result; }
    totals.seed_reads += 1;
    let mut candidates = BTreeSet::new();
    for strand in 0..2 {
        for offset in (0..=length-p.seed).step_by(p.step) {
            totals.seeds += 1; let seed = &oriented[strand][offset..offset+p.seed];
            if seed.contains(&b'N') { totals.with_n += 1; continue; }
            let (lo, hi) = forward.exact(seed);
            if hi-lo > p.seed_hits { totals.repetitive += 1; continue; }
            if hi == lo { totals.no_seed_hit += 1; continue; }
            for row in lo..hi {
                if let Some((r, e)) = text_position(forward.locate(row).0, references, offsets) { candidates.insert((strand, r, e as i64-offset as i64)); }
            }
        }
    }
    totals.candidates += candidates.len();
    let mut accepted = BTreeMap::<(usize, usize, bool), Alignment>::new();
    for (strand, r, center) in candidates {
        if let Some((position, score, operations)) = affine(&oriented[strand], &references[r].sequence, center, p) {
            if 100*score < p.percent*p.scores[0]*length as i64 { continue; }
            let key = (r, position, strand == 1);
            if accepted.get(&key).map_or(true, |a| score > a.score) { accepted.insert(key, Alignment { reference: r, position, reverse: strand == 1, operations, score, mismatches: 0 }); }
        }
    }
    totals.passing += accepted.len();
    let mut accepted: Vec<_> = accepted.into_values().collect();
    if accepted.is_empty() { return result; }
    accepted.sort_by_key(|a| (std::cmp::Reverse(a.score), a.reference, a.position, a.reverse));
    let score = accepted[0].score; result.method = "SEED";
    result.x0 = accepted.iter().filter(|a| a.score == score).count(); result.x1 = accepted.len()-result.x0;
    result.best_references = accepted.iter().filter(|a| a.score == score).map(|a| a.reference).collect();
    let second = accepted.iter().find(|a| a.score < score).map_or(0, |a| a.score);
    result.mapq = if result.x0 >= 2 { 0 } else { (60*(score-second)/score) as usize };
    result.primary = Some(accepted.remove(0)); result.others = accepted; result
}

struct Description { cigar: String, nm: usize, md: String, pairs: Vec<(usize, usize)> }
fn describe(alignment: &Alignment, sequence: &[u8], reference: &[u8], trimmed: usize) -> Description {
    let mut cigar = String::new();
    if alignment.reverse && trimmed > 0 { cigar.push_str(&format!("{}S", trimmed)); }
    let (mut i, mut j, mut position) = (0, alignment.position, 0); let mut nm = 0; let mut matches = 0; let mut md = String::new(); let mut pairs = Vec::new();
    while position < alignment.operations.len() {
        let operation = alignment.operations[position]; let first = position;
        while position < alignment.operations.len() && alignment.operations[position] == operation { position += 1; }
        let count = position-first; cigar.push_str(&format!("{}{}", count, operation as char));
        if operation == b'D' {
            md.push_str(&format!("{}^{}", matches, bytes(&reference[j..j+count]))); matches = 0; nm += count; j += count;
        } else if operation == b'I' { nm += count; i += count; }
        else {
            for _ in 0..count {
                pairs.push((i, j));
                if sequence[i] == reference[j] { matches += 1; } else { md.push_str(&format!("{}{}", matches, reference[j] as char)); matches = 0; nm += 1; }
                i += 1; j += 1;
            }
        }
    }
    md.push_str(&matches.to_string()); if !alignment.reverse && trimmed > 0 { cigar.push_str(&format!("{}S", trimmed)); }
    Description { cigar, nm, md, pairs }
}

fn index_statistics(text: &[u8], reverse_text: &[u8], sa: &suffix_array::SuffixArray, reverse_sa: &suffix_array::SuffixArray,
                    forward: &Index, reverse: &Index, references: &[Reference], offsets: &[usize], p: &Params) -> Vec<String> {
    let n = text.len(); let mut lines = vec![format!("text length {} sequences {}", n, references.len())];
    for (r, reference) in references.iter().enumerate() { lines.push(format!("sequence {} length {} offset {} gc {} masked {}", reference.name, reference.sequence.len(), offsets[r],
        ratio(reference.sequence.iter().filter(|&&b| b == b'G' || b == b'C').count(), reference.sequence.len()), reference.masked)); }
    lines.push(format!("symbols {}", [b'$', b'#', b'A', b'C', b'G', b'T'].iter().map(|&c| format!("{} {}", c as char, text.iter().filter(|&&b| b == c).count())).collect::<Vec<_>>().join(" ")));
    lines.extend([String::new(), "forward_index".to_owned(), format!("suffix_array rounds {}", sa.classes.len()-1)]);
    for (round, &classes) in sa.classes.iter().enumerate() { lines.push(format!("round {} prefix_length {} classes {}", round, 1usize<<round, classes)); }
    let check = suffix_array::check(text, &sa.order);
    lines.push(format!("sa_check pairs {} ordered {} lcp_sum {} mean_lcp {} max_lcp {}", n-1, check.ordered, check.sum, ratio(check.sum, n-1), check.maximum));
    lines.push(format!("longest_repeat {} {} {}", check.maximum, position_name(sa.order[check.row-1], references, offsets), position_name(sa.order[check.row], references, offsets)));
    let mut kmers = BTreeMap::<Vec<u8>, usize>::new();
    if p.seed <= n { for position in 0..=n-p.seed { let kmer = &text[position..position+p.seed]; if kmer.iter().all(|&c| matches!(c, b'A' | b'C' | b'G' | b'T')) { *kmers.entry(kmer.to_vec()).or_default() += 1; } } }
    let occurrences: usize = kmers.values().sum(); let unique = kmers.values().filter(|&&n| n == 1).count();
    lines.push(format!("kmers length {} occurrences {} distinct {} unique {} max_occurrence {} unique_fraction {}", p.seed, occurrences, kmers.len(), unique, kmers.values().max().unwrap_or(&0), ratio(unique, occurrences)));
    lines.push(format!("bwt runs {} head {}", forward.runs(), bytes(&forward.bwt[..n.min(60)])));
    lines.push(format!("c_array {}", [b'$', b'#', b'A', b'C', b'G', b'T'].iter().enumerate().map(|(i, &c)| format!("{} {}", c as char, forward.cumulative[i])).collect::<Vec<_>>().join(" ")));
    lines.push(format!("occ interval {} checkpoints {}", p.occ, forward.checkpoints.len()));
    let samples = forward.samples.iter().flatten().count(); lines.push(format!("sa_sample interval {} samples {}", p.sample, samples));
    let (mut correct, mut total_steps, mut max_steps) = (0, 0, 0);
    for row in 0..n { let (position, steps) = forward.locate(row); correct += usize::from(position == sa.order[row]); total_steps += steps; max_steps = max_steps.max(steps); }
    lines.push(format!("locate rows {} correct {} total_steps {} max_steps {} mean_steps {}", n, correct, total_steps, max_steps, ratio(total_steps, n)));
    lines.push(format!("inverse_bwt identical {}", if forward.inverse() == text { "yes" } else { "no" }));
    lines.extend([String::new(), "reverse_index".to_owned(), format!("suffix_array rounds {}", reverse_sa.classes.len()-1),
        format!("sa_check pairs {} ordered {}", n-1, suffix_array::check(reverse_text, &reverse_sa.order).ordered),
        format!("bwt runs {} head {}", reverse.runs(), bytes(&reverse.bwt[..n.min(60)])),
        format!("inverse_bwt identical {}", if reverse.inverse() == reverse_text { "yes" } else { "no" }), String::new(), "direct_sort".to_owned()]);
    let mut direct = 0;
    for reference in references {
        if reference.sequence.len() <= p.direct {
            direct += 1; let mut text = reference.sequence.clone(); text.push(b'$'); let doubled = suffix_array::build(&text);
            lines.push(format!("{} length {} rounds {} identical {}", reference.name, text.len(), doubled.classes.len()-1,
                if doubled.order == suffix_array::direct(&text) { "yes" } else { "no" }));
        }
    }
    if direct == 0 { lines.push("none".to_owned()); }
    let (occ_bytes, sample_bytes, bitmap_bytes) = (24*forward.checkpoints.len(), 4*samples, (n+7)/8);
    let total = n+occ_bytes+sample_bytes+bitmap_bytes;
    lines.extend([String::new(), format!("index_size bwt_bytes {} occ_bytes {} sample_bytes {} bitmap_bytes {} total_bytes {} full_bytes {} ratio {}", n, occ_bytes, sample_bytes, bitmap_bytes, total, 5*n, ratio(total, 5*n))]);
    lines
}

fn main() {
    let (references, reads, p) = sequence_io::read();
    let mut text = Vec::new(); let mut offsets = Vec::new();
    for (i, reference) in references.iter().enumerate() { offsets.push(text.len()); text.extend_from_slice(&reference.sequence); text.push(if i+1 == references.len() { b'$' } else { b'#' }); }
    let mut reverse_text = text[..text.len()-1].to_vec(); reverse_text.reverse(); reverse_text.push(b'$');
    let sa = suffix_array::build(&text); let reverse_sa = suffix_array::build(&reverse_text);
    let forward = Index::new(&text, &sa.order, p.occ, Some(p.sample)); let reverse = Index::new(&reverse_text, &reverse_sa.order, p.occ, None);
    let index_stats = index_statistics(&text, &reverse_text, &sa, &reverse_sa, &forward, &reverse, &references, &offsets, &p);
    let mut search_totals = SearchTotals::default();
    let mappings: Vec<_> = reads.iter().map(|read| map(read, &p, &references, &offsets, &forward, &reverse, &mut search_totals)).collect();
    let mut sam = sam_writer::header(&references);
    let mut depth: Vec<_> = references.iter().map(|r| vec![0usize; r.sequence.len()]).collect();
    let mut mapq0 = depth.clone();
    let mut pileup: Vec<_> = references.iter().map(|r| vec![[[0usize; 2]; 4]; r.sequence.len()]).collect();
    let maximum_length = reads.iter().map(|r| r.sequence.len()).max().unwrap();
    let mut cycles = vec![(0usize, 0usize); maximum_length]; let mut substitution = [[0usize; 5]; 4];
    let mut quality = [(0usize, 0usize); 2]; let mut quality_bins = [(0usize, 0usize); 5];
    let mut cigar = [0usize; 4]; let mut indels = [0usize; 4]; let mut nm_histogram = BTreeMap::<usize, usize>::new();
    for (i, read) in reads.iter().enumerate() {
        let mapping = &mappings[i];
        let Some(alignment) = &mapping.primary else {
            sam.push(sam_writer::record(&vec![read.name.clone(), "4".to_owned(), "*".to_owned(), "0".to_owned(), "0".to_owned(), "*".to_owned(), "*".to_owned(), "0".to_owned(), "0".to_owned(), bytes(&read.sequence), bytes(&read.quality), format!("YM:Z:{}", mapping.method)])); continue;
        };
        let sequence = if alignment.reverse { sequence_io::reverse_complement(&read.sequence[..mapping.length]) } else { read.sequence[..mapping.length].to_vec() };
        let description = describe(alignment, &sequence, &references[alignment.reference].sequence, mapping.trimmed);
        *nm_histogram.entry(description.nm).or_default() += 1;
        let sam_sequence = if alignment.reverse { sequence_io::reverse_complement(&read.sequence) } else { read.sequence.clone() };
        let sam_quality = if alignment.reverse { read.quality.iter().rev().copied().collect() } else { read.quality.clone() };
        let mut fields = vec![read.name.clone(), if alignment.reverse { "16".to_owned() } else { "0".to_owned() }, references[alignment.reference].name.clone(),
            (alignment.position+1).to_string(), mapping.mapq.to_string(), description.cigar.clone(), "*".to_owned(), "0".to_owned(), "0".to_owned(),
            bytes(&sam_sequence), bytes(&sam_quality), format!("NM:i:{}", description.nm), format!("MD:Z:{}", description.md), format!("AS:i:{}", alignment.score),
            format!("X0:i:{}", mapping.x0), format!("X1:i:{}", mapping.x1), format!("YM:Z:{}", mapping.method)];
        if !mapping.others.is_empty() && mapping.others.len() <= p.alternatives {
            let mut alternatives = String::new();
            for other in &mapping.others {
                let oriented = if other.reverse { sequence_io::reverse_complement(&read.sequence[..mapping.length]) } else { read.sequence[..mapping.length].to_vec() };
                let description = describe(other, &oriented, &references[other.reference].sequence, mapping.trimmed);
                alternatives.push_str(&format!("{},{}{},{},{};", references[other.reference].name, if other.reverse { '-' } else { '+' }, other.position+1, description.cigar, description.nm));
            }
            fields.push(format!("XA:Z:{}", alternatives));
        }
        sam.push(sam_writer::record(&fields));
        if mapping.mapq == 0 { mapq0[alignment.reference][alignment.position] += 1; }
        for &(oriented, reference) in &description.pairs {
            let cycle = if alignment.reverse { mapping.length-oriented } else { oriented+1 };
            let q = (read.quality[cycle-1]-33) as usize;
            let mismatch = sequence[oriented] != references[alignment.reference].sequence[reference];
            if mapping.mapq >= p.mapq {
                depth[alignment.reference][reference] += 1;
                if sequence[oriented] != b'N' && q >= p.variants[1] { pileup[alignment.reference][reference][base_index(sequence[oriented])][usize::from(alignment.reverse)] += 1; }
            }
            if mapping.x0 == 1 {
                cycles[cycle-1].0 += 1; cycles[cycle-1].1 += usize::from(mismatch);
                substitution[base_index(references[alignment.reference].sequence[reference])][base_index(sequence[oriented])] += 1;
                quality[usize::from(mismatch)].0 += 1; quality[usize::from(mismatch)].1 += q;
                quality_bins[(q/10).min(4)].0 += 1; quality_bins[(q/10).min(4)].1 += usize::from(mismatch);
            }
        }
        let mut previous = b' ';
        for &operation in &alignment.operations {
            let category = match operation { b'M' => 0, b'I' => 1, _ => 2 }; cigar[category] += 1;
            if mapping.x0 == 1 && operation != b'M' {
                let category = if operation == b'I' { 0 } else { 2 }; indels[category+1] += 1;
                if operation != previous { indels[category] += 1; }
            }
            previous = operation;
        }
        cigar[3] += mapping.trimmed;
    }
    let mut coverage = vec![format!("window {} min_mapq {}", p.coverage, p.mapq)];
    for (r, reference) in references.iter().enumerate() {
        let depths = &depth[r]; let maximum = *depths.iter().max().unwrap(); let covered = depths.iter().filter(|&&d| d > 0).count(); let sum: usize = depths.iter().sum();
        coverage.push(format!("reference {} length {} covered {} breadth {} mean_depth {} max_depth {}", reference.name, depths.len(), covered, ratio(covered, depths.len()), ratio(sum, depths.len()), maximum));
        coverage.push(format!("depth_histogram {}", (0..=maximum).map(|d| format!("{}:{}", d, depths.iter().filter(|&&v| v == d).count())).collect::<Vec<_>>().join(" ")));
        for first in (0..depths.len()).step_by(p.coverage) {
            let end = (first+p.coverage).min(depths.len()); let values = &depths[first..end]; let sum: usize = values.iter().sum();
            let gc = reference.sequence[first..end].iter().filter(|&&b| b == b'G' || b == b'C').count();
            coverage.push(format!("{} {} {} gc {} sum {} mean {} max {} zero {} mapq0 {} |{}", reference.name, first+1, end, ratio(gc, end-first), sum,
                ratio(sum, end-first), values.iter().max().unwrap(), values.iter().filter(|&&v| v == 0).count(), mapq0[r][first..end].iter().sum::<usize>(), "#".repeat(10*sum/(end-first))));
        }
    }
    let mut variants = vec![format!("min_depth {} min_base_quality {} min_alt_percent {} hom_percent {}", p.variants[0], p.variants[1], p.variants[2], p.variants[3])];
    let (mut callable, mut heterozygous, mut homozygous) = (0, 0, 0);
    for (r, reference) in references.iter().enumerate() {
        for position in 0..reference.sequence.len() {
            let counts: Vec<usize> = pileup[r][position].iter().map(|strands| strands[0]+strands[1]).collect();
            let dp: usize = counts.iter().sum(); if dp < p.variants[0] { continue; } callable += 1;
            let ref_index = base_index(reference.sequence[position]);
            let alternate = (0..4).filter(|&b| b != ref_index).min_by_key(|&b| (std::cmp::Reverse(counts[b]), b)).unwrap();
            let alt = counts[alternate]; if alt < 2 || 100*alt < p.variants[2]*dp { continue; }
            let hom = 100*alt >= p.variants[3]*dp; if hom { homozygous += 1; } else { heterozygous += 1; }
            variants.push(format!("{} {} {}>{} depth {} alt {} fraction {} genotype {} strands {} {} counts {}", reference.name, position+1, reference.sequence[position] as char,
                b"ACGT"[alternate] as char, dp, alt, ratio(alt, dp), if hom { "1/1" } else { "0/1" }, pileup[r][position][alternate][0], pileup[r][position][alternate][1], counts.iter().map(usize::to_string).collect::<Vec<_>>().join(" ")));
        }
    }
    variants.push(format!("callable {} variants {} heterozygous {} homozygous {}", callable, heterozygous+homozygous, heterozygous, homozygous));
    let mapped = mappings.iter().filter(|m| m.primary.is_some()).count(); let unique = mappings.iter().filter(|m| m.x0 == 1).count();
    let short = mappings.iter().filter(|m| m.method == "SHORT").count();
    let mut summary = vec![format!("reads total {} trimmed {} trimmed_bases {} short {}", reads.len(), mappings.iter().filter(|m| m.trimmed > 0).count(), mappings.iter().map(|m| m.trimmed).sum::<usize>(), short),
        format!("mapped {} rate {} unique {} multi {} unmapped {}", mapped, ratio(mapped, reads.len()), unique, mapped-unique, reads.len()-mapped),
        format!("unmapped short {} nohit {}", short, mappings.iter().filter(|m| m.method == "NOHIT").count()),
        format!("method exact {} mismatch {} seed {}", mappings.iter().filter(|m| m.method == "EXACT").count(), mappings.iter().filter(|m| m.method == "MISMATCH").count(), mappings.iter().filter(|m| m.method == "SEED").count()),
        format!("strand forward {} reverse {}", mappings.iter().filter(|m| m.primary.as_ref().map_or(false, |a| !a.reverse)).count(), mappings.iter().filter(|m| m.primary.as_ref().map_or(false, |a| a.reverse)).count())];
    for (r, reference) in references.iter().enumerate() {
        let assigned: Vec<_> = mappings.iter().filter(|m| m.primary.as_ref().map_or(false, |a| a.reference == r)).collect();
        let reverse = assigned.iter().filter(|m| m.primary.as_ref().unwrap().reverse).count();
        summary.push(format!("reference {} mapped {} unique {} forward {} reverse {}", reference.name, assigned.len(), assigned.iter().filter(|m| m.x0 == 1).count(), assigned.len()-reverse, reverse));
    }
    summary.push("length_bins".to_owned());
    let minimum = mappings.iter().map(|m| m.length).min().unwrap()/10*10;
    let maximum = mappings.iter().map(|m| m.length).max().unwrap()/10*10;
    for lo in (minimum..=maximum).step_by(10) {
        let set: Vec<_> = mappings.iter().filter(|m| lo <= m.length && m.length <= lo+9).collect();
        summary.push(format!("{}-{} reads {} mapped {} unique {}", lo, lo+9, set.len(), set.iter().filter(|m| m.primary.is_some()).count(), set.iter().filter(|m| m.x0 == 1).count()));
    }
    let n_reads: Vec<_> = reads.iter().enumerate().filter(|(_, r)| r.sequence.contains(&b'N')).collect();
    summary.push(format!("n_reads {} n_bases {} mapped {}", n_reads.len(), n_reads.iter().map(|(_, r)| r.sequence.iter().filter(|&&b| b == b'N').count()).sum::<usize>(), n_reads.iter().filter(|(i, _)| mappings[*i].primary.is_some()).count()));
    summary.push("multi_targets".to_owned());
    let mut multi = BTreeMap::<String, usize>::new();
    for mapping in mappings.iter().filter(|m| m.x0 >= 2) { let key = mapping.best_references.iter().map(|&r| references[r].name.as_str()).collect::<Vec<_>>().join("+"); *multi.entry(key).or_default() += 1; }
    if multi.is_empty() { summary.push("none".to_owned()); } else { for (names, count) in multi { summary.push(format!("{} {}", names, count)); } }
    summary.push("mapq_histogram".to_owned()); let mut mapq = BTreeMap::<usize, usize>::new();
    for mapping in mappings.iter().filter(|m| m.primary.is_some()) { *mapq.entry(mapping.mapq).or_default() += 1; }
    for (quality, count) in mapq.into_iter().rev() { summary.push(format!("{} {}", quality, count)); }
    summary.push("nm_histogram".to_owned()); for (nm, count) in nm_histogram { summary.push(format!("{} {}", nm, count)); }
    let aligned: usize = cycles.iter().map(|c| c.0).sum(); let mismatches: usize = cycles.iter().map(|c| c.1).sum();
    summary.push(format!("error_profile aligned_bases {} mismatches {} rate {}", aligned, mismatches, ratio(mismatches, aligned)));
    summary.extend(["substitutions".to_owned(), "ref A C G T N".to_owned()]);
    for base in 0..4 { summary.push(format!("{} {}", b"ACGT"[base] as char, substitution[base].iter().map(usize::to_string).collect::<Vec<_>>().join(" "))); }
    summary.push("mismatch_by_cycle".to_owned());
    for (i, &(aligned, mismatches)) in cycles.iter().enumerate() { summary.push(format!("cycle {} aligned {} mismatches {} rate {}", i+1, aligned, mismatches, ratio(mismatches, aligned))); }
    summary.push(format!("quality matched {} mean {} mismatched {} mean {}", quality[0].0, ratio(quality[0].1, quality[0].0), quality[1].0, ratio(quality[1].1, quality[1].0)));
    summary.push("quality_bins".to_owned());
    for (i, &(aligned, mismatches)) in quality_bins.iter().enumerate() { summary.push(format!("{} aligned {} mismatches {} rate {}", ["0-9", "10-19", "20-29", "30-39", "40-"][i], aligned, mismatches, ratio(mismatches, aligned))); }
    summary.push(format!("cigar M {} I {} D {} S {}", cigar[0], cigar[1], cigar[2], cigar[3]));
    summary.push(format!("indels insertions {} {} deletions {} {}", indels[0], indels[1], indels[2], indels[3]));
    summary.push(format!("search dfs_calls {} dfs_nodes {} dfs_leaves {} dfs_positions {}", search_totals.calls, search_totals.nodes, search_totals.leaves, search_totals.positions));
    summary.push(format!("seeds reads {} seeds {} with_n {} repetitive {} without_hit {} candidates {} passing {}", search_totals.seed_reads, search_totals.seeds,
        search_totals.with_n, search_totals.repetitive, search_totals.no_seed_hit, search_totals.candidates, search_totals.passing));
    for (file, lines) in [("alignments.sam", sam), ("coverage.txt", coverage), ("variants.txt", variants), ("index_stats.txt", index_stats), ("summary.txt", summary)] { sam_writer::write(file, &lines); }
}
