package main

import "strings"

const literalDollar = '\x01'

type LogicalLine struct {
	Number int
	Segments []string
	Code, Message string
}

func logicalLines(physical []string) []LogicalLine {
	var lines []LogicalLine
	for index := 0; index < len(physical); {
		line := LogicalLine{Number: index + 1}
		source := physical[index]
		index++
		quoted := false
		var current strings.Builder
		for position := 0; position < len(source); {
			c := source[position]
			switch {
			case c == '\\' && position == len(source)-1:
				source = strings.TrimLeft(physical[index], " ")
				index++
				position = 0
			case quoted && c == '\\':
				follower := source[position+1]
				switch follower {
				case '\\', '"': current.WriteByte(follower)
				case 'n': current.WriteByte('\n')
				case 't': current.WriteByte('\t')
				case '$': current.WriteByte(literalDollar)
				default:
					if line.Code == "" { line.Code, line.Message = "E_ESCAPE", "invalid escape sequence \\" + string(follower) }
				}
				position += 2
			case c == '"':
				line.Segments = append(line.Segments, current.String())
				current.Reset()
				quoted = !quoted
				position++
			case !quoted && (c == ';' || c == '#'):
				position = len(source)
			default:
				current.WriteByte(c)
				position++
			}
		}
		if quoted && line.Code == "" { line.Code, line.Message = "E_UNTERMINATED", "unterminated string" }
		line.Segments = append(line.Segments, current.String())
		lines = append(lines, line)
	}
	return lines
}
