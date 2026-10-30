package main

type PikeThread struct {
	PC       int
	Captures []int
}
type ThreadList struct {
	Threads []PikeThread
	Marks   map[int]bool
}
type PikeVM struct {
	Program     []Instruction
	Flags, Text string
	Groups      int
	Full        bool
	Steps       int
}

func newThreadList() *ThreadList { return &ThreadList{Marks: map[int]bool{}} }
func (vm *PikeVM) add(list *ThreadList, p int, captures []int, q int) {
	if list.Marks[p] {
		return
	}
	list.Marks[p] = true
	vm.Steps++
	ins := vm.Program[p]
	switch ins.Op {
	case "JMP":
		vm.add(list, ins.X, captures, q)
	case "SPLIT":
		vm.add(list, ins.X, captures, q)
		vm.add(list, ins.Y, captures, q)
	case "SAVE":
		c := cloneCaptures(captures)
		c[ins.Number] = q
		vm.add(list, p+1, c, q)
	case "ASSERT":
		if assertion(ins.Kind, vm.Text, q, vm.Flags) {
			vm.add(list, p+1, captures, q)
		}
	default:
		list.Threads = append(list.Threads, PikeThread{p, cloneCaptures(captures)})
	}
}
func (vm *PikeVM) search(start int) []int {
	var match []int
	list := newThreadList()
	for q := start; ; q++ {
		if match == nil && (!vm.Full || q == start) {
			vm.add(list, 0, unsetCaptures(vm.Groups), q)
		}
		next := newThreadList()
		for _, thread := range list.Threads {
			vm.Steps++
			ins := vm.Program[thread.PC]
			if ins.Op == "MATCH" {
				if !vm.Full || q == len(vm.Text) {
					match = cloneCaptures(thread.Captures)
					break
				}
			} else if consumes(ins, vm.Text, q, vm.Flags) {
				vm.add(next, thread.PC+1, thread.Captures, q+1)
			}
		}
		if q == len(vm.Text) || len(next.Threads) == 0 && (match != nil || vm.Full) {
			return match
		}
		list = next
	}
}
