use std::cmp::Ordering;
use crate::pgm_reader::Image;

pub struct Histogram {
    pub maxval: usize,
    pub pixels: i64,
    pub counts: Vec<i64>,
    below_counts: Vec<i64>,
    below_sums: Vec<i64>,
    pub total: i64,
    pub minimum: usize,
    pub maximum: usize,
    pub levels: usize,
    pub median: usize,
    pub mode: usize,
    pub bin_width: usize,
    pub bins: Vec<i64>,
}

impl Histogram {
    pub fn new(image: &Image) -> Self {
        let pixels = (image.width * image.height) as i64;
        let mut counts = vec![0; image.maxval + 1];
        for row in &image.pixels { for &value in row { counts[value as usize] += 1; } }
        let mut below_counts = Vec::new();
        let mut below_sums = Vec::new();
        let (mut count, mut total) = (0, 0);
        for (value, &frequency) in counts.iter().enumerate() {
            count += frequency;
            total += value as i64 * frequency;
            below_counts.push(count);
            below_sums.push(total);
        }
        let present: Vec<_> = (0..counts.len()).filter(|&value| counts[value] > 0).collect();
        let minimum = present[0];
        let maximum = *present.last().unwrap();
        let levels = present.len();
        let median = below_counts.iter().position(|&count| 2 * count >= pixels).unwrap();
        let largest = *counts.iter().max().unwrap();
        let mode = counts.iter().position(|&frequency| frequency == largest).unwrap();
        let bin_width = (image.maxval + 8) / 8;
        let bins = counts.chunks(bin_width).map(|group| group.iter().sum()).collect();
        Self { maxval: image.maxval, pixels, counts, below_counts, below_sums, total, minimum,
            maximum, levels, median, mode, bin_width, bins }
    }
    pub fn split(&self, cutoff: usize) -> (i64, i64, i64, i64) {
        let below = self.below_counts[cutoff];
        let sum_below = self.below_sums[cutoff];
        (below, sum_below, self.pixels - below, self.total - sum_below)
    }
}

pub struct Candidate {
    pub cutoff: usize,
    pub below: i64,
    pub sum_below: i64,
    pub above: i64,
    pub sum_above: i64,
    numerator: i64,
    denominator: i64,
}

fn compare_scores(first: &Candidate, second: &Candidate) -> Ordering {
    let (q1, r1) = (first.numerator / first.denominator, first.numerator % first.denominator);
    let (q2, r2) = (second.numerator / second.denominator, second.numerator % second.denominator);
    q1.cmp(&q2).then_with(|| (r1 * second.denominator).cmp(&(r2 * first.denominator)))
}

pub struct OtsuResult {
    pub cutoff: usize,
    pub upper: usize,
    pub candidates: Vec<Candidate>,
}

pub fn otsu(histogram: &Histogram) -> OtsuResult {
    let mut candidates = Vec::new();
    for cutoff in 0..histogram.maxval {
        let (below, sum_below, above, sum_above) = histogram.split(cutoff);
        if histogram.counts[cutoff] > 0 && above > 0 {
            candidates.push(Candidate { cutoff, below, sum_below, above, sum_above,
                numerator: sum_below * sum_below * above + sum_above * sum_above * below,
                denominator: below * above });
        }
    }
    candidates.sort_by(|first, second| compare_scores(second, first).then(first.cutoff.cmp(&second.cutoff)));
    if candidates.is_empty() { return OtsuResult { cutoff: histogram.minimum, upper: histogram.minimum, candidates }; }
    let cutoff = candidates[0].cutoff;
    let following = (cutoff + 1..=histogram.maxval).find(|&value| histogram.counts[value] > 0).unwrap();
    OtsuResult { cutoff, upper: following - 1, candidates }
}

pub fn isodata(histogram: &Histogram) -> (usize, usize) {
    let mut cutoff = (histogram.total / histogram.pixels) as usize;
    let mut iterations = 0;
    loop {
        let (below, sum_below, above, sum_above) = histogram.split(cutoff);
        if below == 0 || above == 0 { break; }
        let following = ((sum_below * above + sum_above * below) / (2 * below * above)) as usize;
        iterations += 1;
        if following == cutoff { break; }
        cutoff = following;
        if iterations == 100 { break; }
    }
    (cutoff, iterations)
}
