package main

import "strings"

func fold(s string) string {
	b := []byte(s)
	for i, c := range b {
		if c >= 'A' && c <= 'Z' {
			b[i] = c + 32
		} else {
			switch c {
			case '[':
				b[i] = '{'
			case ']':
				b[i] = '}'
			case '\\':
				b[i] = '|'
			case '^':
				b[i] = '~'
			}
		}
	}
	return string(b)
}
func digits(s string) bool {
	if len(s) == 0 {
		return false
	}
	for _, c := range []byte(s) {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}
func letter(c byte) bool  { return c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' }
func special(c byte) bool { return strings.ContainsRune("[]\\`_^{|}", rune(c)) }
func validNick(s string) bool {
	if len(s) == 0 || !letter(s[0]) && !special(s[0]) {
		return false
	}
	for _, c := range []byte(s[1:]) {
		if !letter(c) && !special(c) && !(c >= '0' && c <= '9') && c != '-' {
			return false
		}
	}
	return true
}
func validChannel(s string, limit int) bool {
	return len(s) >= 2 && len(s) <= limit && s[0] == '#' && !strings.Contains(s, ":")
}
func parse(raw string) (string, []string) {
	i := 0
	if strings.HasPrefix(raw, ":") {
		k := strings.IndexByte(raw,
			' ')
		if k < 0 {
			return "", nil
		}
		i = k
	}
	for i < len(raw) && raw[i] == ' ' {
		i++
	}
	start := i
	for i < len(raw) && raw[i] != ' ' {
		i++
	}
	command := strings.ToUpper(raw[start:i])
	var args []string
	for i < len(raw) {
		for i < len(raw) && raw[i] == ' ' {
			i++
		}
		if i == len(raw) {
			break
		}
		if raw[i] == ':' {
			args = append(args,
				raw[i+1:])
			break
		}
		if len(args) == 14 {
			args = append(args, raw[i:])
			break
		}
		start = i
		for i < len(raw) && raw[i] != ' ' {
			i++
		}
		args = append(args,
			raw[start:i])
	}
	return command, args
}
