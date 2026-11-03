package main

import (
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

var sourceNames=[]string{"keyword","memory","question","default","repeat"}
type Session struct {
    Name string
    Turns int
    Sources [5]int
    Previous string
    History, LastTrace []string
    TraceOn bool
    Topics, Words map[string]int
    Stored, Recalled int
    Unrecognized []int
    Undo *State
}
type State struct {
    Positions, Hits, ItemUses, KeywordUses, KeywordReplies []int
    ListPositions map[string]int
    Memory Memory
    Session *Session
}
type Bot struct { Script *Script; State *State; Transcript []string; TotalTurns, Sessions int; TotalSources [5]int }
type RuleEntry struct { Label string; Number int; Rule *Rule }

func cloneCounts(original map[string]int) map[string]int { result:=map[string]int{}; for key,value:=range original { result[key]=value }; return result }
func cloneState(original *State) *State {
    result:=*original
    result.Positions=append([]int(nil),original.Positions...); result.Hits=append([]int(nil),original.Hits...)
    result.ItemUses=append([]int(nil),original.ItemUses...); result.KeywordUses=append([]int(nil),original.KeywordUses...); result.KeywordReplies=append([]int(nil),original.KeywordReplies...)
    result.ListPositions=cloneCounts(original.ListPositions)
    result.Memory.Texts=append([]string(nil),original.Memory.Texts...); result.Memory.Log=append([]string(nil),original.Memory.Log...)
    if original.Session!=nil {
        session:=*original.Session; session.History=append([]string(nil),session.History...); session.LastTrace=append([]string(nil),session.LastTrace...)
        session.Topics=cloneCounts(session.Topics); session.Words=cloneCounts(session.Words); session.Unrecognized=append([]int(nil),session.Unrecognized...)
        if session.Undo!=nil { session.Undo=cloneState(session.Undo) }; result.Session=&session
    }
    return &result
}
func normalize(text string) [][]string {
    var clauses [][]string; var words []string; var word strings.Builder
    finishWord:=func() { value:=strings.Trim(word.String(),"'"); if value!="" { words=append(words,value) }; word.Reset() }
    for i:=0;i<=len(text);i++ {
        c:=byte('.'); if i<len(text) { c=text[i] }; if c>='A' && c<='Z' { c+=32 }
        if c>='a' && c<='z' || c>='0' && c<='9' || c=='\'' { word.WriteByte(c) } else {
            finishWord(); if strings.ContainsRune(",.?!;",rune(c)) && len(words)>0 { clauses=append(clauses,words); words=nil }
        }
    }
    return clauses
}
func flatten(clauses [][]string) []string { var words []string; for _,clause:=range clauses { words=append(words,clause...) }; return words }
func clauseKey(clauses [][]string) string { parts:=make([]string,len(clauses)); for i,clause:=range clauses { parts[i]=strings.Join(clause,"\x00") }; return strings.Join(parts,"\x01") }
func contains(words []string,word string) bool { for _,value:=range words { if word==value { return true } }; return false }
func ruleEntries(key *Keyword) []RuleEntry { var entries []RuleEntry; for i,rule:=range key.Memories { entries=append(entries,RuleEntry{"memory",i+1,rule}) }; for i,rule:=range key.Decomps { entries=append(entries,RuleEntry{"decomp",i+1,rule}) }; return entries }
func grouped(values []string,size int) []string { var lines []string; for i:=0;i<len(values);i+=size { end:=min(i+size,len(values)); lines=append(lines,strings.Join(values[i:end]," ")) }; return lines }
func numberList(values []int,separator string) string { result:=make([]string,len(values)); for i,value:=range values { result[i]=strconv.Itoa(value) }; return strings.Join(result,separator) }
func rankedCounts(counts map[string]int) string {
    var words []string; for word:=range counts { words=append(words,word) }
    sort.Slice(words,func(i,j int)bool { if counts[words[i]]!=counts[words[j]] { return counts[words[i]]>counts[words[j]] }; return words[i]<words[j] })
    var result []string; for _,word:=range words[:min(5,len(words))] { result=append(result,fmt.Sprintf("%s %d",word,counts[word])) }; if len(result)==0 { return "none" }; return strings.Join(result,", ")
}
func sourceLine(turns int,counts [5]int) string { result:=fmt.Sprintf("turns=%d",turns); for i,name:=range sourceNames { result+=fmt.Sprintf(" %s=%d",name,counts[i]) }; return result }
func newBot(script *Script) *Bot {
    state:=&State{Positions:make([]int,len(script.Rules)),Hits:make([]int,len(script.Rules)),ItemUses:make([]int,len(script.Items)),KeywordUses:make([]int,len(script.Keywords)),KeywordReplies:make([]int,len(script.Keywords)),ListPositions:map[string]int{},Memory:Memory{Capacity:script.Memsize}}
    return &Bot{Script:script,State:state}
}
func (b *Bot) prefix() string { return fmt.Sprintf("%s %d",b.State.Session.Name,b.State.Session.Turns) }
func (b *Bot) reset() { for i:=range b.State.Positions { b.State.Positions[i]=0 }; b.State.ListPositions=map[string]int{} }
func (b *Bot) takeText(name string) string { position:=b.State.ListPositions[name]; b.State.ListPositions[name]=(position+1)%len(b.Script.Texts[name]); return b.Script.Texts[name][position] }
func (b *Bot) takeItem(rule *Rule) (*Item,int) { position:=b.State.Positions[rule.Index]; item:=rule.Items[position]; b.State.Positions[rule.Index]=(position+1)%len(rule.Items); b.State.ItemUses[item.Index]++; return item,position+1 }
func (b *Bot) prepared(text string) [][]string { clauses:=normalize(text); for i,clause:=range clauses { var words []string; for _,word:=range clause { if replacement,ok:=b.Script.Pre[word];ok { words=append(words,replacement...) } else { words=append(words,word) } }; clauses[i]=words }; return clauses }
func (b *Bot) isQuit(text string) bool { words:=flatten(normalize(text)); return len(words)==1 && b.Script.Quit[words[0]] }
func (b *Bot) selected(clauses [][]string) (int,[]string) { for i,clause:=range clauses { for _,word:=range clause { if b.Script.KeywordMap[word]!=nil { return i+1,clause } } }; return 0,nil }
func (b *Bot) keywordList(words []string) []*Keyword {
    var keys []*Keyword; seen:=map[string]int{}
    for _,word:=range words { if b.Script.KeywordMap[word]!=nil && seen[word]==0 { keys=append(keys,b.Script.KeywordMap[word]); seen[word]=len(keys) } }
    sort.Slice(keys,func(i,j int)bool { if keys[i].Rank!=keys[j].Rank { return keys[i].Rank>keys[j].Rank }; return seen[keys[i].Word]<seen[keys[j].Word] }); return keys
}
func (b *Bot) findRule(rules []*Rule,words []string) (*Rule,int,[][]string) { for i,rule:=range rules { bindings:=matchPattern(rule.Pattern,words,b.Script.GroupWords); if bindings!=nil { return rule,i+1,bindings } }; return nil,0,nil }
func (b *Bot) keywordReply(clauses [][]string,trace *[]string) (string,bool) {
    number,words:=b.selected(clauses); if number==0 { *trace=append(*trace,"CLAUSE none"); return "",false }
    *trace=append(*trace,fmt.Sprintf("CLAUSE %d %s",number,strings.Join(words," ")))
    keys:=b.keywordList(words); var names []string; for _,key:=range keys { names=append(names,key.Word) }; *trace=append(*trace,"KEYS "+strings.Join(names," "))
    rule,n,bindings:=b.findRule(keys[0].Memories,words)
    if rule!=nil {
        *trace=append(*trace,fmt.Sprintf("MEMORY %s %d",keys[0].Word,n)); b.State.Hits[rule.Index]++
        if len(rule.Items)>0 { item,_:=b.takeItem(rule); text:=buildReply(item.Text,bindings,b.Script.Post); if b.State.Memory.store(b.prefix(),keys[0].Word,text) { b.State.Session.Stored++ } }
    }
    entered:=map[string]bool{}
    for _,initial:=range keys { if entered[initial.Word] { continue }; *trace=append(*trace,"ENTER "+initial.Word); key,current:=initial,words
        for {
            entered[key.Word]=true; b.State.KeywordUses[key.Index]++
            rule,n,bindings=b.findRule(key.Decomps,current)
            if rule==nil { *trace=append(*trace,"NOMATCH "+key.Word); break }
            b.State.Hits[rule.Index]++
            if len(rule.Items)==0 { *trace=append(*trace,fmt.Sprintf("DECOMP %s %d 0",key.Word,n)); break }
            item,position:=b.takeItem(rule); *trace=append(*trace,fmt.Sprintf("DECOMP %s %d %d",key.Word,n,position))
            if item.Kind=="REASM" { b.State.KeywordReplies[key.Index]++; b.State.Session.Topics[key.Word]++; return buildReply(item.Text,bindings,b.Script.Post),true }
            if item.Kind=="NEWKEY" { break }; target:=item.Args[0]
            if b.Script.KeywordMap[target]==nil || entered[target] { *trace=append(*trace,"BLOCKED "+target); break }
            if item.Kind=="RESTATE" { current=restatedWords(item.Args,bindings); line:="RESTATE "+target; if len(current)>0 { line+=" "+strings.Join(current," ") }; *trace=append(*trace,line) } else { *trace=append(*trace,"GOTO "+target) }
            key=b.Script.KeywordMap[target]
        }
    }
    return "",false
}
func (b *Bot) decide(text string) (string,[]string) {
    session:=b.State.Session; clauses:=normalize(text); var trace []string; reply:=""; source:=0
    if len(b.Script.Texts["REPEAT"])>0 && len(clauses)>0 && clauseKey(clauses)==session.Previous { trace=append(trace,"REPEAT"); reply=b.takeText("REPEAT"); source=4
    } else {
        var found bool; reply,found=b.keywordReply(b.prepared(text),&trace)
        if !found {
            if len(b.State.Memory.Texts)>0 { reply=b.State.Memory.recall(b.prefix()); source=1; session.Recalled++
            } else if strings.HasSuffix(text,"?") && len(b.Script.Texts["QUESTION"])>0 { reply=b.takeText("QUESTION"); source=2
            } else { reply=b.takeText("DEFAULT"); source=3 }
        }
    }
    trace=append(trace,"REPLY "+sourceNames[source]); session.Previous=clauseKey(clauses); session.Sources[source]++
    if source==2 || source==3 { session.Unrecognized=append(session.Unrecognized,session.Turns) }; return reply,trace
}
func (b *Bot) command(line string) []string {
    name,text,_:=strings.Cut(line," "); args:=strings.Fields(text)
    noArgs:=contains([]string{":keys",":why",":history",":memory",":forget",":reset",":unused",":stats",":undo"},name)
    oneArg:=contains([]string{":groups",":find",":script",":cycles",":coverage"},name)
    textArg:=contains([]string{":prepare",":reflect",":say",":explain"},name)
    if !noArgs && !oneArg && !textArg && name!=":trace" && name!=":test" { return []string{"unknown command "+name} }
    if noArgs && len(args)>0 || oneArg && len(args)!=1 || textArg && text=="" || name==":test" && len(args)<2 || name==":trace" && (len(args)!=1 || args[0]!="on" && args[0]!="off") { return []string{"bad arguments"} }
    if contains([]string{":script",":cycles",":coverage",":test"},name) && b.Script.KeywordMap[args[0]]==nil { return []string{"unknown keyword "+args[0]} }
    var result []string; session:=b.State.Session
    switch name {
    case ":prepare":
        clauses:=b.prepared(text); for i,clause:=range clauses { result=append(result,fmt.Sprintf("clause %d: %s",i+1,strings.Join(clause," "))) }; if len(clauses)==0 { result=append(result,"no words") }
        number,words:=b.selected(clauses); if number==0 { result=append(result,"selected none") } else { result=append(result,fmt.Sprintf("selected %d",number)); var labels []string; for _,key:=range b.keywordList(words) { labels=append(labels,fmt.Sprintf("%s/%d",key.Word,key.Rank)) }; result=append(result,"keys "+strings.Join(labels," ")) }
    case ":test":
        _,body,_:=strings.Cut(text," "); words:=flatten(b.prepared(body))
        for _,entry:=range ruleEntries(b.Script.KeywordMap[args[0]]) { bindings:=matchPattern(entry.Rule.Pattern,words,b.Script.GroupWords); value:="no match"; if bindings!=nil { var parts []string; for _,bound:=range bindings { parts=append(parts,"["+strings.Join(bound," ")+"]") }; value=strings.Join(parts," "); if len(parts)==0 { value="match" } }; result=append(result,fmt.Sprintf("%s %d: %s",entry.Label,entry.Number,value)) }; if len(result)==0 { result=[]string{"no rules"} }
    case ":reflect": for _,clause:=range b.prepared(text) { result=append(result,strings.Join(reflect(clause,b.Script.Post)," ")) }; if len(result)==0 { result=[]string{"no words"} }
    case ":keys": keys:=append([]*Keyword(nil),b.Script.Keywords...); sort.Slice(keys,func(i,j int)bool { if keys[i].Rank!=keys[j].Rank { return keys[i].Rank>keys[j].Rank }; return keys[i].Word<keys[j].Word }); var labels []string; for _,key:=range keys { labels=append(labels,fmt.Sprintf("%s/%d",key.Word,key.Rank)) }; result=grouped(labels,8)
    case ":groups": for _,group:=range b.Script.Groups { if group.Members[args[0]] { result=append(result,group.Name) } }; sort.Strings(result); if len(result)==0 { result=[]string{"none"} } else { result=[]string{strings.Join(result," ")} }
    case ":find":
        word:=args[0]; if key:=b.Script.KeywordMap[word];key!=nil { result=append(result,fmt.Sprintf("keyword rank %d",key.Rank)) }
        for _,kind:=range []string{"pre","post"} { subs:=b.Script.Pres; if kind=="post" { subs=b.Script.Posts }; for _,sub:=range subs { if sub.Source==word || contains(sub.Replacement,word) { result=append(result,fmt.Sprintf("%s %d: %s -> %s",kind,sub.Line,sub.Source,strings.Join(sub.Replacement," "))) } } }
        for _,group:=range b.Script.Groups { if group.Members[word] { result=append(result,fmt.Sprintf("group %s line %d",group.Name,group.Line)) } }
        for _,key:=range b.Script.Keywords { for _,entry:=range ruleEntries(key) { if contains(entry.Rule.Pattern,word) { result=append(result,fmt.Sprintf("pattern %s %s %d",key.Word,entry.Label,entry.Number)) } } }
        if b.Script.Stop[word] { result=append(result,"stop word") }; if b.Script.Quit[word] { result=append(result,"quit word") }; if len(result)==0 { result=[]string{"not found"} }
    case ":script": key:=b.Script.KeywordMap[args[0]]; numbers:=[]int{key.Line}; for _,entry:=range ruleEntries(key) { numbers=append(numbers,entry.Rule.Line); for _,item:=range entry.Rule.Items { numbers=append(numbers,item.Line) } }; sort.Ints(numbers); for _,number:=range numbers { result=append(result,fmt.Sprintf("%d %s",number,b.Script.Lines[number-1])) }
    case ":why": result=append(result,session.LastTrace...); if session.LastTrace==nil { result=[]string{"no reply yet"} }
    case ":trace": session.TraceOn=args[0]=="on"; result=[]string{"trace "+args[0]}
    case ":history": result=append(result,session.History[max(0,len(session.History)-5):]...); if len(result)==0 { result=[]string{"no turns yet"} }
    case ":memory": result=append(result,fmt.Sprintf("memory %d/%d",len(b.State.Memory.Texts),b.State.Memory.Capacity)); for i,text:=range b.State.Memory.Texts { result=append(result,fmt.Sprintf("%d: %s",i+1,text)) }
    case ":forget": count:=len(b.State.Memory.Texts); b.State.Memory.clear(b.prefix()); result=[]string{fmt.Sprintf("forgot %d",count)}
    case ":cycles",":coverage":
        for _,entry:=range ruleEntries(b.Script.KeywordMap[args[0]]) {
            rule:=entry.Rule; prefix:=fmt.Sprintf("%s %d: ",entry.Label,entry.Number)
            if name==":cycles" { if len(rule.Items)==0 { result=append(result,prefix+"empty") } else { result=append(result,fmt.Sprintf("%snext %d/%d",prefix,b.State.Positions[rule.Index]+1,len(rule.Items))) }
            } else { var uses []int; for _,item:=range rule.Items { uses=append(uses,b.State.ItemUses[item.Index]) }; values:=numberList(uses," "); if len(uses)==0 { values="-" }; result=append(result,fmt.Sprintf("%shits %d entries %s",prefix,b.State.Hits[rule.Index],values)) }
        }; if len(result)==0 { result=[]string{"no rules"} }
    case ":reset": b.reset(); result=[]string{"cycles reset"}
    case ":unused": var numbers []int; for _,item:=range b.Script.Items { if b.State.ItemUses[item.Index]==0 { numbers=append(numbers,item.Line) } }; sort.Ints(numbers); result=[]string{fmt.Sprintf("unused %d",len(numbers))}; values:=make([]string,len(numbers)); for i,n:=range numbers { values[i]=strconv.Itoa(n) }; result=append(result,grouped(values,12)...)
    case ":stats": result=[]string{sourceLine(session.Turns,session.Sources)}
    case ":say",":explain": if b.isQuit(text) { result=[]string{"would quit"} } else { saved:=cloneState(b.State); reply,trace:=b.decide(text); b.State=saved; if name==":say" { result=[]string{reply} } else { result=trace } }
    case ":undo": if session.Undo==nil { result=[]string{"nothing to undo"} } else { b.State=session.Undo; result=[]string{fmt.Sprintf("undone turn %d",b.State.Session.Turns+1)} }
    }
    return result
}
func (b *Bot) indented(lines []string) { for _,line:=range lines { b.Transcript=append(b.Transcript,"  "+line) } }
func (b *Bot) notes() {
    session:=b.State.Session; b.Transcript=append(b.Transcript,"NOTES "+session.Name)
    unrecognized:=numberList(session.Unrecognized," "); if unrecognized=="" { unrecognized="none" }
    b.indented([]string{sourceLine(session.Turns,session.Sources),"topics: "+rankedCounts(session.Topics),"words: "+rankedCounts(session.Words),fmt.Sprintf("memory: stored=%d recalled=%d pending=%d",session.Stored,session.Recalled,len(b.State.Memory.Texts)),"unrecognized: "+unrecognized})
    b.TotalTurns+=session.Turns; for i,value:=range session.Sources { b.TotalSources[i]+=value }
}
func (b *Bot) run(lines []string) {
    for _,line:=range lines {
        if strings.HasPrefix(line,"SESSION ") {
            b.Sessions++; name:=line[8:]
            if b.Sessions>1 { b.Transcript=append(b.Transcript,""); if !b.Script.Persist["cycles"] { b.reset() }; if !b.Script.Persist["memory"] { b.State.Memory.clear(name+" 0") } }
            b.State.Session=&Session{Name:name,Topics:map[string]int{},Words:map[string]int{}}
            b.Transcript=append(b.Transcript,line); b.Transcript=append(b.Transcript,elizaLines(b.Script.Texts["INITIAL"][(b.Sessions-1)%len(b.Script.Texts["INITIAL"])])...)
        } else if strings.HasPrefix(line,":") { b.Transcript=append(b.Transcript,line); b.indented(b.command(line))
        } else {
            b.Transcript=append(b.Transcript,"YOU: "+line)
            if b.isQuit(line) { b.Transcript=append(b.Transcript,elizaLines(b.Script.Texts["FINAL"][(b.Sessions-1)%len(b.Script.Texts["FINAL"])])...); b.notes(); continue }
            snapshot:=cloneState(b.State); snapshot.Session.Undo=nil; session:=b.State.Session; session.Undo=snapshot; session.Turns++
            for _,word:=range flatten(normalize(line)) { if !b.Script.Stop[word] { session.Words[word]++ } }; session.History=append(session.History,fmt.Sprintf("%d: %s",session.Turns,line))
            reply,trace:=b.decide(line); b.Transcript=append(b.Transcript,elizaLines(reply)...); session.LastTrace=trace; if session.TraceOn { b.indented(trace) }
        }
    }
    b.Transcript=append(b.Transcript,"",fmt.Sprintf("SUMMARY sessions=%d %s",b.Sessions,sourceLine(b.TotalTurns,b.TotalSources)))
}
func (b *Bot) statistics() []string {
    keys:=append([]*Keyword(nil),b.Script.Keywords...); sort.Slice(keys,func(i,j int)bool { a,c:=b.State.KeywordUses[keys[i].Index],b.State.KeywordUses[keys[j].Index]; if a!=c { return a>c }; return keys[i].Word<keys[j].Word })
    lines:=[]string{"keyword,rank,uses,replies,decomposition_hits"}
    for _,key:=range keys { var hits []int; for _,rule:=range key.Decomps { hits=append(hits,b.State.Hits[rule.Index]) }; value:=numberList(hits,"/"); if len(hits)==0 { value="-" }; lines=append(lines,fmt.Sprintf("%s,%d,%d,%d,%s",key.Word,key.Rank,b.State.KeywordUses[key.Index],b.State.KeywordReplies[key.Index],value)) }; return lines
}
func writeLines(path string,lines []string) { text:=""; if len(lines)>0 { text=strings.Join(lines,"\n")+"\n" }; if err:=os.WriteFile(path,[]byte(text),0644);err!=nil { panic(err) } }
func main() {
    script:=loadScript("input/script.txt"); if err:=os.MkdirAll("output",0755);err!=nil { panic(err) }; writeLines("output/lint.txt",lintScript(script))
    bot:=newBot(script); bot.run(readLines("input/dialogue.txt")); writeLines("output/transcript.txt",bot.Transcript); writeLines("output/keyword_stats.csv",bot.statistics()); writeLines("output/memory_log.txt",bot.State.Memory.Log)
}
