package main

import "strings"

func stateChar(state Cell) byte { return "?#."[state] }
func charState(c byte) Cell { if c=='#' { return Filled }; if c=='.' { return Empty }; return Unknown }
func stateString(cells []Cell) string { text:=make([]byte,len(cells)); for i,c:=range cells { text[i]=stateChar(c) }; return string(text) }
func gridDisplay(names []string,grids []Grid) []string { lines:=[]string{"grid "+strings.Join(names," ")}; for r:=range grids[0] { parts:=make([]string,len(grids)); for i,g:=range grids { parts[i]=stateString(g[r]) }; lines=append(lines,strings.Join(parts," | ")) }; return lines }
func answerSheet(rows,columns [][]int,grid Grid) []string {
 tokens:=make([][]string,len(columns)); width,depth,margin:=0,0,0
 for c,clue:=range columns { tokens[c]=strings.Split(clueText(clue," ")," "); depth=max(depth,len(tokens[c])); for _,token:=range tokens[c] { width=max(width,len(token)+1) } }; for _,clue:=range rows { margin=max(margin,len(clueText(clue," "))) }; lines:=[]string{}
 for t:=0;t<depth;t++ { line:=strings.Repeat(" ",margin); for _,column:=range tokens { token:=""; skipped:=depth-len(column); if t>=skipped { token=column[t-skipped] }; line+=strings.Repeat(" ",width-len(token))+token }; lines=append(lines,strings.TrimRight(line," ")) }
 for r,clue:=range rows { text:=clueText(clue," "); line:=strings.Repeat(" ",margin-len(text))+text; for _,state:=range grid[r] { line+=strings.Repeat(" ",width-1)+string(stateChar(state)) }; lines=append(lines,line) }; return lines
}
