package main

import (
	"sort"
	"strings"
)

type Rule struct {
	Number          int
	Fields          []string
	Name            string
	From, To, Month int
	Day             DaySpec
	At              int64
	AtType          string
	Save            int64
	Letter          string
}
type RuleInstance struct {
	Rule    *Rule
	Nominal int64
}
type AppliedInstance struct {
	Time int64
	Rule *Rule
}
type LineRun struct {
	PreStart []*Rule
	Applied  []AppliedInstance
	End      int64
}

func instanceSequence(rules []*Rule) []RuleInstance {
	instances := []RuleInstance{}
	for _, rule := range rules {
		for year := rule.From; year <= rule.To; year++ {
			instances = append(instances, RuleInstance{rule, rule.Day.Value(year, rule.Month)*secondsPerDay + rule.At})
		}
	}
	sort.Slice(instances, func(i, j int) bool {
		if instances[i].Nominal != instances[j].Nominal {
			return instances[i].Nominal < instances[j].Nominal
		}
		return instances[i].Rule.Number < instances[j].Rule.Number
	})
	return instances
}
func adjustment(kind string, offset, save int64) int64 {
	if kind == "u" {
		return 0
	}
	if kind == "s" {
		return offset
	}
	return offset + save
}
func runInstances(instances []RuleInstance, offset, start int64, until *Until) LineRun {
	run := LineRun{End: posInfinity}
	save := int64(0)
	for _, instance := range instances {
		rule := instance.Rule
		time := instance.Nominal - adjustment(rule.AtType, offset, save)
		if until != nil && time >= until.Value-adjustment(until.Type, offset, save) {
			break
		}
		if time <= start {
			run.PreStart = append(run.PreStart, rule)
		} else {
			run.Applied = append(run.Applied, AppliedInstance{time, rule})
		}
		save = rule.Save
	}
	if until != nil {
		run.End = until.Value - adjustment(until.Type, offset, save)
	}
	return run
}
func abbreviation(format string, save int64, letter string) string {
	if position := strings.IndexByte(format, '/'); position >= 0 {
		if save == 0 {
			return format[:position]
		}
		return format[position+1:]
	}
	return strings.ReplaceAll(format, "%s", letter)
}
