package main

import "sort"

type Pattern struct { Items []int; Weight int64 }
type FPNode struct { Item int; Count int64; Parent *FPNode; Children map[int]*FPNode }
type FPTree struct { Header []int; Root *FPNode; Links map[int][]*FPNode; Nodes int }
type Growth struct { Header,Nodes,Trees,ConditionalNodes int; Entries []Entry }
func buildTree(base []Pattern,minimum int64) *FPTree {
 supports:=map[int]int64{};for _,p:=range base {for _,i:=range p.Items {supports[i]+=p.Weight}}
 tree:=&FPTree{Root:&FPNode{Item:-1,Children:map[int]*FPNode{}},Links:map[int][]*FPNode{}}
 for i,count:=range supports {if count>=minimum {tree.Header=append(tree.Header,i)}};sort.Slice(tree.Header,func(a,b int)bool{x,y:=tree.Header[a],tree.Header[b];if supports[x]!=supports[y] {return supports[x]>supports[y]};return x<y});order:=map[int]int{};for j,i:=range tree.Header {order[i]=j}
 for _,p:=range base {var path []int;for _,i:=range p.Items {if _,ok:=order[i];ok {path=append(path,i)}};sort.Slice(path,func(i,j int)bool{return order[path[i]]<order[path[j]]});node:=tree.Root
  for _,i:=range path {child:=node.Children[i];if child==nil {child=&FPNode{Item:i,Parent:node,Children:map[int]*FPNode{}};node.Children[i]=child;tree.Links[i]=append(tree.Links[i],child);tree.Nodes++};child.Count+=p.Weight;node=child}
 };return tree
}
func (t *FPTree) conditional(item int) []Pattern {var base []Pattern;for _,node:=range t.Links[item] {var path []int;for ancestor:=node.Parent;ancestor!=t.Root;ancestor=ancestor.Parent {path=append(path,ancestor.Item)};for i,j:=0,len(path)-1;i<j;i,j=i+1,j-1 {path[i],path[j]=path[j],path[i]};base=append(base,Pattern{path,node.Count})};return base}
func fpGrowth(baskets []*Basket,taxonomy map[int]int,minimum int64,maxSize int) Growth {
 var base []Pattern;for _,b:=range baskets {base=append(base,Pattern{b.items(taxonomy,false),1})};tree:=buildTree(base,minimum);r:=Growth{Header:len(tree.Header),Nodes:tree.Nodes}
 type Frame struct {Tree *FPTree;Suffix []int};stack:=[]Frame{{tree,nil}}
 for len(stack)>0 {frame:=stack[len(stack)-1];stack=stack[:len(stack)-1];for j:=len(frame.Tree.Header)-1;j>=0;j-- {item:=frame.Tree.Header[j];set:=union(frame.Suffix,[]int{item});var count int64;for _,node:=range frame.Tree.Links[item] {count+=node.Count};r.Entries=append(r.Entries,Entry{set,count});if len(set)<maxSize {conditional:=buildTree(frame.Tree.conditional(item),minimum);if conditional.Nodes>0 {stack=append(stack,Frame{conditional,set});r.Trees++;r.ConditionalNodes+=conditional.Nodes}}}}
 sort.Slice(r.Entries,func(i,j int)bool{a,b:=r.Entries[i],r.Entries[j];if len(a.Set)!=len(b.Set) {return len(a.Set)<len(b.Set)};return compareSets(a.Set,b.Set)<0});return r
}
