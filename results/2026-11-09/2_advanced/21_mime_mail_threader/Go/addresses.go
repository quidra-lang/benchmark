package main

import "strings"

type Mailbox struct{ Name, Address string }
type Address struct {
	Mailbox *Mailbox
	Group   []Mailbox
}
type AddressParser struct {
	Tokens                []Token
	Position              int
	EncodingError, Failed bool
}

func dotAtom(tokens []Token) bool {
	if len(tokens)%2 == 0 {
		return false
	}
	for i, token := range tokens {
		expected := "word"
		if i%2 != 0 {
			expected = "."
		}
		if token.Kind != expected {
			return false
		}
	}
	return true
}
func (p *AddressParser) peek() string {
	if p.Position < len(p.Tokens) {
		return p.Tokens[p.Position].Kind
	}
	return ""
}
func (p *AddressParser) expect(kind string) {
	if p.peek() != kind {
		p.Failed = true
	} else {
		p.Position++
	}
}
func (p *AddressParser) run(phrase bool) []Token {
	start := p.Position
	for p.peek() == "word" || p.peek() == "." || phrase && p.peek() == "quoted" {
		p.Position++
	}
	return p.Tokens[start:p.Position]
}
func (p *AddressParser) displayName(phrase []Token) string {
	result, previous := "", false
	for index, token := range phrase {
		text, decoded := token.Text, false
		if token.Kind == "word" {
			var failed bool
			text, decoded, failed = decodeWord(text)
			p.EncodingError = p.EncodingError || failed
		}
		if index > 0 && token.Spaced && !(decoded && previous) {
			result += " "
		}
		result += text
		previous = decoded
	}
	return collapseWhitespace(result)
}
func (p *AddressParser) mailbox(phrase, local, domain []Token, named bool) Address {
	if !dotAtom(local) || !dotAtom(domain) {
		p.Failed = true
		return Address{}
	}
	text := ""
	for _, token := range local {
		text += token.Text
	}
	text += "@"
	for _, token := range domain {
		text += token.Text
	}
	name := ""
	if named {
		name = p.displayName(phrase)
	}
	return Address{Mailbox: &Mailbox{name, strings.ToLower(text)}}
}
func (p *AddressParser) address(inGroup bool) Address {
	phrase := p.run(true)
	switch p.peek() {
	case "<":
		p.Position++
		local := p.run(false)
		p.expect("@")
		domain := p.run(false)
		p.expect(">")
		return p.mailbox(phrase, local, domain, true)
	case "@":
		p.Position++
		domain := p.run(false)
		return p.mailbox(nil, phrase, domain, false)
	case ":":
		if inGroup || len(phrase) == 0 {
			p.Failed = true
			return Address{}
		}
		p.Position++
		group := []Mailbox{}
		if p.peek() != ";" {
			for {
				entry := p.address(true)
				if p.Failed || entry.Mailbox == nil {
					p.Failed = true
					return Address{}
				}
				group = append(group, *entry.Mailbox)
				if p.peek() != "," {
					break
				}
				p.Position++
			}
		}
		p.expect(";")
		return Address{Group: group}
	}
	p.Failed = true
	return Address{}
}
func parseAddressList(value string) ([]Address, bool, bool) {
	tokens, ok := tokenize(value, false)
	if !ok || len(tokens) == 0 {
		return nil, false, false
	}
	parser := AddressParser{Tokens: tokens}
	addresses := []Address{}
	for {
		addresses = append(addresses, parser.address(false))
		if parser.Failed {
			return nil, false, false
		}
		if parser.peek() != "," {
			break
		}
		parser.Position++
	}
	return addresses, parser.EncodingError, parser.Position == len(tokens)
}
