package main

import "fmt"

func main() {
	for _, s := range []string{"(a + b) * [c - d]", "{x = [1, 2, (3 + 4)]}", "f(a[i] + g(b)}", "(1 + 2)) * 3",
		"if (a < b) { c = d[0]; }", "((a + b] * c", "[{(x * y) - z}"} {
		stack := []rune{}
		error := -1
		for i, c := range s {
			if c == '(' || c == '[' || c == '{' {
				stack = append(stack, c)
			} else if c == ')' || c == ']' || c == '}' {
				expected := '('
				if c == ']' {
					expected = '['
				} else if c == '}' {
					expected = '{'
				}
				if len(stack) == 0 || stack[len(stack) - 1] != expected {
					error = i
					break
				}
				stack = stack[:len(stack)-1]
			}
		}
		if error < 0 && len(stack) > 0 {
			error = len(s)
		}
		if error < 0 {
			fmt.Printf("%s -> balanced\n", s)
		} else {
			fmt.Printf("%s -> error at index %d\n", s, error)
		}
	}
}
