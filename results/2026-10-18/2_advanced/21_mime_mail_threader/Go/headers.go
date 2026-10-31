package main

import "strings"

const whitespace = " \t"
const addressSpecials = "<>:;@,."
const addressWordChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+-/=?^_`{|}~"
const mimeExcluded = "()<>@,;:\\\"/[]?="

type Field struct{ Name, Value string }
type Header struct {
	Fields  []Field
	Invalid []int
}
type Token struct {
	Kind, Text string
	Spaced     bool
}
type Parameters struct {
	MainType, Subtype string
	Values            map[string]string
}

func splitWords(text string) []string {
	return strings.FieldsFunc(text, func(c rune) bool { return c == ' ' || c == '\t' })
}
func collapseWhitespace(text string) string { return strings.Join(splitWords(text), " ") }
func (h Header) Value(name string) (string, bool) {
	for _, field := range h.Fields {
		if field.Name == strings.ToLower(name) {
			return field.Value, true
		}
	}
	return "", false
}
func (h Header) Count(name string) int {
	count := 0
	for _, field := range h.Fields {
		if field.Name == strings.ToLower(name) {
			count++
		}
	}
	return count
}
func parseFields(lines []MailLine) Header {
	header := Header{}
	inField := false
	for _, line := range lines {
		text := line.Text
		if len(text) > 0 && strings.ContainsRune(whitespace, rune(text[0])) {
			if inField {
				header.Fields[len(header.Fields)-1].Value += text
			} else {
				header.Invalid = append(header.Invalid, line.Number)
			}
			continue
		}
		colon := strings.IndexByte(text, ':')
		inField = colon > 0
		if inField {
			for i := 0; i < colon; i++ {
				if text[i] < 33 || text[i] > 126 {
					inField = false
				}
			}
		}
		if inField {
			header.Fields = append(header.Fields, Field{strings.ToLower(text[:colon]), text[colon+1:]})
		} else {
			header.Invalid = append(header.Invalid, line.Number)
		}
	}
	for i := range header.Fields {
		header.Fields[i].Value = strings.Trim(header.Fields[i].Value, whitespace)
	}
	return header
}
func removeComments(text string) (string, bool) {
	var result strings.Builder
	depth := 0
	for position := 0; position < len(text); position++ {
		c := text[position]
		if depth == 0 {
			if c == '(' {
				depth = 1
				result.WriteByte(' ')
			} else {
				result.WriteByte(c)
			}
		} else if c == '\\' {
			position++
		} else if c == '(' {
			depth++
		} else if c == ')' {
			depth--
		}
	}
	return result.String(), depth == 0
}
func tokenize(text string, mime bool) ([]Token, bool) {
	tokens := []Token{}
	position, spaced := 0, false
	specials := addressSpecials
	if mime {
		specials = "/;="
	}
	isWord := func(c byte) bool {
		if mime {
			return c >= 33 && c <= 126 && !strings.ContainsRune(mimeExcluded, rune(c))
		}
		return strings.ContainsRune(addressWordChars, rune(c))
	}
	for position < len(text) {
		c := text[position]
		if c == ' ' || c == '\t' {
			spaced = true
			position++
			continue
		}
		if c == '(' {
			depth := 1
			position++
			for position < len(text) && depth > 0 {
				c = text[position]
				if c == '\\' {
					position += 2
					continue
				}
				if c == '(' {
					depth++
				} else if c == ')' {
					depth--
				}
				position++
			}
			if depth != 0 {
				return nil, false
			}
			spaced = true
			continue
		}
		if c == '"' {
			var value strings.Builder
			position++
			closed := false
			for position < len(text) {
				c = text[position]
				position++
				if c == '"' {
					closed = true
					break
				}
				if c == '\\' {
					if position == len(text) {
						return nil, false
					}
					c = text[position]
					position++
				}
				value.WriteByte(c)
			}
			if !closed {
				return nil, false
			}
			tokens = append(tokens, Token{"quoted", value.String(), spaced})
		} else if strings.ContainsRune(specials, rune(c)) {
			tokens = append(tokens, Token{string(c), string(c), spaced})
			position++
		} else if isWord(c) {
			end := position + 1
			for end < len(text) && isWord(text[end]) {
				end++
			}
			tokens = append(tokens, Token{"word", text[position:end], spaced})
			position = end
		} else {
			return nil, false
		}
		spaced = false
	}
	return tokens, true
}
func decodeWord(word string) (string, bool, bool) {
	if len(word) < 4 || !strings.HasPrefix(word, "=?") || !strings.HasSuffix(word, "?=") {
		return word, false, false
	}
	parts := strings.Split(word[2:len(word)-2], "?")
	if len(parts) != 3 || parts[0] == "" || parts[1] == "" || parts[2] == "" {
		return word, false, false
	}
	if strings.ToLower(parts[0]) != "us-ascii" {
		return word, false, true
	}
	data := []byte{}
	if parts[1] == "B" || parts[1] == "b" {
		var ok bool
		data, ok = strictBase64(parts[2])
		if !ok {
			return word, false, true
		}
	} else if parts[1] == "Q" || parts[1] == "q" {
		for position := 0; position < len(parts[2]); {
			c := parts[2][position]
			if c == '_' {
				data = append(data, ' ')
				position++
			} else if c == '=' {
				value, ok := escapedByte(parts[2], position)
				if !ok {
					return word, false, true
				}
				data = append(data, value)
				position += 3
			} else {
				data = append(data, c)
				position++
			}
		}
	} else {
		return word, false, true
	}
	for _, c := range data {
		if c < 32 || c > 126 {
			return word, false, true
		}
	}
	return string(data), true, false
}
func decodeUnstructured(value string) (string, bool) {
	result, previous, failed := "", false, false
	for index, word := range splitWords(value) {
		text, decoded, bad := decodeWord(word)
		if index > 0 && !(decoded && previous) {
			result += " "
		}
		result += text
		previous = decoded
		failed = failed || bad
	}
	return collapseWhitespace(result), failed
}
func parseParameters(value string, withSubtype bool) (Parameters, bool) {
	tokens, ok := tokenize(value, true)
	result := Parameters{Values: map[string]string{}}
	if !ok || len(tokens) == 0 || tokens[0].Kind != "word" {
		return result, false
	}
	result.MainType = strings.ToLower(tokens[0].Text)
	position := 1
	if withSubtype {
		if len(tokens) < 3 || tokens[1].Kind != "/" || tokens[2].Kind != "word" {
			return result, false
		}
		result.Subtype = strings.ToLower(tokens[2].Text)
		position = 3
	}
	for position < len(tokens) {
		if position+3 >= len(tokens) || tokens[position].Kind != ";" || tokens[position+1].Kind != "word" || tokens[position+2].Kind != "=" || tokens[position+3].Kind != "word" && tokens[position+3].Kind != "quoted" {
			return result, false
		}
		name := strings.ToLower(tokens[position+1].Text)
		if _, exists := result.Values[name]; !exists {
			result.Values[name] = tokens[position+3].Text
		}
		position += 4
	}
	return result, true
}
