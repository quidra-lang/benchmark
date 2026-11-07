package main

import "math"

type EloRun struct {
	Ratings, Expected, Changes []float64
	Rounds                     [][]float64
}

func expectedScore(home, away, advantage float64) float64 {
	return 1 / (1 + math.Pow(10, (away-home-advantage)/400))
}
func multiplier(match Match, home, away, advantage float64) float64 {
	goals := math.Abs(float64(match.Margin))
	if goals == 0 {
		return 1
	}
	difference := away - home - advantage
	if match.Margin > 0 {
		difference = home + advantage - away
	}
	return math.Log(goals+1) * 2.2 / (0.001*difference + 2.2)
}
func runElo(count int, matches []Match, k, advantage, initial float64) EloRun {
	run := EloRun{Ratings: make([]float64, count)}
	for i := range run.Ratings {
		run.Ratings[i] = initial
	}
	for position, match := range matches {
		home, away := run.Ratings[match.Home], run.Ratings[match.Away]
		expected := expectedScore(home, away, advantage)
		weight := multiplier(match, home, away, advantage)
		change := k * weight * (match.Y() - expected)
		run.Ratings[match.Home] = home + change
		run.Ratings[match.Away] = away - change
		run.Expected = append(run.Expected, expected)
		run.Changes = append(run.Changes, change)
		if position+1 == len(matches) || matches[position+1].Round != match.Round {
			run.Rounds = append(run.Rounds, append([]float64(nil), run.Ratings...))
		}
	}
	return run
}
