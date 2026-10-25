package main

import "fmt"

type Memory struct { Capacity int; Texts, Log []string }
func (m *Memory) store(prefix,keyword,text string) bool {
    for _,stored:=range m.Texts { if stored==text { m.Log=append(m.Log,prefix+" SKIP "+keyword+" "+text); return false } }
    if len(m.Texts)==m.Capacity { m.Log=append(m.Log,prefix+" DROP "+m.Texts[0]); m.Texts=m.Texts[1:] }
    m.Texts=append(m.Texts,text); m.Log=append(m.Log,prefix+" STORE "+keyword+" "+text); return true
}
func (m *Memory) recall(prefix string) string { text:=m.Texts[0]; m.Texts=m.Texts[1:]; m.Log=append(m.Log,prefix+" RECALL "+text); return text }
func (m *Memory) clear(prefix string) { if len(m.Texts)>0 { m.Log=append(m.Log,fmt.Sprintf("%s CLEAR %d",prefix,len(m.Texts))); m.Texts=nil } }
