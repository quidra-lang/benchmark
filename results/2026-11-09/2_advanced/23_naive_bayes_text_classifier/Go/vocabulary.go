package main

import "sort"

type RankedTerm struct {
	Term      string
	Frequency int
	Score     float64
	BestClass int
}
type Vocabulary struct {
	TermCount, CandidateCount int
	Ranking                   []RankedTerm
	Terms                     []string
	Index                     map[string]int
	Frequencies               []int
}

func firstOccurrences(sequence []int) []int {
	result := []int{}
	seen := map[int]bool{}
	for _, term := range sequence {
		if !seen[term] {
			result = append(result, term)
			seen[term] = true
		}
	}
	return result
}
func chiSquare(withTerm, frequency, classSize, total int64) float64 {
	b, c := frequency-withTerm, classSize-withTerm
	e := total - classSize - b
	difference := withTerm*e - b*c
	numerator := total * difference * difference
	denominator := frequency * (total - frequency) * classSize * (total - classSize)
	if denominator == 0 {
		return 0
	}
	return float64(numerator) / float64(denominator)
}
func buildVocabulary(sequences [][]string, labels []int, classCount, minDF, size int) Vocabulary {
	counts := map[string][]int64{}
	classSizes := make([]int64, classCount)
	for i, sequence := range sequences {
		label := labels[i]
		classSizes[label]++
		seen := map[string]bool{}
		for _, term := range sequence {
			if seen[term] {
				continue
			}
			seen[term] = true
			if _, exists := counts[term]; !exists {
				counts[term] = make([]int64, classCount)
			}
			counts[term][label]++
		}
	}
	terms := []string{}
	for term := range counts {
		terms = append(terms, term)
	}
	sort.Strings(terms)
	ranking := []RankedTerm{}
	for _, term := range terms {
		frequency := int64(0)
		for _, count := range counts[term] {
			frequency += count
		}
		if frequency < int64(minDF) {
			continue
		}
		bestClass := 0
		bestScore := chiSquare(counts[term][0], frequency, classSizes[0], int64(len(sequences)))
		for label := 1; label < classCount; label++ {
			score := chiSquare(counts[term][label], frequency, classSizes[label], int64(len(sequences)))
			if score > bestScore {
				bestClass, bestScore = label, score
			}
		}
		ranking = append(ranking, RankedTerm{term, int(frequency), bestScore, bestClass})
	}
	candidateCount := len(ranking)
	sort.Slice(ranking, func(i, j int) bool {
		if ranking[i].Score != ranking[j].Score {
			return ranking[i].Score > ranking[j].Score
		}
		return ranking[i].Term < ranking[j].Term
	})
	if size > 0 && len(ranking) > size {
		ranking = ranking[:size]
	}
	vocabulary := Vocabulary{TermCount: len(counts), CandidateCount: candidateCount, Ranking: ranking, Index: map[string]int{}}
	frequencies := map[string]int{}
	for _, entry := range ranking {
		vocabulary.Terms = append(vocabulary.Terms, entry.Term)
		frequencies[entry.Term] = entry.Frequency
	}
	sort.Strings(vocabulary.Terms)
	for i, term := range vocabulary.Terms {
		vocabulary.Index[term] = i
		vocabulary.Frequencies = append(vocabulary.Frequencies, frequencies[term])
	}
	return vocabulary
}
func (v Vocabulary) Encode(sequence []string) []int {
	encoded := []int{}
	for _, term := range sequence {
		if index, exists := v.Index[term]; exists {
			encoded = append(encoded, index)
		}
	}
	return encoded
}
