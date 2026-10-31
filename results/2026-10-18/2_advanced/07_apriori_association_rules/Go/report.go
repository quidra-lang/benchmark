package main

import (
 "fmt"
 "os"
 "strings"
)

func fractionText(f Fraction) string {negative:=f.N<0;n:=f.N;if negative {n=-n};scaled:=10000*n/f.D;sign,decimalSign:="","";if negative {sign="-";if scaled>0 {decimalSign="-"}};return fmt.Sprintf("%s%d/%d=%s%d.%04d",sign,n,f.D,decimalSign,scaled/10000,scaled%10000)}
func percent(part,whole int64) string {scaled:=10000*part/whole;return fmt.Sprintf("%d.%02d%%",scaled/100,scaled%100)}
func money(cents int64) string {return fmt.Sprintf("%d.%02d",cents/100,cents%100)}
func itemset(set []int,names []string) string {parts:=make([]string,len(set));for j,i:=range set {parts[j]=names[i]};return strings.Join(parts,"+")}
func arrow(r Rule,names []string) string {return itemset(r.X,names)+" -> "+itemset(r.Y,names)}
func rulesCSV(rules []Rule,names []string) []string {lines:=[]string{"rank,antecedent,consequent,count,support,confidence,lift,leverage,conviction,improvement"};for _,r:=range rules {conviction:="INF";if !r.Infinite {conviction=fractionText(r.Conviction)};lines=append(lines,fmt.Sprintf("%d,%s,%s,%d,%s,%s,%s,%s,%s,%s",r.Rank,itemset(r.X,names),itemset(r.Y,names),r.Count,fractionText(r.Support),fractionText(r.Confidence),fractionText(r.Lift),fractionText(r.Leverage),conviction,fractionText(r.Improvement)))};return lines}
func writeReport(name string,lines []string) {if e:=os.MkdirAll("output",0755);e!=nil {panic(e)};text:="";if len(lines)>0 {text=strings.Join(lines,"\n")+"\n"};if e:=os.WriteFile("output/"+name,[]byte(text),0644);e!=nil {panic(e)}}
