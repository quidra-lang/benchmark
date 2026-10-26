package main

import (
	"slices"
	"strings"
)

type Condition struct {
	feature    int
	comparison string
	threshold  float64
}
type Rule struct {
	name       string
	conditions []Condition
}

func readRules() []Rule {
	rules := []Rule{}
	for _, line := range readLines("input/segment_rules.txt") {
		words := strings.Split(line, " ")
		rule := Rule{name: words[0]}
		for i := 1; i < len(words); i += 3 {
			rule.conditions = append(rule.conditions, Condition{slices.Index(featureNames, words[i]), words[i+1], parseReal(words[i+2])})
		}
		rules = append(rules, rule)
	}
	return rules
}
func ruleNumber(rules []Rule, center []float64) int {
	for i, rule := range rules {
		holds := true
		for _, condition := range rule.conditions {
			value := center[condition.feature]
			if condition.comparison == ">" {
				holds = holds && value > condition.threshold
			} else {
				holds = holds && value < condition.threshold
			}
		}
		if holds {
			return i + 1
		}
	}
	panic("unmatched center")
}
func originalScale(center, means, sds []float64) []float64 {
	values := make([]float64, len(center))
	for f, component := range center {
		value := means[f] + sds[f]*component
		if sqrtFeatures[f] {
			value *= value
		}
		values[f] = value
	}
	return values
}
