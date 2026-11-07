package main

var mainSlots = []Slot{
	{"modifier", false}, {"wind", false}, {"variation", false}, {"visibility", false},
	{"rvr", true}, {"weather", true}, {"cloud", true}, {"temperature", false},
	{"pressure", false}, {"noTrend", false},
}

func (s Slot) test(text string) *Value {
	return format(s.kind, text)
}
func isTrend(g Group) bool {
	return g.text == "BECMG" || g.text == "TEMPO"
}

func splitMetar(body []Group) (main, trends, remarks []Group) {
	end := len(body)
	for i, g := range body {
		if g.text == "RMK" {
			end, remarks = i, body[i+1:]
			break
		}
	}
	start := end
	for i, g := range body[:end] {
		if isTrend(g) {
			start = i
			break
		}
	}
	return body[:start], body[start:end], remarks
}

func readTrends(groups []Group, error ErrorFunc) []*Change {
	result := []*Change{}
	for i := 0; i < len(groups); {
		end := i+1
		for end < len(groups) && !isTrend(groups[end]) {
			end++
		}
		c := &Change{kind: groups[i].text}
		cursor, bad := i+1, false
		for cursor < end {
			m := match(`^(FM|TL|AT)(\d{2})(\d{2})$`, groups[cursor].text)
			if m == nil || len(c.times) > 0 && !(len(c.times) == 1 && c.times[0].kind == "FM" && m[1] == "TL") {
				break
			}
			h, n := number(m[2]), number(m[3])
			if h > 23 || n > 59 {
				error(groups[cursor].position, "invalid period", groups[cursor].text)
				bad = true
				break
			}
			c.times = append(c.times, TrendTime{m[1], h, n})
			cursor++
		}
		if !bad {
			c.groups = groups[cursor:end]
			result = append(result, c)
		}
		i = end
	}
	return result
}

func readRemarks(groups []Group) ([]int64, []*Value) {
	pressures, temperatures := []int64{}, []*Value{}
	for _, g := range groups {
		if m := match(`^SLP(\d{3})$`, g.text); m != nil {
			n := number(m[1])
			if n >= 500 {
				n += 9000
			} else {
				n += 10000
			}
			pressures = append(pressures, n)
			continue
		}
		if m := match(`^T([01])(\d{3})([01])(\d{3})$`, g.text); m != nil {
			v := &Value{temp: number(m[2]), dew: number(m[4])}
			if m[1] == "1" {
				v.temp = -v.temp
			}
			if m[3] == "1" {
				v.dew = -v.dew
			}
			temperatures = append(temperatures, v)
		}
	}
	return pressures, temperatures
}
