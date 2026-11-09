package main

import "sort"

func cross(a, b Point) int { return a.X*b.Y - a.Y*b.X }
func rho(point Point, t int, trig Trig, step int) int {
	return floorDiv(point.X*trig[t].X+point.Y*trig[t].Y, 16384*step)
}
func circlePoints(radius int) []Point {
	set := map[Point]bool{}
	a, b, error := radius, 0, 1-radius
	for a >= b {
		for _, p := range []Point{{a, b}, {b, a}, {-b, a}, {-a, b}, {-a, -b}, {-b, -a}, {b, -a}, {a, -b}} {
			set[p] = true
		}
		b++
		if error < 0 {
			error += 2*b + 1
		} else {
			a--
			error += 2*(b-a) + 1
		}
	}
	out := []Point{}
	for p := range set {
		out = append(out, p)
	}
	half := func(p Point) int {
		if p.Y > 0 || p.Y == 0 && p.X > 0 {
			return 0
		}
		return 1
	}
	sort.Slice(out, func(i, j int) bool {
		a, b := out[i], out[j]
		ha, hb := half(a), half(b)
		return ha < hb || ha == hb && cross(a, b) > 0
	})
	return out
}

type CircleCell struct{ Radius, X, Y, Votes, Points int }
type CircleVoting struct {
	Votes               []Image
	Offsets             [][]Point
	Minimum, Candidates int
	Peaks               []CircleCell
}

func circleVote(edge Mask, p Params) CircleVoting {
	width, height := len(edge[0]), len(edge)
	minimum, maximum := p.integer("circle_min_radius"), p.integer("circle_max_radius")
	out := CircleVoting{Minimum: minimum}
	for r := minimum; r <= maximum; r++ {
		offsets := circlePoints(r)
		votes := newImage(width, height)
		for y, row := range edge {
			for x, present := range row {
				if present {
					for _, o := range offsets {
						q := Point{x + o.X, y + o.Y}
						if inside(q, width, height) {
							votes[q.Y][q.X]++
						}
					}
				}
			}
		}
		out.Offsets = append(out.Offsets, offsets)
		out.Votes = append(out.Votes, votes)
	}
	for r := minimum; r <= maximum; r++ {
		index := r - minimum
		denominator := len(out.Offsets[index])
		for y := 0; y < height; y++ {
			for x := 0; x < width; x++ {
				votes := out.Votes[index][y][x]
				if 100*votes < p.integer("circle_min_percent")*denominator {
					continue
				}
				out.Candidates++
				peak := true
				for otherR := max(minimum, r-2); otherR <= min(maximum, r+2) && peak; otherR++ {
					for otherY := max(0, y-2); otherY <= min(height-1, y+2) && peak; otherY++ {
						for otherX := max(0, x-2); otherX <= min(width-1, x+2); otherX++ {
							if otherR == r && otherY == y && otherX == x {
								continue
							}
							other := out.Votes[otherR-minimum][otherY][otherX]
							left, right := votes*len(out.Offsets[otherR-minimum]), other*denominator
							earlier := otherR < r || otherR == r && (otherY < y || otherY == y && otherX < x)
							if left < right || left == right && earlier {
								peak = false
								break
							}
						}
					}
				}
				if peak {
					out.Peaks = append(out.Peaks, CircleCell{r, x, y, votes, denominator})
				}
			}
		}
	}
	sort.Slice(out.Peaks, func(i, j int) bool {
		a, b := out.Peaks[i], out.Peaks[j]
		left, right := a.Votes*b.Points, b.Votes*a.Points
		if left != right {
			return left > right
		}
		if a.Radius != b.Radius {
			return a.Radius < b.Radius
		}
		if a.Y != b.Y {
			return a.Y < b.Y
		}
		return a.X < b.X
	})
	return out
}

type LineCell struct{ Theta, Rho, Votes int }
type LineVoting struct {
	Votes              []map[int]int
	Peaks              []LineCell
	Maximum, Low, High int
}

func lineVote(points []Point, width, height int, trig Trig, step, threshold int) LineVoting {
	out := LineVoting{Votes: make([]map[int]int, 180)}
	initialized := false
	for t := 0; t < 180; t++ {
		out.Votes[t] = map[int]int{}
		for _, p := range []Point{{0, 0}, {width - 1, 0}, {0, height - 1}, {width - 1, height - 1}} {
			r := rho(p, t, trig, step)
			if !initialized {
				out.Low, out.High = r, r
				initialized = true
			}
			out.Low = min(out.Low, r)
			out.High = max(out.High, r)
		}
		for _, p := range points {
			r := rho(p, t, trig, step)
			out.Votes[t][r]++
			out.Maximum = max(out.Maximum, out.Votes[t][r])
		}
	}
	for t := 0; t < 180; t++ {
		for r, votes := range out.Votes[t] {
			if votes < threshold {
				continue
			}
			peak := true
			for otherT := max(0, t-2); otherT <= min(179, t+2) && peak; otherT++ {
				for otherR := r - 2; otherR <= r+2; otherR++ {
					if otherT == t && otherR == r {
						continue
					}
					v := out.Votes[otherT][otherR]
					if v > votes || v == votes && (otherT < t || otherT == t && otherR < r) {
						peak = false
						break
					}
				}
			}
			if peak {
				out.Peaks = append(out.Peaks, LineCell{t, r, votes})
			}
		}
	}
	sort.Slice(out.Peaks, func(i, j int) bool {
		a, b := out.Peaks[i], out.Peaks[j]
		if a.Votes != b.Votes {
			return a.Votes > b.Votes
		}
		if a.Theta != b.Theta {
			return a.Theta < b.Theta
		}
		return a.Rho < b.Rho
	})
	return out
}
