package main

import "strings"

func reflect(words []string,post map[string][]string) []string {
    var result []string
    for _,word:=range words { if replacement,ok:=post[word];ok { result=append(result,replacement...) } else { result=append(result,word) } }
    return result
}
func binding(bindings [][]string,number int) []string { if number>=1 && number<=len(bindings) { return bindings[number-1] }; return nil }
func buildReply(text string,bindings [][]string,post map[string][]string) string {
    var result strings.Builder
    for i:=0;i<len(text); {
        if i+3<=len(text) && isReference(text[i:i+3]) { result.WriteString(strings.Join(reflect(binding(bindings,int(text[i+1]-'0')),post)," ")); i+=3
        } else { result.WriteByte(text[i]); i++ }
    }
    reply:=strings.Join(strings.Fields(result.String())," ")
    if len(reply)>0 && reply[0]>='a' && reply[0]<='z' { reply=string(reply[0]-32)+reply[1:] }
    return reply
}
func restatedWords(args []string,bindings [][]string) []string {
    var words []string
    for _,arg:=range args[1:] { if isReference(arg) { words=append(words,binding(bindings,int(arg[1]-'0'))...) } else { words=append(words,arg) } }
    return words
}
func elizaLines(text string) []string {
    words:=strings.Fields(text); line:="ELIZA: "+words[0]; var lines []string
    for _,word:=range words[1:] { if len(line)+1+len(word)<=72 { line+=" "+word } else { lines=append(lines,line); line="       "+word } }
    return append(lines,line)
}
