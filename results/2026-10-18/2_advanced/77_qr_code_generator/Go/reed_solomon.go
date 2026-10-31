package main

type Field struct {
	exp [255]int
	log [256]int
}

func newField() *Field {
	f := &Field{}
	value := 1
	for i := 0; i < 255; i++ {
		f.exp[i] = value
		f.log[value] = i
		value <<= 1
		if value >= 256 {
			value ^= 285
		}
	}
	return f
}
func (f *Field) power(e int) int {
	e %= 255
	if e < 0 {
		e += 255
	}
	return f.exp[e]
}
func (f *Field) multiply(a, b int) int {
	if a == 0 || b == 0 {
		return 0
	}
	return f.power(f.log[a] + f.log[b])
}
func (f *Field) divide(a, b int) int {
	if a == 0 {
		return 0
	}
	return f.power(f.log[a] - f.log[b])
}
func (f *Field) encode(data []int, e int) []int {
	g := []int{1}
	for i := 0; i < e; i++ {
		next := make([]int, len(g)+1)
		for j, c := range g {
			next[j] ^= c
			next[j+1] ^= f.multiply(c, f.power(i))
		}
		g = next
	}
	out := append(append([]int(nil),
		data...), make([]int, e)...)
	for i := range data {
		factor := out[i]
		for j, c := range g {
			out[i+j] ^= f.multiply(factor,
				c)
		}
	}
	return out[len(data):]
}
func (f *Field) syndromes(words []int, e int) []int {
	out := make([]int, e)
	for j := 0; j < e; j++ {
		for _, w := range words {
			out[j] = f.multiply(out[j], f.power(j)) ^ w
		}
	}
	return out
}
func nonzero(a []int) bool {
	for _, v := range a {
		if v != 0 {
			return true
		}
	}
	return false
}
func (f *Field) polynomial(a []int, x int) int {
	value := 0
	for i := len(a) - 1; i >= 0; i-- {
		value = f.multiply(value, x) ^ a[i]
	}
	return value
}

type Correction struct {
	words, syndromes, positions []int
	ok                          bool
}

func (f *Field) correct(received []int, e int) Correction {
	s := f.syndromes(received, e)
	out := Correction{words: append([]int(nil),
		received...), syndromes: s}
	if !nonzero(s) {
		out.ok = true
		return out
	}
	lambda, b := make([]int, e+1), make([]int,
		e+1)
	lambda[0] = 1
	b[0] = 1
	degree, p, beta := 0, 1, 1
	for q := 0; q < e; q++ {
		delta := s[q]
		for h := 1; h <= degree; h++ {
			delta ^= f.multiply(lambda[h],
				s[q-h])
		}
		if delta == 0 {
			p++
			continue
		}
		old := append([]int(nil), lambda...)
		factor := f.divide(delta, beta)
		for h := 0; h+p <= e; h++ {
			lambda[h+p] ^= f.multiply(factor,
				b[h])
		}
		if 2*degree <= q {
			degree = q + 1 - degree
			b = old
			beta = delta
			p = 1
		} else {
			p++
		}
	}
	if degree > e/2 {
		return out
	}
	var positions []int
	for i := range received {
		z := f.power(-(len(received) - 1 - i))
		if f.polynomial(lambda,
			z) == 0 {
			positions = append(positions, i)
		}
	}
	if len(positions) != degree {
		return out
	}
	omega := make([]int,
		e)
	for i, a := range s {
		for h, b := range lambda {
			if i+h < e {
				omega[i+h] ^= f.multiply(a, b)
			}
		}
	}
	derivative := make([]int,
		e)
	for h := 1; h < len(lambda); h += 2 {
		derivative[h-1] = lambda[h]
	}
	for _, i := range positions {
		x := f.power(len(received) - 1 - i)
		z := f.power(-(len(received) - 1 - i))
		denominator := f.polynomial(derivative,
			z)
		if denominator == 0 {
			return out
		}
		value := f.divide(f.multiply(x, f.polynomial(omega, z)), denominator)
		out.words[i] ^= value
	}
	if nonzero(f.syndromes(out.words,
		e)) {
		return out
	}
	for i, v := range received {
		if out.words[i] != v {
			out.positions = append(out.positions,
				i)
		}
	}
	out.ok = true
	return out
}
