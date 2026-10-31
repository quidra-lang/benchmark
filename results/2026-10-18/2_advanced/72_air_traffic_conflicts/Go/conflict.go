package main

import (
	"math"
	"sort"
)

type Loss struct{ Lo, Hi, Time, Distance, Vertical float64 }
type Piece struct {
	A, B int
	Loss Loss
}
type Conflict struct {
	A, B       int
	Start, End float64
	Pieces     []Piece
	Closest    Piece
}

func lossInterval(p, w Vec, t1, t2 float64, settings Settings) (Loss, bool) {
	dh, dv := float64(settings.DH),
		float64(settings.DV)
	qa := w.X*w.X + w.Y*w.Y
	qb := 2 * (p.X*w.X + p.Y*w.Y)
	qc := (p.X*p.X + p.Y*p.Y) - dh*dh
	lo,
		hi := t1, t2
	if qa < 1e-12 {
		if qc >= 0 {
			return Loss{}, false
		}
	} else {
		d := qb*qb - 4*qa*qc
		if d <= 0 {
			return Loss{},
				false
		}
		s := math.Sqrt(d)
		lo = math.Max(lo, t1+(-qb-s)/(2*qa))
		hi = math.Min(hi, t1+(-qb+s)/(2*qa))
	}
	if w.Z == 0 {
		if math.Abs(p.Z) >= dv {
			return Loss{},
				false
		}
	} else {
		r1, r2 := (-dv-p.Z)/w.Z, (dv-p.Z)/w.Z
		lo = math.Max(lo, t1+math.Min(r1, r2))
		hi = math.Min(hi,
			t1+math.Max(r1, r2))
	}
	if hi-lo <= 1e-6 {
		return Loss{}, false
	}
	tc := t1
	if qa >= 1e-12 {
		tc = t1 + (-qb / (2 * qa))
	}
	tc = math.Min(math.Max(tc,
		lo), hi)
	tau := tc - t1
	ex, ey := p.X+w.X*tau, p.Y+w.Y*tau
	return Loss{lo, hi, tc, math.Sqrt(ex*ex + ey*ey),
		math.Abs(p.Z + w.Z*tau)}, true
}
func pairConflicts(a, b int, ta, tb Trajectory, settings Settings) []Conflict {
	var pieces []Piece
	for i, sa := range ta.Segments {
		for j, sb := range tb.Segments {
			t1, t2 := math.Max(sa.Start, sb.Start), math.Min(sa.End,
				sb.End)
			if t1 >= t2 {
				continue
			}
			loss, exists := lossInterval(sa.at(t1).subtract(sb.at(t1)), sa.Velocity.subtract(sb.Velocity),
				t1, t2, settings)
			if exists {
				pieces = append(pieces, Piece{i, j, loss})
			}
		}
	}
	sort.SliceStable(pieces, func(i,
		j int) bool {
		return pieces[i].Loss.Lo < pieces[j].Loss.Lo
	})
	var result []Conflict
	for _, piece := range pieces {
		if len(result) == 0 || piece.Loss.Lo-result[len(result)-1].End > 1e-6 {
			result = append(result,
				Conflict{a, b, piece.Loss.Lo, piece.Loss.Hi, []Piece{piece}, piece})
		} else {
			last := &result[len(result)-1]
			last.Pieces = append(last.Pieces,
				piece)
			last.End = piece.Loss.Hi
			if piece.Loss.Distance < last.Closest.Loss.Distance-1e-9 {
				last.Closest = piece
			}
		}
	}
	return result
}
func conflictLess(a, b Conflict) bool {
	return a.Start < b.Start || a.Start == b.Start && (a.A < b.A || a.A == b.A && a.B < b.B)
}
func conflicts(trajectories []Trajectory, settings Settings) []Conflict {
	var a []Conflict
	for i := 0; i < len(trajectories); i++ {
		for j := i + 1; j < len(trajectories); j++ {
			a = append(a,
				pairConflicts(i, j, trajectories[i], trajectories[j], settings)...)
		}
	}
	sort.SliceStable(a, func(i,
		j int) bool {
		return conflictLess(a[i], a[j])
	})
	return a
}
