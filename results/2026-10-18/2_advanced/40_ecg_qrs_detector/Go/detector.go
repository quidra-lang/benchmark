package main

type Peak struct {
	Time, R                                     int
	PeakI, PeakF, Slope, ThresholdI, ThresholdF int64
	Class                                       string
}
type Levels struct{ SPKI, NPKI, SPKF, NPKF int64 }

func findPeaks(s *Signals) []*Peak {
	peaks := []*Peak{}
	for time, value := range s.Integrated {
		if value <= 0 {
			continue
		}
		valid := true
		for j := max(0, time-20); j < time; j++ {
			if s.Integrated[j] >= value {
				valid = false
				break
			}
		}
		if !valid {
			continue
		}
		for j := time + 1; j < min(len(s.Integrated), time+21); j++ {
			if s.Integrated[j] > value {
				valid = false
				break
			}
		}
		if !valid {
			continue
		}
		r := max(0, time-30)
		for j := r + 1; j <= time; j++ {
			if abs(s.Bandpass[j]) > abs(s.Bandpass[r]) {
				r = j
			}
		}
		var slope int64
		for j := max(0, time-29); j <= time; j++ {
			slope = max(slope, abs(s.Derivative[j]))
		}
		peaks = append(peaks, &Peak{Time: time, R: r, PeakI: value, PeakF: abs(s.Bandpass[r]), Slope: slope})
	}
	return peaks
}
func initialLevels(s *Signals) Levels {
	var sumI, sumF, maxI, maxF int64
	for i := range 400 {
		sumI += s.Integrated[i]
		sumF += abs(s.Bandpass[i])
		maxI = max(maxI, s.Integrated[i])
		maxF = max(maxF, abs(s.Bandpass[i]))
	}
	return Levels{maxI / 3, sumI / 800, maxF / 3, sumF / 800}
}
func widthMS(band []int64, r int) int64 {
	peak := abs(band[r])
	first, last := -1, -1
	for j := max(0, r-25); j < min(len(band), r+26); j++ {
		if 4*abs(band[j]) >= peak {
			if first < 0 {
				first = j
			}
			last = j
		}
	}
	return int64(5 * (last - first + 1))
}
