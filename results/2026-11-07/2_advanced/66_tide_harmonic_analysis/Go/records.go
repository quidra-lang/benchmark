package main

import (
	"os"
	"strconv"
	"strings"
	"time"
)

type Settings struct {
	Epoch           time.Time
	Reference, Plot string
	Flat, W, C, Top, SurgeHours, Start, Hours,
	Grid, Lag, PlotWidth, ZT, ZB, ZS int
	KS, D, Rayleigh, SNR, Surge, MinRange float64
}
type Constituent struct {
	Name  string
	Speed float64
}
type Station struct {
	Code, Name string
	Rows       int
	Values     map[int]float64
	NA         map[int]bool
}

func must(e error) {
	if e != nil {
		panic(e)
	}
}
func text(path string) string      { b, e := os.ReadFile(path); must(e); return string(b) }
func integer(s string) int         { n, e := strconv.Atoi(s); must(e); return n }
func real(s string) float64        { n, e := strconv.ParseFloat(s, 64); must(e); return n }
func parseDate(s string) time.Time { t, e := time.Parse("2006-01-02 15:04", s); must(e); return t }
func datetime(p Settings, minutes int) string {
	return p.Epoch.Add(time.Duration(minutes) * time.Minute).Format("2006-01-02 15:04")
}
func date(p Settings, hour int) string { return datetime(p, hour*60)[:10] }
func readInput() (Settings, []Constituent, []*Station) {
	var p Settings
	var stations []*Station
	for _, line := range strings.Split(strings.TrimSpace(text("input/params.txt")), "\n") {
		a := strings.Fields(line)
		switch a[0] {
		case "epoch":
			p.Epoch = parseDate(a[1] + " " + a[2])
		case "station":
			stations = append(stations,
				&Station{a[1], strings.TrimPrefix(line, "station "+a[1]+" "), 0, map[int]float64{}, map[int]bool{}})
		case "reference":
			p.Reference = a[1]
		case "flat_run":
			p.Flat = integer(a[1])
		case "spike":
			p.W,
				p.C, p.KS, p.D = integer(a[1]), integer(a[2]), real(a[3]), real(a[4])
		case "rayleigh":
			p.Rayleigh = real(a[1])
		case "snr_min":
			p.SNR = real(a[1])
		case "top_residuals":
			p.Top = integer(a[1])
		case "surge":
			p.Surge,
				p.SurgeHours = real(a[1]), integer(a[2])
		case "predict":
			p.Start = int(parseDate(a[1]+" "+a[2]).Sub(p.Epoch) / time.Hour)
			p.Hours = integer(a[3])
		case "grid_minutes":
			p.Grid = integer(a[1])
		case "min_range":
			p.MinRange = real(a[1])
		case "correlation_lag":
			p.Lag = integer(a[1])
		case "plot":
			p.Plot,
				p.PlotWidth, p.ZT, p.ZB, p.ZS = a[1], integer(a[2]), integer(a[3]), integer(a[4]), integer(a[5])
		}
	}
	lines := strings.Split(strings.TrimSpace(text("input/constituents.txt")),
		"\n")
	var constituents []Constituent
	for _, line := range lines[1:] {
		a := strings.Fields(line)
		constituents = append(constituents,
			Constituent{a[0], real(a[1])})
	}
	byCode := map[string]*Station{}
	for _, s := range stations {
		byCode[s.Code] = s
	}
	for _, line := range strings.Split(strings.TrimSpace(text("input/observations.csv")), "\n")[1:] {
		a := strings.Split(line,
			",")
		s := byCode[a[0]]
		t := int(parseDate(a[1]).Sub(p.Epoch) / time.Hour)
		s.Rows++
		if a[2] == "NA" {
			s.NA[t] = true
		} else {
			s.Values[t] = real(a[2])
		}
	}
	return p,
		constituents, stations
}
