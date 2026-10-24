package main

import (
	"fmt"
	"strconv"
)

type Parser struct {
	tokens []string
	position int
	variables map[string]int64
	err string
}

func tokenize(line string) []string {
	tokens := []string{}
	for i := 0; i < len(line); {
		if line[i] == ' ' {
			i++
			continue
		}
		start := i
		if line[i] >= '0' && line[i] <= '9' {
			for i < len(line) && line[i] >= '0' && line[i] <= '9' {
				i++
			}
		} else if line[i] >= 'a' && line[i] <= 'z' {
			for i < len(line) && line[i] >= 'a' && line[i] <= 'z' {
				i++
			}
		} else {
			i++
		}
		tokens = append(tokens, line[start:i])
	}
	return tokens
}
func (p *Parser) unary() int64 {
	token := p.tokens[p.position]
	p.position++
	if token == "-" {
		return -p.unary()
	}
	if token == "(" {
		value := p.sum()
		if p.err == "" {
			p.position++
		}
		return value
	}
	if token[0] >= '0' && token[0] <= '9' {
		value, _ := strconv.ParseInt(token, 10, 64)
		return value
	}
	value, ok := p.variables[token]
	if !ok {
		p.err = "undefined variable " + token
	}
	return value
}
func (p *Parser) product() int64 {
	value := p.unary()
	for p.err == "" && p.position < len(p.tokens) && (p.tokens[p.position] == "*" || p.tokens[p.position] == "/") {
		operation := p.tokens[p.position]
		p.position++
		right := p.unary()
		if p.err != "" {
			return 0
		}
		if operation == "/" && right == 0 {
			p.err = "division by zero"
			return 0
		}
		if operation == "*" {
			value *= right
		} else {
			value /= right
		}
	}
	return value
}
func (p *Parser) sum() int64 {
	value := p.product()
	for p.err == "" && p.position < len(p.tokens) && (p.tokens[p.position] == "+" || p.tokens[p.position] == "-") {
		operation := p.tokens[p.position]
		p.position++
		right := p.product()
		if p.err != "" {
			return 0
		}
		if operation == "+" {
			value += right
		} else {
			value -= right
		}
	}
	return value
}

func main() {
	variables := map[string]int64{}
	for _, line := range []string{"width = 12", "height = width - 5", "area = width * height", "(area + 6) / 4",
		"shift = -area / 8 + 3", "height = 100 / (height - 7) + bonus", "volume = area * depth", "width = (width+3)*-(2-4)",
		"width * shift - height"} {
		tokens := tokenize(line)
		assignment := len(tokens) > 1 && tokens[1] == "="
		parser := Parser{tokens: tokens, variables: variables}
		if assignment {
			parser.position = 2
		}
		value := parser.sum()
		if parser.err != "" {
			fmt.Printf("error: %s\n", parser.err)
		} else if assignment {
			variables[tokens[0]] = value
			fmt.Printf("%s = %d\n", tokens[0], value)
		} else {
			fmt.Println(value)
		}
	}
}
