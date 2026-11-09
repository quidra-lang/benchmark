package main

import "slices"

func positionChoices(total, size int, visit func([]int)) {
	choice := make([]int, size)
	for i := range choice {
		choice[i] = i
	}
	for {
		visit(append([]int(nil), choice...))
		index := size - 1
		for index >= 0 && choice[index] == total-size+index {
			index--
		}
		if index < 0 {
			return
		}
		choice[index]++
		for next := index + 1; next < size; next++ {
			choice[next] = choice[next-1] + 1
		}
	}
}
func reducedFraction(numerator, denominator int64) (int64, int64) {
	a, b := numerator, denominator
	for b != 0 {
		a, b = b, a%b
	}
	return numerator / a, denominator / a
}
func contrast(firstTotal int64, firstSize int, secondTotal int64, secondSize int) int64 {
	return int64(secondSize)*firstTotal - int64(firstSize)*secondTotal
}

type ValueCount struct {
	value int64
	count int
}

func valueCounts(values []int64) []ValueCount {
	counts := map[int64]int{}
	for _, value := range values {
		counts[value]++
	}
	keys := make([]int64, 0, len(counts))
	for value := range counts {
		keys = append(keys, value)
	}
	slices.Sort(keys)
	result := make([]ValueCount, 0, len(keys))
	for _, value := range keys {
		result = append(result, ValueCount{value, counts[value]})
	}
	return result
}
func doubledRanks(values []int64) []int64 {
	ranks := map[int64]int64{}
	smaller := 0
	for _, item := range valueCounts(values) {
		ranks[item.value] = int64(2*smaller + item.count + 1)
		smaller += item.count
	}
	result := make([]int64, len(values))
	for i, value := range values {
		result[i] = ranks[value]
	}
	return result
}
func splitList[T any](items []T, sizes []int) [][]T {
	groups := make([][]T, 0, len(sizes))
	start := 0
	for _, size := range sizes {
		groups = append(groups, items[start:start+size])
		start += size
	}
	return groups
}
func sumsOfSquares(samples [][]int64) (float64, float64) {
	count := 0
	total := int64(0)
	for _, sample := range samples {
		count += len(sample)
		total += sumIntegers(sample)
	}
	grandMean := float64(total) / float64(100*count)
	between, within := 0.0, 0.0
	for _, sample := range samples {
		center := mean(sample)
		difference := center - grandMean
		between += float64(len(sample)) * (difference * difference)
		squares := 0.0
		for _, value := range sample {
			e := float64(value)/100 - center
			squares += e * e
		}
		within += squares
	}
	return between, within
}
func fStatistic(between, within float64, groups, total int) float64 {
	return between / float64(groups-1) / (within / float64(total-groups))
}
func hStatistic(rankSums []int64, sizes []int, correction float64) float64 {
	count := 0
	total := 0.0
	for i, rank := range rankSums {
		total += float64(rank*rank) / float64(4*sizes[i])
		count += sizes[i]
	}
	return (12*total/float64(count*(count+1)) - float64(3*(count+1))) / correction
}
