package main

import (
	"fmt"
	"os"
	"sort"
	"strings"
)

type Group struct {
	text		string
	position	int
}
type Slot struct {
	kind	string
	repeat	bool
}
type Runway struct {
	name	string
	heading	int64
}
type Station struct {
	code, name	string
	elevation	int64
	runways		[]Runway
}
type Params struct {
	crosswind, tailwind	int64
	verify			[]string
}
type Section struct {
	context, category						string
	modifier, wind, variation, visibility, temperature, pressure	*Value
	rvr, weather, cloud						[]*Value
	noTrend								bool
	ceiling								int64
}
type TrendTime struct {
	kind		string
	hour, minute	int64
}
type Change struct {
	kind			string
	time, start, end	int64
	groups			[]Group
	times			[]TrendTime
	state			*Section
}
type Temporary struct {
	kind	string
	state	*Section
}
type Hour struct {
	prevailing	*Section
	temporary	[]Temporary
}
type Component struct {
	head, cross	int64
}
type RunwayWind struct {
	name	string
	mean	Component
	gust	*Component
	usable	bool
}
type Report struct {
	number, bodyStart			int
	kind, modifier				string
	station					*Station
	time, issueDay, start, end		int64
	main, base				*Section
	trends, changes				[]*Change
	timeline				map[int64]*Hour
	slp					[]int64
	precise					[]*Value
	speciReasons				[]string
	pressureAltitude, densityAltitude	*int64
	winds					[]RunwayWind
	preferred				string
}
type ParseError struct {
	report, position	int
	content			string
}
type ErrorFunc func(int, string, string)

func readLines(name string) []string {
	b, err := os.ReadFile("input/" + name)
	if err != nil {
		panic(err)
	}
	return strings.Split(strings.TrimSuffix(string(b), "\n"), "\n")
}

func record(errors *[]ParseError, n int) ErrorFunc {
	return func(p int, reason, text string) {
		if text != "" {
			reason += " \"" + text + "\""
		}
		*errors = append(*errors, ParseError{n, p, reason})
	}
}

func parseHeader(words []string, n int, stations map[string]*Station, c Calendar, error ErrorFunc) *Report {
	kind := words[0]
	if kind != "METAR" && kind != "SPECI" && kind != "TAF" {
		error(1, "rejected report, invalid type", kind)
		return nil
	}
	r := &Report{number: n, kind: kind}
	i := 1
	if kind == "TAF" && i < len(words) && (words[i] == "AMD" || words[i] == "COR") {
		r.modifier = words[i]
		i++
	}
	items := []string{"station", "time"}
	if kind == "TAF" {
		items = append(items, "validity")
	}
	for _, item := range items {
		if i == len(words) {
			error(i+1, "rejected report, missing " + item, "")
			return nil
		}
		w := words[i]
		ok := false
		switch item {
		case "station":
			r.station = stations[w]
			ok = r.station != nil
		case "time":
			r.time = c.observation(w)
			ok = r.time >= 0
			r.issueDay = r.time/1440 + 1
		case "validity":
			r.start, r.end, ok = c.period(w, r.issueDay, 1800)
		}
		if !ok {
			error(i+1, "rejected report, invalid " + item, w)
			return nil
		}
		i++
	}
	r.bodyStart = i
	return r
}

func joinGroups(words []string, start int) []Group {
	result := []Group{}
	for i := start; i < len(words); i++ {
		position, text := i+1, words[i]
		if match(`^\d$`, text) != nil && i+1 < len(words) && match(`^\d/\d{1,2}SM$`, words[i+1]) != nil {
			i++
			text += " " + words[i]
		}
		result = append(result, Group{text, position})
	}
	return result
}

func matchSection(body []Group, slots []Slot, context string, station *Station, error ErrorFunc) *Section {
	s := &Section{context: context}
	current := 0
	for _, g := range body {
		found := current
		var v *Value
		for found < len(slots) {
			v = slots[found].test(g.text)
			if v != nil {
				break
			}
			found++
		}
		if found == len(slots) {
			reason := "unknown group"
			for _, slot := range slots[:current] {
				if slot.test(g.text) != nil {
					reason = "out of order group"
					break
				}
			}
			error(g.position, reason, g.text)
			continue
		}
		slot := slots[found]
		if !valid(slot.kind, v, s, station) {
			error(g.position, "invalid group", g.text)
			continue
		}
		accept(s, slot.kind, v)
		current = found
		if !slot.repeat {
			current++
		}
		if slot.kind == "visibility" && v.kind == "cavok" {
			for i, slot := range slots {
				if slot.kind == "cloud" {
					current = i+1
					break
				}
			}
		}
	}
	return s
}

func derive(s *Section) {
	s.ceiling = -1
	for _, c := range s.cloud {
		if c.amount == "BKN" || c.amount == "OVC" || c.amount == "VV" {
			s.ceiling = c.height
			break
		}
	}
	n, d := int64(0), int64(1)
	if s.visibility != nil {
		n, d = mileFraction(s.visibility)
	}
	less := func(k int64) bool {
		return s.visibility != nil && n < k*d
	}
	atMost := func(k int64) bool {
		return s.visibility != nil && n <= k*d
	}
	switch {
	case s.ceiling >= 0 && s.ceiling < 500 || less(1): s.category = "LIFR"
	case s.ceiling >= 0 && s.ceiling < 1000 || less(3): s.category = "IFR"
	case s.ceiling >= 0 && s.ceiling <= 3000 || atMost(5): s.category = "MVFR"
	default: s.category = "VFR"
	}
}

func components(d, h, w int64) Component {
	return Component{floorDiv(w*sin(d-h+90), 1000), floorDiv(w*sin(d-h), 1000)}
}

func runwayWinds(r *Report, p Params) {
	w := r.main.wind
	if w == nil || w.variable || w.calm {
		return
	}
	r.winds = []RunwayWind{}
	best := int64(-1 << 62)
	for _, runway := range r.station.runways {
		mean := components(w.direction, runway.heading, w.speed)
		v := RunwayWind{name: runway.name, mean: mean}
		deciding := mean
		if w.gust >= 0 {
			g := components(w.direction, runway.heading, w.gust)
			v.gust = &g
			deciding = g
		}
		v.usable = abs(deciding.cross) <= p.crosswind && -deciding.head <= p.tailwind
		if v.usable && mean.head > best {
			best = mean.head
			r.preferred = v.name
		}
		r.winds = append(r.winds, v)
	}
}

func windChanges(a, b *Value, alpha int64) []string {
	reasons := []string{}
	if a == nil || b == nil {
		return reasons
	}
	if !a.variable && !a.calm && !b.variable && !b.calm && (a.speed >= 10 || b.speed >= 10) {
		d := abs(a.direction-b.direction) % 360
		if d > 180 {
			d = 360-d
		}
		if d >= alpha {
			reasons = append(reasons, "wind shift")
		}
	}
	if abs(a.speed-b.speed) >= 10 {
		reasons = append(reasons, "wind speed")
	}
	return reasons
}

func weatherFlag(s *Section, freezing bool) bool {
	for _, w := range s.weather {
		if !freezing && w.descriptor == "TS" {
			return true
		}
		if freezing && w.descriptor == "FZ" {
			for _, p := range w.codes {
				if p == "DZ" || p == "RA" {
					return true
				}
			}
		}
	}
	return false
}

func speciCheck(previous, r *Report) []string {
	if previous == nil {
		return []string{"no previous report"}
	}
	a, b := previous.main, r.main
	reasons := []string{}
	if a.category != b.category {
		reasons = append(reasons, "category " + a.category + " to " + b.category)
	}
	reasons = append(reasons, windChanges(a.wind, b.wind, 45)...)
	for _, freezing := range []bool{false, true} {
		if weatherFlag(a, freezing) != weatherFlag(b, freezing) {
			label, phase := "thunderstorm", "ended"
			if freezing {
				label = "freezing precipitation"
			}
			if weatherFlag(b, freezing) {
				phase = "began"
			}
			reasons = append(reasons, label + " " + phase)
		}
	}
	if len(reasons) == 0 {
		reasons = append(reasons, "no criteria met")
	}
	return reasons
}

func decodeObservation(r *Report, body []Group, p Params, error ErrorFunc) {
	main, trends, remarks := splitMetar(body)
	r.main = matchSection(main, mainSlots, "main", r.station, error)
	derive(r.main)
	r.trends = readTrends(trends, error)
	for _, t := range r.trends {
		t.state = matchSection(t.groups, tafSlots, "trend", r.station, error)
	}
	r.slp, r.precise = readRemarks(remarks)
	if r.main.pressure != nil {
		a := r.station.elevation + (2992-r.main.pressure.inches)*10
		r.pressureAltitude = &a
		if r.main.temperature != nil {
			d := a + floorDiv(120*(1000*r.main.temperature.temp-15000+2*a), 1000)
			r.densityAltitude = &d
		}
	}
	runwayWinds(r, p)
}

func decodeForecast(r *Report, body []Group, c Calendar, error ErrorFunc) {
	base, changes := splitTaf(body, r, c, error)
	r.base = matchSection(base, tafSlots, "base", r.station, error)
	r.changes = changes
	for _, change := range changes {
		change.state = matchSection(change.groups, tafSlots, "change", r.station, error)
	}
	expand(r)
}

func windPhrase(w *Value) string {
	if w.calm {
		return "calm"
	}
	phrase := fmt.Sprintf("%03d degrees at %d KT", w.direction, w.speed)
	if w.variable {
		phrase = fmt.Sprintf("variable at %d KT", w.speed)
	}
	if w.gust >= 0 {
		phrase += fmt.Sprintf(" gusting %d KT", w.gust)
	}
	return phrase
}

func windCode(w *Value) string {
	if w.calm {
		return "00000KT"
	}
	d := pad(w.direction, 3)
	if w.variable {
		d = "VRB"
	}
	s := d + pad(w.speed, 2)
	if w.gust >= 0 {
		s += "G" + pad(w.gust, 2)
	}
	return s + "KT"
}

func mileNumber(v *Value) string {
	if !v.fractional {
		return fmt.Sprint(v.whole)
	}
	f := fmt.Sprintf("%d/%d", v.num, v.den)
	if v.whole > 0 {
		return fmt.Sprintf("%d %s", v.whole, f)
	}
	return f
}

func qualifier(q string) string {
	if q == "M" {
		return "less than "
	}
	if q == "P" {
		return "more than "
	}
	return ""
}

func visibilityPhrase(v *Value) string {
	if v.kind == "cavok" {
		return "10 km or more (CAVOK)"
	}
	if v.kind == "meter" {
		if v.qualifier == "P" {
			return "10 km or more"
		}
		return fmt.Sprintf("%d m", v.meters)
	}
	return qualifier(v.qualifier) + mileNumber(v) + " SM"
}

func visibilityCode(v *Value) string {
	if v.kind == "mile" {
		return v.qualifier + mileNumber(v) + "SM"
	}
	return v.raw
}

func weatherPhrase(w *Value) string {
	if w.nsw {
		return "no significant weather"
	}
	parts := []string{}
	if w.intensity != "" {
		parts = append(parts, intensities[w.intensity])
	}
	if w.descriptor != "" {
		parts = append(parts, descriptors[w.descriptor])
	}
	p := []string{}
	for _, code := range w.codes {
		p = append(p, phenomena[code])
	}
	if len(p) > 0 {
		parts = append(parts, strings.Join(p, " and "))
	}
	return strings.Join(parts, " ")
}

func cloudPhrase(c *Value) string {
	if clearCloud[c.amount] != "" {
		return clearCloud[c.amount]
	}
	if c.amount == "VV" {
		return fmt.Sprintf("vertical visibility %d ft", c.height)
	}
	s := fmt.Sprintf("%s at %d ft", amounts[c.amount], c.height)
	if c.suffix == "CB" {
		s += " cumulonimbus"
	}
	if c.suffix == "TCU" {
		s += " towering cumulus"
	}
	return s
}

func summary(s *Section) string {
	parts := []string{}
	if s.wind != nil {
		parts = append(parts, "wind " + windPhrase(s.wind))
	}
	if s.visibility != nil {
		parts = append(parts, "visibility " + visibilityPhrase(s.visibility))
	}
	weather, cloud := []string{}, []string{}
	for _, w := range s.weather {
		weather = append(weather, weatherPhrase(w))
	}
	for _, c := range s.cloud {
		cloud = append(cloud, cloudPhrase(c))
	}
	if len(weather) > 0 {
		parts = append(parts, "weather " + strings.Join(weather, ", "))
	}
	if len(cloud) > 0 {
		parts = append(parts, "cloud " + strings.Join(cloud, ", "))
	}
	if len(parts) == 0 {
		return "no conditions"
	}
	return strings.Join(parts, "; ")
}

func tokens(s *Section) string {
	parts := []string{}
	if s.wind != nil {
		parts = append(parts, windCode(s.wind))
	}
	if s.visibility != nil {
		parts = append(parts, visibilityCode(s.visibility))
	}
	for _, w := range s.weather {
		if !w.nsw {
			parts = append(parts, w.raw)
		}
	}
	for _, c := range s.cloud {
		parts = append(parts, c.raw)
	}
	parts = append(parts, s.category)
	return strings.Join(parts, " ")
}

func tenth(v int64) string {
	sign := ""
	if v < 0 {
		sign = "-"
	}
	v = abs(v)
	return fmt.Sprintf("%s%d.%d", sign, v/10, v%10)
}

func pressurePhrase(p *Value) string {
	a := fmt.Sprintf("%d.%02d inHg", p.inches/100, p.inches%100)
	q := fmt.Sprintf("%d hPa", p.hecto)
	if p.unit == "A" {
		return a + " (" + q + ")"
	}
	return q + " (" + a + ")"
}

func rvrPhrase(v *Value) string {
	a := qualifier(v.qualifier) + fmt.Sprint(v.first)
	if v.hasSecond {
		a = "between " + a + " and " + qualifier(v.qualifier2) + fmt.Sprint(v.second)
	}
	trend := map[string]string{"U": ", rising", "D": ", falling", "N": ", no change"}[v.trend]
	return "runway " + v.runway + " " + a + " " + v.unit + trend
}

func componentPhrase(c Component) string {
	s := fmt.Sprintf("headwind %d KT", c.head)
	if c.head < 0 {
		s = fmt.Sprintf("tailwind %d KT", -c.head)
	}
	if c.cross == 0 {
		return s + ", crosswind 0 KT"
	}
	direction := "right"
	if c.cross < 0 {
		direction = "left"
	}
	return s + fmt.Sprintf(", crosswind %d KT from %s", abs(c.cross), direction)
}

func altitudePhrase(a *int64) string {
	if a == nil {
		return "not available"
	}
	return fmt.Sprintf("%d ft", *a)
}

func observationLines(r *Report, c Calendar) []string {
	s := r.main
	lines := []string{"time: " + c.stamp(r.time)}
	if s.modifier != nil {
		lines = append(lines, "modifier: " + map[string]string{"AUTO": "automated", "COR": "corrected"}[s.modifier.raw])
	}
	w := "not reported"
	if s.wind != nil {
		w = windPhrase(s.wind)
	}
	if s.variation != nil {
		w += fmt.Sprintf(", varying between %03d and %03d degrees", s.variation.first, s.variation.second)
	}
	lines = append(lines, "wind: " + w)
	v := "not reported"
	if s.visibility != nil {
		v = visibilityPhrase(s.visibility)
	}
	lines = append(lines, "visibility: " + v)
	for _, x := range s.rvr {
		lines = append(lines, "runway visual range: " + rvrPhrase(x))
	}
	for _, x := range s.weather {
		lines = append(lines, "weather: " + weatherPhrase(x))
	}
	if s.visibility != nil && s.visibility.kind == "cavok" {
		lines = append(lines, "cloud: no significant cloud")
	} else if s.cloud == nil {
		lines = append(lines, "cloud: not reported")
	} else {
		for _, x := range s.cloud {
			lines = append(lines, "cloud: " + cloudPhrase(x))
		}
	}
	t := "not reported"
	if s.temperature != nil {
		x := s.temperature
		t = fmt.Sprintf("%d C, dew point %d C, spread %d C", x.temp, x.dew, x.temp-x.dew)
	}
	lines = append(lines, "temperature: " + t)
	p := "not reported"
	if s.pressure != nil {
		p = pressurePhrase(s.pressure)
	}
	lines = append(lines, "altimeter: " + p)
	if s.noTrend {
		lines = append(lines, "trend: no significant change")
	}
	for _, trend := range r.trends {
		p := "becoming"
		if trend.kind == "TEMPO" {
			p = "temporarily"
		}
		for _, t := range trend.times {
			p += fmt.Sprintf(" %s %02d:%02dZ", map[string]string{"FM": "from", "TL": "until", "AT": "at"}[t.kind], t.hour, t.minute)
		}
		lines = append(lines, "trend: " + p + ": " + summary(trend.state))
	}
	for _, x := range r.slp {
		lines = append(lines, "sea level pressure: " + tenth(x) + " hPa")
	}
	for _, x := range r.precise {
		lines = append(lines, "precise temperature: " + tenth(x.temp) + " C, dew point " + tenth(x.dew) + " C")
	}
	ceiling := "none"
	if s.ceiling >= 0 {
		ceiling = fmt.Sprintf("%d ft", s.ceiling)
	}
	lines = append(lines, "ceiling: " + ceiling, "flight category: " + s.category,
		"pressure altitude: " + altitudePhrase(r.pressureAltitude), "density altitude: " + altitudePhrase(r.densityAltitude))
	if r.winds == nil {
		lines = append(lines, "runway wind: not computed")
	} else {
		usable := []string{}
		for _, rw := range r.winds {
			p := componentPhrase(rw.mean)
			if rw.gust != nil {
				p += "; gusts " + componentPhrase(*rw.gust)
			}
			lines = append(lines, "runway " + rw.name + ": " + p)
			if rw.usable {
				usable = append(usable, rw.name)
			}
		}
		u, p := strings.Join(usable, " "), r.preferred
		if u == "" {
			u = "none"
		}
		if p == "" {
			p = "none"
		}
		lines = append(lines, "usable runways: " + u, "preferred runway: " + p)
	}
	if r.kind == "SPECI" {
		lines = append(lines, "speci check: " + strings.Join(r.speciReasons, ", "))
	}
	return lines
}

func forecastLines(r *Report, c Calendar) []string {
	lines := []string{"issued: " + c.stamp(r.time)}
	if r.modifier != "" {
		lines = append(lines, "modifier: " + map[string]string{"AMD": "amended", "COR": "corrected"}[r.modifier])
	}
	lines = append(lines, "valid: " + c.stamp(r.start) + " to " + c.stamp(r.end), "base: " + summary(r.base))
	for _, change := range r.changes {
		p := c.stamp(change.time)
		if change.kind != "FM" {
			p = c.stamp(change.start) + " to " + c.stamp(change.end)
		}
		lines = append(lines, change.kind + " " + p + ": " + summary(change.state))
	}
	return lines
}

func decodedBlock(r *Report, c Calendar) string {
	lines := []string{fmt.Sprintf("REPORT %d: %s %s (%s)", r.number, r.kind, r.station.code, r.station.name)}
	body := forecastLines
	if r.kind != "TAF" {
		body = observationLines
	}
	for _, line := range body(r, c) {
		lines = append(lines, "  " + line)
	}
	return strings.Join(lines, "\n")
}

func countsPhrase(counts [4]int64) string {
	parts := []string{}
	for i, cat := range categories {
		parts = append(parts, fmt.Sprintf("%s %d", cat, counts[i]))
	}
	return strings.Join(parts, ", ")
}

func timelineBlock(r *Report, c Calendar) string {
	lines := []string{"TAF " + r.station.code + " issued " + c.stamp(r.time) + " valid " + c.stamp(r.start) + " to " + c.stamp(r.end)}
	counts := [4]int64{}
	for h := r.start; h < r.end; h += 60 {
		hour := r.timeline[h]
		line := c.stamp(h) + " " + tokens(hour.prevailing)
		counts[categoryIndex(hour.prevailing.category)]++
		for _, tmp := range hour.temporary {
			line += " | " + tmp.kind + " " + tokens(tmp.state)
		}
		lines = append(lines, line)
	}
	lines = append(lines, "summary: " + countsPhrase(counts))
	return strings.Join(lines, "\n")
}

func categoriesLine(r *Report, c Calendar) string {
	s := r.main
	ceiling, visibility := "NONE", "NONE"
	if s.ceiling >= 0 {
		ceiling = fmt.Sprint(s.ceiling)
	}
	if s.visibility != nil {
		visibility = s.visibility.qualifier + fmt.Sprint(meterValue(s.visibility))
	}
	return strings.Join([]string{r.station.code, c.stamp(r.time), ceiling, visibility, s.category}, ",")
}

func strength(w *Value) int64 {
	if w.gust >= 0 {
		return w.gust
	}
	return w.speed
}

func extremeLines(obs []*Report, c Calendar) []string {
	selected := [5]*Report{}
	for _, o := range obs {
		s := o.main
		if s.temperature != nil {
			if selected[0] == nil || s.temperature.temp < selected[0].main.temperature.temp {
				selected[0] = o
			}
			if selected[1] == nil || s.temperature.temp > selected[1].main.temperature.temp {
				selected[1] = o
			}
		}
		if s.wind != nil && (selected[2] == nil || strength(s.wind) > strength(selected[2].main.wind)) {
			selected[2] = o
		}
		if s.ceiling >= 0 && (selected[3] == nil || s.ceiling < selected[3].main.ceiling) {
			selected[3] = o
		}
		if s.visibility != nil && (selected[4] == nil || compareVisibility(s.visibility, selected[4].main.visibility) < 0) {
			selected[4] = o
		}
	}
	labels := []string{"lowest temperature", "highest temperature", "strongest wind", "lowest ceiling", "lowest visibility"}
	lines := []string{}
	for i, o := range selected {
		v := "not available"
		if o != nil {
			s := o.main
			switch i {
			case 0, 1: v = fmt.Sprintf("%d C", s.temperature.temp)
			case 2: v = windPhrase(s.wind)
			case 3: v = fmt.Sprintf("%d ft", s.ceiling)
			case 4: v = visibilityPhrase(s.visibility)
			}
			v += " at " + c.stamp(o.time)
		}
		lines = append(lines, labels[i] + ": " + v)
	}
	return lines
}

func tableRow(label string, values []string) string {
	s := fmt.Sprintf("%-8s", label)
	for _, v := range values {
		s += fmt.Sprintf("%6s", v)
	}
	return s
}

func verificationBlock(station *Station, obs, tafs []*Report, c Calendar) string {
	a := analyze(obs, tafs)
	metars := 0
	counts := [4]int64{}
	for _, o := range obs {
		if o.kind == "METAR" {
			metars++
		}
		counts[categoryIndex(o.main.category)]++
	}
	lines := []string{"station " + station.code + " (" + station.name + ")",
		fmt.Sprintf("reports: METAR %d, SPECI %d", metars, len(obs)-metars), "observed categories: " + countsPhrase(counts)}
	lines = append(lines, extremeLines(obs, c)...)
	lines = append(lines, fmt.Sprintf("verified: %d", a.total), fmt.Sprintf("no forecast: %d", a.noForecast),
		tableRow("forecast", append(append([]string{}, categories...), "total")))
	for i, cat := range categories {
		values := []string{}
		for _, n := range a.table[i] {
			values = append(values, fmt.Sprint(n))
		}
		values = append(values, fmt.Sprint(a.rows[i]))
		lines = append(lines, tableRow(cat, values))
	}
	totals := []string{}
	for _, n := range a.columns {
		totals = append(totals, fmt.Sprint(n))
	}
	totals = append(totals, fmt.Sprint(a.total))
	lines = append(lines, tableRow("total", totals), "hit rate: " + a.hitRate(),
		"hit rate with temporary groups: " + a.temporaryRate(), "heidke skill score: " + a.skill())
	for i, cat := range categories {
		lines = append(lines, cat + ": pod " + a.pod(i) + ", far " + a.far(i))
	}
	for i, b := range a.buckets {
		lines = append(lines, fmt.Sprintf("hours %d-%d: %s", i*6, i*6+5, fraction(b[0], b[1])))
	}
	for _, choice := range a.choices {
		observed, forecast := choice.observation.main, choice.forecast.prevailing
		reasons := []string{}
		if !choice.temporaryHit {
			reasons = append(reasons, "category " + observed.category + ", forecast " + forecast.category)
		}
		if len(windChanges(forecast.wind, observed.wind, 60)) > 0 {
			reasons = append(reasons, "wind " + windCode(observed.wind) + ", forecast " + windCode(forecast.wind))
		}
		if len(reasons) > 0 {
			lines = append(lines, "amendment " + c.stamp(choice.observation.time) + ": " + strings.Join(reasons, "; "))
		}
	}
	return strings.Join(lines, "\n")
}

func lineText(lines []string, separator string) string {
	if len(lines) == 0 {
		return ""
	}
	return strings.Join(lines, separator) + "\n"
}

func main() {
	stations := map[string]*Station{}
	for _, line := range readLines("stations.txt") {
		p := strings.SplitN(line, " ", 4)
		s := &Station{code: p[0], elevation: number(p[1]), name: p[3]}
		for _, entry := range strings.Split(p[2], ",") {
			r := strings.Split(entry, "/")
			s.runways = append(s.runways, Runway{r[0], number(r[1])})
		}
		stations[s.code] = s
	}
	settings := map[string][]string{}
	for _, line := range readLines("params.txt") {
		p := strings.Split(line, " ")
		settings[p[0]] = p[1:]
	}
	c := newCalendar(number(settings["YEAR"][0]), number(settings["MONTH"][0]))
	p := Params{number(settings["CROSSWIND_LIMIT"][0]), number(settings["TAILWIND_LIMIT"][0]), settings["VERIFY"]}
	raw := [][]string{}
	for _, line := range readLines("reports.txt") {
		words := strings.Fields(line)
		if line[0] == ' ' {
			raw[len(raw)-1] = append(raw[len(raw)-1], words...)
		} else {
			raw = append(raw, words)
		}
	}
	reports, obs, tafs := []*Report{}, []*Report{}, []*Report{}
	errors := []ParseError{}
	previous := map[string]*Report{}
	for i, words := range raw {
		error := record(&errors, i+1)
		r := parseHeader(words, i+1, stations, c, error)
		if r == nil {
			continue
		}
		body := joinGroups(words, r.bodyStart)
		if r.kind == "TAF" {
			decodeForecast(r, body, c, error)
			tafs = append(tafs, r)
		} else {
			decodeObservation(r, body, p, error)
			if r.kind == "SPECI" {
				r.speciReasons = speciCheck(previous[r.station.code], r)
			}
			previous[r.station.code] = r
			obs = append(obs, r)
		}
		reports = append(reports, r)
	}
	decoded, timelines, verifications := []string{}, []string{}, []string{}
	csv := []string{"station,time,ceiling,visibility,category"}
	for _, r := range reports {
		decoded = append(decoded, decodedBlock(r, c))
	}
	for _, r := range obs {
		csv = append(csv, categoriesLine(r, c))
	}
	for _, r := range tafs {
		timelines = append(timelines, timelineBlock(r, c))
	}
	for _, code := range p.verify {
		oo, tt := []*Report{}, []*Report{}
		for _, o := range obs {
			if o.station.code == code {
				oo = append(oo, o)
			}
		}
		for _, t := range tafs {
			if t.station.code == code {
				tt = append(tt, t)
			}
		}
		verifications = append(verifications, verificationBlock(stations[code], oo, tt, c))
	}
	sort.SliceStable(errors, func(i, j int) bool {
		if errors[i].report != errors[j].report {
			return errors[i].report < errors[j].report
		}
		return errors[i].position < errors[j].position
	})
	errorLines := []string{}
	for _, e := range errors {
		errorLines = append(errorLines, fmt.Sprintf("report %d word %d: %s", e.report, e.position, e.content))
	}
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	outputs := map[string]string{
		"decoded.txt": lineText(decoded, "\n\n"),
		"categories.csv": lineText(csv, "\n"),
		"taf_timeline.txt": lineText(timelines, "\n\n"),
		"verification.txt": lineText(verifications, "\n\n"),
		"errors.txt": lineText(errorLines, "\n"),
	}
	for name, text := range outputs {
		if err := os.WriteFile("output/"+name, []byte(text), 0644); err != nil {
			panic(err)
		}
	}
}
