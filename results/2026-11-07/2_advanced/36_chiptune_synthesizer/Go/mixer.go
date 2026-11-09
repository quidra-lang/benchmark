package main

func channelValue(c *Channel) int64 {
	if !c.Sounding {
		return 0
	}
	level := waveValue(c.Instrument, c.Mode, c.Phase, c.Register)
	c.Phase += c.Increment
	if c.Phase >= 65536 {
		c.Phase -= 65536
		if c.Instrument.Wave == "NOISE" {
			c.Register = clockRegister(c.Register, c.Mode)
		}
	}
	return (2*level - 15) * c.Amplitude
}
func mixTick(channels []*Channel, count int, gain int64, muted []bool, samples *[]int64, lanes *[][]int64) int {
	clipped := 0
	for range count {
		var total int64
		for i, c := range channels {
			value := channelValue(c)
			(*lanes)[i] = append((*lanes)[i], value)
			if !muted[i] {
				total += value
			}
		}
		sample := 128 + floorDiv(gain*total, 4096)
		if sample < 0 || sample > 255 {
			clipped++
			sample = clamp(sample, 0, 255)
		}
		*samples = append(*samples, sample)
	}
	return clipped
}
func fadeOut(samples []int64, fade int) {
	n := len(samples)
	length := min(n, fade)
	for i := n - length; i < n; i++ {
		samples[i] = 128 + floorDiv((samples[i]-128)*int64(n-1-i), int64(length))
	}
}
