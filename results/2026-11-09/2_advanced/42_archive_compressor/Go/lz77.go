package main

type Token struct{ Literal, Distance, Length int }

func tokenize(data []byte, b, k int) []Token {
	window, lookahead := 1<<b, (1<<k)+2
	prefixes := map[[3]byte][]int{}
	tokens := []Token{}
	position := 0
	prefix := func(i int) [3]byte { return [3]byte{data[i], data[i+1], data[i+2]} }
	for position < len(data) {
		distance, longest := 0, 0
		limit := min(lookahead, len(data)-position)
		if limit >= 3 {
			candidates := prefixes[prefix(position)]
			for j := len(candidates) - 1; j >= 0; j-- {
				start := candidates[j]
				if start < position-window {
					break
				}
				d := position - start
				length := 3
				for length < limit && data[position+length] == data[position+length-d] {
					length++
				}
				if length > longest {
					distance, longest = d, length
				}
				if longest == limit {
					break
				}
			}
		}
		consumed := 1
		if longest >= 3 {
			tokens = append(tokens, Token{Distance: distance, Length: longest})
			consumed = longest
		} else {
			tokens = append(tokens, Token{Literal: int(data[position])})
		}
		for start := position; start < min(position+consumed, len(data)-2); start++ {
			key := prefix(start)
			prefixes[key] = append(prefixes[key], start)
		}
		position += consumed
	}
	return tokens
}
func copyMatch(out []byte, d, length, n int) ([]byte, *DecodeError) {
	if d > len(out) {
		return nil, &DecodeError{"bad_offset", len(out)}
	}
	if len(out)+length > n {
		return nil, &DecodeError{"overrun", len(out)}
	}
	for i := 0; i < length; i++ {
		out = append(out, out[len(out)-d])
	}
	return out, nil
}
