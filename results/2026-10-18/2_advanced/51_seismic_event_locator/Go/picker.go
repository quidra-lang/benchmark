package main

import "math"

type Pick struct {
	Station                 *Station
	Sample, Duration        int
	Ratio                   float64
	Amplitude               int64
	Clipped, Assigned       bool
	State                   string
	Event                   int
	FirstResidual, Residual float64
}

func abs64(v int64) int64 {
	if v < 0 {
		return -v
	}
	return v
}
func floorDiv(a, b int64) int64 {
	q := a / b
	if a%b < 0 {
		q--
	}
	return q
}
func detectStation(station *Station, p Params) []*Pick {
	n := len(station.Samples)
	total := int64(0)
	for _, v := range station.Samples {
		total += v
	}
	mean := floorDiv(total, int64(n))
	d, energy := make([]int64, n), make([]int64, n)
	absolute := make([]float64, n)
	prefix := make([]int64, n+1)
	for i, v := range station.Samples {
		d[i] = v - mean
		energy[i] = d[i] * d[i]
		absolute[i] = float64(abs64(d[i]))
		prefix[i+1] = prefix[i] + energy[i]
		station.Peak = max(station.Peak, abs64(d[i]))
		if abs64(v) >= int64(p.integer("clip_level", 0)) {
			station.ClippedSamples++
		}
	}
	station.Mean, station.Noise = mean, median(absolute)
	sw, lw := p.integer("sta_window", 0), p.integer("lta_window", 0)
	on := false
	beginning := 0
	peakRatio := 0.0
	finish := func(end int) {
		station.Triggers++
		duration := end - beginning
		if duration < p.integer("min_duration", 0) {
			station.ShortTriggers++
			return
		}
		position := beginning
		for position-1 >= beginning-sw+1 && energy[position-1] >= int64(p.integer("noise_level", 0)) {
			position--
		}
		amplitude := int64(0)
		clipped := false
		for j := position; j < min(position+p.integer("amplitude_window", 0), n); j++ {
			amplitude = max(amplitude, abs64(d[j]))
			if abs64(station.Samples[j]) >= int64(p.integer("clip_level", 0)) {
				clipped = true
			}
		}
		station.Picks = append(station.Picks, &Pick{Station: station, Sample: station.Start + position,
			Duration: duration, Ratio: peakRatio, Amplitude: amplitude, Clipped: clipped, State: "unassociated"})
	}
	for i := sw + lw - 1; i < n; i++ {
		sta, lta := prefix[i+1]-prefix[i-sw+1], prefix[i-sw+1]-prefix[i-sw-lw+1]
		numerator, denominator := sta*int64(lw), lta*int64(sw)
		if !on {
			if numerator*int64(p.integer("trigger_on", 1)) >= int64(p.integer("trigger_on", 0))*denominator {
				on = true
				beginning = i
				peakRatio = float64(numerator) / float64(denominator)
			}
		} else if numerator*int64(p.integer("trigger_off", 1)) < int64(p.integer("trigger_off", 0))*denominator {
			finish(i)
			on = false
		} else {
			peakRatio = math.Max(peakRatio, float64(numerator)/float64(denominator))
		}
	}
	if on {
		finish(n)
	}
	return station.Picks
}
