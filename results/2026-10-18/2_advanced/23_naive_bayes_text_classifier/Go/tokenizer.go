package main

import "strings"

type Tokens struct {
	Raw, Stopwords, Short       int
	Words, Bigrams, BigramTerms []string
}

func tokenize(text string, stopwords map[string]bool) Tokens {
	tokens := Tokens{Words: []string{}, Bigrams: []string{}}
	text = strings.ToLower(text)
	for position := 0; position < len(text); {
		wordChar := func(c byte) bool { return c >= 'a' && c <= 'z' || c >= '0' && c <= '9' }
		if !wordChar(text[position]) {
			position++
			continue
		}
		end := position + 1
		for end < len(text) && wordChar(text[end]) {
			end++
		}
		word := text[position:end]
		tokens.Raw++
		if stopwords[word] {
			tokens.Stopwords++
		} else if len(word) == 1 {
			tokens.Short++
		} else {
			tokens.Words = append(tokens.Words, word)
		}
		position = end
	}
	for i := 0; i+1 < len(tokens.Words); i++ {
		tokens.Bigrams = append(tokens.Bigrams, tokens.Words[i]+"_"+tokens.Words[i+1])
	}
	tokens.BigramTerms = append(append([]string{}, tokens.Words...), tokens.Bigrams...)
	return tokens
}
func (t Tokens) Terms(bigrams bool) []string {
	if bigrams {
		return t.BigramTerms
	}
	return t.Words
}
func isBigram(term string) bool { return strings.Contains(term, "_") }
