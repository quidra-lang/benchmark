package main

import "sort"

type Histogram struct {
	Maxval                                           int
	Pixels, Total                                    int64
	Counts, BelowCounts, BelowSums                   []int64
	Minimum, Maximum, Median, Mode, Levels, BinWidth int
	Bins                                             []int64
}

func newHistogram(image Image) Histogram {
	h := Histogram{Maxval: image.Maxval, Pixels: int64(image.Width * image.Height), Counts: make([]int64, image.Maxval+1), Minimum: image.Maxval, Median: -1}
	for _, row := range image.Pixels {
		for _, value := range row {
			h.Counts[value]++
		}
	}
	count := int64(0)
	for value, frequency := range h.Counts {
		count += frequency
		h.Total += int64(value) * frequency
		h.BelowCounts = append(h.BelowCounts, count)
		h.BelowSums = append(h.BelowSums, h.Total)
		if frequency > 0 {
			h.Minimum = min(h.Minimum, value)
			h.Maximum = value
			h.Levels++
		}
		if h.Median < 0 && 2*count >= h.Pixels {
			h.Median = value
		}
		if frequency > h.Counts[h.Mode] {
			h.Mode = value
		}
	}
	h.BinWidth = (image.Maxval + 8) / 8
	for start := 0; start <= image.Maxval; start += h.BinWidth {
		sum := int64(0)
		for _, frequency := range h.Counts[start:min(start+h.BinWidth, len(h.Counts))] {
			sum += frequency
		}
		h.Bins = append(h.Bins, sum)
	}
	return h
}

func (h Histogram) Split(cutoff int) (int64, int64, int64, int64) {
	below, sum := h.BelowCounts[cutoff], h.BelowSums[cutoff]
	return below, sum, h.Pixels - below, h.Total - sum
}

type Candidate struct {
	Cutoff                                                   int
	Below, SumBelow, Above, SumAbove, Numerator, Denominator int64
}

func compareScores(first, second Candidate) int {
	q1, r1 := first.Numerator/first.Denominator, first.Numerator%first.Denominator
	q2, r2 := second.Numerator/second.Denominator, second.Numerator%second.Denominator
	if q1 != q2 {
		if q1 > q2 {
			return 1
		}
		return -1
	}
	left, right := r1*second.Denominator, r2*first.Denominator
	if left > right {
		return 1
	}
	if left < right {
		return -1
	}
	return 0
}

type OtsuResult struct {
	Cutoff, Upper int
	Candidates    []Candidate
}

func otsu(h Histogram) OtsuResult {
	var candidates []Candidate
	for cutoff := 0; cutoff < h.Maxval; cutoff++ {
		below, sumBelow, above, sumAbove := h.Split(cutoff)
		if h.Counts[cutoff] > 0 && above > 0 {
			candidates = append(candidates, Candidate{cutoff, below, sumBelow, above, sumAbove, sumBelow*sumBelow*above + sumAbove*sumAbove*below, below * above})
		}
	}
	sort.Slice(candidates, func(i, j int) bool {
		order := compareScores(candidates[i], candidates[j])
		if order == 0 {
			return candidates[i].Cutoff < candidates[j].Cutoff
		}
		return order > 0
	})
	if len(candidates) == 0 {
		return OtsuResult{h.Minimum, h.Minimum, candidates}
	}
	cutoff := candidates[0].Cutoff
	following := cutoff + 1
	for h.Counts[following] == 0 {
		following++
	}
	return OtsuResult{cutoff, following - 1, candidates}
}

func isodata(h Histogram) (int, int) {
	cutoff, iterations := int(h.Total/h.Pixels), 0
	for {
		below, sumBelow, above, sumAbove := h.Split(cutoff)
		if below == 0 || above == 0 {
			break
		}
		following := int((sumBelow*above + sumAbove*below) / (2 * below * above))
		iterations++
		if following == cutoff {
			break
		}
		cutoff = following
		if iterations == 100 {
			break
		}
	}
	return cutoff, iterations
}
