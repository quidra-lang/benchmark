package main

import (
 "fmt"
 "strings"
)
type Step struct { row bool; index,gain int; contradiction bool }
func (s Step) Label() string { return lineLabel(s.row,s.index) }
func (s Step) Text() string { if s.contradiction { return s.Label()+"!" }; return fmt.Sprintf("%s+%d",s.Label(),s.gain) }
type Propagation struct { steps []Step; conflict int }
func (p Propagation) Record() string { parts:=make([]string,len(p.steps)); for i,s:=range p.steps { parts[i]=s.Text() }; return strings.Join(parts," ") }
func lineLabel(row bool,index int) string { prefix:="C"; if row { prefix="R" }; return fmt.Sprintf("%s%d",prefix,index+1) }
func lineCells(grid Grid,row bool,index int) []Cell { if row { return append([]Cell(nil),grid[index]...) }; cells:=make([]Cell,len(grid)); for r:=range grid { cells[r]=grid[r][index] }; return cells }
func determined(grid Grid) int { n:=0; for _,row:=range grid { for _,c:=range row { if c!=Unknown { n++ } } }; return n }
func cloneGrid(grid Grid) Grid { copy:=make(Grid,len(grid)); for r:=range grid { copy[r]=append([]Cell(nil),grid[r]...) }; return copy }
func propagate(grid Grid,rows,columns [][]int,precise bool,rowMarks,columnMarks []bool) Propagation {
 result:=Propagation{conflict:-1}
 for { isRow,index:=true,-1; for i,mark:=range rowMarks { if mark { index=i; break } }; if index<0 { isRow=false; for i,mark:=range columnMarks { if mark { index=i; break } } }; if index<0 { return result }
  var clue []int; if isRow { rowMarks[index]=false; clue=rows[index] } else { columnMarks[index]=false; clue=columns[index] }; cells:=lineCells(grid,isRow,index); solved:=solveLine(cells,clue,precise); step:=Step{row:isRow,index:index}
  if solved==nil { step.contradiction=true; result.steps=append(result.steps,step); result.conflict=len(result.steps)-1; return result }
  for position,state:=range solved { if cells[position]!=Unknown || state==Unknown { continue }; step.gain++; if isRow { grid[index][position]=state; columnMarks[position]=true } else { grid[position][index]=state; rowMarks[position]=true } }; result.steps=append(result.steps,step)
 }
}
