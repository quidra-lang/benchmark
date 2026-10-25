package main

import "strings"

func matchPattern(pattern,words []string,groups map[string]map[string]bool) [][]string {
    ends:=make([]int,len(pattern))
    var visit func(int,int)bool
    visit=func(i,j int)bool {
        if i==len(pattern) { return j==len(words) }
        element:=pattern[i]
        if element=="*" { for end:=j;end<=len(words);end++ { ends[i]=end; if visit(i+1,end) { return true } }; return false }
        if j<len(words) && (element=="#" || element==words[j] || strings.HasPrefix(element,"@") && groups[element[1:]][words[j]]) { ends[i]=j+1; return visit(i+1,j+1) }
        return false
    }
    if !visit(0,0) { return nil }
    result:=make([][]string,0); start:=0
    for i,element:=range pattern { if isWildcard(element) { result=append(result,append([]string(nil),words[start:ends[i]]...)) }; start=ends[i] }
    return result
}
func patternCovers(earlier,later []string,groups map[string]map[string]bool) bool {
    fits:=func(element,other string)bool {
        if element=="#" { return other!="*" }
        if strings.HasPrefix(element,"@") {
            members:=groups[element[1:]]
            if strings.HasPrefix(other,"@") { for word:=range groups[other[1:]] { if !members[word] { return false } }; return true }
            return members[other]
        }
        return element==other
    }
    var visit func(int,int)bool
    visit=func(i,j int)bool {
        if i==len(earlier) { return j==len(later) }
        if earlier[i]=="*" { for end:=j;end<=len(later);end++ { if visit(i+1,end) { return true } }; return false }
        return j<len(later) && fits(earlier[i],later[j]) && visit(i+1,j+1)
    }
    return visit(0,0)
}
