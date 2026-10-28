package main

import "math"

func buckling(member Member, section Section, material Material) float64 {
	return 3.141592653589793 * 3.141592653589793 * material.E * section.Inertia / (member.Length * member.Length)
}
func utilization(force float64, member Member, section Section, material Material) float64 {
	return math.Max(math.Abs(force/section.Area)/material.FY,
		math.Max(0, -force)/buckling(member, section, material))
}
func slenderness(member Member, section Section) float64 {
	return member.Length / math.Sqrt(section.Inertia/section.Area)
}
func slendernessLimit(member int, combinations []Result, m Model) float64 {
	for _, r := range combinations {
		if r.Forces[member] < 0 {
			return m.Settings.Compression
		}
	}
	return m.Settings.Tension
}
func selectSection(group int, combinations []Result, m Model) int {
	for section, candidate := range m.Sections {
		valid := true
		for i, member := range m.Members {
			if member.Group != group {
				continue
			}
			if slenderness(member, candidate) > slendernessLimit(i,
				combinations, m) {
				valid = false
				break
			}
			for _, r := range combinations {
				if utilization(r.Forces[i], member,
					candidate, m.Materials[member.Material]) > 1 {
					valid = false
					break
				}
			}
			if !valid {
				break
			}
		}
		if valid {
			return section
		}
	}
	return len(m.Sections) - 1
}
