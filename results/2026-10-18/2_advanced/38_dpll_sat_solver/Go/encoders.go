package main

func queens(n int) Formula {
	f := Formula{Variables: n * n}
	for r := 1; r <= n; r++ {
		clause := []int{}
		for c := 1; c <= n; c++ {
			clause = append(clause, (r-1)*n+c)
		}
		f.Clauses = append(f.Clauses, clause)
	}
	for a := 1; a <= f.Variables; a++ {
		ra, ca := (a-1)/n, (a-1)%n
		for b := a + 1; b <= f.Variables; b++ {
			rb, cb := (b-1)/n, (b-1)%n
			if ra == rb || ca == cb || abs(ra-rb) == abs(ca-cb) {
				f.Clauses = append(f.Clauses, []int{-a, -b})
			}
		}
	}
	return f
}
func pigeon(p, h int) Formula {
	f := Formula{Variables: p * h}
	for i := 1; i <= p; i++ {
		clause := []int{}
		for j := 1; j <= h; j++ {
			clause = append(clause, (i-1)*h+j)
		}
		f.Clauses = append(f.Clauses, clause)
	}
	for i := 1; i <= p; i++ {
		for j1 := 1; j1 <= h; j1++ {
			for j2 := j1 + 1; j2 <= h; j2++ {
				f.Clauses = append(f.Clauses, []int{-((i-1)*h + j1), -((i-1)*h + j2)})
			}
		}
	}
	for j := 1; j <= h; j++ {
		for i1 := 1; i1 <= p; i1++ {
			for i2 := i1 + 1; i2 <= p; i2++ {
				f.Clauses = append(f.Clauses, []int{-((i1-1)*h + j), -((i2-1)*h + j)})
			}
		}
	}
	return f
}
func coloring(g *Graph, k int) Formula {
	f := Formula{Variables: g.Vertices * k}
	for v := 1; v <= g.Vertices; v++ {
		clause := []int{}
		for c := 1; c <= k; c++ {
			clause = append(clause, (v-1)*k+c)
		}
		f.Clauses = append(f.Clauses, clause)
	}
	for v := 1; v <= g.Vertices; v++ {
		for c1 := 1; c1 <= k; c1++ {
			for c2 := c1 + 1; c2 <= k; c2++ {
				f.Clauses = append(f.Clauses, []int{-((v-1)*k + c1), -((v-1)*k + c2)})
			}
		}
	}
	for _, e := range g.Edges {
		for c := 1; c <= k; c++ {
			f.Clauses = append(f.Clauses, []int{-((e[0]-1)*k + c), -((e[1]-1)*k + c)})
		}
	}
	return f
}
func positions(model []bool, rows, width int) []int {
	places := []int{}
	for r := 1; r <= rows; r++ {
		for c := 1; c <= width; c++ {
			if model[(r-1)*width+c] {
				places = append(places, c)
				break
			}
		}
	}
	return places
}
