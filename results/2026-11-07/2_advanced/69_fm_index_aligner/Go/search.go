package main

type SearchLeaf struct {
	Interval   Interval
	Mismatches int
}
type SearchResult struct {
	Leaves      []SearchLeaf
	Nodes, Hits int
}

func lowerBound(reverse FMIndex, w string) []int {
	d := make([]int, len(w))
	z := 0
	iv := Interval{0, len(reverse.Text)}
	for i := range w {
		iv = reverse.extend(iv,
			w[i])
		if iv.Lo >= iv.Hi {
			z++
			iv = Interval{0, len(reverse.Text)}
		}
		d[i] = z
	}
	return d
}
func backtrack(forward, reverse FMIndex, w string, zmax int) SearchResult {
	d := lowerBound(reverse, w)
	type State struct {
		I,
		Z, Lo, Hi int
	}
	stack := []State{{len(w) - 1, zmax, 0, len(forward.Text)}}
	var result SearchResult
	for len(stack) > 0 {
		state := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		result.Nodes++
		bound := 0
		if state.I >= 0 {
			bound = d[state.I]
		}
		if state.Z < bound {
			continue
		}
		if state.I < 0 {
			iv := Interval{state.Lo,
				state.Hi}
			result.Leaves = append(result.Leaves, SearchLeaf{iv, zmax - state.Z})
			result.Hits += state.Hi - state.Lo
			continue
		}
		for _, b := range []byte("TGCA") {
			iv := forward.extend(Interval{state.Lo, state.Hi}, b)
			if iv.Lo >= iv.Hi {
				continue
			}
			z := state.Z
			if b != w[state.I] {
				if z == 0 {
					continue
				}
				z--
			}
			stack = append(stack,
				State{state.I - 1, z, iv.Lo, iv.Hi})
		}
	}
	return result
}
