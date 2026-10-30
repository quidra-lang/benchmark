package main

import (
	"fmt"
	"strconv"
	"strings"
)

type ExecutableInstruction struct {
	Instruction
	Unit *Unit
}
type Frame struct {
	Locals []int64
	Return int
}
type RunResult struct {
	Output                               []string
	Executed, MaximumStack, MaximumDepth int
	Counts                               []int
	Calls                                map[string]int
	Pairs                                map[[2]string]int
	Error                                string
	FaultPC                              int
	Frames                               []Frame
}

func flatten(units []*Unit) []ExecutableInstruction {
	out := []ExecutableInstruction{}
	for _, unit := range units {
		for _, original := range unit.Code {
			instruction := original
			if jump(instruction.Op) {
				instruction.A += int64(unit.Start)
			}
			out = append(out, ExecutableInstruction{instruction, unit})
		}
	}
	return out
}
func execute(units []*Unit, cells int, input []int64) *RunResult {
	code := flatten(units)
	r := &RunResult{Counts: make([]int, len(code)), Calls: map[string]int{}, Pairs: map[[2]string]int{}, FaultPC: -1}
	globals := make([]int64, cells)
	stack := []int64{}
	frames := []Frame{}
	pc, read := 0, 0
	starts := map[int]*Unit{}
	for _, unit := range units {
		starts[unit.Start] = unit
	}
	pop := func() int64 {
		value := stack[len(stack)-1]
		stack = stack[:len(stack)-1]
		return value
	}
	fault := func(message string) *RunResult {
		r.Error = message
		r.FaultPC = pc
		r.Frames = append([]Frame{}, frames...)
		return r
	}
	for {
		instruction := code[pc]
		if r.Executed == 100000 {
			return fault("instruction limit exceeded")
		}
		r.Executed++
		r.Counts[pc]++
		next := pc + 1
		switch instruction.Op {
		case "PUSH":
			stack = append(stack, instruction.A)
		case "POP":
			pop()
		case "LOADG":
			stack = append(stack, globals[int(instruction.A)])
		case "STOREG":
			globals[int(instruction.A)] = pop()
		case "LOADL":
			stack = append(stack, frames[len(frames)-1].Locals[int(instruction.A)])
		case "STOREL":
			frames[len(frames)-1].Locals[int(instruction.A)] = pop()
		case "LOADA", "STOREA":
			value := int64(0)
			if instruction.Op == "STOREA" {
				value = pop()
			}
			index := pop()
			if index < 0 || index >= instruction.B {
				return fault(fmt.Sprintf("index %d out of bounds for array of size %d", index, instruction.B))
			}
			address := int(instruction.A + index)
			if instruction.Op == "LOADA" {
				stack = append(stack, globals[address])
			} else {
				globals[address] = value
			}
		case "ADD", "SUB", "MUL", "DIV", "MOD":
			b, a := pop(), pop()
			value := int64(0)
			switch instruction.Op {
			case "ADD":
				value = a + b
			case "SUB":
				value = a - b
			case "MUL":
				value = a * b
			case "DIV", "MOD":
				if b == 0 {
					return fault("division by zero")
				}
				quotient := a / b
				if instruction.Op == "DIV" {
					value = quotient
				} else {
					value = a - quotient*b
				}
			}
			if value < -2147483648 || value > 2147483647 {
				return fault("integer overflow")
			}
			stack = append(stack, value)
		case "NEG":
			value := -pop()
			if value < -2147483648 || value > 2147483647 {
				return fault("integer overflow")
			}
			stack = append(stack, value)
		case "NOT":
			value := pop()
			result := int64(0)
			if value == 0 {
				result = 1
			}
			stack = append(stack, result)
		case "LT", "LE", "GT", "GE", "EQ", "NE":
			b, a := pop(), pop()
			answer := false
			switch instruction.Op {
			case "LT":
				answer = a < b
			case "LE":
				answer = a <= b
			case "GT":
				answer = a > b
			case "GE":
				answer = a >= b
			case "EQ":
				answer = a == b
			case "NE":
				answer = a != b
			}
			value := int64(0)
			if answer {
				value = 1
			}
			stack = append(stack, value)
		case "JUMP":
			next = int(instruction.A)
		case "JUMPF", "JUMPT":
			value := pop()
			if instruction.Op == "JUMPF" && value == 0 || instruction.Op == "JUMPT" && value != 0 {
				next = int(instruction.A)
			}
		case "CALL":
			if len(frames) == 100 {
				return fault("call depth limit exceeded")
			}
			count := int(instruction.B)
			locals := append([]int64{}, stack[len(stack)-count:]...)
			stack = stack[:len(stack)-count]
			frames = append(frames, Frame{locals, pc + 1})
			next = int(instruction.A)
			called := starts[next].Name
			r.Calls[called]++
			r.Pairs[[2]string{instruction.Unit.Name, called}]++
		case "ENTER":
			frame := &frames[len(frames)-1]
			for len(frame.Locals) < int(instruction.A) {
				frame.Locals = append(frame.Locals, 0)
			}
		case "RET", "RETV":
			next = frames[len(frames)-1].Return
			frames = frames[:len(frames)-1]
		case "READ":
			if read == len(input) {
				return fault("read past end of input")
			}
			stack = append(stack, input[read])
			read++
		case "PRINT":
			count := int(instruction.A)
			values := []string{}
			for _, value := range stack[len(stack)-count:] {
				values = append(values, strconv.FormatInt(value, 10))
			}
			stack = stack[:len(stack)-count]
			r.Output = append(r.Output, strings.Join(values, " "))
		case "HALT":
			r.MaximumStack = max(r.MaximumStack, len(stack))
			r.MaximumDepth = max(r.MaximumDepth, len(frames))
			return r
		}
		r.MaximumStack = max(r.MaximumStack, len(stack))
		r.MaximumDepth = max(r.MaximumDepth, len(frames))
		pc = next
	}
}
