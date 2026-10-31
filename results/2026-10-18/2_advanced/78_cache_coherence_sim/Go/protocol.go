package main

func dirty(state string) bool { return state == "M" || state == "O" }
func requestTransition(protocol, state, operation string) (string, string) {
	if protocol == "VI" {
		if operation == "W" {
			return "BusWr",
				state
		}
		if state == "I" {
			return "BusRd", "V"
		}
		return "", state
	}
	if state == "I" {
		if operation == "W" {
			return "BusRdX",
				"M"
		}
		if protocol == "MSI" {
			return "BusRd", "S"
		}
		return "BusRd", "E/S"
	}
	if operation == "R" {
		return "",
			state
	}
	if state == "S" || state == "O" {
		return "BusUpgr", "M"
	}
	return "", "M"
}
func snoopTransition(protocol, state, kind string) (string, bool, bool) {
	if kind != "BusRd" {
		return "I", (kind == "BusRdX" && dirty(state)),
			false
	}
	if protocol == "VI" {
		return state, false, false
	}
	if state == "M" {
		if protocol == "MOESI" {
			return "O",
				true, false
		}
		return "S", true, true
	}
	if state == "O" {
		return "O", true, false
	}
	return "S", false, false
}
