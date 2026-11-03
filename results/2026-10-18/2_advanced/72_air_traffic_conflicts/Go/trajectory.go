package main

import "math"

type Vec struct{ X, Y, Z float64 }

func (a Vec) subtract(b Vec) Vec { return Vec{a.X - b.X, a.Y - b.Y, a.Z - b.Z} }

type Segment struct {
	Number, Leg               int
	Phase                     string
	Start, End                float64
	Position, Velocity, Final Vec
}
type Trajectory struct {
	Segments []Segment
	Length   float64
}

func buildTrajectory(p Plan, aircraft AircraftType) Trajectory {
	var result Trajectory
	t := float64(p.Departure + p.Delay)
	level := p.Level + p.Offset
	for k := 1; k < len(p.Waypoints); k++ {
		a,
			b := p.Waypoints[k-1], p.Waypoints[k]
		dx, dy := b.X-a.X, b.Y-a.Y
		length := math.Sqrt(float64(dx*dx+dy*dy)) / 10
		duration := length * 3600 / float64(p.Speed)
		vx,
			vy := (float64(dx)/10)/duration, (float64(dy)/10)/duration
		xp, yp, xq, yq := float64(a.X)/10, float64(a.Y)/10,
			float64(b.X)/10, float64(b.Y)/10
		target := level
		if b.HasLevel {
			target = b.Level + p.Offset
		}
		if target == level {
			result.Segments = append(result.Segments,
				Segment{len(result.Segments) + 1, k, "LVL", t, t + duration, Vec{xp, yp, float64(level * 100)}, Vec{vx, vy, 0},
					Vec{xq, yq, float64(level * 100)}})
		} else {
			rate := aircraft.Climb
			phase := "CLB"
			vz := float64(rate) / 60
			if target < level {
				rate = aircraft.Descent
				phase = "DES"
				vz = -(float64(rate) / 60)
			}
			difference := target - level
			if difference < 0 {
				difference = -difference
			}
			change := float64(difference*6000) / float64(rate)
			xc,
				yc := xp+vx*change, yp+vy*change
			result.Segments = append(result.Segments, Segment{len(result.Segments) + 1,
				k, phase, t, t + change, Vec{xp, yp, float64(level * 100)}, Vec{vx, vy, vz}, Vec{xc, yc, float64(target * 100)}})
			result.Segments = append(result.Segments,
				Segment{len(result.Segments) + 1, k, "LVL", t + change, t + duration, Vec{xc, yc, float64(target * 100)}, Vec{vx,
					vy, 0}, Vec{xq, yq, float64(target * 100)}})
		}
		result.Length += length
		t = t + duration
		level = target
	}
	return result
}
func (s Segment) at(time float64) Vec {
	dt := time - s.Start
	return Vec{s.Position.X + s.Velocity.X*dt, s.Position.Y + s.Velocity.Y*dt, s.Position.Z + s.Velocity.Z*dt}
}
func (t Trajectory) at(time float64) (Vec, Segment, bool) {
	if time < t.Segments[0].Start || time >= t.Segments[len(t.Segments)-1].End {
		return Vec{},
			Segment{}, false
	}
	for _, s := range t.Segments {
		if s.Start <= time && time < s.End {
			return s.at(time), s,
				true
		}
	}
	return Vec{}, Segment{}, false
}
func (t Trajectory) arrival() float64 { return t.Segments[len(t.Segments)-1].End }
