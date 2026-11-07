package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

type Alignment struct {
	R, Pos, Strand int
	Operations     string
	Score, MM      int
}
type Mapping struct {
	Mapped                            bool
	Method                            string
	Core                              [2]string
	Trim, Length, Score, X0, X1, MapQ int
	Alignments                        []Alignment
}
type SearchCounters struct{ Calls, Nodes, Leaves, Hits, SeedReads, Seeds, WithN, Repetitive, WithoutHit, Candidates, Passing int }
type Position struct{ R, Pos, Strand int }
type Candidate struct{ Strand, R, C int }

const unreachable = -1000000

type DPRow struct {
	Lo      int
	H, E, F []int
}

func (r DPRow) value(kind byte, j int) int {
	i := j - r.Lo
	if i < 0 || i >= len(r.H) {
		return unreachable
	}
	switch kind {
	case 'E':
		return r.E[i]
	case 'F':
		return r.F[i]
	default:
		return r.H[i]
	}
}
func position(refs []Reference, p int) (int, int) {
	for r, reference := range refs {
		if p >= reference.Offset && p < reference.Offset+len(reference.Sequence) {
			return r,
				p - reference.Offset
		}
	}
	return -1, -1
}
func positionName(refs []Reference, p int) string {
	r, offset := position(refs, p)
	if r < 0 {
		return "*"
	}
	return fmt.Sprintf("%s:%d", refs[r].Name, offset+1)
}
func positionLess(a, b Alignment) bool {
	return a.R < b.R || a.R == b.R && (a.Pos < b.Pos || a.Pos == b.Pos && a.Strand < b.Strand)
}
func align(w, s string, c, band int, scores []int) (Alignment, bool) {
	length, size := len(w), len(s)
	rows := make([]DPRow,
		length+1)
	get := func(i, j int, kind byte) int {
		if i < 0 || i > length {
			return unreachable
		}
		return rows[i].value(kind,
			j)
	}
	for i := 0; i <= length; i++ {
		lo, hi := max(0, i+c-band), min(size, i+c+band)
		width := max(0, hi-lo+1)
		row := DPRow{Lo: lo,
			H: make([]int, width), E: make([]int, width), F: make([]int, width)}
		for k := 0; k < width; k++ {
			row.H[k], row.E[k],
				row.F[k] = unreachable, unreachable, unreachable
		}
		rows[i] = row
		for j := lo; j <= hi; j++ {
			k := j - lo
			if i == 0 {
				row.H[k] = 0
				continue
			}
			h,
				f := get(i-1, j, 'H'), get(i-1, j, 'F')
			if h > unreachable {
				row.F[k] = h - scores[2] - scores[3]
			}
			if f > unreachable {
				row.F[k] = max(row.F[k],
					f-scores[3])
			}
			if j >= 1 {
				h, e := get(i, j-1, 'H'), get(i, j-1, 'E')
				if h > unreachable {
					row.E[k] = h - scores[2] - scores[3]
				}
				if e > unreachable {
					row.E[k] = max(row.E[k],
						e-scores[3])
				}
				diagonal := get(i-1, j-1, 'H')
				if diagonal > unreachable {
					score := -scores[1]
					if w[i-1] == s[j-1] {
						score = scores[0]
					}
					row.H[k] = diagonal + score
				}
			}
			row.H[k] = max(row.H[k],
				row.F[k], row.E[k])
		}
	}
	best, j := unreachable, -1
	for k, value := range rows[length].H {
		if value > best {
			best,
				j = value, rows[length].Lo+k
		}
	}
	if j < 0 {
		return Alignment{}, false
	}
	i, state := length, byte('H')
	var operations []byte
	for {
		if state == 'H' {
			if i == 0 {
				break
			}
			diagonal := get(i-1,
				j-1, 'H')
			score := -scores[1]
			if j >= 1 && w[i-1] == s[j-1] {
				score = scores[0]
			}
			if j >= 1 && diagonal > unreachable && get(i,
				j, 'H') == diagonal+score {
				operations = append(operations, 'M')
				i--
				j--
				continue
			}
			if get(i, j, 'F') > unreachable && get(i,
				j, 'H') == get(i, j, 'F') {
				state = 'I'
			} else {
				state = 'D'
			}
		} else if state == 'I' {
			operations = append(operations,
				'I')
			previous := get(i-1, j, 'F')
			if previous > unreachable && get(i, j, 'F') == previous-scores[3] {
				state = 'I'
			} else {
				state = 'H'
			}
			i--
		} else {
			operations = append(operations,
				'D')
			previous := get(i, j-1, 'E')
			if previous > unreachable && get(i, j, 'E') == previous-scores[3] {
				state = 'D'
			} else {
				state = 'H'
			}
			j--
		}
	}
	for a,
		b := 0, len(operations)-1; a < b; a, b = a+1, b-1 {
		operations[a], operations[b] = operations[b], operations[a]
	}
	return Alignment{Pos: j,
		Operations: string(operations), Score: best}, true
}
func mapRead(read Read, refs []Reference, forward, reverse FMIndex, params map[string][]int, counters *SearchCounters) Mapping {
	length := len(read.Bases)
	for length > 0 && int(read.Quality[length-1])-33 < params["TRIM_QUALITY"][0] {
		length--
	}
	m := Mapping{Length: length,
		Trim: len(read.Bases) - length}
	if length < params["MIN_READ_LENGTH"][0] {
		m.Method = "SHORT"
		return m
	}
	m.Core = [2]string{read.Bases[:length],
		reverseComplement(read.Bases[:length])}
	zs := params["MAX_MISMATCHES"][0]
	for _, w := range m.Core {
		iv := forward.exact(w)
		if iv.Lo < iv.Hi {
			zs = 1
			break
		}
	}
	var hits []Alignment
	for strand, w := range m.Core {
		result := backtrack(forward, reverse, w, zs)
		counters.Calls++
		counters.Nodes += result.Nodes
		counters.Leaves += len(result.Leaves)
		counters.Hits += result.Hits
		for _, leaf := range result.Leaves {
			for row := leaf.Interval.Lo; row < leaf.Interval.Hi; row++ {
				p, _ := forward.locate(row)
				r,
					offset := position(refs, p)
				hits = append(hits, Alignment{R: r, Pos: offset, Strand: strand, Operations: strings.Repeat("M",
					length), MM: leaf.Mismatches})
			}
		}
	}
	scores := params["SCORES"]
	if len(hits) > 0 {
		sort.Slice(hits, func(i,
			j int) bool {
			a, b := hits[i], hits[j]
			return a.MM < b.MM || a.MM == b.MM && positionLess(a, b)
		})
		best := hits[0].MM
		for _, hit := range hits {
			if hit.MM == best {
				m.X0++
			}
			if hit.MM == best+1 {
				m.X1++
			}
			if hit.MM <= best+1 {
				m.Alignments = append(m.Alignments,
					hit)
			}
		}
		m.Mapped = true
		m.Method = "EXACT"
		if best > 0 {
			m.Method = "MISMATCH"
		}
		m.Score = (length-best)*scores[0] - best*scores[1]
		if m.X0 >= 2 {
			m.MapQ = 0
		} else if m.X1 == 0 {
			m.MapQ = 60 - 12*best
		} else {
			m.MapQ = max(30-12*best-3*m.X1,
				1)
		}
		return m
	}
	seedLength := params["SEED_LENGTH"][0]
	m.Method = "NOHIT"
	if length < seedLength {
		return m
	}
	counters.SeedReads++
	candidateSet := map[Candidate]bool{}
	for strand, w := range m.Core {
		for o := 0; o+seedLength <= length; o += params["SEED_STEP"][0] {
			counters.Seeds++
			seed := w[o : o+seedLength]
			if strings.Contains(seed,
				"N") {
				counters.WithN++
				continue
			}
			iv := forward.exact(seed)
			count := iv.Hi - iv.Lo
			if count > params["MAX_SEED_HITS"][0] {
				counters.Repetitive++
				continue
			}
			if count == 0 {
				counters.WithoutHit++
				continue
			}
			for row := iv.Lo; row < iv.Hi; row++ {
				p,
					_ := forward.locate(row)
				r, e := position(refs, p)
				candidateSet[Candidate{strand, r, e - o}] = true
			}
		}
	}
	candidates := make([]Candidate,
		0, len(candidateSet))
	for candidate := range candidateSet {
		candidates = append(candidates, candidate)
	}
	sort.Slice(candidates,
		func(i, j int) bool {
			a, b := candidates[i], candidates[j]
			return a.Strand < b.Strand || a.Strand == b.Strand && (a.R < b.R || a.R == b.R && a.C < b.C)
		})
	counters.Candidates += len(candidates)
	accepted := map[Position]Alignment{}
	for _, candidate := range candidates {
		a, exists := align(m.Core[candidate.Strand], refs[candidate.R].Sequence,
			candidate.C, params["BAND_WIDTH"][0], scores)
		if !exists || 100*a.Score < params["MIN_SCORE_PERCENT"][0]*scores[0]*length {
			continue
		}
		a.R,
			a.Strand = candidate.R, candidate.Strand
		key := Position{a.R, a.Pos, a.Strand}
		if old, found := accepted[key]; !found || a.Score > old.Score {
			accepted[key] = a
		}
	}
	counters.Passing += len(accepted)
	if len(accepted) == 0 {
		return m
	}
	for _, a := range accepted {
		m.Alignments = append(m.Alignments, a)
	}
	sort.Slice(m.Alignments, func(i, j int) bool {
		a,
			b := m.Alignments[i], m.Alignments[j]
		return a.Score > b.Score || a.Score == b.Score && positionLess(a, b)
	})
	m.Mapped = true
	m.Method = "SEED"
	m.Score = m.Alignments[0].Score
	second := 0
	for _, a := range m.Alignments {
		if a.Score == m.Score {
			m.X0++
		} else {
			second = max(second, a.Score)
		}
	}
	m.X1 = len(m.Alignments) - m.X0
	if m.X0 == 1 {
		m.MapQ = 60 * (m.Score - second) / m.Score
	}
	return m
}
func describe(a Alignment, core [2]string, refs []Reference, trim int) (string, int, string) {
	var cigar,
		md strings.Builder
	if trim > 0 && a.Strand == 1 {
		fmt.Fprintf(&cigar, "%dS", trim)
	}
	for i := 0; i < len(a.Operations); {
		j := i + 1
		for j < len(a.Operations) && a.Operations[j] == a.Operations[i] {
			j++
		}
		fmt.Fprintf(&cigar,
			"%d%c", j-i, a.Operations[i])
		i = j
	}
	if trim > 0 && a.Strand == 0 {
		fmt.Fprintf(&cigar, "%dS", trim)
	}
	w, s := core[a.Strand],
		refs[a.R].Sequence
	i, j, u, nm := 0, a.Pos, 0, 0
	for k := 0; k < len(a.Operations); {
		op := a.Operations[k]
		switch op {
		case 'M':
			if w[i] == s[j] {
				u++
			} else {
				fmt.Fprintf(&md,
					"%d%c", u, s[j])
				u = 0
				nm++
			}
			i++
			j++
			k++
		case 'I':
			i++
			nm++
			k++
		case 'D':
			fmt.Fprintf(&md, "%d^", u)
			u = 0
			for k < len(a.Operations) && a.Operations[k] == 'D' {
				md.WriteByte(s[j])
				j++
				nm++
				k++
			}
		}
	}
	fmt.Fprintf(&md,
		"%d", u)
	return cigar.String(), nm, md.String()
}
func bwtRuns(s string) int {
	n := 0
	for i := range s {
		if i == 0 || s[i] != s[i-1] {
			n++
		}
	}
	return n
}
func yes(b bool) string {
	if b {
		return "yes"
	}
	return "no"
}
func reportIndex(out *strings.Builder, refs []Reference, forward, reverse FMIndex, params map[string][]int) {
	n := len(forward.Text)
	line(out,
		"text length %d sequences %d", n, len(refs))
	for _, r := range refs {
		gc := strings.Count(r.Sequence,
			"G") + strings.Count(r.Sequence, "C")
		line(out, "sequence %s length %d offset %d gc %s masked %d",
			r.Name, len(r.Sequence), r.Offset, ratio(gc, len(r.Sequence)), r.Masked)
	}
	var symbols [6]int
	for i := range forward.Text {
		symbols[symbol(forward.Text[i])]++
	}
	line(out,
		"symbols $ %d # %d A %d C %d G %d T %d", symbols[0], symbols[1], symbols[2], symbols[3], symbols[4],
		symbols[5])
	line(out, "")
	line(out, "forward_index")
	classes := forward.Suffix.Classes
	line(out, "suffix_array rounds %d",
		len(classes)-1)
	for t, c := range classes {
		line(out, "round %d prefix_length %d classes %d", t, 1<<t,
			c)
	}
	check := adjacent(forward.Text, forward.Suffix.SA)
	line(out, "sa_check pairs %d ordered %d lcp_sum %d mean_lcp %s max_lcp %d",
		n-1, check.Ordered, check.LCPSum, ratio(check.LCPSum, n-1), check.MaxLCP)
	line(out, "longest_repeat %d %s %s",
		check.MaxLCP, positionName(refs, forward.Suffix.SA[check.Star-1]), positionName(refs, forward.Suffix.SA[check.Star]))
	seedLength := params["SEED_LENGTH"][0]
	kmers := map[string]int{}
	occurrences := 0
	for p := 0; p+seedLength <= n; p++ {
		kmer := forward.Text[p : p+seedLength]
		if !strings.ContainsAny(kmer,
			"#$") {
			kmers[kmer]++
			occurrences++
		}
	}
	unique, maxOccurrence := 0, 0
	for _, count := range kmers {
		if count == 1 {
			unique++
		}
		maxOccurrence = max(maxOccurrence,
			count)
	}
	line(out, "kmers length %d occurrences %d distinct %d unique %d max_occurrence %d unique_fraction %s",
		seedLength, occurrences, len(kmers), unique, maxOccurrence, ratio(unique, occurrences))
	line(out, "bwt runs %d head %s",
		bwtRuns(forward.BWT), forward.BWT[:min(60, n)])
	line(out, "c_array $ %d # %d A %d C %d G %d T %d",
		forward.C[0], forward.C[1], forward.C[2], forward.C[3], forward.C[4], forward.C[5])
	line(out, "occ interval %d checkpoints %d",
		forward.OccInterval, len(forward.Checkpoints))
	line(out, "sa_sample interval %d samples %d", params["SA_SAMPLE_INTERVAL"][0],
		len(forward.Sample))
	correct, totalSteps, maxSteps := 0, 0, 0
	for row, expected := range forward.Suffix.SA {
		p,
			steps := forward.locate(row)
		if p == expected {
			correct++
		}
		totalSteps += steps
		maxSteps = max(maxSteps,
			steps)
	}
	line(out, "locate rows %d correct %d total_steps %d max_steps %d mean_steps %s", n, correct,
		totalSteps, maxSteps, ratio(totalSteps, n))
	line(out, "inverse_bwt identical %s", yes(forward.inverse() == forward.Text))
	line(out,
		"")
	line(out, "reverse_index")
	line(out, "suffix_array rounds %d", len(reverse.Suffix.Classes)-1)
	reverseCheck := adjacent(reverse.Text,
		reverse.Suffix.SA)
	line(out, "sa_check pairs %d ordered %d", n-1, reverseCheck.Ordered)
	line(out,
		"bwt runs %d head %s", bwtRuns(reverse.BWT), reverse.BWT[:min(60, n)])
	line(out, "inverse_bwt identical %s",
		yes(reverse.inverse() == reverse.Text))
	line(out, "")
	line(out, "direct_sort")
	count := 0
	for _, r := range refs {
		if len(r.Sequence) > params["DIRECT_SORT_LIMIT"][0] {
			continue
		}
		u := r.Sequence + "$"
		a := suffixArray(u)
		b := directSort(u)
		identical := true
		for i, v := range a.SA {
			if v != b[i] {
				identical = false
			}
		}
		line(out, "%s length %d rounds %d identical %s", r.Name,
			len(u), len(a.Classes)-1, yes(identical))
		count++
	}
	if count == 0 {
		line(out, "none")
	}
	line(out, "")
	occBytes,
		sampleBytes, bitmapBytes := 24*len(forward.Checkpoints), 4*len(forward.Sample), (n+7)/8
	total := n + occBytes + sampleBytes + bitmapBytes
	line(out,
		"index_size bwt_bytes %d occ_bytes %d sample_bytes %d bitmap_bytes %d total_bytes %d full_bytes %d ratio %s",
		n, occBytes, sampleBytes, bitmapBytes, total, 5*n, ratio(total, 5*n))
}
func main() {
	refs, reads, params := readInput()
	var text strings.Builder
	for i := range refs {
		refs[i].Offset = text.Len()
		text.WriteString(refs[i].Sequence)
		if i+1 < len(refs) {
			text.WriteByte('#')
		}
	}
	joined := text.String()
	forward := buildIndex(joined+"$",
		params["OCC_INTERVAL"][0], params["SA_SAMPLE_INTERVAL"][0])
	backward := buildIndex(reverse(joined)+"$",
		params["OCC_INTERVAL"][0], 0)
	var counters SearchCounters
	mappings := make([]Mapping, len(reads))
	var sam,
		indexOut, coverage, variants, summary strings.Builder
	sam.WriteString(samHeader(refs))
	for i, read := range reads {
		mappings[i] = mapRead(read,
			refs, forward, backward, params, &counters)
		line(&sam, "%s", samRecord(read, mappings[i], refs, params["MAX_ALT_HITS"][0]))
	}
	reportIndex(&indexOut,
		refs, forward, backward, params)
	depth, zeroStarts := make([][]int, len(refs)), make([][]int, len(refs))
	pileup := make([][][2][4]int, len(refs))
	for r, reference := range refs {
		depth[r] = make([]int, len(reference.Sequence))
		zeroStarts[r] = make([]int,
			len(reference.Sequence))
		pileup[r] = make([][2][4]int, len(reference.Sequence))
	}
	mapped, unique,
		multi, trimmed, trimmedBases, short, nohit, forwardCount, reverseCount := 0, 0, 0, 0, 0, 0, 0, 0, 0
	methods := map[string]int{}
	referenceStats := make([][4]int,
		len(refs))
	lengthBins := map[int][3]int{}
	minLength, maxLength, maxOriginal := len(reads[0].Bases),
		0, 0
	nReads, nBases, nMapped := 0, 0, 0
	multiTargets := map[string]int{}
	mapqHistogram, nmHistogram := map[int]int{},
		map[int]int{}
	aligned, mismatches := 0, 0
	var substitutions [4][5]int
	cycleAligned, cycleMismatches := make([]int,
		101), make([]int, 101)
	matchedQuality, mismatchQuality, matchedPairs, mismatchPairs := 0, 0, 0, 0
	var qualityAligned,
		qualityMismatch [5]int
	var cigarCounts [4]int
	insertionEvents, insertionBases, deletionEvents,
		deletionBases := 0, 0, 0, 0
	for ri, read := range reads {
		m := mappings[ri]
		minLength = min(minLength,
			m.Length)
		maxLength = max(maxLength, m.Length)
		maxOriginal = max(maxOriginal, len(read.Bases))
		if m.Trim > 0 {
			trimmed++
		}
		trimmedBases += m.Trim
		bin := m.Length / 10 * 10
		binStats := lengthBins[bin]
		binStats[0]++
		containsN := strings.Contains(read.Bases,
			"N")
		if containsN {
			nReads++
			nBases += strings.Count(read.Bases, "N")
		}
		if !m.Mapped {
			if m.Method == "SHORT" {
				short++
			} else {
				nohit++
			}
			lengthBins[bin] = binStats
			continue
		}
		mapped++
		methods[m.Method]++
		mapqHistogram[m.MapQ]++
		binStats[1]++
		if containsN {
			nMapped++
		}
		a := m.Alignments[0]
		referenceStats[a.R][0]++
		if a.Strand == 0 {
			forwardCount++
			referenceStats[a.R][2]++
		} else {
			reverseCount++
			referenceStats[a.R][3]++
		}
		isUnique := m.X0 == 1
		if isUnique {
			unique++
			binStats[2]++
			referenceStats[a.R][1]++
		} else {
			multi++
			targets := map[int]bool{}
			for _, other := range m.Alignments {
				best := other.MM == a.MM
				if m.Method == "SEED" {
					best = other.Score == m.Score
				}
				if best {
					targets[other.R] = true
				}
			}
			var names []string
			for r, reference := range refs {
				if targets[r] {
					names = append(names, reference.Name)
				}
			}
			multiTargets[strings.Join(names,
				"+")]++
		}
		lengthBins[bin] = binStats
		_, nm, _ := describe(a, m.Core, refs, m.Trim)
		nmHistogram[nm]++
		cigarCounts[3] += m.Trim
		if m.MapQ == 0 {
			zeroStarts[a.R][a.Pos]++
		}
		i,
			j := 0, a.Pos
		w, reference := m.Core[a.Strand], refs[a.R].Sequence
		for k := 0; k < len(a.Operations); k++ {
			op := a.Operations[k]
			switch op {
			case 'M':
				cigarCounts[0]++
				cycle := i + 1
				if a.Strand == 1 {
					cycle = m.Length - i
				}
				quality := int(read.Quality[cycle-1]) - 33
				match := w[i] == reference[j]
				if m.MapQ >= params["COVERAGE_MIN_MAPQ"][0] {
					depth[a.R][j]++
					if w[i] != 'N' && quality >= params["VARIANTS"][1] {
						base := strings.IndexByte("ACGT",
							w[i])
						pileup[a.R][j][a.Strand][base]++
					}
				}
				if isUnique {
					aligned++
					cycleAligned[cycle]++
					qb := min(quality/10,
						4)
					qualityAligned[qb]++
					refBase, readBase := strings.IndexByte("ACGT", reference[j]), strings.IndexByte("ACGTN",
						w[i])
					substitutions[refBase][readBase]++
					if match {
						matchedPairs++
						matchedQuality += quality
					} else {
						mismatches++
						cycleMismatches[cycle]++
						qualityMismatch[qb]++
						mismatchPairs++
						mismatchQuality += quality
					}
				}
				i++
				j++
			case 'I':
				cigarCounts[1]++
				i++
				if isUnique {
					insertionBases++
					if k == 0 || a.Operations[k-1] != 'I' {
						insertionEvents++
					}
				}
			case 'D':
				cigarCounts[2]++
				j++
				if isUnique {
					deletionBases++
					if k == 0 || a.Operations[k-1] != 'D' {
						deletionEvents++
					}
				}
			}
		}
	}
	window, mapq := params["COVERAGE_WINDOW"][0], params["COVERAGE_MIN_MAPQ"][0]
	line(&coverage, "window %d min_mapq %d",
		window, mapq)
	for r, ref := range refs {
		covered, total, maximum := 0, 0, 0
		for _, d := range depth[r] {
			if d > 0 {
				covered++
			}
			total += d
			maximum = max(maximum,
				d)
		}
		line(&coverage, "reference %s length %d covered %d breadth %s mean_depth %s max_depth %d",
			ref.Name, len(ref.Sequence), covered, ratio(covered, len(ref.Sequence)), ratio(total, len(ref.Sequence)),
			maximum)
		histogram := make([]int, maximum+1)
		for _, d := range depth[r] {
			histogram[d]++
		}
		parts := []string{"depth_histogram"}
		for d, n := range histogram {
			parts = append(parts, fmt.Sprintf("%d:%d", d, n))
		}
		line(&coverage, strings.Join(parts,
			" "))
		for first := 0; first < len(ref.Sequence); first += window {
			last := min(first+window, len(ref.Sequence))
			gc,
				sum, maximum, zero, mapq0 := 0, 0, 0, 0, 0
			for j := first; j < last; j++ {
				if ref.Sequence[j] == 'G' || ref.Sequence[j] == 'C' {
					gc++
				}
				d := depth[r][j]
				sum += d
				maximum = max(maximum,
					d)
				if d == 0 {
					zero++
				}
				mapq0 += zeroStarts[r][j]
			}
			width := last - first
			line(&coverage, "%s %d %d gc %s sum %d mean %s max %d zero %d mapq0 %d |%s",
				ref.Name, first+1, last, ratio(gc, width), sum, ratio(sum, width), maximum, zero, mapq0, strings.Repeat("#",
					10*sum/width))
		}
	}
	vp := params["VARIANTS"]
	line(&variants, "min_depth %d min_base_quality %d min_alt_percent %d hom_percent %d",
		vp[0], vp[1], vp[2], vp[3])
	callable, variantCount, heterozygous, homozygous := 0, 0, 0, 0
	for r, ref := range refs {
		for j, site := range pileup[r] {
			var counts [4]int
			dp := 0
			for b := 0; b < 4; b++ {
				counts[b] = site[0][b] + site[1][b]
				dp += counts[b]
			}
			if dp < vp[0] {
				continue
			}
			callable++
			alt,
				nAlt := -1, -1
			for b := 0; b < 4; b++ {
				if "ACGT"[b] != ref.Sequence[j] && counts[b] > nAlt {
					alt, nAlt = b, counts[b]
				}
			}
			if nAlt < 2 || 100*nAlt < vp[2]*dp {
				continue
			}
			variantCount++
			genotype := "0/1"
			if 100*nAlt >= vp[3]*dp {
				genotype = "1/1"
				homozygous++
			} else {
				heterozygous++
			}
			line(&variants,
				"%s %d %c>%c depth %d alt %d fraction %s genotype %s strands %d %d counts %d %d %d %d", ref.Name,
				j+1, ref.Sequence[j], "ACGT"[alt], dp, nAlt, ratio(nAlt, dp), genotype, site[0][alt], site[1][alt],
				counts[0], counts[1], counts[2], counts[3])
		}
	}
	line(&variants, "callable %d variants %d heterozygous %d homozygous %d",
		callable, variantCount, heterozygous, homozygous)
	line(&summary, "reads total %d trimmed %d trimmed_bases %d short %d", len(reads), trimmed, trimmedBases,
		short)
	line(&summary, "mapped %d rate %s unique %d multi %d unmapped %d", mapped, ratio(mapped,
		len(reads)), unique, multi, len(reads)-mapped)
	line(&summary, "unmapped short %d nohit %d", short,
		nohit)
	line(&summary, "method exact %d mismatch %d seed %d", methods["EXACT"], methods["MISMATCH"],
		methods["SEED"])
	line(&summary, "strand forward %d reverse %d", forwardCount, reverseCount)
	for r, ref := range refs {
		v := referenceStats[r]
		line(&summary, "reference %s mapped %d unique %d forward %d reverse %d",
			ref.Name, v[0], v[1], v[2], v[3])
	}
	line(&summary, "length_bins")
	for lo := minLength / 10 * 10; lo <= maxLength; lo += 10 {
		v := lengthBins[lo]
		line(&summary,
			"%d-%d reads %d mapped %d unique %d", lo, lo+9, v[0], v[1], v[2])
	}
	line(&summary, "n_reads %d n_bases %d mapped %d",
		nReads, nBases, nMapped)
	line(&summary, "multi_targets")
	var targetNames []string
	for name := range multiTargets {
		targetNames = append(targetNames,
			name)
	}
	sort.Strings(targetNames)
	if len(targetNames) == 0 {
		line(&summary, "none")
	}
	for _, name := range targetNames {
		line(&summary,
			"%s %d", name, multiTargets[name])
	}
	line(&summary, "mapq_histogram")
	var mapqs []int
	for q := range mapqHistogram {
		mapqs = append(mapqs,
			q)
	}
	sort.Sort(sort.Reverse(sort.IntSlice(mapqs)))
	for _, q := range mapqs {
		line(&summary, "%d %d",
			q, mapqHistogram[q])
	}
	line(&summary, "nm_histogram")
	var nms []int
	for nm := range nmHistogram {
		nms = append(nms,
			nm)
	}
	sort.Ints(nms)
	for _, nm := range nms {
		line(&summary, "%d %d", nm, nmHistogram[nm])
	}
	line(&summary,
		"error_profile aligned_bases %d mismatches %d rate %s", aligned, mismatches, ratio(mismatches,
			aligned))
	line(&summary, "substitutions")
	line(&summary, "ref A C G T N")
	for i, c := range []byte("ACGT") {
		v := substitutions[i]
		line(&summary,
			"%c %d %d %d %d %d", c, v[0], v[1], v[2], v[3], v[4])
	}
	line(&summary, "mismatch_by_cycle")
	for cycle := 1; cycle <= maxOriginal; cycle++ {
		line(&summary,
			"cycle %d aligned %d mismatches %d rate %s", cycle, cycleAligned[cycle], cycleMismatches[cycle],
			ratio(cycleMismatches[cycle], cycleAligned[cycle]))
	}
	line(&summary, "quality matched %d mean %s mismatched %d mean %s",
		matchedPairs, ratio(matchedQuality, matchedPairs), mismatchPairs, ratio(mismatchQuality, mismatchPairs))
	line(&summary,
		"quality_bins")
	ranges := []string{"0-9", "10-19", "20-29", "30-39", "40-"}
	for i, name := range ranges {
		line(&summary,
			"%s aligned %d mismatches %d rate %s", name, qualityAligned[i], qualityMismatch[i], ratio(qualityMismatch[i],
				qualityAligned[i]))
	}
	line(&summary, "cigar M %d I %d D %d S %d", cigarCounts[0], cigarCounts[1],
		cigarCounts[2], cigarCounts[3])
	line(&summary, "indels insertions %d %d deletions %d %d", insertionEvents,
		insertionBases, deletionEvents, deletionBases)
	line(&summary, "search dfs_calls %d dfs_nodes %d dfs_leaves %d dfs_positions %d",
		counters.Calls, counters.Nodes, counters.Leaves, counters.Hits)
	line(&summary, "seeds reads %d seeds %d with_n %d repetitive %d without_hit %d candidates %d passing %d",
		counters.SeedReads, counters.Seeds, counters.WithN, counters.Repetitive, counters.WithoutHit,
		counters.Candidates, counters.Passing)
	must(os.MkdirAll("output", 0755))
	for path, s := range map[string]*strings.Builder{"alignments.sam": &sam,
		"coverage.txt": &coverage, "variants.txt": &variants, "index_stats.txt": &indexOut, "summary.txt": &summary} {
		write("output/"+path,
			s)
	}
}
