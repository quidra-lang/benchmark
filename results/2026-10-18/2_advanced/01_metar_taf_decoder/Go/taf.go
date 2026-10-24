package main

var tafSlots = []Slot{{"wind", false}, {"visibility", false}, {"weather", true}, {"cloud", true}}

func isIndicator(g Group) bool {
	return g.text == "BECMG" || g.text == "TEMPO" || g.text == "PROB30" || g.text == "PROB40" || match(`^FM\d{6}$`, g.text) != nil
}

func splitTaf(body []Group, r *Report, calendar Calendar, error ErrorFunc) ([]Group, []*Change) {
	i := 0
	for i < len(body) && !isIndicator(body[i]) {
		i++
	}
	base, changes := body[:i], []*Change{}
	for i < len(body) {
		indicator := body[i]
		kind := indicator.text
		if len(kind) == 8 && kind[:2] == "FM" {
			kind = "FM"
		}
		i++
		if (kind == "PROB30" || kind == "PROB40") && i < len(body) && body[i].text == "TEMPO" {
			kind += " TEMPO"
			i++
		}
		end := i
		for end < len(body) && !isIndicator(body[end]) {
			end++
		}
		c := &Change{kind: kind}
		if kind == "FM" {
			c.time = calendar.changeTime(indicator.text, r.issueDay)
			if c.time < r.start || c.time >= r.end {
				error(indicator.position, "invalid period", indicator.text)
			} else {
				c.groups = body[i:end]
				changes = append(changes, c)
			}
		} else if i == end || match(`^\d{4}/\d{4}$`, body[i].text) == nil {
			error(indicator.position, "missing period", kind)
		} else {
			s, e, ok := calendar.period(body[i].text, r.issueDay, 0)
			if !ok || s < r.start || e > r.end {
				error(body[i].position, "invalid period", body[i].text)
			} else {
				c.start, c.end = s, e
				c.groups = body[i+1:end]
				changes = append(changes, c)
			}
		}
		i = end
	}
	return base, changes
}

func stateOf(s *Section) *Section {
	return &Section{wind: s.wind, visibility: s.visibility, weather: s.weather, cloud: s.cloud}
}
func overlay(s, c *Section) *Section {
	r := stateOf(s)
	if c.wind != nil {
		r.wind = c.wind
	}
	if c.visibility != nil {
		r.visibility = c.visibility
	}
	if c.weather != nil {
		r.weather = c.weather
	}
	if c.cloud != nil {
		r.cloud = c.cloud
	}
	return r
}
func expand(r *Report) {
	r.timeline = map[int64]*Hour{}
	for h := r.start; h < r.end; h += 60 {
		p := stateOf(r.base)
		for _, c := range r.changes {
			if c.kind == "FM" && c.time <= h {
				p = stateOf(c.state)
			}
			if c.kind == "BECMG" && c.end <= h {
				p = overlay(p, c.state)
			}
		}
		hour := &Hour{prevailing: p}
		derive(p)
		for _, c := range r.changes {
			if c.kind != "FM" && c.kind != "BECMG" && c.start <= h && h < c.end {
				s := overlay(p, c.state)
				derive(s)
				hour.temporary = append(hour.temporary, Temporary{c.kind, s})
			}
		}
		r.timeline[h] = hour
	}
}
