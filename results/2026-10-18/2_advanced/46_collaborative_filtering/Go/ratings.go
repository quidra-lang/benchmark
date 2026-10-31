package main

import (
	"os"
	"sort"
	"strconv"
	"strings"
)

type Rating struct {
	User, Item, Value int
	Time              int64
}
type RatingPair struct{ Other, Value int }
type ItemInfo struct {
	Title, GenreText string
	Genres           []string
}
type Params struct {
	Neighbors, Shrinkage                          int
	MinSimilarity, ItemReg, UserReg               float64
	Factors                                       int
	Rate, Regularization                          float64
	Epochs                                        int
	ALSReg                                        float64
	ALSIterations                                 int
	Seed                                          int64
	TopN                                          int
	Cutoffs, NeighborGrid, UserGroups, ItemGroups []int
	Buckets, ListSize                             int
	RecommendUsers, SimilarItems                  []int
}
type Ratings struct {
	Training, Test         []Rating
	Catalog                map[int]ItemInfo
	Users, Items           []int
	UserIndex, ItemIndex   map[int]int
	ByUser, ByItem         [][]RatingPair
	Values                 [][]int
	UserCounts, ItemCounts []int
	UserMeans, ItemMeans   []float64
	Mean                   float64
	Params                 Params
}

func readLines(path string) []string {
	v, e := os.ReadFile(path)
	if e != nil {
		panic(e)
	}
	return strings.Split(strings.TrimSuffix(string(v), "\n"), "\n")
}
func integer(s string) int {
	v, e := strconv.Atoi(s)
	if e != nil {
		panic(e)
	}
	return v
}
func decimal(s string) float64 {
	v, e := strconv.ParseFloat(s, 64)
	if e != nil {
		panic(e)
	}
	return v
}
func integerList(v []string) []int {
	out := make([]int, len(v))
	for i, s := range v {
		out[i] = integer(s)
	}
	return out
}
func readParams() Params {
	v := map[string][]string{}
	for _, line := range readLines("input/params.txt") {
		f := strings.Split(line, " ")
		v[f[0]] = f[1:]
	}
	return Params{integer(v["NEIGHBORS"][0]), integer(v["SHRINKAGE"][0]), decimal(v["MIN_SIMILARITY"][0]),
		decimal(v["BIAS_REG"][0]), decimal(v["BIAS_REG"][1]), integer(v["FACTORS"][0]), decimal(v["LEARNING_RATE"][0]),
		decimal(v["REGULARIZATION"][0]), integer(v["EPOCHS"][0]), decimal(v["ALS_REG"][0]), integer(v["ALS_ITERATIONS"][0]),
		int64(integer(v["SEED"][0])), integer(v["TOP_N"][0]), integerList(v["CUTOFFS"]), integerList(v["NEIGHBOR_GRID"]),
		integerList(v["USER_GROUPS"]), integerList(v["ITEM_GROUPS"]), integer(v["TIME_BUCKETS"][0]),
		integer(v["LIST_SIZE"][0]), integerList(v["RECOMMEND_USERS"]), integerList(v["SIMILAR_ITEMS"])}
}
func readRatingFile(path string) []Rating {
	rows := []Rating{}
	for _, line := range readLines(path)[1:] {
		f := strings.Split(line, ",")
		r := Rating{User: integer(f[0]), Item: integer(f[1]), Value: integer(f[2])}
		if len(f) == 4 {
			r.Time = int64(integer(f[3]))
		}
		rows = append(rows, r)
	}
	return rows
}
func readInputs() *Ratings {
	d := &Ratings{Training: readRatingFile("input/ratings.csv"), Test: readRatingFile("input/test.csv"),
		Catalog: map[int]ItemInfo{}, UserIndex: map[int]int{}, ItemIndex: map[int]int{}, Params: readParams()}
	users, items := map[int]bool{}, map[int]bool{}
	total := 0
	for _, r := range d.Training {
		users[r.User] = true
		items[r.Item] = true
		total += r.Value
	}
	for u := range users {
		d.Users = append(d.Users, u)
	}
	for i := range items {
		d.Items = append(d.Items, i)
	}
	sort.Ints(d.Users)
	sort.Ints(d.Items)
	for u, id := range d.Users {
		d.UserIndex[id] = u
	}
	for i, id := range d.Items {
		d.ItemIndex[id] = i
	}
	d.ByUser = make([][]RatingPair, len(d.Users))
	d.ByItem = make([][]RatingPair, len(d.Items))
	d.Values = make([][]int, len(d.Users))
	d.UserCounts = make([]int, len(d.Users))
	d.ItemCounts = make([]int, len(d.Items))
	d.UserMeans = make([]float64, len(d.Users))
	d.ItemMeans = make([]float64, len(d.Items))
	for u := range d.Values {
		d.Values[u] = make([]int, len(d.Items))
	}
	for j, r := range d.Training {
		u, i := d.UserIndex[r.User], d.ItemIndex[r.Item]
		d.Training[j].User = u
		d.Training[j].Item = i
		d.Values[u][i] = r.Value
		d.ByUser[u] = append(d.ByUser[u], RatingPair{i, r.Value})
		d.ByItem[i] = append(d.ByItem[i], RatingPair{u, r.Value})
	}
	for j, r := range d.Test {
		d.Test[j].User = d.UserIndex[r.User]
		d.Test[j].Item = d.ItemIndex[r.Item]
	}
	for u, rows := range d.ByUser {
		sort.Slice(rows, func(i, j int) bool { return rows[i].Other < rows[j].Other })
		sum := 0
		for _, r := range rows {
			sum += r.Value
		}
		d.UserCounts[u] = len(rows)
		d.UserMeans[u] = float64(sum) / float64(len(rows))
	}
	for i, rows := range d.ByItem {
		sort.Slice(rows, func(a, b int) bool { return rows[a].Other < rows[b].Other })
		sum := 0
		for _, r := range rows {
			sum += r.Value
		}
		d.ItemCounts[i] = len(rows)
		d.ItemMeans[i] = float64(sum) / float64(len(rows))
	}
	d.Mean = float64(total) / float64(len(d.Training))
	for _, line := range readLines("input/items.csv")[1:] {
		f := strings.Split(line, ",")
		d.Catalog[integer(f[0])] = ItemInfo{f[1], f[2], strings.Split(f[2], "|")}
	}
	return d
}
