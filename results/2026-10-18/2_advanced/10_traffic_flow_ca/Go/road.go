package main

import "fmt"

type Turn struct { target *Segment; weight int; vehicles int64 }
type BusStop struct { segment *Segment; cell, dwell int; buses int64 }
type Segment struct {
 id, from, to string
 length, lanes, limit int
 cells [][]int
 junction *Junction
 turns []*Turn
 stop *BusStop
 entered, vehicleSum, speedSum, greenCount, queueSum, failures, passed, blocked int64
 maxVehicles, maxQueue int
 changes [3]int64
}
func (s *Segment) Free(lane, x, cap int) int { n := 0; for n < cap && x+n+1 < s.length && s.cells[lane][x+n+1] == 0 { n++ }; return n }
func (s *Segment) First(lane int) int { for x, v := range s.cells[lane] { if v != 0 { return x } }; return s.length }
func (s *Segment) Safe(lane, x int) bool { for i := max(0,x-s.limit); i <= x; i++ { if s.cells[lane][i] != 0 { return false } }; return true }
func (s *Segment) CellsText(lane int, vehicles []*Vehicle) string {
 row := make([]byte,s.length); for x, id := range s.cells[lane] { if id == 0 { row[x] = '.' } else if id < 0 { row[x] = '#' } else { row[x] = byte('0'+vehicles[id-1].speed) } }; return string(row)
}
type Incident struct { segment *Segment; lane, cell, start, end, state, activeStart, activeEnd int }
func (i *Incident) Update(t int) string {
 event := ""; s := i.segment
 if i.state == 1 && t > i.end { i.state = 2; s.cells[i.lane][i.cell] = 0; event = "INCIDENT_END" } else if i.state == 0 && t > i.end { i.state = 3 } else if i.state == 0 && t >= i.start && s.cells[i.lane][i.cell] == 0 { i.state = 1; s.cells[i.lane][i.cell] = -1; i.activeStart = t; event = "INCIDENT_START" }
 if i.state == 1 { i.activeEnd = t }; if event == "" { return "" }; return fmt.Sprintf("%04d %s %s lane %d cell %d",t,event,s.id,i.lane+1,i.cell)
}
