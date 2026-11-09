package main

func clearedRoute(g *Signal, routes []*Route) *Route {
	for _, r := range routes {
		if r.start != g || r.state != "LOCKED" {
			continue
		}
		clear := true
		for _, requirement := range r.requirements() {
			p := requirement.point
			if !p.detected() || p.position != requirement.position {
				clear = false
			}
		}
		for _, section := range append(append([]*Section(nil), r.sections...), r.overlap...) {
			if section.occupied() {
				clear = false
			}
		}
		if clear {
			return r
		}
	}
	return nil
}
func signalAspects(layout *Layout, routes []*Route) map[*Signal]string {
	cleared := map[*Signal]*Route{}
	for _, signal := range layout.signals {
		cleared[signal] = clearedRoute(signal, routes)
	}
	aspects := map[*Signal]string{}
	for _, signal := range layout.signals {
		route := cleared[signal]
		aspect := "RED"
		if route != nil {
			if finish := layout.signalByName[route.finish]; finish != nil {
				aspect = "YELLOW"
				if cleared[finish] != nil {
					aspect = "GREEN"
				}
			} else if layout.bufferByName[route.finish] != nil {
				aspect = "YELLOW"
			} else {
				aspect = "GREEN"
			}
		}
		aspects[signal] = aspect
	}
	return aspects
}
