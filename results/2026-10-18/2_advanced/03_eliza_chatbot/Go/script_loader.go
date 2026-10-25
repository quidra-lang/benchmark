package main

import (
    "fmt"
    "os"
    "strconv"
    "strings"
)

type Diagnostic struct { Line int; Code, Message string; Order int }
type Substitution struct { Source string; Replacement []string; Line int }
type Group struct { Name string; Members map[string]bool; Line int }
type Item struct { Kind, Text string; Args []string; Line, Index int }
type Rule struct { Kind string; Pattern []string; Line, Index int; Items []*Item }
type Keyword struct { Word string; Rank, Line, Index int; Memories, Decomps []*Rule }
type Script struct {
    Lines []string
    Texts map[string][]string
    Quit, Stop, Persist map[string]bool
    Memsize int
    Pres, Posts []Substitution
    Pre, Post map[string][]string
    Groups []Group
    GroupWords map[string]map[string]bool
    Keywords []*Keyword
    KeywordMap map[string]*Keyword
    Rules []*Rule
    Items []*Item
    Diagnostics []Diagnostic
}

var textDirectives = map[string]bool{"INITIAL":true,"FINAL":true,"DEFAULT":true,"QUESTION":true,"REPEAT":true}
var globalDirectives = map[string]bool{"INITIAL":true,"FINAL":true,"DEFAULT":true,"QUESTION":true,"REPEAT":true,"QUIT":true,"STOP":true,"MEMSIZE":true,"PERSIST":true,"PRE":true,"POST":true,"SYNON":true}
var ruleDirectives = map[string]bool{"DECOMP":true,"MEMORY":true}
var itemDirectives = map[string]bool{"REASM":true,"GOTO":true,"NEWKEY":true,"RESTATE":true}

func readLines(path string) []string {
    data, err := os.ReadFile(path); if err != nil { panic(err) }
    return strings.Split(strings.TrimSuffix(string(data),"\n"),"\n")
}
func isWord(text string) bool {
    if text == "" || text[0] == '\'' || text[len(text)-1] == '\'' { return false }
    for i:=0;i<len(text);i++ { c:=text[i]; if !(c>='a' && c<='z' || c>='0' && c<='9' || c=='\'') { return false } }
    return true
}
func isReference(text string) bool { return len(text)==3 && text[0]=='(' && text[1]>='0' && text[1]<='9' && text[2]==')' }
func isWildcard(text string) bool { return text=="*" || text=="#" || strings.HasPrefix(text,"@") }
func isNumber(text string) bool {
    if len(text)<1 || len(text)>2 { return false }; for i:=range text { if text[i]<'0' || text[i]>'9' { return false } }; return true
}
func every(words []string, predicate func(string)bool) bool { for _,word:=range words { if !predicate(word) { return false } }; return true }
func wellFormed(name string,args []string) bool {
    n:=len(args)
    if textDirectives[name] || name=="REASM" { return n>=1 }
    switch name {
    case "QUIT","STOP": return n>=1 && every(args,isWord)
    case "MEMSIZE": if n!=1 || !isNumber(args[0]) { return false }; value,_:=strconv.Atoi(args[0]); return value>=1 && value<=20
    case "PERSIST": return n==1 && (args[0]=="cycles" || args[0]=="memory")
    case "PRE","SYNON": return n>=2 && every(args,isWord)
    case "POST": return n>=2 && isWord(args[0])
    case "KEY": return n==2 && isWord(args[0]) && isNumber(args[1])
    case "DECOMP","MEMORY": return n>=1 && every(args,func(x string)bool { return x=="*" || x=="#" || strings.HasPrefix(x,"@") && isWord(x[1:]) || isWord(x) })
    case "GOTO": return n==1 && isWord(args[0])
    case "NEWKEY": return n==0
    case "RESTATE": return n>=2 && isWord(args[0]) && every(args[1:],func(x string)bool { return isWord(x) || isReference(x) })
    }
    return false
}
func loadScript(path string) *Script {
    s:=&Script{Lines:readLines(path),Texts:map[string][]string{},Quit:map[string]bool{},Stop:map[string]bool{},Persist:map[string]bool{},Memsize:3,Pre:map[string][]string{},Post:map[string][]string{},GroupWords:map[string]map[string]bool{},KeywordMap:map[string]*Keyword{}}
    definitions:=map[string]int{}; var keyword *Keyword; var rule *Rule; ignoring:=false
    for i,line:=range s.Lines {
        number:=i+1; if line=="" || strings.HasPrefix(line,"#") { continue }
        name,text,_:=strings.Cut(line," "); args:=strings.Fields(text)
        if globalDirectives[name] || name=="KEY" { keyword=nil; rule=nil; ignoring=false
        } else if ruleDirectives[name] || itemDirectives[name] { if ignoring { continue }; if ruleDirectives[name] { rule=nil } }
        definition:=""; if name=="MEMSIZE" { definition=name } else if name=="KEY" || name=="PRE" || name=="POST" || name=="SYNON" || name=="PERSIST" { if len(args)>0 { definition=name+" "+args[0] } }
        code,message:="",""
        switch {
        case !globalDirectives[name] && name!="KEY" && !ruleDirectives[name] && !itemDirectives[name]: code,message="SYNTAX","unknown directive "+name
        case !wellFormed(name,args): code,message="SYNTAX","bad arguments for "+name
        case ruleDirectives[name] && keyword==nil: code,message="ORPHAN",name+" without KEY"
        case name=="REASM" && rule==nil: code,message="ORPHAN","REASM without DECOMP or MEMORY"
        case (name=="GOTO" || name=="NEWKEY" || name=="RESTATE") && (rule==nil || rule.Kind=="MEMORY"): code,message="ORPHAN",name+" without DECOMP"
        case definition!="" && definitions[definition]>0:
            code,message="DUPLICATE",fmt.Sprintf("%s first defined at line %d",definition,definitions[definition]); if name=="KEY" { ignoring=true }
        }
        if code!="" { s.Diagnostics=append(s.Diagnostics,Diagnostic{Line:number,Code:code,Message:message}); continue }
        if definition!="" { definitions[definition]=number }
        if textDirectives[name] { s.Texts[name]=append(s.Texts[name],text); continue }
        switch name {
        case "QUIT","STOP": destination:=s.Quit; if name=="STOP" { destination=s.Stop }; for _,word:=range args { destination[word]=true }
        case "MEMSIZE": s.Memsize,_=strconv.Atoi(args[0])
        case "PERSIST": s.Persist[args[0]]=true
        case "PRE","POST":
            substitution:=Substitution{args[0],args[1:],number}
            if name=="PRE" { s.Pres=append(s.Pres,substitution); s.Pre[args[0]]=args[1:] } else { s.Posts=append(s.Posts,substitution); s.Post[args[0]]=args[1:] }
        case "SYNON": members:=map[string]bool{}; for _,word:=range args { members[word]=true }; s.Groups=append(s.Groups,Group{args[0],members,number}); s.GroupWords[args[0]]=members
        case "KEY": rank,_:=strconv.Atoi(args[1]); keyword=&Keyword{Word:args[0],Rank:rank,Line:number,Index:len(s.Keywords)}; s.Keywords=append(s.Keywords,keyword); s.KeywordMap[keyword.Word]=keyword
        case "DECOMP","MEMORY": rule=&Rule{Kind:name,Pattern:args,Line:number,Index:len(s.Rules)}; s.Rules=append(s.Rules,rule); if name=="MEMORY" { keyword.Memories=append(keyword.Memories,rule) } else { keyword.Decomps=append(keyword.Decomps,rule) }
        default: item:=&Item{Kind:name,Text:text,Args:args,Line:number,Index:len(s.Items)}; s.Items=append(s.Items,item); rule.Items=append(rule.Items,item)
        }
    }
    return s
}
