package main

import (
	"strconv"
	"strings"
)

type RuntimeIssue struct {
	Position Position
	Message  string
}

func runtimeError(position Position, message string) { panic(RuntimeIssue{position, message}) }
func formatOutput(values []Value, position Position) string {
	format := values[0].text()
	argument := 1
	var out strings.Builder
	for i := 0; i < len(format); {
		if format[i] != '%' {
			out.WriteByte(format[i])
			i++
			continue
		}
		i++
		if i < len(format) && format[i] == '%' {
			out.WriteByte('%')
			i++
			continue
		}
		left, zero := false, false
		for i < len(format) && (format[i] == '-' || format[i] == '0') {
			left = left || format[i] == '-'
			zero = zero || format[i] == '0'
			i++
		}
		start := i
		for i < len(format) && digit(format[i]) {
			i++
		}
		width := 0
		if i > start {
			width = int(decimal(format[start:i]))
		}
		precision := -1
		if i < len(format) && format[i] == '.' {
			i++
			start = i
			for i < len(format) && digit(format[i]) {
				i++
			}
			precision = 0
			if i > start {
				precision = int(decimal(format[start:i]))
			}
		}
		if i == len(format) || !strings.ContainsRune("discxo", rune(format[i])) {
			runtimeError(position, "invalid format")
		}
		kind := format[i]
		i++
		if argument == len(values) {
			runtimeError(position, "not enough arguments")
		}
		value := values[argument]
		argument++
		body := ""
		if strings.ContainsRune("dixo", rune(kind)) {
			n := value.number()
			base := 10
			if kind == 'x' {
				base = 16
			} else if kind == 'o' {
				base = 8
			}
			absolute := n
			if n < 0 {
				absolute = -n
			}
			digits := strconv.FormatInt(absolute, base)
			if precision == 0 && n == 0 {
				digits = ""
			}
			if precision > len(digits) {
				digits = strings.Repeat("0", precision-len(digits)) + digits
			}
			body = digits
			if n < 0 {
				body = "-" + body
			}
			if len(body) < width {
				pad := width - len(body)
				if left {
					body += strings.Repeat(" ", pad)
				} else if zero && precision < 0 {
					if n < 0 {
						body = "-" + strings.Repeat("0", pad) + digits
					} else {
						body = strings.Repeat("0", pad) + body
					}
				} else {
					body = strings.Repeat(" ", pad) + body
				}
			}
		} else {
			if kind == 's' {
				body = value.text()
				if precision >= 0 && len(body) > precision {
					body = body[:precision]
				}
			} else if value.Kind == "number" || value.Kind == "strnum" {
				n := value.number()
				if n != 10 && (n < 32 || n > 126) {
					runtimeError(position, "invalid character code")
				}
				body = string(byte(n))
			} else {
				body = value.text()
				if len(body) > 1 {
					body = body[:1]
				}
			}
			if len(body) < width {
				padding := strings.Repeat(" ", width-len(body))
				if left {
					body += padding
				} else {
					body = padding + body
				}
			}
		}
		out.WriteString(body)
	}
	return out.String()
}
func invokeBuiltin(name string, values []Value, position Position) Value {
	switch name {
	case "substr":
		text := values[0].text()
		start := values[1].number()
		end := int64(len(text) + 1)
		if len(values) == 3 {
			end = start + values[2].number()
		}
		start = max(start, 1)
		end = min(end, int64(len(text)+1))
		if end <= start {
			return stringValue("")
		}
		return stringValue(text[int(start-1):int(end-1)])
	case "index":
		text, part := values[0].text(), values[1].text()
		if part == "" {
			return numeric(0)
		}
		return numeric(int64(strings.Index(text, part) + 1))
	case "toupper":
		return stringValue(strings.ToUpper(values[0].text()))
	case "tolower":
		return stringValue(strings.ToLower(values[0].text()))
	case "int":
		return numeric(values[0].number())
	case "sprintf":
		return stringValue(formatOutput(values, position))
	}
	panic("unknown built-in")
}
