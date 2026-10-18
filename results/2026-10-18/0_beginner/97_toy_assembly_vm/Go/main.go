package main

import (
	"fmt"
	"strings"
	"strconv"
)

func value(token string, registers[4]int64) int64 {
	if token[0] >= 'A' && token[0] <= 'D' {
		return registers[token[0] - 'A']
	}
	n, _ := strconv.ParseInt(token, 10, 64)
	return n
}

func main() {
	program := []string{"SET A 1", "SET B 1", "SET D 8", "MUL A B", "PRINT A", "ADD B 1", "SUB D 1",
		"JNZ D -4", "SET A 1071", "SET B 462", "SET C A", "MOD C B", "SET A B", "SET B C", "JNZ B -4", "PRINT A",
		"HALT"}
	registers := [4]int64{}
	pc, executed := 0, 0
	for pc >= 0 && pc < len(program) {
		parts := strings.Fields(program[pc])
		op := parts[0]
		executed++
		if op == "HALT" {
			break
		}
		if op == "JNZ" {
			if value(parts[1], registers) != 0 {
				off, _ := strconv.Atoi(parts[2])
				pc += off
			} else {
				pc++
			}
			continue
		}
		if op == "PRINT" {
			fmt.Println(value(parts[1], registers))
		} else {
			r := int(parts[1][0] - 'A')
			x := value(parts[2], registers)
			switch op {
			case "SET":
				registers[r] = x
			case "ADD":
				registers[r] += x
			case "SUB":
				registers[r] -= x
			case "MUL":
				registers[r] *= x
			case "MOD":
				registers[r] %= x
			}
		}
		pc++
	}
	fmt.Printf("executed: %d\n", executed)
}
