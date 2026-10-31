package main

import (
	"os"
	"sort"
	"strconv"
	"strings"
)

type Team struct{ Code, Name string }
type Match struct{ Round, Home, Away, HomeScore, AwayScore, Margin, Result2 int }

func (m Match) Y() float64 { return float64(m.Result2) / 2 }

type Settings struct {
	WinPoints, DrawPoints, FormLength, CloseMargin                                              int
	Exponent, EloK, EloHome, EloInitial                                                         float64
	GridK, GridHome                                                                             []int
	BTIterations, ODIterations, LinkIterations, Holdout, Upsets, Bins, Simulations, Top, Bottom int
	Seed                                                                                        int64
}

func readLines(path string) []string {
	data, err := os.ReadFile(path)
	if err != nil {
		panic(err)
	}
	return strings.Split(strings.TrimSuffix(string(data), "\n"), "\n")
}
func integer(text string) int { value, _ := strconv.Atoi(text); return value }
func loadSeason() ([]Team, []Match, Settings) {
	teams := []Team{}
	indices := map[string]int{}
	for _, line := range readLines("input/teams.csv")[1:] {
		fields := strings.Split(line, ",")
		indices[fields[0]] = len(teams)
		teams = append(teams, Team{fields[0], fields[1]})
	}
	matches := []Match{}
	for _, line := range readLines("input/matches.csv")[1:] {
		f := strings.Split(line, ",")
		homeScore, awayScore := integer(f[3]), integer(f[4])
		result := 0
		if homeScore > awayScore {
			result = 2
		} else if homeScore == awayScore {
			result = 1
		}
		matches = append(matches, Match{integer(f[0]), indices[f[1]], indices[f[2]], homeScore, awayScore, homeScore - awayScore, result})
	}
	sort.SliceStable(matches, func(i, j int) bool { return matches[i].Round < matches[j].Round })
	values := map[string][]string{}
	for _, line := range readLines("input/params.txt") {
		fields := strings.Split(line, " ")
		values[fields[0]] = fields[1:]
	}
	i := func(key string) int { return integer(values[key][0]) }
	list := func(key string) []int {
		result := []int{}
		for _, text := range values[key] {
			result = append(result, integer(text))
		}
		return result
	}
	exponent, _ := strconv.ParseFloat(values["PYTHAGOREAN_EXPONENT"][0], 64)
	settings := Settings{WinPoints: i("WIN_POINTS"), DrawPoints: i("DRAW_POINTS"), FormLength: i("FORM_LENGTH"), CloseMargin: i("CLOSE_MARGIN"), Exponent: exponent, EloK: float64(i("ELO_K")), EloHome: float64(i("ELO_HOME")), EloInitial: float64(i("ELO_INITIAL")), GridK: list("ELO_GRID_K"), GridHome: list("ELO_GRID_HOME"), BTIterations: i("BT_ITERATIONS"), ODIterations: i("OD_ITERATIONS"), LinkIterations: i("LINK_ITERATIONS"), Holdout: i("HOLDOUT_ROUND"), Upsets: i("UPSETS"), Bins: i("CALIBRATION_BINS"), Simulations: i("SIMULATIONS"), Seed: int64(i("SIM_SEED")), Top: i("TOP_POSITIONS"), Bottom: i("BOTTOM_POSITIONS")}
	return teams, matches, settings
}
func matchesBefore(matches []Match, round int) []Match {
	result := []Match{}
	for _, match := range matches {
		if match.Round < round {
			result = append(result, match)
		}
	}
	return result
}
