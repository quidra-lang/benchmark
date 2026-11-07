package main

import (
	"fmt"
	"strconv"
	"strings"
)

func main() {
	expressions := []string{"3 4 + 2 *", "-17 5 / 4 -3 * -", "1 2 + * 3", "15 7 1 1 + - / 3 * 2 1 1 + + -",
		"4 2 5 * + 1 3 2 * - 5 + /", "2 3 4 + 5", "46341 46339 * -2 /"}
	for _, expression := range expressions {
		stack := []int64{}
		message := ""
		for _, token := range strings.Fields(expression) {
			if len(token) == 1 && strings.Contains("+-*/", token) {
				if len(stack) < 2 {
					message = "stack underflow"
					break
				}
				b, a := stack[len(stack)-1], stack[len(stack)-2]
				stack = stack[:len(stack)-2]
				if token == "/" && b == 0 {
					message = "division by zero"
					break
				}
				value := int64(0)
				switch token {
				case "+":
					value = a + b
				case "-":
					value = a - b
				case "*":
					value = a * b
				case "/":
					value = a / b
				}
				stack = append(stack, value)
			} else {
				value, _ := strconv.ParseInt(token, 10, 64)
				stack = append(stack, value)
			}
		}
		if message == "" && len(stack) != 1 {
			message = "leftover operands"
		}
		if message != "" {
			fmt.Printf("%s => error: %s\n", expression, message)
		} else {
			fmt.Printf("%s => %d\n", expression, stack[0])
		}
	}
}
