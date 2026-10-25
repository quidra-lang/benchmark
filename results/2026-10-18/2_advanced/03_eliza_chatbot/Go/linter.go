package main

import (
    "fmt"
    "sort"
    "strings"
)

func lintScript(s *Script) []string {
    codes:=[]string{"SYNTAX","ORPHAN","DUPLICATE","KEY_NO_DECOMP","KEY_UNREACHABLE","SYNON_UNUSED","PRE_CHAIN","SYNON_UNKNOWN","RULE_NO_REASM","RULE_SHADOWED","REF_UNBOUND","TARGET_UNDEFINED","TARGET_CYCLE"}
    order:=map[string]int{}; for i,code:=range codes { order[code]=i }
    errors:=map[string]bool{"SYNTAX":true,"ORPHAN":true,"DUPLICATE":true,"SYNON_UNKNOWN":true,"REF_UNBOUND":true,"TARGET_UNDEFINED":true,"TARGET_CYCLE":true}
    found:=append([]Diagnostic(nil),s.Diagnostics...)
    add:=func(line int,code,message string) { found=append(found,Diagnostic{Line:line,Code:code,Message:message}) }
    replacements,targets,used:=map[string]bool{},map[string]bool{},map[string]bool{}
    for _,pre:=range s.Pres { for _,word:=range pre.Replacement { replacements[word]=true } }
    for _,item:=range s.Items { if item.Kind=="GOTO" || item.Kind=="RESTATE" { targets[item.Args[0]]=true } }
    for _,rule:=range s.Rules { for _,element:=range rule.Pattern { if strings.HasPrefix(element,"@") { used[element[1:]]=true } } }
    graph:=map[string][]string{}
    for _,keyword:=range s.Keywords {
        word:=keyword.Word
        if len(keyword.Decomps)==0 { add(keyword.Line,"KEY_NO_DECOMP","keyword "+word+" has no DECOMP") }
        if _,ok:=s.Pre[word];ok && !replacements[word] && !targets[word] { add(keyword.Line,"KEY_UNREACHABLE","keyword "+word+" is replaced by PRE") }
        for _,rule:=range keyword.Decomps { for _,item:=range rule.Items { if (item.Kind=="GOTO" || item.Kind=="RESTATE") && s.KeywordMap[item.Args[0]]!=nil { graph[word]=append(graph[word],item.Args[0]) } } }
    }
    for _,group:=range s.Groups { if !used[group.Name] { add(group.Line,"SYNON_UNUSED","group "+group.Name+" is never used") } }
    for _,pre:=range s.Pres { for _,word:=range pre.Replacement { if _,ok:=s.Pre[word];ok { add(pre.Line,"PRE_CHAIN","replacement "+word+" is itself replaced by PRE") } } }
    unknown:=func(rule *Rule) []string { var result []string; for _,element:=range rule.Pattern { if strings.HasPrefix(element,"@") && s.GroupWords[element[1:]]==nil { result=append(result,element[1:]) } }; return result }
    var reaches func(string,string,map[string]bool)bool
    reaches=func(start,goal string,seen map[string]bool)bool { if start==goal { return true }; if seen[start] { return false }; seen[start]=true; for _,target:=range graph[start] { if reaches(target,goal,seen) { return true } }; return false }
    for _,keyword:=range s.Keywords { for _,rules:=range [][]*Rule{keyword.Memories,keyword.Decomps} { for i,rule:=range rules {
        missing:=unknown(rule); for _,name:=range missing { add(rule.Line,"SYNON_UNKNOWN","unknown group "+name) }
        if len(rule.Items)==0 { add(rule.Line,"RULE_NO_REASM","rule has no reassembly") }
        if len(missing)==0 { for _,earlier:=range rules[:i] { if len(unknown(earlier))==0 && patternCovers(earlier.Pattern,rule.Pattern,s.GroupWords) { add(rule.Line,"RULE_SHADOWED",fmt.Sprintf("pattern is shadowed by line %d",earlier.Line)); break } } }
        count:=0; for _,element:=range rule.Pattern { if isWildcard(element) { count++ } }
        for _,item:=range rule.Items {
            var references []int
            if item.Kind=="REASM" { for j:=0;j+3<=len(item.Text);j++ { if isReference(item.Text[j:j+3]) { references=append(references,int(item.Text[j+1]-'0')) } }
            } else if item.Kind=="RESTATE" { for _,arg:=range item.Args[1:] { if isReference(arg) { references=append(references,int(arg[1]-'0')) } } }
            for _,number:=range references { if number==0 || number>count { add(item.Line,"REF_UNBOUND",fmt.Sprintf("reference (%d) is not bound",number)) } }
            if item.Kind=="GOTO" || item.Kind=="RESTATE" { target:=item.Args[0]; if s.KeywordMap[target]==nil { add(item.Line,"TARGET_UNDEFINED","target "+target+" is not a keyword") } else if reaches(target,keyword.Word,map[string]bool{}) { add(item.Line,"TARGET_CYCLE","edge "+keyword.Word+" -> "+target+" is on a cycle") } }
        }
    } } }
    sort.SliceStable(found,func(i,j int)bool { if found[i].Line!=found[j].Line { return found[i].Line<found[j].Line }; return order[found[i].Code]<order[found[j].Code] })
    if len(found)==0 { return []string{"OK"} }
    var lines []string; count:=0
    for _,d:=range found { lines=append(lines,fmt.Sprintf("%d %s %s",d.Line,d.Code,d.Message)); if errors[d.Code] { count++ } }
    return append(lines,fmt.Sprintf("TOTAL %d errors=%d warnings=%d",len(found),count,len(found)-count))
}
