package main

func pairFu(pair, seat, round int) int {
	value := 0
	if pair >= 31 {
		value += 2
	}
	if pair == seat {
		value += 2
	}
	if pair == round {
		value += 2
	}
	return value
}
func concealed(b Block, by string) bool {
	return b.source == "A" || b.source == "concealed" && (!b.winning || by == "tsumo")
}
func fuBreakdown(candidate *Candidate, s *Situation, closed bool, pinfu bool) ([]Award, int, int) {
	if candidate.kind == "chiitoitsu" {
		return []Award{{"chiitoitsu",
			25}}, 25, 25
	}
	out := []Award{{"base", 20}}
	if closed && s.by == "ron" {
		out = append(out, Award{"closed_ron",
			10})
	}
	if s.by == "tsumo" && !pinfu {
		out = append(out, Award{"tsumo", 2})
	}
	if value := pairFu(candidate.pair,
		windKind(s.seat), windKind(s.round)); value > 0 {
		out = append(out, Award{"pair " + blockNotation(candidate.pair,
			2, false), value})
	}
	for _, b := range candidate.blocks {
		if b.sequence {
			continue
		}
		kind, value := "open_triplet",
			2
		if concealed(b, s.by) {
			kind = "closed_triplet"
			value = 4
		}
		if b.kan {
			if concealed(b, s.by) {
				kind = "closed_kan"
				value = 16
			} else {
				kind = "open_kan"
				value = 8
			}
		}
		if yaochuu(b.kind) {
			value *= 2
		}
		out = append(out,
			Award{kind + " " + b.notation(), value})
	}
	if candidate.wait == "kanchan" || candidate.wait == "penchan" || candidate.wait == "tanki" {
		out = append(out,
			Award{"wait " + candidate.wait, 2})
	}
	total := 0
	for _, a := range out {
		total += a.value
	}
	if !closed && total == 20 {
		out = append(out,
			Award{"open_pinfu", 10})
		total += 10
	}
	return out, total, (total + 9) / 10 * 10
}
func limitScore(han, fu int, rule *Rule) (string, int) {
	switch {
	case han >= 13 && rule.kazoe:
		return "kazoe_yakuman",
			8000
	case han >= 11:
		return "sanbaiman", 6000
	case han >= 8:
		return "baiman", 4000
	case han >= 6:
		return "haneman",
			3000
	}
	base := fu * (1 << uint(han+2))
	if han == 5 || base >= 2000 || rule.kiriage && base == 1920 {
		return "mangan",
			2000
	}
	return "none", base
}
func roundHundred(x int) int { return (x + 99) / 100 * 100 }

type Payment struct{ points, ron, dealer, nondealer, all int }

func payments(base int, seat, by string) Payment {
	p := Payment{}
	if by == "ron" {
		multiplier := 4
		if seat == "E" {
			multiplier = 6
		}
		p.ron = roundHundred(multiplier * base)
		p.points = p.ron
	} else if seat == "E" {
		p.all = roundHundred(2 * base)
		p.points = 3 * p.all
	} else {
		p.dealer = roundHundred(2 * base)
		p.nondealer = roundHundred(base)
		p.points = p.dealer + 2*p.nondealer
	}
	return p
}
