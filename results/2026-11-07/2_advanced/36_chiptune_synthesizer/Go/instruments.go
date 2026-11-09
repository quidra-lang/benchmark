package main

var noteTable = []int64{26163, 27718, 29366, 31113, 32963, 34923, 36999, 39200, 41530, 44000, 46616, 49388}
var sineTable = []int64{0, 24, 49, 74, 97, 120, 141, 161, 180, 197, 212, 224, 235, 244, 250, 253,
	255, 253, 250, 244, 235, 224, 212, 197, 180, 161, 141, 120, 97, 74, 49, 24}
var pulseWidths = []int64{1, 2, 4, 6}

func floorDiv(a, b int64) int64 {
	q := a / b
	if a%b < 0 {
		q--
	}
	return q
}
func clamp(v, lo, hi int64) int64 { return min(max(v, lo), hi) }
func noteFrequency(note int) int64 {
	o, j := note/12, note%12
	if o >= 4 {
		return noteTable[j] << uint(o-4)
	}
	return noteTable[j] >> uint(4-o)
}
func transpose(frequency, semitones int64) int64 {
	return (frequency * noteTable[semitones%12] / noteTable[0]) << uint(semitones/12)
}
func oscillation(position, depth, divisor int64) int64 {
	q := sineTable[position%32] * depth / divisor
	if position >= 32 {
		return -q
	}
	return q
}
func envelopeValue(ins *Instrument, age int64, released bool, releaseAge, releaseLevel int64) int64 {
	if released {
		elapsed := age - releaseAge
		if elapsed < ins.Release {
			return floorDiv(releaseLevel*(ins.Release-1-elapsed), ins.Release)
		}
		return 0
	}
	if age < ins.Attack {
		return 15 * (age + 1) / ins.Attack
	}
	if age < ins.Attack+ins.Decay {
		return 15 - (15-ins.Sustain)*(age-ins.Attack+1)/ins.Decay
	}
	return ins.Sustain
}
func waveValue(ins *Instrument, mode, phase, register int64) int64 {
	switch ins.Wave {
	case "PULSE":
		if phase/8192 < pulseWidths[mode] {
			return 15
		}
		return 0
	case "TRIANGLE":
		j := phase / 2048
		if j < 16 {
			return 15 - j
		}
		return j - 16
	case "SAW":
		return phase / 4096
	case "TABLE":
		return ins.Table[phase/2048]
	default:
		if register%2 == 0 {
			return 15
		}
		return 0
	}
}
func clockRegister(register, mode int64) int64 {
	tap := uint(1)
	if mode != 0 {
		tap = 6
	}
	feedback := (register ^ (register >> tap)) & 1
	return register/2 + feedback*16384
}
