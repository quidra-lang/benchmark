package main

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strings"
)

var groupNames = []string{"mean", "median", "trimmed_mean", "sd"}
var groupFunctions = []func([]int64) float64{mean, median, trimmedMean, sd}
var pairNames = []string{"mean_diff", "median_ratio", "hodges_lehmann", "cohen_d"}
var pairFunctions = []func([]int64, []int64) float64{meanDifference, medianRatio, hodgesLehmann, cohenD}
var testNames = []string{"mean", "median", "ranksum", "absdev"}

func ceilDiv(numerator, denominator int) int { return (numerator + denominator - 1) / denominator }

type Summary struct {
	estimate                                          float64
	values, ordered                                   []float64
	average, se, bias, low, high, basicLow, basicHigh float64
}

func newSummary(estimate float64, values []float64, ranks [2]int) Summary {
	average, se := meanAndSE(values)
	ordered := orderedReals(values)
	low, high := ordered[ranks[0]-1], ordered[ranks[1]-1]
	return Summary{estimate, values, ordered, average, se, average - estimate, low, high, 2*estimate - high, 2*estimate - low}
}
func (s Summary) csvLine(name, statistic string) string {
	fields := []string{name, statistic}
	for _, value := range []float64{s.estimate, s.se, s.bias, s.low, s.high, s.basicLow, s.basicHigh} {
		fields = append(fields, realText(value))
	}
	return strings.Join(fields, ",")
}
func (s Summary) intervalText() string {
	return fmt.Sprintf("se %s bias %s percentile %s %s basic %s %s", realText(s.se), realText(s.bias), realText(s.low), realText(s.high), realText(s.basicLow), realText(s.basicHigh))
}

type GroupBootstrap struct {
	group     *Group
	indices   [][]int
	samples   [][]int64
	summaries [4]Summary
}

func newGroupBootstrap(group *Group, indices [][]int, ranks [2]int) *GroupBootstrap {
	bootstrap := &GroupBootstrap{group: group, indices: indices}
	for _, replicate := range indices {
		sample := make([]int64, len(replicate))
		for i, index := range replicate {
			sample[i] = group.values[index]
		}
		bootstrap.samples = append(bootstrap.samples, sample)
	}
	for i, function := range groupFunctions {
		values := make([]float64, len(indices))
		for r, sample := range bootstrap.samples {
			values[r] = function(sample)
		}
		bootstrap.summaries[i] = newSummary(function(group.values), values, ranks)
	}
	return bootstrap
}

type PairBootstrap struct {
	first, second *GroupBootstrap
	name          string
	summaries     [4]Summary
}

func newPairBootstrap(first, second *GroupBootstrap, ranks [2]int) *PairBootstrap {
	pair := &PairBootstrap{first: first, second: second, name: first.group.name + "-" + second.group.name}
	for i, function := range pairFunctions {
		values := make([]float64, len(first.samples))
		for r, sample := range first.samples {
			values[r] = function(sample, second.samples[r])
		}
		pair.summaries[i] = newSummary(function(first.group.values, second.group.values), values, ranks)
	}
	return pair
}

type Jackknife struct {
	values                      []float64
	average, variance, bias, se float64
}

func jackknifeSpread(values []float64) (float64, float64) {
	count := float64(len(values))
	average := sequentialSum(values) / count
	squares := 0.0
	for _, value := range values {
		difference := value - average
		squares += difference * difference
	}
	return average, (count - 1) * squares / count
}
func newJackknife(estimate float64, values []float64) Jackknife {
	average, variance := jackknifeSpread(values)
	return Jackknife{values, average, variance, float64(len(values)-1) * (average - estimate), math.Sqrt(variance)}
}

type Tally struct {
	observed         int64
	extreme, greater int
}

func (t *Tally) count(value int64) {
	if absInteger(value) >= absInteger(t.observed) {
		t.extreme++
	}
	if value >= t.observed {
		t.greater++
	}
}
func (t Tally) text(offset, denominator int) string {
	return fmt.Sprintf("extreme %d greater %d p_two %s p_greater %s", t.extreme, t.greater, pValue(int64(t.extreme+offset), int64(denominator)), pValue(int64(t.greater+offset), int64(denominator)))
}

type DisplayRange struct{ low, delta int64 }

func newDisplayRange(values []int64) DisplayRange {
	low, high := values[0], values[0]
	for _, value := range values[1:] {
		low = min(low, value)
		high = max(high, value)
	}
	return DisplayRange{low, 100 * (high - low)}
}
func (d DisplayRange) position(value int64) int {
	return int((120*(value-100*d.low) + d.delta) / (2 * d.delta))
}
func outlierIndices(values []int64) []int {
	first, third := quantileNumerator(values, 25), quantileNumerator(values, 75)
	result := []int{}
	for i, value := range values {
		if 200*value < 5*first-3*third || 200*value > 5*third-3*first {
			result = append(result, i)
		}
	}
	return result
}
func seriesLines(kind, name string, values []int64, display DisplayRange, stems bool) []string {
	count := len(values)
	average, deviation := mean(values), sd(values)
	second, third, fourth := centralMoments(values)
	clipped := winsorized(values)
	firstQuartile, thirdQuartile := quantileNumerator(values, 25), quantileNumerator(values, 75)
	outliers := outlierIndices(values)
	outside := map[int]bool{}
	numbers := []int{}
	for _, index := range outliers {
		outside[index] = true
		numbers = append(numbers, index+1)
	}
	inside := []int64{}
	for i, value := range values {
		if !outside[i] {
			inside = append(inside, value)
		}
	}
	orderedInside := orderedIntegers(inside)
	lowWhisker, highWhisker := orderedInside[0], orderedInside[len(inside)-1]
	band := []byte(strings.Repeat(".", 61))
	for position := display.position(100 * lowWhisker); position <= display.position(100*highWhisker); position++ {
		band[position] = '-'
	}
	for position := display.position(firstQuartile); position <= display.position(thirdQuartile); position++ {
		band[position] = '='
	}
	band[display.position(quantileNumerator(values, 50))] = '|'
	for _, index := range outliers {
		band[display.position(100*values[index])] = 'o'
	}
	ordered := orderedIntegers(values)
	lines := []string{kind + " " + name, fmt.Sprintf("n %d", count), "mean " + realText(average), "median " + realText(median(values)), fmt.Sprintf("trimmed_mean %s trim %d", realText(trimmedMean(values)), count/10), fmt.Sprintf("winsorized_mean %s winsorized_sd %s", realText(mean(clipped)), realText(sd(clipped))), "sd " + realText(deviation), "se_mean " + realText(deviation/math.Sqrt(float64(count))), "cv " + realText(deviation/average), "skewness " + realText(third/(second*math.Sqrt(second))), "kurtosis " + realText(fourth/(second*second)-3), "mad " + realText(mad(values)), "min " + realText(float64(ordered[0])/100), "q1 " + realText(float64(firstQuartile)/10000), "q3 " + realText(float64(thirdQuartile)/10000), "iqr " + realText(float64(thirdQuartile-firstQuartile)/10000), "max " + realText(float64(ordered[len(ordered)-1])/100)}
	percentiles := []string{"percentiles"}
	for i, percent := range []int{5, 10, 90, 95} {
		percentiles = append(percentiles, []string{"p05", "p10", "p90", "p95"}[i], realText(float64(quantileNumerator(values, percent))/10000))
	}
	lines = append(lines, strings.Join(percentiles, " "), fmt.Sprintf("whiskers %s %s", realText(float64(lowWhisker)/100), realText(float64(highWhisker)/100)), "outliers "+numberList(numbers), "box "+string(band))
	if stems {
		for stem := ordered[0] / 100; stem <= ordered[len(ordered)-1]/100; stem++ {
			leaves := ""
			for _, value := range ordered {
				if value/100 == stem {
					leaves += fmt.Sprint(value % 100 / 10)
				}
			}
			line := fmt.Sprintf("stem %d", stem)
			if leaves != "" {
				line += " " + leaves
			}
			lines = append(lines, line)
		}
	}
	return lines
}
func bootstrapLines(ordinary, balanced []*GroupBootstrap, pairs []*PairBootstrap) []string {
	lines := []string{"group,statistic,estimate,se,bias,percentile_lo,percentile_hi,basic_lo,basic_hi"}
	for i, bootstrap := range ordinary {
		for j, summary := range bootstrap.summaries {
			lines = append(lines, summary.csvLine(bootstrap.group.name, groupNames[j]))
		}
		for j, summary := range balanced[i].summaries {
			lines = append(lines, summary.csvLine(bootstrap.group.name, "balanced_"+groupNames[j]))
		}
	}
	for _, pair := range pairs {
		for j, summary := range pair.summaries {
			lines = append(lines, summary.csvLine(pair.name, pairNames[j]))
		}
	}
	return lines
}
func pairJackknifeLines(pair *PairBootstrap) []string {
	x, y := pair.first.group.values, pair.second.group.values
	lines := []string{}
	for statistic, function := range pairFunctions {
		estimate := pair.summaries[statistic].estimate
		firstValues := make([]float64, len(x))
		secondValues := make([]float64, len(y))
		for i := range x {
			firstValues[i] = function(without(x, i), y)
		}
		for i := range y {
			secondValues[i] = function(x, without(y, i))
		}
		first, second := newJackknife(estimate, firstValues), newJackknife(estimate, secondValues)
		bias, variance := 0.0, 0.0
		bias += first.bias
		bias += second.bias
		variance += first.variance
		variance += second.variance
		lines = append(lines, fmt.Sprintf("pair %s %s estimate %s bias %s se %s", pair.name, pairNames[statistic], realText(estimate), realText(bias), realText(math.Sqrt(variance))))
	}
	return lines
}
func deviationTotal(sample []int64, center int64) int64 {
	total := int64(0)
	for _, value := range sample {
		total += absInteger(2*value - center)
	}
	return total
}
func splitStatistics(values, ranks []int64, order []int, size int) [4]int64 {
	first, second := []int64{}, []int64{}
	rankTotal := int64(0)
	for i, index := range order {
		if i < size {
			first = append(first, values[index])
			rankTotal += ranks[index]
		} else {
			second = append(second, values[index])
		}
	}
	firstCenter, secondCenter := doubledMedian(first), doubledMedian(second)
	return [4]int64{contrast(sumIntegers(first), len(first), sumIntegers(second), len(second)), firstCenter - secondCenter, rankTotal - int64(len(first)*(len(first)+len(second)+1)), contrast(deviationTotal(first, firstCenter), len(first), deviationTotal(second, secondCenter), len(second))}
}
func signedRanks(differences []int64) []int64 {
	magnitudes := []int64{}
	for _, value := range differences {
		if value != 0 {
			magnitudes = append(magnitudes, absInteger(value))
		}
	}
	ranks := doubledRanks(magnitudes)
	result := make([]int64, len(differences))
	cursor := 0
	for i, value := range differences {
		if value == 0 {
			continue
		}
		result[i] = ranks[cursor]
		if value < 0 {
			result[i] = -result[i]
		}
		cursor++
	}
	return result
}
func welchLine(samples [][]int64) string {
	groupCount := len(samples)
	means := make([]float64, groupCount)
	weights := make([]float64, groupCount)
	for i, sample := range samples {
		means[i] = mean(sample)
		deviation := sd(sample)
		weights[i] = float64(len(sample)) / (deviation * deviation)
	}
	totalWeight := sequentialSum(weights)
	weighted := 0.0
	for i, weight := range weights {
		weighted += weight * means[i]
	}
	center := weighted / totalWeight
	spread, lambda := 0.0, 0.0
	for i, weight := range weights {
		difference := means[i] - center
		spread += weight * (difference * difference)
		share := 1 - weight/totalWeight
		lambda += share * share / float64(len(samples[i])-1)
	}
	spread /= float64(groupCount - 1)
	f := spread / (1 + float64(2*(groupCount-2))*lambda/float64(groupCount*groupCount-1))
	degrees := float64(groupCount*groupCount-1) / (3 * lambda)
	return fmt.Sprintf("welch f %s df %d %s", realText(f), groupCount-1, realText(degrees))
}

type Delta struct{ numerator, denominator int64 }

func groupDeltas(samples [][]int64, pairs [][2]int) []Delta {
	result := make([]Delta, len(pairs))
	for i, pair := range pairs {
		x, y := samples[pair[0]], samples[pair[1]]
		result[i] = Delta{absInteger(contrast(sumIntegers(x), len(x), sumIntegers(y), len(y))), int64(len(x) * len(y))}
	}
	return result
}
func deltaAtLeast(value, bound Delta) bool {
	return value.numerator*bound.denominator >= bound.numerator*value.denominator
}
func largestDelta(deltas []Delta) Delta {
	largest := deltas[0]
	for _, delta := range deltas[1:] {
		if !deltaAtLeast(largest, delta) {
			largest = delta
		}
	}
	return largest
}

type Study struct {
	data      *Dataset
	generator Minstd
	ranks     [2]int
	zLow      float64
}

func newStudy(data *Dataset) *Study {
	low := (data.settings.bootstrap + 1) * (100 - data.settings.confidence) / 200
	return &Study{data, Minstd{data.settings.seed}, [2]int{low, data.settings.bootstrap + 1 - low}, phiInverse(float64(100-data.settings.confidence) / 200)}
}
func (s *Study) descriptiveLines() []string {
	all := []int64{}
	for _, group := range s.data.groups {
		all = append(all, group.values...)
	}
	lines := []string{fmt.Sprintf("groups %d observations %d", len(s.data.groups), len(all))}
	display := newDisplayRange(all)
	for _, group := range s.data.groups {
		lines = append(lines, seriesLines("group", group.name, group.values, display, true)...)
	}
	paired := s.data.paired
	lines = append(lines, fmt.Sprintf("paired subjects %d", len(paired.differences)))
	together := append(append([]int64(nil), paired.before...), paired.after...)
	display = newDisplayRange(together)
	lines = append(lines, seriesLines("series", "before", paired.before, display, false)...)
	lines = append(lines, seriesLines("series", "after", paired.after, display, false)...)
	return append(lines, seriesLines("series", "diff", paired.differences, newDisplayRange(paired.differences), false)...)
}
func (s *Study) pairedBootstrap() (Summary, Summary) {
	paired := s.data.paired
	means, correlations := []float64{}, []float64{}
	for _, indices := range ordinaryIndices(&s.generator, len(paired.differences), s.data.settings.bootstrap) {
		before, after, differences := []int64{}, []int64{}, []int64{}
		for _, index := range indices {
			before = append(before, paired.before[index])
			after = append(after, paired.after[index])
			differences = append(differences, paired.differences[index])
		}
		means = append(means, mean(differences))
		correlations = append(correlations, correlation(before, after))
	}
	return newSummary(mean(paired.differences), means, s.ranks), newSummary(correlation(paired.before, paired.after), correlations, s.ranks)
}
func (s *Study) histogramLines(name, statistic string, summary Summary) []string {
	bins := s.data.settings.bins
	values := summary.values
	low, high := summary.ordered[0], summary.ordered[len(values)-1]
	counts := make([]int, bins)
	top := 0
	for _, value := range values {
		index := binNumber(value, low, high, bins) - 1
		counts[index]++
		top = max(top, counts[index])
	}
	marks := make([][]string, bins)
	marks[binNumber(summary.low, low, high, bins)-1] = append(marks[binNumber(summary.low, low, high, bins)-1], "L")
	estimateBin := "none"
	if low <= summary.estimate && summary.estimate <= high {
		index := binNumber(summary.estimate, low, high, bins) - 1
		estimateBin = fmt.Sprint(index + 1)
		marks[index] = append(marks[index], "E")
	}
	index := binNumber(summary.high, low, high, bins) - 1
	marks[index] = append(marks[index], "H")
	convergence := []string{}
	for quarter := 1; quarter <= 4; quarter++ {
		size := quarter * s.data.settings.bootstrap / 4
		_, se := meanAndSE(values[:size])
		convergence = append(convergence, fmt.Sprintf("%d:%s", size, realText(se)))
	}
	lines := []string{fmt.Sprintf("histogram %s %s min %s max %s width %s top %d estimate_bin %s", name, statistic, realText(low), realText(high), realText((high-low)/float64(bins)), top, estimateBin), "convergence " + strings.Join(convergence, " ")}
	for index, count := range counts {
		parts := []string{"bin", fmt.Sprint(index + 1), realText(low + (high-low)*float64(index)/float64(bins)), fmt.Sprint(count)}
		if count > 0 {
			parts = append(parts, bar(count, top))
		}
		parts = append(parts, marks[index]...)
		lines = append(lines, strings.Join(parts, " "))
	}
	return lines
}
func (s *Study) histogramFile(ordinary []*GroupBootstrap, pairs []*PairBootstrap) []string {
	lines := []string{}
	for _, bootstrap := range ordinary {
		for i, summary := range bootstrap.summaries {
			lines = append(lines, s.histogramLines(bootstrap.group.name, groupNames[i], summary)...)
		}
	}
	for _, pair := range pairs {
		for i, summary := range pair.summaries {
			lines = append(lines, s.histogramLines(pair.name, pairNames[i], summary)...)
		}
	}
	return lines
}
func (s *Study) bcaLine(statistic string, summary Summary, jackknife Jackknife) string {
	replicates := s.data.settings.bootstrap
	below := 0
	for _, value := range summary.values {
		if value < summary.estimate {
			below++
		}
	}
	z0 := phiInverse(float64(below) / float64(replicates))
	squares, cubes := 0.0, 0.0
	for _, value := range jackknife.values {
		u := jackknife.average - value
		squares += u * u
		cubes += u * u * u
	}
	acceleration := cubes / (6 * squares * math.Sqrt(squares))
	alpha := func(z float64) float64 { return phi(z0 + (z0+z)/(1-acceleration*(z0+z))) }
	lower := min(max(int(math.Floor(float64(replicates+1)*alpha(s.zLow))), 1), replicates)
	upper := min(max(replicates+1-int(math.Floor(float64(replicates+1)*(1-alpha(-s.zLow)))), 1), replicates)
	return fmt.Sprintf("bca %s below %d z0 %s acceleration %s ranks %d %d interval %s %s", statistic, below, realText(z0), realText(acceleration), lower, upper, realText(summary.ordered[lower-1]), realText(summary.ordered[upper-1]))
}
func (s *Study) afterBootstrapLines(bootstrap *GroupBootstrap, meanJackknife Jackknife) []string {
	values := bootstrap.group.values
	count := len(values)
	omitted := make([][]int, count)
	for r, replicate := range bootstrap.indices {
		chosen := make([]bool, count)
		for _, index := range replicate {
			chosen[index] = true
		}
		for index, used := range chosen {
			if !used {
				omitted[index] = append(omitted[index], r)
			}
		}
	}
	errors := make([][]float64, 4)
	lines := []string{}
	for i, summary := range bootstrap.summaries {
		errors[i] = make([]float64, count)
		for index, replicates := range omitted {
			selected := make([]float64, len(replicates))
			for r, number := range replicates {
				selected[r] = summary.values[number]
			}
			_, errors[i][index] = meanAndSE(selected)
		}
		average, variance := jackknifeSpread(errors[i])
		lines = append(lines, fmt.Sprintf("after_bootstrap %s se %s average %s se_of_se %s", groupNames[i], realText(summary.se), realText(average), realText(math.Sqrt(variance))))
	}
	sizes := make([]int, count)
	smallest, largest := len(bootstrap.indices), 0
	for i, numbers := range omitted {
		sizes[i] = len(numbers)
		smallest = min(smallest, len(numbers))
		largest = max(largest, len(numbers))
	}
	lines = append(lines, fmt.Sprintf("without min %d max %d", smallest, largest))
	total := sumIntegers(values)
	ranking := make([]int, count)
	for i := range ranking {
		ranking[i] = i
	}
	sort.SliceStable(ranking, func(i, j int) bool {
		return absInteger(int64(count)*values[ranking[i]]-total) > absInteger(int64(count)*values[ranking[j]]-total)
	})
	summary := bootstrap.summaries[0]
	for rank, index := range ranking[:min(5, count)] {
		influence := float64(count-1) * (meanJackknife.average - meanJackknife.values[index])
		shifted := []float64{}
		for _, number := range omitted[index] {
			shifted = append(shifted, summary.values[number]-summary.estimate)
		}
		shifted = orderedReals(shifted)
		quantiles := []string{}
		for _, percent := range []int{5, 50, 95} {
			quantiles = append(quantiles, realText(shifted[ceilDiv(percent*sizes[index], 100)-1]))
		}
		lines = append(lines, fmt.Sprintf("influence %d obs %d value %s l %s without %d se %s q05 %s q50 %s q95 %s", rank+1, index+1, realText(float64(values[index])/100), realText(influence), sizes[index], realText(errors[0][index]), quantiles[0], quantiles[1], quantiles[2]))
	}
	return lines
}
func (s *Study) groupJackknifeLines(bootstrap *GroupBootstrap) []string {
	values := bootstrap.group.values
	jackknives := make([]Jackknife, 4)
	lines := []string{fmt.Sprintf("group %s n %d", bootstrap.group.name, len(values))}
	for i, function := range groupFunctions {
		deleted := make([]float64, len(values))
		for index := range values {
			deleted[index] = function(without(values, index))
		}
		summary := bootstrap.summaries[i]
		jackknife := newJackknife(summary.estimate, deleted)
		jackknives[i] = jackknife
		lines = append(lines, fmt.Sprintf("jackknife %s estimate %s average %s bias %s se %s", groupNames[i], realText(summary.estimate), realText(jackknife.average), realText(jackknife.bias), realText(jackknife.se)))
	}
	for i, summary := range bootstrap.summaries {
		lines = append(lines, s.bcaLine(groupNames[i], summary, jackknives[i]))
	}
	return append(lines, s.afterBootstrapLines(bootstrap, jackknives[0])...)
}
func (s *Study) jackknifeFile(ordinary []*GroupBootstrap, pairs []*PairBootstrap) []string {
	lines := []string{}
	for _, bootstrap := range ordinary {
		lines = append(lines, s.groupJackknifeLines(bootstrap)...)
	}
	for _, pair := range pairs {
		lines = append(lines, pairJackknifeLines(pair)...)
	}
	return lines
}
func (s *Study) permutationLines(x, y []int64) ([]string, [4]int) {
	permutations := s.data.settings.permutations
	combined := append(append([]int64(nil), x...), y...)
	ranks := doubledRanks(combined)
	positions := make([]int, len(combined))
	for i := range positions {
		positions[i] = i
	}
	observed := splitStatistics(combined, ranks, positions, len(x))
	tallies := [4]Tally{}
	for i, value := range observed {
		tallies[i].observed = value
	}
	for r := 0; r < permutations; r++ {
		order := append([]int(nil), positions...)
		shuffle(&s.generator, order)
		for i, value := range splitStatistics(combined, ranks, order, len(x)) {
			tallies[i].count(value)
		}
	}
	k, m := len(x), len(y)
	rankTotal := sumIntegers(ranks[:k])
	results := [4]string{}
	extremes := [4]int{}
	for i, tally := range tallies {
		results[i] = tally.text(1, permutations+1)
		extremes[i] = tally.extreme
	}
	return []string{fmt.Sprintf("permutation n %d %d perms %d", k, m, permutations), fmt.Sprintf("mean diff %s %s", realText(meanDifference(x, y)), results[0]), fmt.Sprintf("median diff %s %s", realText(float64(observed[1])/200), results[1]), fmt.Sprintf("ranksum w %s u %s %s", realText(float64(rankTotal)/2), realText(float64(rankTotal-int64(k*(k+1)))/2), results[2]), fmt.Sprintf("absdev diff %s %s", realText(float64(observed[3])/float64(200*k*m)), results[3])}, extremes
}
func (s *Study) simulationRejects(first, second []int64) bool {
	settings := s.data.settings
	k, m := len(first), len(second)
	combined := append(append([]int64(nil), first...), second...)
	total := sumIntegers(combined)
	observed := absInteger(contrast(sumIntegers(first), k, sumIntegers(second), m))
	count := 0
	for r := 0; r < settings.powerPerms; r++ {
		shuffled := append([]int64(nil), combined...)
		shuffle(&s.generator, shuffled)
		head := sumIntegers(shuffled[:k])
		if absInteger(contrast(head, k, total-head, m)) >= observed {
			count++
		}
	}
	return 100*(count+1) <= (100-settings.confidence)*(settings.powerPerms+1)
}
func (s *Study) powerLine(x, y []int64) string {
	settings := s.data.settings
	rejections := 0
	for simulation := 0; simulation < settings.powerSims; simulation++ {
		first, second := make([]int64, len(x)), make([]int64, len(y))
		for i, index := range resampleIndices(&s.generator, len(x)) {
			first[i] = x[index]
		}
		for i, index := range resampleIndices(&s.generator, len(y)) {
			second[i] = y[index]
		}
		if s.simulationRejects(first, second) {
			rejections++
		}
	}
	power := float64(rejections) / float64(settings.powerSims)
	se := math.Sqrt(power * (1 - power) / float64(settings.powerSims))
	return fmt.Sprintf("power sims %d perms %d rejections %d power %s se %s", settings.powerSims, settings.powerPerms, rejections, realText(power), realText(se))
}
func (s *Study) exactLines(x, y []int64) []string {
	size := s.data.settings.pilot
	combined := append(append([]int64(nil), x[:size]...), y[:size]...)
	ranks := doubledRanks(combined)
	total := sumIntegers(combined)
	meanValues, rankValues := []int64{}, []int64{}
	positionChoices(2*size, size, func(choice []int) {
		chosen, rankTotal := int64(0), int64(0)
		for _, index := range choice {
			chosen += combined[index]
			rankTotal += ranks[index]
		}
		meanValues = append(meanValues, contrast(chosen, size, total-chosen, size))
		rankValues = append(rankValues, rankTotal-int64(size*(2*size+1)))
	})
	splits := len(meanValues)
	meanTally, rankTally := Tally{observed: meanValues[0]}, Tally{observed: rankValues[0]}
	absolute := make([]int64, splits)
	for i, value := range meanValues {
		meanTally.count(value)
		rankTally.count(rankValues[i])
		absolute[i] = absInteger(value)
	}
	critical := "critical diff none attained none"
	frequencies := valueCounts(absolute)
	cumulative := 0
	for i := len(frequencies) - 1; i >= 0; i-- {
		item := frequencies[i]
		cumulative += item.count
		if 100*cumulative > (100-s.data.settings.confidence)*splits {
			break
		}
		critical = fmt.Sprintf("critical diff %s attained %s", realText(float64(item.value)/float64(100*size*size)), pValue(int64(cumulative), int64(splits)))
	}
	rankTotal := sumIntegers(ranks[:size])
	return []string{fmt.Sprintf("exact size %d splits %d", size, splits), fmt.Sprintf("mean diff %s %s", realText(meanDifference(x[:size], y[:size])), meanTally.text(0, splits)), fmt.Sprintf("ranksum w %s u %s %s", realText(float64(rankTotal)/2), realText(float64(rankTotal-int64(size*(size+1)))/2), rankTally.text(0, splits)), critical}
}
func (s *Study) studentizedLines(pair *PairBootstrap) []string {
	x, y := pair.first.group.values, pair.second.group.values
	k, m := float64(len(x)), float64(len(y))
	estimate := meanDifference(x, y)
	firstSD, secondSD := sd(x), sd(y)
	firstVariance, secondVariance := firstSD*firstSD/k, secondSD*secondSD/m
	se0 := math.Sqrt(firstVariance + secondVariance)
	t := estimate / se0
	statistics := []float64{}
	extreme := 0
	for i, difference := range pair.summaries[0].values {
		first, second := pair.first.summaries[3].values[i], pair.second.summaries[3].values[i]
		spread := math.Sqrt(first*first/k + second*second/m)
		value := (difference - estimate) / spread
		statistics = append(statistics, value)
		if math.Abs(value) >= math.Abs(t) {
			extreme++
		}
	}
	ordered := orderedReals(statistics)
	lower, upper := estimate-ordered[s.ranks[1]-1]*se0, estimate-ordered[s.ranks[0]-1]*se0
	degrees := (firstVariance + secondVariance) * (firstVariance + secondVariance) / (firstVariance*firstVariance/(k-1) + secondVariance*secondVariance/(m-1))
	greater, equal := 0, 0
	for _, first := range x {
		for _, second := range y {
			if first > second {
				greater++
			}
			if first == second {
				equal++
			}
		}
	}
	d := cohenD(x, y)
	hedges := d * (1 - 3/(4*(k+m-2)-1))
	cles := float64(2*greater+equal) / float64(2*len(x)*len(y))
	return []string{fmt.Sprintf("bootstrap_t t %s df %s extreme %d p %s interval %s %s", realText(t), realText(degrees), extreme, pValue(int64(extreme+1), int64(s.data.settings.bootstrap+1)), realText(lower), realText(upper)), fmt.Sprintf("effect pooled_sd %s cohen_d %s hedges_g %s cles %s", realText(pooledSD(x, y)), realText(d), realText(hedges), realText(cles))}
}
func (s *Study) pairTestLines(pair *PairBootstrap) ([]string, [4]int) {
	first, second := pair.first.group, pair.second.group
	lines := []string{"compare " + first.name + " " + second.name}
	permutation, extremes := s.permutationLines(first.values, second.values)
	lines = append(lines, permutation...)
	lines = append(lines, s.powerLine(first.values, second.values))
	lines = append(lines, s.exactLines(first.values, second.values)...)
	lines = append(lines, s.studentizedLines(pair)...)
	return lines, extremes
}
func (s *Study) holmLines(extremes [][4]int) []string {
	settings := s.data.settings
	count := len(s.data.pairs)
	lines := []string{}
	for column, statistic := range testNames {
		order := make([]int, count)
		for i := range order {
			order[i] = i
		}
		sort.SliceStable(order, func(i, j int) bool { return extremes[order[i]][column] < extremes[order[j]][column] })
		adjusted := 0
		for rank, index := range order {
			extreme := extremes[index][column]
			adjusted = max(adjusted, min(settings.permutations+1, (count-rank)*(extreme+1)))
			decision := "retain"
			if 100*adjusted <= (100-settings.confidence)*(settings.permutations+1) {
				decision = "reject"
			}
			pair := s.data.pairs[index]
			lines = append(lines, fmt.Sprintf("holm %s rank %d %s %s p %s adjusted %s %s", statistic, rank+1, pair[0].name, pair[1].name, pValue(int64(extreme+1), int64(settings.permutations+1)), pValue(int64(adjusted), int64(settings.permutations+1)), decision))
		}
	}
	return lines
}
func hyperbolicTangent(value float64) float64 {
	growth := math.Exp(2 * value)
	return (growth - 1) / (growth + 1)
}
func (s *Study) pairedLines(meanSummary, correlationSummary Summary) []string {
	paired := s.data.paired
	count := len(paired.differences)
	positive, negative := 0, 0
	for _, difference := range paired.differences {
		if difference > 0 {
			positive++
		} else if difference < 0 {
			negative++
		}
	}
	average, deviation := mean(paired.differences), sd(paired.differences)
	r := correlation(paired.before, paired.after)
	z := 0.5 * math.Log((1+r)/(1-r))
	halfWidth := -s.zLow / math.Sqrt(float64(count-3))
	return []string{fmt.Sprintf("paired subjects %d positive %d negative %d zero %d", count, positive, negative, count-positive-negative), fmt.Sprintf("paired before %s after %s diff %s sd_diff %s t %s dz %s", realText(mean(paired.before)), realText(mean(paired.after)), realText(average), realText(deviation), realText(average/(deviation/math.Sqrt(float64(count)))), realText(average/deviation)), "paired_bootstrap " + meanSummary.intervalText(), fmt.Sprintf("correlation r %s %s fisher %s %s", realText(r), correlationSummary.intervalText(), realText(hyperbolicTangent(z-halfWidth)), realText(hyperbolicTangent(z+halfWidth)))}
}
func (s *Study) signFlipLines() []string {
	permutations := s.data.settings.permutations
	differences := s.data.paired.differences
	signed := signedRanks(differences)
	meanTally, rankTally := Tally{observed: sumIntegers(differences)}, Tally{observed: sumIntegers(signed)}
	for r := 0; r < permutations; r++ {
		meanTotal, rankTotal := int64(0), int64(0)
		for i, difference := range differences {
			sign := int64(1)
			if s.generator.draw()%2 == 1 {
				sign = -1
			}
			meanTotal += sign * difference
			rankTotal += sign * signed[i]
		}
		meanTally.count(meanTotal)
		rankTally.count(rankTotal)
	}
	positive := int64(0)
	for _, rank := range signed {
		if rank > 0 {
			positive += rank
		}
	}
	return []string{fmt.Sprintf("signflip flips %d", permutations), fmt.Sprintf("mean diff %s %s", realText(mean(differences)), meanTally.text(1, permutations+1)), fmt.Sprintf("signedrank w_plus %s %s", realText(float64(positive)/2), rankTally.text(1, permutations+1))}
}
func (s *Study) anovaPermutationLines(combined, ranks []int64, sizes []int, f, h, correction float64) []string {
	permutations := s.data.settings.permutations
	groupCount, totalCount := len(sizes), len(combined)
	pairs := [][2]int{}
	for i := 0; i < groupCount; i++ {
		for j := i + 1; j < groupCount; j++ {
			pairs = append(pairs, [2]int{i, j})
		}
	}
	observed := groupDeltas(splitList(combined, sizes), pairs)
	extremes, maxima := make([]int, len(pairs)), make([]int, len(pairs))
	fExtreme, hExtreme := 0, 0
	positions := make([]int, totalCount)
	for i := range positions {
		positions[i] = i
	}
	for r := 0; r < permutations; r++ {
		order := append([]int(nil), positions...)
		shuffle(&s.generator, order)
		parts := splitList(order, sizes)
		samples := make([][]int64, groupCount)
		rankSums := make([]int64, groupCount)
		for i, part := range parts {
			for _, index := range part {
				samples[i] = append(samples[i], combined[index])
				rankSums[i] += ranks[index]
			}
		}
		between, within := sumsOfSquares(samples)
		if fStatistic(between, within, groupCount, totalCount) >= f-0.000000001*f {
			fExtreme++
		}
		if hStatistic(rankSums, sizes, correction) >= h-0.000000001*h {
			hExtreme++
		}
		deltas := groupDeltas(samples, pairs)
		largest := largestDelta(deltas)
		for i, bound := range observed {
			if deltaAtLeast(deltas[i], bound) {
				extremes[i]++
			}
			if deltaAtLeast(largest, bound) {
				maxima[i]++
			}
		}
	}
	lines := []string{fmt.Sprintf("anova_permutation perms %d f_extreme %d f_p %s h_extreme %d h_p %s", permutations, fExtreme, pValue(int64(fExtreme+1), int64(permutations+1)), hExtreme, pValue(int64(hExtreme+1), int64(permutations+1)))}
	for i, pair := range pairs {
		first, second := s.data.groups[pair[0]], s.data.groups[pair[1]]
		lines = append(lines, fmt.Sprintf("pairwise %s %s diff %s extreme %d p %s maxt %d adjusted %s", first.name, second.name, realText(meanDifference(first.values, second.values)), extremes[i], pValue(int64(extremes[i]+1), int64(permutations+1)), maxima[i], pValue(int64(maxima[i]+1), int64(permutations+1))))
	}
	return lines
}
func (s *Study) anovaLines(ordinary []*GroupBootstrap) []string {
	samples := make([][]int64, len(s.data.groups))
	sizes := make([]int, len(samples))
	combined := []int64{}
	totalCount := 0
	for i, group := range s.data.groups {
		samples[i] = group.values
		sizes[i] = len(group.values)
		totalCount += sizes[i]
		combined = append(combined, group.values...)
	}
	groupCount := len(samples)
	between, within := sumsOfSquares(samples)
	f := fStatistic(between, within, groupCount, totalCount)
	eta := between / (between + within)
	msw := within / float64(totalCount-groupCount)
	omega := (between - float64(groupCount-1)*msw) / (between + within + msw)
	etaValues := make([]float64, s.data.settings.bootstrap)
	for number := range etaValues {
		replicate := make([][]int64, len(ordinary))
		for i, bootstrap := range ordinary {
			replicate[i] = bootstrap.samples[number]
		}
		first, second := sumsOfSquares(replicate)
		etaValues[number] = first / (first + second)
	}
	etaSummary := newSummary(eta, etaValues, s.ranks)
	ranks := doubledRanks(combined)
	rankSums := make([]int64, groupCount)
	for i, part := range splitList(ranks, sizes) {
		rankSums[i] = sumIntegers(part)
	}
	ties := 0
	tieTotal := int64(0)
	for _, item := range valueCounts(combined) {
		if item.count >= 2 {
			count := int64(item.count)
			ties++
			tieTotal += count*count*count - count
		}
	}
	count := int64(totalCount)
	correction := 1 - float64(tieTotal)/float64(count*count*count-count)
	h := hStatistic(rankSums, sizes, correction)
	lines := []string{fmt.Sprintf("anova groups %d observations %d ssb %s ssw %s df %d %d f %s eta_squared %s omega_squared %s", groupCount, totalCount, realText(between), realText(within), groupCount-1, totalCount-groupCount, realText(f), realText(eta), realText(omega)), "eta_bootstrap " + etaSummary.intervalText(), welchLine(samples), fmt.Sprintf("kruskal h %s tie_groups %d", realText(h), ties)}
	return append(lines, s.anovaPermutationLines(combined, ranks, sizes, f, h, correction)...)
}

type OutputFile struct {
	name  string
	lines []string
}

func (s *Study) run() []OutputFile {
	ordinary, balanced := []*GroupBootstrap{}, []*GroupBootstrap{}
	count := s.data.settings.bootstrap
	for _, group := range s.data.groups {
		ordinary = append(ordinary, newGroupBootstrap(group, ordinaryIndices(&s.generator, len(group.values), count), s.ranks))
	}
	for _, group := range s.data.groups {
		balanced = append(balanced, newGroupBootstrap(group, balancedIndices(&s.generator, len(group.values), count), s.ranks))
	}
	meanSummary, correlationSummary := s.pairedBootstrap()
	pairs := []*PairBootstrap{}
	for _, pair := range s.data.pairs {
		pairs = append(pairs, newPairBootstrap(ordinary[pair[0].number-1], ordinary[pair[1].number-1], s.ranks))
	}
	lines := []string{}
	extremes := [][4]int{}
	for _, pair := range pairs {
		records, counts := s.pairTestLines(pair)
		lines = append(lines, records...)
		extremes = append(extremes, counts)
	}
	lines = append(lines, s.holmLines(extremes)...)
	lines = append(lines, s.pairedLines(meanSummary, correlationSummary)...)
	lines = append(lines, s.signFlipLines()...)
	lines = append(lines, s.anovaLines(ordinary)...)
	return []OutputFile{{"descriptives.txt", s.descriptiveLines()}, {"bootstrap.csv", bootstrapLines(ordinary, balanced, pairs)}, {"jackknife.txt", s.jackknifeFile(ordinary, pairs)}, {"tests.txt", lines}, {"histograms.txt", s.histogramFile(ordinary, pairs)}}
}
func main() {
	study := newStudy(loadDataset())
	files := study.run()
	if err := os.MkdirAll("output", 0755); err != nil {
		panic(err)
	}
	for _, file := range files {
		writeLines(file.name, file.lines)
	}
}
