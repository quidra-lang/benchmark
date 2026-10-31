package main

import "math/bits"

type LZWStats struct {
	Codes, Clears int
	Widths        [4]int
	Longest       int
}

func initialLZWDictionary() map[string]int {
	m := make(map[string]int, 256)
	for k := 0; k < 256; k++ {
		m[string([]byte{byte(k)})] = k
	}
	return m
}
func encodeLZW(data []byte) ([]byte, LZWStats) {
	writer := BitWriter{}
	stats := LZWStats{}
	dictionary := initialLZWDictionary()
	next, since := 258, 0
	emit := func(code, length int) {
		width := min(12, bits.Len(uint(258+since)))
		writer.write(code, width)
		stats.Codes++
		stats.Widths[width-9]++
		stats.Longest = max(stats.Longest, length)
		if code == 256 {
			stats.Clears++
			since = 0
		} else {
			since++
		}
	}
	emit(256, 0)
	sequence := ""
	for _, x := range data {
		single := string([]byte{x})
		extended := sequence + single
		if _, ok := dictionary[extended]; ok {
			sequence = extended
			continue
		}
		emit(dictionary[sequence], len(sequence))
		dictionary[extended] = next
		next++
		if next == 4096 {
			emit(256, 0)
			dictionary = initialLZWDictionary()
			next = 258
		}
		sequence = single
	}
	if sequence != "" {
		emit(dictionary[sequence], len(sequence))
	}
	emit(257, 0)
	return writer.finish(), stats
}
func decodeLZW(payload []byte, n int) ([]byte, *DecodeError) {
	reader := BitReader{Payload: payload}
	dictionary := make([][]byte, 258)
	reset := func() {
		dictionary = make([][]byte, 258)
		for k := 0; k < 256; k++ {
			dictionary[k] = []byte{byte(k)}
		}
	}
	reset()
	previous, since := -1, 0
	out := []byte{}
	for {
		count := since
		width := min(12, bits.Len(uint(258+count)))
		code, err := reader.read(width, len(out))
		if err != nil {
			return nil, err
		}
		if code == 256 {
			reset()
			previous = -1
			since = 0
			continue
		}
		since++
		if code == 257 {
			if len(out) < n {
				return nil, &DecodeError{"early_end", len(out)}
			}
			return out, nil
		}
		if count == 3838 {
			return nil, &DecodeError{"bad_code", len(out)}
		}
		var sequence []byte
		if previous < 0 {
			if code >= 256 {
				return nil, &DecodeError{"bad_code", len(out)}
			}
			sequence = dictionary[code]
		} else if code < len(dictionary) {
			sequence = dictionary[code]
		} else if code == len(dictionary) {
			sequence = append(append([]byte{}, dictionary[previous]...), dictionary[previous][0])
		} else {
			return nil, &DecodeError{"bad_code", len(out)}
		}
		if len(out)+len(sequence) > n {
			return nil, &DecodeError{"overrun", len(out)}
		}
		out = append(out, sequence...)
		if previous >= 0 {
			dictionary = append(dictionary, append(append([]byte{}, dictionary[previous]...), sequence[0]))
		}
		previous = code
	}
}
