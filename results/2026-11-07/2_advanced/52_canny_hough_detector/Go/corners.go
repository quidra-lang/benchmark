package main

import "sort"

type Corner struct {
	Number   int
	Point    Point
	Response int64
	Match    string
}

func harris(gx, gy Image, p Params) ([]*Corner, int) {
	width, height := len(gx[0]), len(gx)
	response := make([][]int64, height)
	half := p.integer("harris_window") / 2
	for y := 0; y < height; y++ {
		response[y] = make([]int64, width)
		for x := 0; x < width; x++ {
			xx, yy, xy := int64(0), int64(0), int64(0)
			for j := -half; j <= half; j++ {
				for i := -half; i <= half; i++ {
					a, b := int64(reference(gx, x+i, y+j)), int64(reference(gy, x+i, y+j))
					xx += a * a
					yy += b * b
					xy += a * b
				}
			}
			trace := xx + yy
			response[y][x] = xx*yy - xy*xy - trace*trace/25
		}
	}
	candidates := []*Corner{}
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			v := response[y][x]
			if v < p["harris_threshold"][0] {
				continue
			}
			peak := true
			for _, q := range neighbors(Point{x, y}, width, height) {
				other := response[q.Y][q.X]
				if other > v || other == v && (q.Y < y || q.Y == y && q.X < x) {
					peak = false
					break
				}
			}
			if peak {
				candidates = append(candidates, &Corner{Point: Point{x, y}, Response: v, Match: "none"})
			}
		}
	}
	sort.Slice(candidates, func(i, j int) bool {
		a, b := candidates[i], candidates[j]
		if a.Response != b.Response {
			return a.Response > b.Response
		}
		if a.Point.Y != b.Point.Y {
			return a.Point.Y < b.Point.Y
		}
		return a.Point.X < b.Point.X
	})
	count := len(candidates)
	candidates = candidates[:min(len(candidates), p.integer("harris_max_count"))]
	for i, c := range candidates {
		c.Number = i + 1
	}
	return candidates, count
}
