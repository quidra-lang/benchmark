package main

type ArithStats struct{ Bits, Contexts, Rescales int }
type FrequencyTable struct {
	Frequencies     [257]int
	Total, Rescales int
}

func newFrequencyTable() *FrequencyTable {
	t := &FrequencyTable{Total: 257}
	for i := range t.Frequencies {
		t.Frequencies[i] = 1
	}
	return t
}
func (t *FrequencyTable) interval(symbol int) (int, int) {
	sum := 0
	for _, v := range t.Frequencies[:symbol] {
		sum += v
	}
	return sum, t.Frequencies[symbol]
}
func (t *FrequencyTable) locate(value int) (int, int, int) {
	sum := 0
	for s, f := range t.Frequencies {
		if value < sum+f {
			return s, sum, f
		}
		sum += f
	}
	panic("arithmetic interval outside model")
}
func (t *FrequencyTable) update(symbol int) {
	t.Frequencies[symbol] += 32
	t.Total += 32
	if t.Total >= 8192 {
		t.Total = 0
		for i, f := range t.Frequencies {
			t.Frequencies[i] = (f + 1) / 2
			t.Total += t.Frequencies[i]
		}
		t.Rescales++
	}
}

type ArithmeticModel map[int]*FrequencyTable

func (m ArithmeticModel) table(context int) *FrequencyTable {
	if m[context] == nil {
		m[context] = newFrequencyTable()
	}
	return m[context]
}
func encodeArith(data []byte) ([]byte, ArithStats) {
	writer := BitWriter{}
	model := ArithmeticModel{}
	low, high, follow, context := 0, 65535, 0, 10
	emit := func(bit int) {
		writer.write(bit, 1)
		for j := 0; j < follow; j++ {
			writer.write(1-bit, 1)
		}
		follow = 0
	}
	for i := 0; i <= len(data); i++ {
		symbol := 256
		if i < len(data) {
			symbol = int(data[i])
		}
		table := model.table(context)
		cum, freq := table.interval(symbol)
		span := high - low + 1
		high = low + span*(cum+freq)/table.Total - 1
		low += span * cum / table.Total
		for {
			if high < 32768 {
				emit(0)
			} else if low >= 32768 {
				emit(1)
				low -= 32768
				high -= 32768
			} else if low >= 16384 && high < 49152 {
				follow++
				low -= 16384
				high -= 16384
			} else {
				break
			}
			low *= 2
			high = 2*high + 1
		}
		if symbol != 256 {
			table.update(symbol)
			context = symbol
		}
	}
	follow++
	if low < 16384 {
		emit(0)
	} else {
		emit(1)
	}
	stats := ArithStats{Bits: writer.Count, Contexts: len(model)}
	for _, t := range model {
		stats.Rescales += t.Rescales
	}
	return writer.finish(), stats
}
func decodeArith(payload []byte, n int) ([]byte, *DecodeError) {
	reader := BitReader{Payload: payload, ZeroFill: true}
	model := ArithmeticModel{}
	low, high, context := 0, 65535, 10
	value, _ := reader.read(16, 0)
	out := []byte{}
	for {
		table := model.table(context)
		span := high - low + 1
		q := ((value-low+1)*table.Total - 1) / span
		symbol, cum, freq := table.locate(q)
		high = low + span*(cum+freq)/table.Total - 1
		low += span * cum / table.Total
		for {
			if high < 32768 {
			} else if low >= 32768 {
				low -= 32768
				high -= 32768
				value -= 32768
			} else if low >= 16384 && high < 49152 {
				low -= 16384
				high -= 16384
				value -= 16384
			} else {
				break
			}
			low *= 2
			high = 2*high + 1
			bit, _ := reader.read(1, len(out))
			value = 2*value + bit
		}
		if symbol == 256 {
			if len(out) < n {
				return nil, &DecodeError{"early_end", len(out)}
			}
			return out, nil
		}
		if len(out) == n {
			return nil, &DecodeError{"overrun", len(out)}
		}
		out = append(out, byte(symbol))
		table.update(symbol)
		context = symbol
	}
}
