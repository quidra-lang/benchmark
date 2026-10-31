package main

import (
 "strconv"
 "strings"
)
func isClueLine(text string) bool { if text=="" { return false }; for _,c:=range []byte(text) { if c!=' ' && (c<'0' || c>'9') { return false } }; return true }
func parseClue(text string) ([]int,bool) {
 if text=="0" { return []int{},true }; clue:=[]int{}
 for _,token:=range strings.Split(text," ") { if len(token)<1 || len(token)>2 || token[0]=='0' { return nil,false }; for _,c:=range []byte(token) { if c<'0' || c>'9' { return nil,false } }; n,_:=strconv.Atoi(token); clue=append(clue,n) }; return clue,true
}
func runClue(cells []Cell) []int { clue:=[]int{}; run:=0; for _,cell:=range cells { if cell==Filled { run++ } else if run>0 { clue=append(clue,run); run=0 } }; if run>0 { clue=append(clue,run) }; return clue }
func clueText(clue []int,separator string) string { if len(clue)==0 { return "0" }; parts:=make([]string,len(clue)); for i,n:=range clue { parts[i]=strconv.Itoa(n) }; return strings.Join(parts,separator) }
func clueSpan(clue []int) int { sum:=len(clue)-1; for _,n:=range clue { sum+=n }; return sum }
func equalClue(a,b []int) bool { if len(a)!=len(b) { return false }; for i:=range a { if a[i]!=b[i] { return false } }; return true }
