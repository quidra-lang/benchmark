package main

import "fmt"

type Manoeuvre struct {
	Name, Kind string
	Amount     int
}

func manoeuvres(settings Settings) []Manoeuvre {
	a := []Manoeuvre{{"level_up", "level", 10}, {"level_down",
		"level", -10}, {"speed_down", "speed", 0}}
	for delay := 60; delay <= settings.MaxDelay; delay += 60 {
		a = append(a,
			Manoeuvre{fmt.Sprintf("delay_%d", delay), "delay", delay})
	}
	return a
}
func apply(p Plan, move Manoeuvre, aircraft AircraftType, settings Settings) (Plan, bool) {
	switch move.Kind {
	case "level":
		p.Offset += move.Amount
		for _, level := range flightLevels(p) {
			if level < settings.MinLevel || level > settings.MaxLevel {
				return p, false
			}
		}
	case "speed":
		p.Speed = p.Speed * 9 / 10
		if p.Speed < aircraft.MinSpeed {
			return p,
				false
		}
	case "delay":
		p.Delay += move.Amount
	}
	return p, true
}
func lowerPriority(a, b Plan) bool {
	ta, tb := a.Departure+a.Delay, b.Departure+b.Delay
	return ta > tb || ta == tb && a.Callsign > b.Callsign
}
