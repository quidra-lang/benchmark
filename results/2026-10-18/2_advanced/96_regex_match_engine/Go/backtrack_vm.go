package main

type BacktrackState struct {
	PC, Position int
	Captures     []int
	Visited      map[int]bool
}
type BacktrackResult struct {
	Captures []int
	Position int
}
type BacktrackVM struct {
	Program     []Instruction
	Flags, Text string
	Groups      int
	Full        bool
	Steps       int
	Aborted     bool
}

func cloneCaptures(c []int) []int { return append([]int{}, c...) }
func cloneVisited(v map[int]bool) map[int]bool {
	out := map[int]bool{}
	for p := range v {
		out[p] = true
	}
	return out
}
func unsetCaptures(groups int) []int {
	out := make([]int, 2*groups+2)
	for i := range out {
		out[i] = -1
	}
	return out
}
func (vm *BacktrackVM) execute(pc, position int, captures []int, partial bool) *BacktrackResult {
	stack := []BacktrackState{{pc, position, cloneCaptures(captures), map[int]bool{}}}
	for len(stack) > 0 {
		state := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		p, q, c, visited := state.PC, state.Position, state.Captures, state.Visited
		running := true
		for running {
			vm.Steps++
			if vm.Steps > 200000 {
				vm.Aborted = true
				return nil
			}
			ins := vm.Program[p]
			switch ins.Op {
			case "CHAR", "ANY", "CLASS":
				if !consumes(ins, vm.Text, q, vm.Flags) {
					running = false
					break
				}
				p++
				q++
				visited = map[int]bool{}
			case "SPLIT":
				if visited[p] {
					running = false
					break
				}
				visited[p] = true
				stack = append(stack, BacktrackState{ins.Y, q, cloneCaptures(c), cloneVisited(visited)})
				p = ins.X
			case "JMP":
				p = ins.X
			case "SAVE":
				c[ins.Number] = q
				p++
			case "ASSERT":
				if assertion(ins.Kind, vm.Text, q, vm.Flags) {
					p++
				} else {
					running = false
				}
			case "BACKREF":
				a, b := c[2*ins.Number], c[2*ins.Number+1]
				if a < 0 || b < 0 || a > b || q+b-a > len(vm.Text) {
					running = false
					break
				}
				matches := true
				for j := 0; j < b-a; j++ {
					if !charMatches(vm.Text[q+j], vm.Text[a+j], vm.Flags) {
						matches = false
						break
					}
				}
				if !matches {
					running = false
					break
				}
				if b > a {
					visited = map[int]bool{}
				}
				q += b - a
				p++
			case "LOOK":
				result := vm.execute(p+1, q, c, true)
				if vm.Aborted {
					return nil
				}
				if ins.Kind == "NOT" {
					if result == nil {
						p = ins.X
					} else {
						running = false
					}
				} else if result == nil {
					running = false
				} else {
					c = result.Captures
					if ins.Kind == "ATOMIC" {
						if result.Position > q {
							visited = map[int]bool{}
						}
						q = result.Position
					}
					p = ins.X
				}
			case "MATCH":
				if partial || !vm.Full || q == len(vm.Text) {
					return &BacktrackResult{c, q}
				}
				running = false
			}
		}
	}
	return nil
}
func (vm *BacktrackVM) search(start int) []int {
	last := len(vm.Text)
	if vm.Full {
		start = 0
		last = 0
	}
	for b := start; b <= last; b++ {
		result := vm.execute(0, b, unsetCaptures(vm.Groups), false)
		if vm.Aborted {
			return nil
		}
		if result != nil {
			return result.Captures
		}
	}
	return nil
}
