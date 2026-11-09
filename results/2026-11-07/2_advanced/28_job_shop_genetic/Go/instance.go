package main

import (
	"fmt"
	"strings"
)

type Operation struct{ Ident, Job, Index, Machine, Duration, Head, Tail, Prev, Next int }

func (o Operation) Code() string { return fmt.Sprintf("J%d-%d", o.Job, o.Index) }

type Job struct {
	Number, Work int
	Operations   []int
}
type Machine struct {
	Number, Load, Head, Tail, Bound int
	Operations                      []int
}
type Instance struct {
	MachineCount int
	Jobs         []Job
	Operations   []Operation
	Durations    []int
	Machines     []Machine
	Errors       []string
	ByJob        map[int]Job
}

func loadInstance() *Instance {
	lines := readLines("input/instance.txt")
	f := strings.Fields(lines[0])
	count, machines := integer(f[0]), integer(f[1])
	in := &Instance{MachineCount: machines, ByJob: map[int]Job{}}
	for j := 1; j <= count; j++ {
		steps := [][2]int{}
		used := map[int]bool{}
		valid := true
		for k, field := range strings.Fields(lines[j]) {
			pair := strings.Split(field, ":")
			m, d := integer(pair[0]), integer(pair[1])
			reason := ""
			if m < 1 || m > machines {
				reason = fmt.Sprintf("unknown machine %d", m)
			} else if d < 1 || d > 99 {
				reason = fmt.Sprintf("bad duration %d", d)
			} else if used[m] {
				reason = fmt.Sprintf("repeated machine %d", m)
			}
			if reason != "" {
				in.Errors = append(in.Errors, fmt.Sprintf("job %d operation %d: %s", j, k+1, reason))
				valid = false
				break
			}
			used[m] = true
			steps = append(steps, [2]int{m, d})
		}
		if !valid {
			continue
		}
		job := Job{Number: j}
		head := 0
		for k, step := range steps {
			id := len(in.Operations)
			prev, next := -1, -1
			if k > 0 {
				prev = id - 1
			}
			if k+1 < len(steps) {
				next = id + 1
			}
			in.Operations = append(in.Operations, Operation{id, j, k + 1, step[0], step[1], head, 0, prev, next})
			in.Durations = append(in.Durations, step[1])
			job.Operations = append(job.Operations, id)
			head += step[1]
		}
		job.Work = head
		for _, id := range job.Operations {
			o := &in.Operations[id]
			o.Tail = head - o.Head - o.Duration
		}
		in.Jobs = append(in.Jobs, job)
		in.ByJob[j] = job
	}
	for m := 1; m <= machines; m++ {
		machine := Machine{Number: m, Head: 1 << 30, Tail: 1 << 30}
		for id, o := range in.Operations {
			if o.Machine == m {
				machine.Operations = append(machine.Operations, id)
				machine.Load += o.Duration
				machine.Head = min(machine.Head, o.Head)
				machine.Tail = min(machine.Tail, o.Tail)
			}
		}
		machine.Bound = machine.Head + machine.Load + machine.Tail
		in.Machines = append(in.Machines, machine)
	}
	return in
}
