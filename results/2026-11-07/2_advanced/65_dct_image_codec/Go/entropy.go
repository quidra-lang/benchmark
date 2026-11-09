package main

import "sort"

type Huffman struct {
	Bits         [17]int
	Values       []int
	Length, Code [256]int
}

func (t *Huffman) Assign() {
	t.Length = [256]int{}
	t.Code = [256]int{}
	code, k := 0, 0
	for l := 1; l <= 16; l++ {
		for n := 0; n < t.Bits[l]; n++ {
			v := t.Values[k]
			k++
			t.Length[v] = l
			t.Code[v] = code
			code++
		}
		code *= 2
	}
}
func category(a int) int {
	a = abs(a)
	n := 0
	for a > 0 {
		n++
		a >>= 1
	}
	return n
}
func extra(a int) int {
	if a < 0 {
		return a + (1 << category(a)) - 1
	}
	return a
}
func decodedExtra(w, n int) int {
	if n == 0 {
		return 0
	}
	if w < 1<<(n-1) {
		return w - (1 << n) + 1
	}
	return w
}
func optimized(count [256]int) Huffman {
	var freq, size [257]int
	var next [257]int
	for i := 0; i <= 256; i++ {
		next[i] = -1
		if i < 256 {
			freq[i] = count[i]
		}
	}
	freq[256] = 1
	for {
		a,
			b := -1, -1
		for v := 0; v <= 256; v++ {
			if freq[v] > 0 && (a < 0 || freq[v] <= freq[a]) {
				a = v
			}
		}
		for v := 0; v <= 256; v++ {
			if v != a && freq[v] > 0 && (b < 0 || freq[v] <= freq[b]) {
				b = v
			}
		}
		if b < 0 {
			break
		}
		freq[a] += freq[b]
		freq[b] = 0
		size[a]++
		for next[a] >= 0 {
			a = next[a]
			size[a]++
		}
		next[a] = b
		size[b]++
		for next[b] >= 0 {
			b = next[b]
			size[b]++
		}
	}
	var lengths [258]int
	longest := 0
	for _, n := range size {
		if n > 0 {
			lengths[n]++
			longest = max(longest, n)
		}
	}
	for l := longest; l >= 17; l-- {
		for lengths[l] > 0 {
			j := l - 2
			for lengths[j] == 0 {
				j--
			}
			lengths[l] -= 2
			lengths[l-1]++
			lengths[j+1] += 2
			lengths[j]--
		}
	}
	for l := 16; l >= 1; l-- {
		if lengths[l] > 0 {
			lengths[l]--
			break
		}
	}
	var t Huffman
	copy(t.Bits[1:],
		lengths[1:17])
	for v := 0; v < 256; v++ {
		if size[v] > 0 {
			t.Values = append(t.Values, v)
		}
	}
	sort.Slice(t.Values,
		func(i, j int) bool {
			a, b := t.Values[i], t.Values[j]
			return size[a] < size[b] || size[a] == size[b] && a < b
		})
	t.Assign()
	return t
}
