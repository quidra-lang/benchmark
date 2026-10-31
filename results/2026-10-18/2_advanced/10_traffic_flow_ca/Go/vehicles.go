package main

type VehicleClass struct { name string; vmax, weight int; overtake, stops bool }
type Vehicle struct {
 number int; class *VehicleClass; source *Source
 arrival, inserted, exited int; sink string
 segment *Segment; lane, cell, speed int; turn *Turn
 route []*Segment; steps, distance, stoppedSteps, stopCount, laneChanges int64
 dwell int; completed map[*Segment]bool; trajectory []string
}
func (v *Vehicle) Maximum() int { return min(v.class.vmax,v.segment.limit) }
func (v *Vehicle) Place(s *Segment, lane, x int) { if v.segment != nil { v.segment.cells[v.lane][v.cell] = 0 }; s.cells[lane][x] = v.number; v.segment = s; v.lane = lane; v.cell = x }
func (v *Vehicle) Leave() { v.segment.cells[v.lane][v.cell] = 0; v.segment = nil }
func (v *Vehicle) Heading() bool { return v.segment != nil && v.class.stops && v.segment.stop != nil && !v.completed[v.segment] && v.cell <= v.segment.stop.cell }
func (v *Vehicle) Travel() int64 { return int64(v.exited-v.inserted+1) }
func randomSlowdown(speed, previous int, value int64, p, p0 int) int { probability := p; if previous == 0 { probability = p0 }; if speed > 0 && value%1000 < int64(probability) { speed-- }; return speed }
