package main

func sum(values []int64) int64 {
	var total int64
	for _, v := range values {
		total += v
	}
	return total
}
func sumSquares(values []int64) int64 {
	var total int64
	for _, v := range values {
		total += v * v
	}
	return total
}
func valuePointer(v int64) *int64 { return &v }
func mean(values []int64) *int64 {
	if len(values) == 0 {
		return nil
	}
	return valuePointer(rdiv(100*sum(values), int64(len(values))))
}

type RRStatistics struct {
	Count             int
	MeanRR, MeanHR    *int64
	Shortest, Longest *Beat
}

func rrStatistics(beats []*Beat) RRStatistics {
	s := RRStatistics{}
	values := []int64{}
	for _, b := range beats {
		if b.RR == 0 {
			continue
		}
		s.Count++
		values = append(values, b.RR)
		if s.Shortest == nil || b.RR < s.Shortest.RR {
			s.Shortest = b
		}
		if s.Longest == nil || b.RR > s.Longest.RR {
			s.Longest = b
		}
	}
	s.MeanRR = mean(values)
	if len(values) > 0 {
		s.MeanHR = valuePointer(rdiv(6000000*int64(len(values)), sum(values)))
	}
	return s
}

type NNStatistics struct {
	Intervals                                              []int64
	Pairs                                                  [][2]int64
	E, K, NN50, HistogramMax                               int
	MeanNN, SDNN, RMSSD, SDSD, PNN50, SD1, SD2, Triangular *int64
	Histogram                                              map[int64]int
}

func nnStatistics(beats []*Beat) *NNStatistics {
	s := &NNStatistics{Histogram: map[int64]int{}}
	nn := map[int]int64{}
	for i := 2; i < len(beats); i++ {
		previous, current := beats[i-1], beats[i]
		if previous.Label == "N" && current.Label == "N" && 5*abs(current.RR-previous.RR) <= previous.RR {
			nn[current.Number] = current.RR
			s.Intervals = append(s.Intervals, current.RR)
			if value, ok := nn[current.Number-1]; ok {
				s.Pairs = append(s.Pairs, [2]int64{value, current.RR})
			}
		}
	}
	s.E, s.K = len(s.Intervals), len(s.Pairs)
	s.MeanNN = mean(s.Intervals)
	e, k := int64(s.E), int64(s.K)
	if e >= 2 {
		s.SDNN = valuePointer(root(e*sumSquares(s.Intervals)-sum(s.Intervals)*sum(s.Intervals), e*(e-1)))
	}
	differences, sums := []int64{}, []int64{}
	for _, pair := range s.Pairs {
		d := pair[1] - pair[0]
		differences = append(differences, d)
		sums = append(sums, pair[0]+pair[1])
		if abs(d) > 50 {
			s.NN50++
		}
	}
	if k > 0 {
		s.RMSSD = valuePointer(root(sumSquares(differences), k))
		s.PNN50 = valuePointer(rdiv(10000*int64(s.NN50), k))
	}
	if k >= 2 {
		dn := k*sumSquares(differences) - sum(differences)*sum(differences)
		sn := k*sumSquares(sums) - sum(sums)*sum(sums)
		s.SDSD = valuePointer(root(dn, k*(k-1)))
		s.SD1 = valuePointer(root(dn, 2*k*(k-1)))
		s.SD2 = valuePointer(root(sn, 2*k*(k-1)))
	}
	for _, u := range s.Intervals {
		s.Histogram[16*u/125]++
	}
	for _, count := range s.Histogram {
		s.HistogramMax = max(s.HistogramMax, count)
	}
	if s.HistogramMax > 0 {
		s.Triangular = valuePointer(rdiv(100*e, int64(s.HistogramMax)))
	}
	return s
}
func consecutiveRanges(indices []int) [][2]int {
	ranges := [][2]int{}
	if len(indices) == 0 {
		return ranges
	}
	start, end := indices[0], indices[0]
	for _, i := range indices[1:] {
		if i == end+1 {
			end = i
		} else {
			ranges = append(ranges, [2]int{start, end})
			start, end = i, i
		}
	}
	return append(ranges, [2]int{start, end})
}
func linkedSequences(indices []int, interval int, labels map[int]string) [][]int {
	chains := [][]int{}
	current := []int{}
	for _, index := range indices {
		linked := len(current) > 0 && index == current[len(current)-1]+interval
		if linked {
			for j := current[len(current)-1] + 1; j < index; j++ {
				if labels[j] != "N" {
					linked = false
					break
				}
			}
		}
		if linked {
			current = append(current, index)
		} else {
			if len(current) > 0 {
				chains = append(chains, current)
			}
			current = []int{index}
		}
	}
	if len(current) > 0 {
		chains = append(chains, current)
	}
	return chains
}
