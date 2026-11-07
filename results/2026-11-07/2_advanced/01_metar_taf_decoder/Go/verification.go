package main

var categories = []string{"VFR", "MVFR", "IFR", "LIFR"}

func categoryIndex(s string) int {
	for i, c := range categories {
		if c == s {
			return i
		}
	}
	return 0
}
func covers(t, o *Report) bool {
	h := o.time-o.time%60
	return t.time <= o.time && t.start <= h && h < t.end
}
func selectTaf(tafs []*Report, o *Report) *Report {
	var selected *Report
	for _, t := range tafs {
		if covers(t, o) && (selected == nil || t.time > selected.time || t.time == selected.time && t.number > selected.number) {
			selected = t
		}
	}
	return selected
}

type Choice struct {
	observation	*Report
	forecast	*Hour
	temporaryHit	bool
}
type Analysis struct {
	table							[4][4]int64
	rows, columns						[4]int64
	buckets							[5][2]int64
	total, noForecast, hits, temporaryHits, expected	int64
	choices							[]Choice
}

func analyze(observations, tafs []*Report) *Analysis {
	a := &Analysis{}
	for _, o := range observations {
		h, cat := o.time-o.time%60, o.main.category
		for _, t := range tafs {
			if covers(t, o) {
				b := (h-t.start)/360
				a.buckets[b][1]++
				if t.timeline[h].prevailing.category == cat {
					a.buckets[b][0]++
				}
			}
		}
		chosen := selectTaf(tafs, o)
		if chosen == nil {
			a.noForecast++
			continue
		}
		f := chosen.timeline[h]
		fc := f.prevailing.category
		hit, tempHit := fc == cat, fc == cat
		for _, tmp := range f.temporary {
			tempHit = tempHit || tmp.state.category == cat
		}
		a.table[categoryIndex(fc)][categoryIndex(cat)]++
		if hit {
			a.hits++
		}
		if tempHit {
			a.temporaryHits++
		}
		a.choices = append(a.choices, Choice{o, f, tempHit})
	}
	for i := 0; i < 4; i++ {
		for j := 0; j < 4; j++ {
			a.rows[i] += a.table[i][j]
			a.columns[j] += a.table[i][j]
			a.total += a.table[i][j]
		}
	}
	for i := 0; i < 4; i++ {
		a.expected += a.rows[i]*a.columns[i]
	}
	return a
}

func (a *Analysis) hitRate() string {
	return fraction(a.hits, a.total)
}
func (a *Analysis) temporaryRate() string {
	return fraction(a.temporaryHits, a.total)
}
func (a *Analysis) skill() string {
	return fraction(a.total*a.hits-a.expected, a.total*a.total-a.expected)
}
func (a *Analysis) pod(i int) string {
	return fraction(a.table[i][i], a.columns[i])
}
func (a *Analysis) far(i int) string {
	return fraction(a.rows[i]-a.table[i][i], a.rows[i])
}
