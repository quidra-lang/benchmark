package main

import (
	"fmt"
	"math"
	"math/cmplx"
)

func sum(v []float64) float64 {
	s := 0.0
	for _, x := range v {
		s += x
	}
	return s
}
func squares(v []float64) float64 {
	s := 0.0
	for _, x := range v {
		s += x * x
	}
	return s
}
func rms(v []float64) float64 { return math.Sqrt(squares(v) / float64(len(v))) }
func db(v float64) float64    { return 20 * math.Log10(v) }
func best(v []float64, lo, hi int) int {
	k := lo
	for j := lo + 1; j <= hi; j++ {
		if v[j] > v[k] {
			k = j
		}
	}
	return k
}
func harmonicBin(a []float64, center float64, d int) int {
	k := -1
	for j := 1; j+1 < len(a); j++ {
		if math.Abs(float64(j)-center) <= float64(d) && (k < 0 || a[j] > a[k]) {
			k = j
		}
	}
	return k
}
func detrend(s []float64, fs int) ([]float64, []any) {
	n := len(s)
	mu := sum(s) / float64(n)
	center := float64(n-1) / 2
	num, den := 0.0, 0.0
	lo, hi := s[0], s[0]
	for i, v := range s {
		t := float64(i) - center
		num += t * (v - mu)
		den += t * t
		lo = math.Min(lo, v)
		hi = math.Max(hi, v)
	}
	slope := num / den
	d := make([]float64, n)
	peak, cube, four := 0.0, 0.0, 0.0
	for i, v := range s {
		d[i] = v - mu - slope*(float64(i)-center)
		peak = math.Max(peak, math.Abs(d[i]))
		cube += d[i] * d[i] * d[i]
		four += d[i] * d[i] * d[i] * d[i]
	}
	r := rms(d)
	return d, []any{"mean", mu, "slope", slope * float64(fs), "rms", r, "min", lo, "max", hi, "crest",
		peak / r, "skewness", cube / float64(n) / (r * r * r), "kurtosis", four / float64(n) / (r * r * r * r)}
}
func bandwidth(a []float64, k int) float64 {
	limit := a[k] / math.Sqrt(2)
	left, right := 0.0, float64(len(a)-1)
	for j := k + 1; j < len(a); j++ {
		if a[j] <= limit {
			right = float64(j-1) + (a[j-1]-limit)/(a[j-1]-a[j])
			break
		}
	}
	for j := k - 1; j >= 0; j-- {
		if a[j] <= limit {
			left = float64(j+1) - (a[j+1]-limit)/(a[j+1]-a[j])
			break
		}
	}
	return right - left
}
func correlationLag(v []float64, limit int) (int, float64) {
	q := len(v)
	at := func(k int) float64 { return v[(k%q+q)%q] }
	chosen := -limit
	for lag := -limit + 1; lag <= limit; lag++ {
		v1, v2 := at(lag), at(chosen)
		if v1 > v2 || (v1 == v2 && (absInt(lag) < absInt(chosen) || (absInt(lag) == absInt(chosen) && lag < chosen))) {
			chosen = lag
		}
	}
	position, _ := interpolate([]float64{at(chosen - 1), at(chosen), at(chosen + 1)}, 1, false)
	return chosen, float64(chosen) + position - 1
}
func absInt(a int) int {
	if a < 0 {
		return -a
	}
	return a
}
func check(v float64) string {
	if v <= 1e-6 {
		return "ok"
	}
	return "failed"
}
func yes(v bool) string {
	if v {
		return "yes"
	}
	return "no"
}
func main() {
	fs, s1, s2, p := readInput()
	n := len(s1)
	x, stats1 := detrend(s1, fs)
	y, stats2 := detrend(s2, fs)
	m, kmax := p.M, p.M/2
	frequency := func(k int) float64 { return float64(k*fs) / float64(m) }
	w := window(p.MainWindow, m)
	fig := figures(w, fs)
	u, mainFFT, a := amplitude(x, w)
	amax := a[best(a, 0, kmax)]
	floor := median(a[1:kmax])
	peaks := rankedPeaks(a, p.PeakCount, func(k int) bool { return db(a[k]/amax) >= p.Threshold })
	positions := make([]float64, len(peaks))
	for rank, k := range peaks {
		positions[rank], _ = interpolate(a, k, true)
	}
	wr := welch(x, y, fs, p.L, p.WelchWindow)
	labels := make([]string, len(peaks))
	for rank, k := range peaks {
		q := positions[rank]
		label := "other"
		for h := 1; h <= 10; h++ {
			if math.Abs(q-float64(h)*p.Fundamental*float64(m)/float64(fs)) <= float64(p.D) {
				label = fmt.Sprint("h", h)
				break
			}
		}
		if label == "other" {
			fq := q * float64(fs) / float64(m)
			j := int(math.Floor(fq/float64(p.Notch) + .5))
			if j >= 1 && math.Abs(fq-float64(j*p.Notch)) <= float64(p.Width) {
				label = "mains"
			}
		}
		if label == "other" {
		outer:
			for pr, kp := range peaks {
				if pr == rank || a[kp] <= a[k] {
					continue
				}
				for rr, kr := range peaks {
					if rr != rank && rr != pr && a[kp] > a[kr] && math.Abs(q+positions[rr]-2*positions[pr]) <= 1 {
						label = fmt.Sprint("sideband", pr+1)
						break outer
					}
				}
			}
		}
		labels[rank] = label
	}
	rows := [][]any{}
	for k, v := range a {
		rows = append(rows, []any{frequency(k), v})
	}
	writeCSV("spectrum.csv", "frequency,amplitude", rows)
	peakLines := []string{fields("length", m, "window", p.MainWindow, "resolution", float64(fs)/float64(m),
		"threshold_db", p.Threshold), fields("max_amplitude", amax, "noise_floor", floor, "noise_floor_db",
		db(floor)), fields("peaks", len(peaks))}
	for rank, k := range peaks {
		q, v := interpolate(a, k, true)
		peakLines = append(peakLines, fmt.Sprint(rank+1)+" "+fields("bin", k, "frequency", frequency(k),
			"refined", q*float64(fs)/float64(m), "amplitude", v, "level_db", db(a[k]/amax), "phase",
			cmplx.Phase(mainFFT[k])*180/pi, "bandwidth", bandwidth(a, k)*float64(fs)/float64(m),
			"snr_db", db(a[k]/floor), "coherence", wr.Coherence[(2*k*p.L+m)/(2*m)], "label", labels[rank]))
	}
	writeLines("peaks.txt", peakLines)
	rows = nil
	for k, v := range wr.PSD {
		rows = append(rows, []any{float64(k*fs) / float64(p.L), 10 * math.Log10(v)})
	}
	writeCSV("welch_psd.csv", "frequency,psd_db", rows)
	report := []string{"[signal]", fields("sample_rate", fs, "samples", n, "duration", float64(n)/float64(fs)),
		"channel=1 " + fields(stats1...), "channel=2 " + fields(stats2...), "[levels]"}
	blocks := n / p.Block
	levelLines := []string{}
	loudest := 0
	maxRMS := -1.0
	for g := 0; g < blocks; g++ {
		lo, hi := g*p.Block, (g+1)*p.Block
		r1, r2 := rms(x[lo:hi]), rms(y[lo:hi])
		peak := 0.0
		for _, v := range x[lo:hi] {
			peak = math.Max(peak, math.Abs(v))
		}
		if r1 > maxRMS {
			loudest, maxRMS = g, r1
		}
		levelLines = append(levelLines, fields("block", g, "time", float64(lo)/float64(fs), "rms1", r1, "rms2", r2, "peak1", peak))
	}
	report = append(report, fields("block_length", p.Block, "blocks", blocks, "loudest", loudest))
	report = append(report, levelLines...)
	report = append(report, "[windows]")
	for _, name := range windowNames {
		ww := window(name, m)
		f := figures(ww, fs)
		_, _, aw := amplitude(x, ww)
		kb := harmonicBin(aw, p.Fundamental*float64(m)/float64(fs), p.D)
		_, av := interpolate(aw, kb, true)
		report = append(report, fields("name", name, "coherent_gain", f.Gain, "enbw_bins", f.ENBW, "enbw_hz",
			f.Hz, "scalloping_db", f.Scalloping, "fundamental_bin", kb, "bin_amplitude", aw[kb],
			"refined_amplitude", av, "floor_db", db(median(aw[1:kmax]))))
	}
	harmonicBins := make([]int, 10)
	harmonicPositions, harmonicValues := make([]float64, 10), make([]float64, 10)
	for h := 1; h <= 10; h++ {
		kh := harmonicBin(a, float64(h)*p.Fundamental*float64(m)/float64(fs), p.D)
		harmonicBins[h-1] = kh
		harmonicPositions[h-1], harmonicValues[h-1] = interpolate(a, kh, true)
	}
	pw := make([]float64, len(a))
	power, weighted, logPower, fundamentalPower := 0.0, 0.0, 0.0, 0.0
	for k := 1; k < kmax; k++ {
		pw[k] = a[k] * a[k] / 2
		power += pw[k]
		weighted += frequency(k) * pw[k]
		logPower += math.Log(pw[k])
		if absInt(k-harmonicBins[0]) <= p.D {
			fundamentalPower += pw[k]
		}
	}
	ptot := power / fig.ENBW
	p1 := fundamentalPower / fig.ENBW
	centroid := weighted / power
	spread, run, rolloff := 0.0, 0.0, 0.0
	rolled := false
	for k := 1; k < kmax; k++ {
		d := frequency(k) - centroid
		spread += d * d * pw[k]
		run += pw[k]
		if !rolled && run >= .85*power {
			rolloff = frequency(k)
			rolled = true
		}
	}
	method, size := "radix2", m
	if pow2(m) != m {
		method, size = "bluestein", pow2(2*m-1)
	}
	report = append(report, "[main]", fields("length", m, "window", p.MainWindow, "method", method, "transform_size",
		size, "resolution", float64(fs)/float64(m)), fields("total_power", ptot, "centroid", centroid,
		"spread", math.Sqrt(spread/power), "rolloff", rolloff, "flatness_db", 10*math.Log10(math.Exp(logPower/float64(kmax-1))/(power/float64(kmax-1)))),
		"[bands]")
	for eta := 0; eta+1 < len(p.Bands); eta++ {
		s := 0.0
		for k := 1; k < kmax; k++ {
			if p.Bands[eta]*m <= k*fs && k*fs < p.Bands[eta+1]*m {
				s += pw[k]
			}
		}
		s /= fig.ENBW
		report = append(report, fields("range", fmt.Sprint(p.Bands[eta], "-", p.Bands[eta+1]), "power", s, "percent", 100*s/ptot))
	}
	report = append(report, "[third_octave]")
	for b := p.T1; b <= p.T2; b++ {
		center := 1000 * math.Pow(2, float64(b)/3)
		lo := 1000 * math.Pow(2, float64(2*b-1)/6)
		hi := 1000 * math.Pow(2, float64(2*b+1)/6)
		count, s := 0, 0.0
		for k := 1; k < kmax; k++ {
			if lo <= frequency(k) && frequency(k) < hi {
				count++
				s += pw[k]
			}
		}
		report = append(report, fields("band", b, "center", center, "lower", lo, "upper", hi, "bins", count, "level_db", 10*math.Log10(s/fig.ENBW)))
	}
	report = append(report, "[harmonics]", fields("fundamental", p.Fundamental, "search", p.D))
	n3 := 0
	for h := 1; h <= 10; h++ {
		level := db(harmonicValues[h-1] / harmonicValues[0])
		if h >= 3 && level >= -30 {
			n3++
		}
		report = append(report, fields("h", h, "target", float64(h)*p.Fundamental, "bin", harmonicBins[h-1],
			"refined", harmonicPositions[h-1]*float64(fs)/float64(m), "amplitude", harmonicValues[h-1],
			"level_db", level))
	}
	thd := math.Sqrt(squares(harmonicValues[1:])) / harmonicValues[0]
	thdn := math.Sqrt((ptot - p1) / p1)
	report = append(report, fields("thd_percent", 100*thd, "thd_db", db(thd)), fields("thdn_percent", 100*thdn, "thdn_db", db(thdn)))
	frames, packingError := frameTransforms(x, window(p.SpectrogramWindow, p.F), p.H)
	nt := len(frames)
	g := make([][]float64, nt)
	gmax := 0.0
	for t, frame := range frames {
		g[t] = make([]float64, len(frame))
		for k, z := range frame {
			g[t][k] = cmplx.Abs(z)
			gmax = math.Max(gmax, g[t][k])
		}
	}
	flux := make([]float64, nt)
	for t := 1; t < nt; t++ {
		for k := range g[t] {
			flux[t] += math.Max(0, g[t][k]-g[t-1][k])
		}
	}
	theta := p.Onset * median(flux[1:])
	onsets := []int{}
	for t := 1; t < nt; t++ {
		if flux[t] > theta && flux[t] > flux[t-1] && (t == nt-1 || flux[t] > flux[t+1]) {
			onsets = append(onsets, t)
		}
	}
	kappa := make([]float64, p.F/2+1)
	for k := range kappa {
		s2, s4 := 0.0, 0.0
		for t := 0; t < nt; t++ {
			v := g[t][k]
			s2 += v * v
			s4 += v * v * v * v
		}
		kappa[k] = float64(nt)*s4/(s2*s2) - 2
	}
	kk := best(kappa, 1, p.F/2-1)
	sg := []string{fields("frames", nt, "bins", p.F/2+1, "frame_length", p.F, "hop", p.H, "window", p.SpectrogramWindow, "band_db", p.B, "max_db", db(gmax))}
	sg = append(sg, shadeLines(g, fs, p.F, p.B, gmax)...)
	sg = append(sg, "track")
	for t := 0; t < nt; t++ {
		kd := best(g[t], 1, p.F/2-1)
		sg = append(sg, fields("frame", t, "time", float64(t*p.H)/float64(fs), "frequency", float64(kd*fs)/float64(p.F), "level_db", db(g[t][kd]/gmax)))
	}
	sg = append(sg, fields("onsets", len(onsets), "threshold", theta))
	for _, t := range onsets {
		sg = append(sg, fields("frame", t, "time", float64(t*p.H)/float64(fs), "flux", flux[t]))
	}
	sg = append(sg, "kurtosis "+fields("bin", kk, "frequency", float64(kk*fs)/float64(p.F), "value", kappa[kk]))
	writeLines("spectrogram.txt", sg)
	xf := transform(realComplex(x, n), false)
	bp, nf, ze := make([]complex128, n), make([]complex128, n), make([]complex128, n)
	kept, removed := 0, 0
	for k, z := range xf {
		gk := min(k, n-k) * fs
		if p.B1*n <= gk && gk <= p.B2*n {
			bp[k] = z
			kept++
		}
		jk := (2*gk + p.Notch*n) / (2 * p.Notch * n)
		if jk >= 1 && absInt(gk-jk*p.Notch*n) <= p.Width*n {
			removed++
		} else {
			nf[k] = z
		}
		if k >= 1 && k <= (n-1)/2 && p.E1*n <= k*fs && k*fs <= p.E2*n {
			ze[k] = 2 * z
		}
	}
	bandpassed := realParts(transform(bp, true))
	notched := realParts(transform(nf, true))
	analytic := transform(ze, true)
	envelope := make([]float64, n)
	for i, z := range analytic {
		envelope[i] = cmplx.Abs(z)
	}
	em := sum(envelope) / float64(n)
	centered := make([]float64, n)
	for i, v := range envelope {
		centered[i] = v - em
	}
	ev := transform(realComplex(centered, n), false)
	be := make([]float64, n)
	for k, z := range ev {
		be[k] = 2 * cmplx.Abs(z) / float64(n)
	}
	ke := best(be, 1, (p.E2-p.E1)*n/(2*fs))
	qe, envAmplitude := interpolate(be, ke, true)
	depth := envAmplitude / em
	nu := make([]float64, n-1)
	for i := 1; i < n; i++ {
		dp := cmplx.Phase(analytic[i]) - cmplx.Phase(analytic[i-1])
		if dp <= -pi {
			dp += 2 * pi
		}
		if dp > pi {
			dp -= 2 * pi
		}
		nu[i-1] = dp * float64(fs) / (2 * pi)
	}
	nuMean := sum(nu) / float64(n-1)
	nuVar := 0.0
	for _, v := range nu {
		nuVar += (v - nuMean) * (v - nuMean)
	}
	sm := convolution(y, p.FIR)
	dc, firGain := sum(p.FIR), complex(0, 0)
	for j, h := range p.FIR {
		firGain += complex(h, 0) * rot(2*pi*p.Fundamental*float64(j)/float64(fs))
	}
	rows = nil
	for i := 0; i < n; i++ {
		rows = append(rows, []any{i, bandpassed[i], notched[i], sm[i], envelope[i]})
	}
	writeCSV("filtered.csv", "index,bandpass,notched,smoothed,envelope", rows)
	lam1, lam2 := (fs+p.P2-1)/p.P2, fs/p.P1
	hpsBin := -1
	hpsMax := math.Inf(-1)
	for k := 1; 5*k <= kmax; k++ {
		if p.P1*m <= k*fs && k*fs <= p.P2*m {
			s := 0.0
			for r := 1; r <= 5; r++ {
				s += math.Log(a[r*k])
			}
			if s > hpsMax {
				hpsMax, hpsBin = s, k
			}
		}
	}
	q := pow2(2*n - 1)
	bf := radix(realComplex(bandpassed, q), false)
	for k, z := range bf {
		v := cmplx.Abs(z)
		bf[k] = complex(v*v, 0)
	}
	rho := realParts(radix(bf, true))
	lag := best(rho, lam1, lam2)
	tau, rhoStar := interpolate(rho, lag, false)
	crossings := 0
	for i := 1; i < n; i++ {
		if bandpassed[i-1] < 0 && bandpassed[i] >= 0 {
			crossings++
		}
	}
	report = append(report, "[pitch]", fields("range", fmt.Sprint(p.P1, "-", p.P2), "lags", fmt.Sprint(lam1,
		"-", lam2)), "hps "+fields("bin", hpsBin, "order", 5, "frequency", frequency(hpsBin)), "autocorrelation "+fields("lag",
		lag, "period", tau, "frequency", float64(fs)/tau, "strength", rhoStar/rho[0]), "zero_crossing "+fields("count",
		crossings, "frequency", float64(crossings*fs)/float64(n)), "[zoom]")
	dz := float64(p.Z2-p.Z1) / float64(p.J-1)
	zoomFFT := chirpZ(u, fs, p.Z1, p.Z2, p.J)
	zm := make([]float64, p.J)
	for j, z := range zoomFFT {
		zm[j] = 2 * cmplx.Abs(z) / fig.S1
	}
	report = append(report, fields("band", fmt.Sprint(p.Z1, "-", p.Z2), "points", p.J, "step", dz))
	for rank, j := range rankedPeaks(zm, 3, nil) {
		qz, v := interpolate(zm, j, true)
		report = append(report, fields("peak", rank+1, "frequency", float64(p.Z1)+qz*dz, "amplitude", v))
	}
	integrated := sum(wr.PSD) * float64(fs) / float64(p.L)
	variance := rms(x) * rms(x)
	report = append(report, "[welch]", fields("segment_length", p.L, "segments", wr.Segments, "window",
		p.WelchWindow, "resolution", float64(fs)/float64(p.L)), fields("integrated_power", integrated,
		"variance", variance, "ratio", integrated/variance))
	for rank, k := range rankedPeaks(wr.PSD, 5, nil) {
		report = append(report, fields("peak", rank+1, "frequency", float64(k*fs)/float64(p.L), "psd_db",
			10*math.Log10(wr.PSD[k]), "coherence", wr.Coherence[k], "gain", cmplx.Abs(wr.Transfer[k]),
			"phase", cmplx.Phase(wr.Transfer[k])*180/pi))
	}
	report = append(report, "[filter]", fields("bandpass", fmt.Sprint(p.B1, "-", p.B2), "bins_kept",
		kept, "rms", rms(bandpassed), "energy_ratio", squares(bandpassed)/squares(x)), fields("notch",
		p.Notch, "width", p.Width, "bins_removed", removed, "rms", rms(notched)), fields("fir_taps",
		len(p.FIR), "dc_gain", dc, "gain_at_fundamental_db", db(cmplx.Abs(firGain)), "rms", rms(sm[:n])),
		"[envelope]", fields("band", fmt.Sprint(p.E1, "-", p.E2), "mean", em, "bin", ke, "frequency",
			qe*float64(fs)/float64(n), "amplitude", envAmplitude, "depth", depth), "instantaneous_frequency "+fields("mean",
			nuMean, "std", math.Sqrt(nuVar/float64(n-1))))
	fx, fy := radix(realComplex(x, q), false), radix(realComplex(y, q), false)
	cxy, phat := make([]complex128, q), make([]complex128, q)
	for k := range fx {
		cxy[k] = cmplx.Conj(fx[k]) * fy[k]
		phat[k] = cxy[k] / complex(cmplx.Abs(cxy[k]), 0)
	}
	r, rp := realParts(radix(cxy, true)), realParts(radix(phat, true))
	ell, refined := correlationLag(r, p.MaxLag)
	plag, prefined := correlationLag(rp, p.MaxLag)
	report = append(report, "[correlation]", fields("max_lag", p.MaxLag, "lag", ell, "refined_lag", refined,
		"delay_ms", 1000*refined/float64(fs), "coefficient", r[(ell+q)%q]/math.Sqrt(squares(x)*squares(y))),
		fields("phat_lag", plag, "refined_lag", prefined, "delay_ms", 1000*prefined/float64(fs)))
	back := transform(mainFFT, true)
	inverseError := 0.0
	for i, v := range back {
		inverseError = math.Max(inverseError, cmplx.Abs(v-complex(u[i], 0)))
	}
	fftEnergy := 0.0
	for _, z := range mainFFT {
		v := cmplx.Abs(z)
		fftEnergy += v * v
	}
	parseval := math.Abs(squares(u)-fftEnergy/float64(m)) / squares(u)
	firError := 0.0
	for i, v := range sm {
		direct := 0.0
		for j := 0; j < n; j++ {
			h := i - j
			if h >= 0 && h < len(p.FIR) {
				direct += y[j] * p.FIR[h]
			}
		}
		firError = math.Max(firError, math.Abs(v-direct))
	}
	spotError := 0.0
	for _, k := range peaks {
		z := complex(0, 0)
		for j, v := range u {
			z += complex(v, 0) * rot(2*pi*float64(k*j%m)/float64(m))
		}
		spotError = math.Max(spotError, cmplx.Abs(z-mainFFT[k]))
	}
	report = append(report, "[checks]", fields("inverse_roundtrip", check(inverseError)), fields("parseval",
		check(parseval)), fields("real_packing", check(math.Max(wr.Error, packingError)), "transforms",
		2*wr.Segments+nt), fields("fir_fft_vs_direct", check(firError)), fields("dft_spot_check",
		check(spotError), "bins", len(peaks)), "[diagnosis]")
	ratio := harmonicValues[1] / harmonicValues[0]
	electrical := false
	electricalLevel := any("none")
	for rank, label := range labels {
		if label == "mains" {
			level := db(a[peaks[rank]] / amax)
			electrical, electricalLevel = level >= -20, level
			break
		}
	}
	findings := 0
	for _, v := range []bool{ratio >= .5, n3 >= 3, depth >= .2, electrical, len(onsets) > 0} {
		if v {
			findings++
		}
	}
	status := "normal"
	if findings == 1 {
		status = "warning"
	} else if findings >= 2 {
		status = "alarm"
	}
	report = append(report, fields("misalignment", yes(ratio >= .5), "ratio", ratio), fields("looseness",
		yes(n3 >= 3), "harmonics", n3), fields("bearing", yes(depth >= .2), "depth", depth), fields("electrical",
		yes(electrical), "level_db", electricalLevel), fields("transient", yes(len(onsets) > 0),
		"onsets", len(onsets)), fields("status", status, "findings", findings))
	writeLines("report.txt", report)
}
