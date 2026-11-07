package main

func bradleyTerry(count int, matches []Match, iterations int) ([]float64, float64) {
	wins := make([]float64, count)
	homeWins := 0.0
	for _, match := range matches {
		y := match.Y()
		wins[match.Home] += y
		wins[match.Away] += 1 - y
		homeWins += y
	}
	strengths := make([]float64, count)
	for i := range strengths {
		strengths[i] = 1
	}
	theta := 1.0
	for iteration := 0; iteration < iterations; iteration++ {
		zeta := make([]float64, count)
		for _, match := range matches {
			q := theta*strengths[match.Home] + strengths[match.Away]
			zeta[match.Home] += theta / q
			zeta[match.Away] += 1 / q
		}
		for i := range strengths {
			strengths[i] = wins[i] / zeta[i]
		}
		total := 0.0
		for _, strength := range strengths {
			total += strength
		}
		for i := range strengths {
			strengths[i] = strengths[i] * float64(count) / total
		}
		denominator := 0.0
		for _, match := range matches {
			home := strengths[match.Home]
			denominator += home / (theta*home + strengths[match.Away])
		}
		theta = homeWins / denominator
	}
	return strengths, theta
}
func offenseDefense(count int, matches []Match, iterations int) ([]float64, []float64, []float64) {
	points := realMatrix(count)
	for _, match := range matches {
		points[match.Home][match.Away] += float64(match.AwayScore)
		points[match.Away][match.Home] += float64(match.HomeScore)
	}
	offense, defense := make([]float64, count), make([]float64, count)
	for i := range defense {
		defense[i] = 1
	}
	for iteration := 0; iteration < iterations; iteration++ {
		for j := 0; j < count; j++ {
			total := 0.0
			for i := 0; i < count; i++ {
				total += points[i][j] / defense[i]
			}
			offense[j] = total
		}
		for i := 0; i < count; i++ {
			total := 0.0
			for j := 0; j < count; j++ {
				total += points[i][j] / offense[j]
			}
			defense[i] = total
		}
	}
	ratings := make([]float64, count)
	for i := range ratings {
		ratings[i] = offense[i] / defense[i]
	}
	return offense, defense, ratings
}
