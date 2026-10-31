package main

type Cell uint8
const ( Unknown Cell=iota; Filled; Empty )
type Grid [][]Cell
type Placements struct { cells []Cell; clue []int; before,after [][]bool }
func fitTable(cells []Cell,clue []int) [][]bool {
 n,k:=len(cells),len(clue); empties:=make([]int,n+1); for i,c:=range cells { empties[i+1]=empties[i]; if c==Empty { empties[i+1]++ } }; table:=make([][]bool,n+1); for i:=range table { table[i]=make([]bool,k+1) }; table[0][0]=true
 for end:=1;end<=n;end++ { for count:=0;count<=k;count++ { fits:=cells[end-1]!=Filled && table[end-1][count]; if !fits && count>0 { start:=end-clue[count-1]; if start>=0 && empties[end]==empties[start] { if start==0 { fits=count==1 } else { fits=cells[start-1]!=Filled && table[start-1][count-1] } } }; table[end][count]=fits } }; return table
}
func placements(cells []Cell,clue []int) Placements { reversed:=make([]Cell,len(cells)); for i,c:=range cells { reversed[len(cells)-1-i]=c }; back:=make([]int,len(clue)); for i,n:=range clue { back[len(clue)-1-i]=n }; return Placements{cells,clue,fitTable(cells,clue),fitTable(reversed,back)} }
func (p Placements) Consistent() bool { return p.before[len(p.cells)][len(p.clue)] }
func (p Placements) Starts(block int) []int {
 starts:=[]int{}; n:=len(p.cells); length:=p.clue[block]
 for start:=0;start+length<=n;start++ { end:=start+length; possible:=true; for _,c:=range p.cells[start:end] { if c==Empty { possible=false; break } }; if !possible { continue }; left:=block==0; if start>0 { left=p.cells[start-1]!=Filled && p.before[start-1][block] }; rest:=len(p.clue)-block-1; right:=rest==0; if end<n { right=p.cells[end]!=Filled && p.after[n-end-1][rest] }; if left && right { starts=append(starts,start) } }; return starts
}
func hasPlacement(cells []Cell,clue []int) bool { return placements(cells,clue).Consistent() }
func solveLine(cells []Cell,clue []int,precise bool) []Cell {
 p:=placements(cells,clue); if !p.Consistent() { return nil }; solved:=append([]Cell(nil),cells...); filled:=make([]bool,len(cells)); covered:=make([]bool,len(cells))
 for block,length:=range clue { starts:=p.Starts(block); if precise { for _,start:=range starts { for i:=start;i<start+length;i++ { filled[i]=true } } } else { low,high:=starts[0],starts[len(starts)-1]; for i:=high;i<low+length;i++ { if solved[i]==Unknown { solved[i]=Filled } }; for i:=low;i<high+length;i++ { covered[i]=true } } }
 for i,c:=range cells { if c!=Unknown { continue }; if precise { emptiable:=false; for k:=0;k<=len(clue);k++ { if p.before[i][k] && p.after[len(cells)-i-1][len(clue)-k] { emptiable=true; break } }; if filled[i] && !emptiable { solved[i]=Filled } else if emptiable && !filled[i] { solved[i]=Empty } } else if solved[i]==Unknown && !covered[i] { solved[i]=Empty } }; return solved
}
