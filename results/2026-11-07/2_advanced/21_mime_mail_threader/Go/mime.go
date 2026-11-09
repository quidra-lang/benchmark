package main

import "strings"

const base64Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

func strictBase64(text string) ([]byte, bool) {
	if len(text)%4 != 0 {
		return nil, false
	}
	data := strings.TrimRight(text, "=")
	if len(text)-len(data) >= 3 {
		return nil, false
	}
	result := []byte{}
	buffer, bits := 0, 0
	for i := 0; i < len(data); i++ {
		value := strings.IndexByte(base64Alphabet, data[i])
		if value < 0 {
			return nil, false
		}
		buffer = buffer<<6 | value
		bits += 6
		if bits >= 8 {
			bits -= 8
			result = append(result, byte(buffer>>bits))
			buffer &= (1 << bits) - 1
		}
	}
	return result, true
}

func decodeBase64Body(text string) (string, bool) {
	compact := strings.NewReplacer(" ", "", "\t", "", "\n", "").Replace(text)
	data, ok := strictBase64(compact)
	if !ok {
		return "", false
	}
	content := strings.ReplaceAll(string(data), "\r\n", "\n")
	for i := 0; i < len(content); i++ {
		c := content[i]
		if c != 9 && c != 10 && (c < 32 || c > 126) {
			return "", false
		}
	}
	return content, true
}

func hexValue(c byte) int {
	if c >= '0' && c <= '9' {
		return int(c - '0')
	}
	if c >= 'a' && c <= 'f' {
		return int(c-'a') + 10
	}
	if c >= 'A' && c <= 'F' {
		return int(c-'A') + 10
	}
	return -1
}

func escapedByte(line string, position int) (byte, bool) {
	if position+2 >= len(line) {
		return 0, false
	}
	a, b := hexValue(line[position+1]), hexValue(line[position+2])
	if a < 0 || b < 0 {
		return 0, false
	}
	return byte(a*16 + b), true
}

func decodeQuotedPrintable(text string) (string, bool) {
	var output strings.Builder
	failed := false
	lines := strings.Split(text, "\n")
	for index, line := range lines {
		line = strings.TrimRight(line, whitespace)
		soft := strings.HasSuffix(line, "=")
		if soft {
			line = line[:len(line)-1]
		}
		for position := 0; position < len(line); {
			c := line[position]
			if c == '=' {
				decoded, ok := escapedByte(line, position)
				if ok && (decoded == 9 || decoded >= 32 && decoded <= 126) {
					output.WriteByte(decoded)
					position += 3
					continue
				}
				failed = true
			}
			output.WriteByte(c)
			position++
		}
		if !soft && index < len(lines)-1 {
			output.WriteByte('\n')
		}
	}
	return output.String(), failed
}
