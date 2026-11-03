package main

import "fmt"

type Guess struct { number,depth,row,column int; value Cell; solves,known int; result string }
type Search struct { rows,columns [][]int; guesses []Guess; solutions []Grid; maxDepth,backtracks,lineSolves int }
func guessCell(grid Grid) (int,int) { rows:=make([]int,len(grid)); columns:=make([]int,len(grid[0])); for r,row:=range grid { for c,state:=range row { if state==Unknown { rows[r]++; columns[c]++ } } }; bestR,bestC,score:=-1,-1,0; for r,row:=range grid { for c,state:=range row { if state==Unknown && (bestR<0 || rows[r]+columns[c]<score) { bestR,bestC,score=r,c,rows[r]+columns[c] } } }; return bestR,bestC }
func (s *Search) Run(grid Grid,depth int) bool {
 r,c:=guessCell(grid)
 for _,value:=range []Cell{Filled,Empty} { child:=cloneGrid(grid); child[r][c]=value; rowMarks,columnMarks:=make([]bool,len(s.rows)),make([]bool,len(s.columns)); rowMarks[r]=true; columnMarks[c]=true; p:=propagate(child,s.rows,s.columns,true,rowMarks,columnMarks); known:=determined(child); result:="open"
  if p.conflict>=0 { result="contradiction at="+p.steps[p.conflict].Label(); s.backtracks++ } else if known==len(s.rows)*len(s.columns) { s.solutions=append(s.solutions,child); result=fmt.Sprintf("solution%d",len(s.solutions)) }; s.maxDepth=max(s.maxDepth,depth); s.lineSolves+=len(p.steps); s.guesses=append(s.guesses,Guess{len(s.guesses)+1,depth,r,c,value,len(p.steps),known,result})
  if result=="open" { if s.Run(child,depth+1) { return true } } else if len(s.solutions)==2 { return true }
 }; return false
}
