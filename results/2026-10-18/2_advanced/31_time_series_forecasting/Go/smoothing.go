package main

type SmoothParameters struct{ Alpha, Beta, Gamma, Phi float64 }
type SmoothState struct {
	Level, Slope float64
	Seasonal     []float64
}

func smoothRecurse(name string, values []float64, season int, p SmoothParameters) ([]float64, []SmoothState) {
	seasonal := name == "hw_add" || name == "hw_mult"
	level, slope := values[0], 0.0
	components := []float64(nil)
	if seasonal {
		level = mean(values[:season])
		slope = (mean(values[season:2*season]) - level) / float64(season)
		for _, v := range values[:season] {
			if name == "hw_add" {
				components = append(components, v-level)
			} else {
				components = append(components, v/level)
			}
		}
	} else if name != "ses" {
		slope = (values[season] - values[0]) / float64(season)
	}
	errors := []float64{}
	states := []SmoothState{}
	for t, observed := range values {
		states = append(states, SmoothState{level, slope, append([]float64(nil), components...)})
		predicted, nextLevel, nextSlope := 0.0, 0.0, slope
		if name == "ses" {
			predicted = level
			nextLevel = p.Alpha*observed + (1-p.Alpha)*level
		} else if seasonal {
			j := t % season
			previous, base := components[j], level+slope
			if name == "hw_add" {
				predicted = base + previous
				nextLevel = p.Alpha*(observed-previous) + (1-p.Alpha)*base
				components[j] = p.Gamma*(observed-base) + (1-p.Gamma)*previous
			} else {
				predicted = base * previous
				nextLevel = p.Alpha*(observed/previous) + (1-p.Alpha)*base
				components[j] = p.Gamma*(observed/base) + (1-p.Gamma)*previous
			}
			nextSlope = p.Beta*(nextLevel-level) + (1-p.Beta)*slope
		} else {
			predicted = level + p.Phi*slope
			nextLevel = p.Alpha*observed + (1-p.Alpha)*predicted
			nextSlope = p.Beta*(nextLevel-level) + (1-p.Beta)*p.Phi*slope
		}
		errors = append(errors, observed-predicted)
		level, slope = nextLevel, nextSlope
	}
	states = append(states, SmoothState{level, slope, append([]float64(nil), components...)})
	return errors, states
}
func smoothForecast(name string, state SmoothState, p SmoothParameters, origin, steps, season int) []float64 {
	result := []float64{}
	power, accumulated := p.Phi, 0.0
	for k := 1; k <= steps; k++ {
		value := state.Level
		switch name {
		case "holt", "damped":
			accumulated += power
			value += accumulated * state.Slope
			power *= p.Phi
		case "hw_add", "hw_mult":
			component := state.Seasonal[(origin+k-1)%season]
			base := state.Level + float64(k)*state.Slope
			if name == "hw_add" {
				value = base + component
			} else {
				value = base * component
			}
		}
		result = append(result, value)
	}
	return result
}
