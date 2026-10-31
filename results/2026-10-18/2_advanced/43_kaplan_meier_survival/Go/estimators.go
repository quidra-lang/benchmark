package main

import (
	"math"
	"sort"
)

type RiskSet struct{ Time, Risk, Events, Censored int }

func riskSets(subjects []Subject) []RiskSet {
	counts, events := map[int]int{}, map[int]int{}
	for _, s := range subjects {
		counts[s.Time]++
		events[s.Time] += s.Event
	}
	times := []int{}
	for t := range counts {
		times = append(times, t)
	}
	sort.Ints(times)
	risk := len(subjects)
	rows := []RiskSet{}
	for _, t := range times {
		rows = append(rows, RiskSet{t, risk, events[t], counts[t] - events[t]})
		risk -= counts[t]
	}
	return rows
}

type KMRow struct {
	Time, Risk, Events, Censored                 int
	Survival, SE, Lower, Upper, Hazard, HazardSE float64
}

func kaplanMeier(subjects []Subject) []KMRow {
	times := riskSets(subjects)
	eventTimes := []int{}
	for _, r := range times {
		if r.Events > 0 {
			eventTimes = append(eventTimes, r.Time)
		}
	}
	survival, greenwood, hazard, variance := 1.0, 0.0, 0.0, 0.0
	rows := []KMRow{}
	for _, r := range times {
		n, d := r.Risk, r.Events
		if d == 0 {
			continue
		}
		survival *= float64(n-d) / float64(n)
		if n == d {
			greenwood = math.NaN()
		} else if !math.IsNaN(greenwood) {
			greenwood += float64(d) / float64(n*(n-d))
		}
		se, lo, hi := math.NaN(), math.NaN(), math.NaN()
		if survival != 0 {
			root := math.Sqrt(greenwood)
			se = survival * root
			l := math.Log(survival)
			omega := z95 * root / (-l)
			lo = math.Exp(l * math.Exp(omega))
			hi = math.Exp(l * math.Exp(-omega))
		}
		hazard += float64(d) / float64(n)
		variance += float64(d) / float64(n*n)
		index := len(rows)
		censored := 0
		for _, s := range subjects {
			if s.Event == 0 && s.Time >= r.Time && (index+1 == len(eventTimes) || s.Time < eventTimes[index+1]) {
				censored++
			}
		}
		rows = append(rows, KMRow{r.Time, n, d, censored, survival, se, lo, hi, hazard, math.Sqrt(variance)})
	}
	return rows
}
func rowAt(rows []KMRow, t int) KMRow {
	for j := len(rows) - 1; j >= 0; j-- {
		if rows[j].Time <= t {
			return rows[j]
		}
	}
	return KMRow{Survival: 1, Lower: math.NaN(), Upper: math.NaN()}
}

type LifeRow struct {
	Start, End, Risk, Events, Withdrawn int
	Exposed, Q, Survival, SE, Hazard    float64
}

func lifeTable(subjects []Subject, width, count int) []LifeRow {
	rows := []LifeRow{}
	survival, variance := 1.0, 0.0
	for i := 0; i < count; i++ {
		a, b := i*width, (i+1)*width
		n, d, c := 0, 0, 0
		for _, s := range subjects {
			if s.Time >= a {
				n++
			}
			if a <= s.Time && s.Time < b {
				if s.Event == 1 {
					d++
				} else {
					c++
				}
			}
		}
		f := 2*n - c
		survival *= float64(f-2*d) / float64(f)
		variance += float64(4*d) / float64(f*(f-2*d))
		rows = append(rows, LifeRow{a, b, n, d, c, float64(f) / 2, float64(2*d) / float64(f), survival,
			survival * math.Sqrt(variance), float64(2000*d) / float64(width*(f-d))})
	}
	return rows
}
