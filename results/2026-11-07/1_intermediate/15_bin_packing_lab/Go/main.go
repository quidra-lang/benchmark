package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"strconv"
	"strings"
)

var methods = []string{
	"NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST",
	"HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD",
}

type commandError string

func (e commandError) Error() string { return string(e) }
func fail(reason string) { panic(commandError(reason)) }

func number(text string) int {
	value, _ := strconv.Atoi(text)
	return value
}

func ceiling(a, b int) int { return (a + b - 1) / b }

type item struct { id, size int }

func (i item) text() string { return fmt.Sprintf("%d:%d", i.id, i.size) }

func descending(items []item) []item {
	result := append([]item(nil), items...)
	sort.Slice(result, func(i, j int) bool {
		if result[i].size != result[j].size {
			return result[i].size > result[j].size
		}
		return result[i].id < result[j].id
	})
	return result
}

type bin struct {
	items []item
	load int
	category int
}

func (b *bin) put(i item) {
	b.items = append(b.items, i)
	b.load += i.size
}

func copyBins(bins []*bin) []*bin {
	result := make([]*bin, len(bins))
	for i, b := range bins {
		result[i] = &bin{items: append([]item(nil), b.items...), load: b.load, category: b.category}
	}
	return result
}

type step struct {
	item item
	bin, inspected, closed, category int
	opened bool
}

type packing struct {
	method string
	parameter int
	bins []*bin
	steps []step
	inspections, closes int
}

func (p *packing) name() string {
	if p.method == "HARMONIC" || p.method == "KBOUNDED" {
		return fmt.Sprintf("%s k=%d", p.method, p.parameter)
	}
	return p.method
}

func (p *packing) header(capacity, total int) string {
	line := fmt.Sprintf("%s bins=%d inspections=%d waste=%d", p.name(), len(p.bins),
		p.inspections, len(p.bins)*capacity-total)
	if p.method == "KBOUNDED" {
		line += fmt.Sprintf(" closes=%d", p.closes)
	}
	return line
}

func pack(items []item, capacity int, method string, parameter int) *packing {
	result := &packing{method: method, parameter: parameter}
	ordered := items
	if method == "FFD" || method == "BFD" || method == "WFD" {
		ordered = descending(items)
	}
	active := []int{}
	current := make(map[int]int)
	for _, it := range ordered {
		chosen, closed, class := -1, -1, 0
		before := result.inspections
		switch method {
		case "NEXTFIT":
			if len(result.bins) > 0 {
				result.inspections++
				last := len(result.bins)-1
				if result.bins[last].load+it.size <= capacity {
					chosen = last
				}
			}
		case "FIRSTFIT", "FFD", "KBOUNDED":
			candidates := active
			if method != "KBOUNDED" {
				candidates = make([]int, len(result.bins))
				for i := range candidates { candidates[i] = i }
			}
			for _, i := range candidates {
				result.inspections++
				if result.bins[i].load+it.size <= capacity {
					chosen = i
					break
				}
			}
		case "HARMONIC":
			class = capacity / it.size
			if class > parameter { class = parameter }
			if index, ok := current[class]; ok {
				result.inspections++
				if result.bins[index].load+it.size <= capacity {
					chosen = index
				}
			}
		default:
			result.inspections += len(result.bins)
			fitting := []int{}
			for i, b := range result.bins {
				if b.load+it.size <= capacity {
					fitting = append(fitting, i)
				}
			}
			if len(fitting) > 0 {
				if method == "BESTFIT" || method == "BFD" {
					chosen = fitting[0]
					for _, i := range fitting {
						if result.bins[i].load > result.bins[chosen].load {
							chosen = i
						}
					}
				} else {
					sort.Slice(fitting, func(i, j int) bool {
						a, b := fitting[i], fitting[j]
						if result.bins[a].load != result.bins[b].load {
							return result.bins[a].load < result.bins[b].load
						}
						return a < b
					})
					chosen = fitting[0]
					if method == "ALMOSTWORST" && len(fitting) > 1 {
						chosen = fitting[1]
					}
				}
			}
		}
		opened := chosen < 0
		if opened {
			if method == "KBOUNDED" && len(active) == parameter {
				closed = active[0]
				for _, i := range active {
					if result.bins[i].load > result.bins[closed].load {
						closed = i
					}
				}
				for j, i := range active {
					if i == closed {
						active = append(active[:j], active[j+1:]...)
						break
					}
				}
				result.closes++
			}
			chosen = len(result.bins)
			result.bins = append(result.bins, &bin{category: class})
			if method == "KBOUNDED" { active = append(active, chosen) }
			if method == "HARMONIC" { current[class] = chosen }
		}
		result.bins[chosen].put(it)
		result.steps = append(result.steps, step{item: it, bin: chosen,
			inspected: result.inspections-before, opened: opened, closed: closed, category: class})
	}
	return result
}

type boundRow struct { alpha, j1, j2, j3, bound int }
type boundsResult struct { l1, l2 int; rows []boundRow }

func bounds(items []item, capacity int) boundsResult {
	total := 0
	thresholds := map[int]bool{0:true}
	for _, it := range items {
		total += it.size
		if 2*it.size <= capacity { thresholds[it.size] = true }
	}
	values := make([]int, 0, len(thresholds))
	for alpha := range thresholds { values = append(values, alpha) }
	sort.Ints(values)
	answer := boundsResult{l1: ceiling(total, capacity)}
	for _, alpha := range values {
		j1, j2, j3, sum2, sum3 := 0, 0, 0, 0, 0
		for _, it := range items {
			s := it.size
			switch {
			case s > capacity-alpha:
				j1++
			case 2*s > capacity:
				j2++
				sum2 += s
			case s >= alpha:
				j3++
				sum3 += s
			}
		}
		excess := sum3 - (j2*capacity-sum2)
		bound := j1+j2
		if excess > 0 { bound += ceiling(excess, capacity) }
		answer.rows = append(answer.rows, boundRow{alpha,j1,j2,j3,bound})
		if bound > answer.l2 { answer.l2 = bound }
	}
	return answer
}

type exactSearch struct {
	order []item
	capacity, limit, lower int
	remaining []int
	best, live []*bin
	nodes int
	status string
	lab *lab
}

func newExact(items []item, capacity, limit, lower int, incumbent []*bin, lab *lab) *exactSearch {
	order := descending(items)
	remaining := make([]int, len(order)+1)
	for i := len(order)-1; i >= 0; i-- {
		remaining[i] = remaining[i+1]+order[i].size
	}
	return &exactSearch{order:order, capacity:capacity, limit:limit,
		lower:lower, remaining:remaining, best:copyBins(incumbent), lab:lab}
}

func (e *exactSearch) visit(index int) {
	if e.nodes == e.limit {
		e.status = "limit"
		return
	}
	e.nodes++
	count := len(e.live)
	used := e.remaining[0]-e.remaining[index]
	free := count*e.capacity-used
	excess := e.remaining[index]-free
	minimum := count
	if excess > 0 { minimum += ceiling(excess,e.capacity) }
	if minimum >= len(e.best) { return }
	if index == len(e.order) {
		e.best = copyBins(e.live)
		e.lab.emit(fmt.Sprintf("IMPROVE bins=%d nodes=%d", count, e.nodes))
		if count == e.lower { e.status = "bound" }
		return
	}
	it := e.order[index]
	seen := map[int]bool{}
	for _, b := range e.live {
		old := b.load
		if seen[old] || old+it.size > e.capacity { continue }
		seen[old] = true
		b.put(it)
		e.visit(index+1)
		b.items = b.items[:len(b.items)-1]
		b.load = old
		if e.status != "" { return }
	}
	if count+1 < len(e.best) {
		b := &bin{}
		b.put(it)
		e.live = append(e.live,b)
		e.visit(index+1)
		e.live = e.live[:len(e.live)-1]
	}
}

type rect struct { id, w, h int }
func (r rect) letter() byte { return byte('A' + r.id - 1) }
func (r rect) area() int { return r.w*r.h }

type placement struct {
	rect rect
	x,y,w,h int
	rotated bool
}

type shelf struct {
	y,h,used int
	placed []placement
}

type freeRect struct { x,y,w,h int }
func (f freeRect) area() int { return f.w*f.h }
func (f freeRect) text() string { return fmt.Sprintf("%d,%d,%dx%d", f.x,f.y,f.w,f.h) }

type sheet struct {
	free []freeRect
	placed []placement
	area int
}

type piece struct { length, demand int }
type pattern struct { counts []int; trim int }

type lab struct {
	items []item
	capacity int
	out strings.Builder
}

func (l *lab) emit(s string) { fmt.Fprintln(&l.out, s) }

func (l *lab) total() int {
	total := 0
	for _, it := range l.items { total += it.size }
	return total
}

func (l *lab) binLine(number int, b *bin, cap int, classes, over bool) {
	items := make([]string,len(b.items))
	for i,it := range b.items { items[i] = it.text() }
	line := fmt.Sprintf("BIN %d load=%d/%d items=%s",number,b.load,cap,strings.Join(items," "))
	if classes { line += fmt.Sprintf(" class=%d",b.category) }
	if over { line += " OVER" }
	l.emit(line)
}

func (l *lab) binLines(bins []*bin, classes bool) {
	for i,b := range bins { l.binLine(i+1,b,l.capacity,classes,false) }
}

func parameter(method string, words []string, index int) int {
	if method != "HARMONIC" && method != "KBOUNDED" { return 0 }
	n := number(words[index])
	if n == 0 { fail("BAD PARAMETER") }
	return n
}

func (l *lab) itemsCommand(words []string) {
	capacity := number(words[1])
	if capacity == 0 { fail("BAD CAPACITY") }
	next := make([]item,0,len(words)-2)
	for i := 2; i < len(words); i++ {
		size := number(words[i])
		if size == 0 || size > capacity { fail(fmt.Sprintf("BAD ITEM %d",i-1)) }
		next = append(next,item{i-1,size})
	}
	l.items,l.capacity = next,capacity
	l.emit(fmt.Sprintf("ITEMS count=%d capacity=%d total=%d",len(next),capacity,l.total()))
}

func (l *lab) randomCommand(words []string) {
	n,capacity,seed := number(words[1]),number(words[2]),int64(number(words[3]))
	if n == 0 || n > 40 { fail("BAD COUNT") }
	if capacity == 0 { fail("BAD CAPACITY") }
	if seed == 0 || seed >= 2147483647 { fail("BAD SEED") }
	next := make([]item,0,n)
	sizes := make([]string,0,n)
	for i := 1; i <= n; i++ {
		seed = 48271*seed%2147483647
		size := int(seed%int64(capacity))+1
		next = append(next,item{i,size})
		sizes = append(sizes,strconv.Itoa(size))
	}
	l.items,l.capacity = next,capacity
	l.emit(fmt.Sprintf("RANDOM count=%d capacity=%d total=%d",n,capacity,l.total()))
	l.emit("SIZES "+strings.Join(sizes," "))
}

func (l *lab) methodCommand(method string,k int) {
	p := pack(l.items,l.capacity,method,k)
	l.emit(p.header(l.capacity,l.total()))
	l.binLines(p.bins,method=="HARMONIC")
}

func (l *lab) trace(method string,k int) {
	p := pack(l.items,l.capacity,method,k)
	l.emit("TRACE "+p.header(l.capacity,l.total()))
	for i,s := range p.steps {
		line := fmt.Sprintf("STEP %d item=%s bin=%d inspected=%d",i+1,s.item.text(),s.bin+1,s.inspected)
		if s.opened { line += " new" }
		if s.closed >= 0 { line += fmt.Sprintf(" closed=%d",s.closed+1) }
		if method == "HARMONIC" { line += fmt.Sprintf(" class=%d",s.category) }
		l.emit(line)
	}
}

func (l *lab) reduce(method string,k int) {
	p := pack(l.items,l.capacity,method,k)
	bins := p.bins
	before := len(bins)
	events := []string{}
	for {
		sources := make([]int,len(bins))
		for i := range sources { sources[i] = i }
		sort.Slice(sources,func(i,j int)bool{
			a,b := sources[i],sources[j]
			if bins[a].load != bins[b].load { return bins[a].load < bins[b].load }
			return a < b
		})
		eliminated := false
		for _,source := range sources {
			loads := make([]int,len(bins))
			for i,b := range bins { loads[i] = b.load }
			moved, destinations := []item{},[]int{}
			possible := true
			for _,it := range descending(bins[source].items) {
				target := -1
				for i := range bins {
					if i==source || loads[i]+it.size>l.capacity { continue }
					if target<0 || loads[i]>loads[target] { target=i }
				}
				if target<0 { possible=false; break }
				loads[target] += it.size
				moved=append(moved,it)
				destinations=append(destinations,target)
			}
			if !possible { continue }
			moves := make([]string,len(moved))
			for i,it := range moved {
				target:=destinations[i]
				moves[i]=fmt.Sprintf("%s->%d",it.text(),target+1)
				bins[target].put(it)
			}
			events=append(events,fmt.Sprintf("ELIMINATE bin=%d load=%d moves=%s",
				source+1,bins[source].load,strings.Join(moves," ")))
			bins=append(bins[:source],bins[source+1:]...)
			eliminated=true
			break
		}
		if !eliminated { break }
	}
	l.emit(fmt.Sprintf("REDUCE %s before=%d after=%d eliminated=%d",
		p.name(),before,len(bins),before-len(bins)))
	for _,event := range events { l.emit(event) }
	l.binLines(bins,method=="HARMONIC")
}

func (l *lab) boundsCommand() {
	b:=bounds(l.items,l.capacity)
	l.emit(fmt.Sprintf("BOUNDS total=%d L1=%d L2=%d",l.total(),b.l1,b.l2))
	for _,r:=range b.rows{
		l.emit(fmt.Sprintf("ALPHA %d j1=%d j2=%d j3=%d bound=%d",
			r.alpha,r.j1,r.j2,r.j3,r.bound))
	}
}

func (l *lab) compare(k int) {
	if k==0 { fail("BAD PARAMETER") }
	b:=bounds(l.items,l.capacity)
	results:=make([]*packing,0,len(methods))
	for _,method:=range methods { results=append(results,pack(l.items,l.capacity,method,k)) }
	sort.Slice(results,func(i,j int)bool{
		if len(results[i].bins)!=len(results[j].bins) { return len(results[i].bins)<len(results[j].bins) }
		return results[i].method<results[j].method
	})
	l.emit(fmt.Sprintf("COMPARE k=%d L1=%d L2=%d",k,b.l1,b.l2))
	for _,p:=range results {
		count:=len(p.bins)
		l.emit(fmt.Sprintf("%s bins=%d gap=%d waste=%d inspections=%d",
			p.method,count,count-b.l2,count*l.capacity-l.total(),p.inspections))
	}
}

func (l *lab) exact(limit int) {
	if limit==0 { fail("BAD PARAMETER") }
	if len(l.items)>=21 { fail("TOO MANY ITEMS") }
	incumbent:=pack(l.items,l.capacity,"FFD",0).bins
	lower:=bounds(l.items,l.capacity).l2
	l.emit(fmt.Sprintf("EXACT ffd=%d L2=%d",len(incumbent),lower))
	search:=newExact(l.items,l.capacity,limit,lower,incumbent,l)
	if len(incumbent)==lower { search.status="bound" } else { search.visit(0) }
	if search.status=="" { search.status="complete" }
	l.emit(fmt.Sprintf("RESULT bins=%d nodes=%d status=%s",len(search.best),search.nodes,search.status))
	l.binLines(search.best,false)
}

func (l *lab) check(words []string) {
	if len(words)-1!=len(l.items) { fail("BAD ASSIGNMENT") }
	bins:=map[int]*bin{}
	for i,it:=range l.items{
		label:=number(words[i+1])
		if label==0 { fail("BAD ASSIGNMENT") }
		if bins[label]==nil { bins[label]=&bin{} }
		bins[label].put(it)
	}
	labels:=make([]int,0,len(bins))
	over:=0
	for label,b:=range bins {
		labels=append(labels,label)
		if b.load>l.capacity { over++ }
	}
	sort.Ints(labels)
	status:="valid"
	if over>0 { status="invalid" }
	l.emit(fmt.Sprintf("CHECK bins=%d over=%d L2=%d status=%s",
		len(bins),over,bounds(l.items,l.capacity).l2,status))
	for _,label:=range labels {
		l.binLine(label,bins[label],l.capacity,false,bins[label].load>l.capacity)
	}
}

func (l *lab) coverLines(name string,bins []*bin) {
	covered:=[]*bin{}
	var rest *bin
	for _,b:=range bins {
		if b.load>=l.capacity { covered=append(covered,b) } else { rest=b }
	}
	restLoad:=0
	if rest!=nil { restLoad=rest.load }
	l.emit(fmt.Sprintf("%s covered=%d rest=%d",name,len(covered),restLoad))
	l.binLines(covered,false)
	if rest!=nil {
		words:=make([]string,len(rest.items))
		for i,it:=range rest.items { words[i]=it.text() }
		l.emit("REST items="+strings.Join(words," "))
	}
}

func (l *lab) cover() {
	l.emit(fmt.Sprintf("COVER total=%d upper=%d",l.total(),l.total()/l.capacity))
	sequential:=[]*bin{}
	for _,it:=range l.items {
		if len(sequential)==0 || sequential[len(sequential)-1].load>=l.capacity {
			sequential=append(sequential,&bin{})
		}
		sequential[len(sequential)-1].put(it)
	}
	l.coverLines("DNF",sequential)
	order:=descending(l.items)
	paired:=[]*bin{}
	for first,last:=0,len(order)-1; first<=last; {
		b:=&bin{}
		b.put(order[first]);first++
		for b.load<l.capacity && first<=last {
			b.put(order[last]);last--
		}
		paired=append(paired,b)
	}
	l.coverLines("BIGSMALL",paired)
}

func (l *lab) machines(bins []*bin) {
	for i,b:=range bins {
		words:=make([]string,len(b.items))
		for j,it:=range b.items { words[j]=it.text() }
		text:=strings.Join(words," ")
		if text=="" { text="-" }
		l.emit(fmt.Sprintf("MACHINE %d load=%d items=%s",i+1,b.load,text))
	}
}

func (l *lab) multifit(m int) {
	if m==0 { fail("BAD PARAMETER") }
	largest:=0
	for _,it:=range l.items { if it.size>largest {largest=it.size} }
	lo:=ceiling(l.total(),m);hi:=ceiling(2*l.total(),m)
	if largest>lo {lo=largest}
	if largest>hi {hi=largest}
	l.emit(fmt.Sprintf("MULTIFIT m=%d lower=%d upper=%d",m,lo,hi))
	for lo<hi {
		mid:=lo+(hi-lo)/2
		count:=len(pack(l.items,mid,"FFD",0).bins)
		ok:=count<=m
		text:="fail"
		if ok { text="ok"; hi=mid } else {lo=mid+1}
		l.emit(fmt.Sprintf("TRY cap=%d bins=%d %s",mid,count,text))
	}
	bins:=pack(l.items,hi,"FFD",0).bins
	for len(bins)<m { bins=append(bins,&bin{}) }
	makespan:=0
	for _,b:=range bins { if b.load>makespan {makespan=b.load} }
	l.emit(fmt.Sprintf("RESULT cap=%d makespan=%d",hi,makespan))
	l.machines(bins)
	lpt:=make([]*bin,m)
	for i:=range lpt {lpt[i]=&bin{}}
	for _,it:=range descending(l.items) {
		best:=0
		for i:=1;i<m;i++ {if lpt[i].load<lpt[best].load {best=i}}
		lpt[best].put(it)
	}
	makespan=0
	for _,b:=range lpt {if b.load>makespan {makespan=b.load}}
	l.emit(fmt.Sprintf("LPT makespan=%d",makespan))
	l.machines(lpt)
}

func (l *lab) cutstock(words []string) {
	length:=number(words[1])
	if length==0 {fail("BAD CAPACITY")}
	pieces:=make([]piece,0,len(words)-2)
	seen:=map[int]bool{}
	for i:=2;i<len(words);i++{
		parts:=strings.Split(words[i],":")
		size,demand:=number(parts[0]),number(parts[1])
		if size==0 || size>length || demand==0 {fail(fmt.Sprintf("BAD PIECE %d",i-1))}
		if seen[size] {fail(fmt.Sprintf("DUPLICATE PIECE %d",i-1))}
		seen[size]=true
		pieces=append(pieces,piece{size,demand})
	}
	sort.Slice(pieces,func(i,j int)bool{return pieces[i].length>pieces[j].length})
	patterns:=[]pattern{}
	counts:=make([]int,len(pieces))
	var visit func(int,int)
	visit=func(index,remaining int){
		max:=remaining/pieces[index].length
		if index==len(pieces)-1 {
			counts[index]=max
			patterns=append(patterns,pattern{
				counts:append([]int(nil),counts...),
				trim:remaining-max*pieces[index].length,
			})
			return
		}
		for c:=max;c>=0;c-- {
			counts[index]=c
			visit(index+1,remaining-c*pieces[index].length)
		}
	}
	visit(0,length)
	l.emit(fmt.Sprintf("CUTSTOCK L=%d pieces=%d patterns=%d",length,len(pieces),len(patterns)))
	for i,p:=range patterns {
		breakdown:=[]string{}
		for j,c:=range p.counts {
			if c>0 {breakdown=append(breakdown,fmt.Sprintf("%dx%d",c,pieces[j].length))}
		}
		l.emit(fmt.Sprintf("PATTERN %d %s rest=%d",i+1,strings.Join(breakdown,"+"),p.trim))
	}
	remaining:=make([]int,len(pieces))
	cut:=make([]int,len(pieces))
	used:=make([]int,len(patterns))
	for i,p:=range pieces {remaining[i]=p.demand}
	for {
		needed:=0
		for _,value:=range remaining { needed+=value }
		if needed==0 {break}
		chosen,highest:=-1,-1
		for j,p:=range patterns {
			useful:=0
			for i,c:=range p.counts {
				if c<remaining[i] {useful+=c} else {useful+=remaining[i]}
			}
			if useful>highest {chosen,highest=j,useful}
		}
		used[chosen]++
		for i,c:=range patterns[chosen].counts {
			cut[i]+=c
			if c>remaining[i] {remaining[i]=0} else {remaining[i]-=c}
		}
	}
	bars,trim,total,demandTotal,cutTotal:=0,0,0,0,0
	stock:=[]item{}
	for i,p:=range patterns {
		if used[i]>0 {
			l.emit(fmt.Sprintf("USE %d bars=%d",i+1,used[i]))
			bars+=used[i];trim+=p.trim*used[i]
		}
	}
	for _,p:=range pieces {
		total+=p.length*p.demand
		demandTotal+=p.demand
		for j:=0;j<p.demand;j++ {stock=append(stock,item{len(stock)+1,p.length})}
	}
	for i,p:=range pieces {
		l.emit(fmt.Sprintf("PIECE %d demand=%d cut=%d",p.length,p.demand,cut[i]))
		cutTotal+=cut[i]
	}
	l.emit(fmt.Sprintf("TOTAL bars=%d trim=%d surplus=%d waste=%d",
		bars,trim,cutTotal-demandTotal,bars*length-total))
	ffd:=len(pack(stock,length,"FIRSTFIT",0).bins)
	l.emit(fmt.Sprintf("FFD bars=%d waste=%d",ffd,ffd*length-total))
	l.emit(fmt.Sprintf("LOWER bars=%d",ceiling(total,length)))
}

func rectangles(words []string,start,width,height int,rotate bool) []rect {
	result:=make([]rect,0,len(words)-start)
	for i:=start;i<len(words);i++ {
		parts:=strings.Split(words[i],"x")
		w,h:=number(parts[0]),number(parts[1])
		fits:=w<=width
		if height>0 {fits=(w<=width && h<=height) || (rotate && h<=width && w<=height)}
		if w==0 || h==0 || !fits {fail(fmt.Sprintf("BAD RECT %d",i-start+1))}
		result=append(result,rect{id:i-start+1,w:w,h:h})
	}
	return result
}

func (l *lab) draw(width,height int,placed []placement) {
	grid:=make([][]byte,height)
	for y:=range grid {
		grid[y]=make([]byte,width)
		for x:=range grid[y] {grid[y][x]='.'}
	}
	for _,p:=range placed {
		for y:=p.y;y<p.y+p.h;y++ {
			for x:=p.x;x<p.x+p.w;x++ {
				grid[y][x]=p.rect.letter()
			}
		}
	}
	for y:=height-1;y>=0;y-- {l.emit(string(grid[y]))}
}

func (l *lab) shelfCommand(words []string) {
	width:=number(words[1])
	if width==0 {fail("BAD CAPACITY")}
	source:=rectangles(words,2,width,0,false)
	area:=0
	for _,r:=range source {area+=r.area()}
	l.emit(fmt.Sprintf("SHELF W=%d rects=%d area=%d",width,len(source),area))
	order:=append([]rect(nil),source...)
	sort.Slice(order,func(i,j int)bool {
		a,b:=order[i],order[j]
		if a.h!=b.h {return a.h>b.h}
		if a.w!=b.w {return a.w>b.w}
		return a.id<b.id
	})
	for _,method:=range []string{"NFDH","FFDH","BFDH"} {
		shelves:=[]*shelf{}
		placed:=[]placement{}
		for _,r:=range order {
			var selected *shelf
			if method=="NFDH" {
				if len(shelves)>0 && shelves[len(shelves)-1].used+r.w<=width {
					selected=shelves[len(shelves)-1]
				}
			} else {
				for _,candidate:=range shelves {
					if candidate.used+r.w>width {continue}
					if selected==nil || (method=="BFDH" && candidate.used>selected.used) {
						selected=candidate
					}
					if method=="FFDH" {break}
				}
			}
			if selected==nil {
				y:=0
				if len(shelves)>0 {
					last:=shelves[len(shelves)-1]
					y=last.y+last.h
				}
				selected=&shelf{y:y,h:r.h}
				shelves=append(shelves,selected)
			}
			p:=placement{rect:r,x:selected.used,y:selected.y,w:r.w,h:r.h}
			selected.placed=append(selected.placed,p)
			placed=append(placed,p)
			selected.used+=r.w
		}
		last:=shelves[len(shelves)-1]
		height:=last.y+last.h
		l.emit(fmt.Sprintf("%s height=%d shelves=%d util=%d",method,height,len(shelves),
			area*100/(width*height)))
		for i,s:=range shelves {
			names:=make([]string,len(s.placed))
			for j,p:=range s.placed {names[j]=fmt.Sprintf("%c@%d",p.rect.letter(),p.x)}
			l.emit(fmt.Sprintf("LEVEL %d y=%d h=%d used=%d items=%s",
				i+1,s.y,s.h,s.used,strings.Join(names," ")))
		}
		l.draw(width,height,placed)
	}
	columns:=make([]int,width)
	placed:=[]placement{}
	for _,r:=range order {
		bestX,bestY:=0,int(^uint(0)>>1)
		for x:=0;x<=width-r.w;x++{
			y:=0
			for j:=x;j<x+r.w;j++ {if columns[j]>y {y=columns[j]}}
			if y<bestY {bestX,bestY=x,y}
		}
		p:=placement{rect:r,x:bestX,y:bestY,w:r.w,h:r.h}
		placed=append(placed,p)
		for j:=bestX;j<bestX+r.w;j++ {columns[j]=bestY+r.h}
	}
	height:=0
	for _,h:=range columns {if h>height {height=h}}
	l.emit(fmt.Sprintf("SKYLINE height=%d util=%d",height,area*100/(width*height)))
	for _,p:=range placed {
		l.emit(fmt.Sprintf("PLACE %c x=%d y=%d w=%d h=%d",p.rect.letter(),p.x,p.y,p.w,p.h))
	}
	l.draw(width,height,placed)
}

func fits(r rect,f freeRect,rotate bool) bool {
	return (r.w<=f.w && r.h<=f.h) || (rotate && r.h<=f.w && r.w<=f.h)
}

func (l *lab) guillotine(words []string) {
	width,height:=number(words[1]),number(words[2])
	if width==0 || height==0 {fail("BAD CAPACITY")}
	rotate:=words[3]=="ROTATE"
	best:=words[4]=="BEST"
	order:=rectangles(words,5,width,height,rotate)
	sort.Slice(order,func(i,j int)bool{
		if order[i].area()!=order[j].area() {return order[i].area()>order[j].area()}
		return order[i].id<order[j].id
	})
	area:=0
	for _,r:=range order {area+=r.area()}
	sheets:=[]*sheet{}
	rotated:=0
	for _,r:=range order {
		var selected *sheet
		selectedIndex,selectedArea:=-1,int(^uint(0)>>1)
		for _,s:=range sheets {
			for i,f:=range s.free {
				if !fits(r,f,rotate) {continue}
				if selected==nil || (best && f.area()<selectedArea) {
					selected=s
					selectedIndex=i
					selectedArea=f.area()
				}
				if !best {break}
			}
			if selected!=nil && !best {break}
		}
		if selected==nil {
			selected=&sheet{free:[]freeRect{{0,0,width,height}}}
			sheets=append(sheets,selected)
			selectedIndex=0
		}
		f:=selected.free[selectedIndex]
		selected.free=append(selected.free[:selectedIndex],selected.free[selectedIndex+1:]...)
		turned:=r.w>f.w || r.h>f.h
		w,h:=r.w,r.h
		if turned {w,h=h,w;rotated++}
		p:=placement{rect:r,x:f.x,y:f.y,w:w,h:h,rotated:turned}
		selected.placed=append(selected.placed,p)
		selected.area+=r.area()
		rw,rh:=f.w-w,f.h-h
		var top,right freeRect
		if rw<=rh {
			top=freeRect{f.x,f.y+h,f.w,rh}
			right=freeRect{f.x+w,f.y,rw,h}
		} else {
			top=freeRect{f.x,f.y+h,w,rh}
			right=freeRect{f.x+w,f.y,rw,f.h}
		}
		if top.w>0 && top.h>0 {selected.free=append(selected.free,top)}
		if right.w>0 && right.h>0 {selected.free=append(selected.free,right)}
	}
	l.emit(fmt.Sprintf("GUILLOTINE W=%d H=%d mode=%s rule=%s rects=%d sheets=%d rotated=%d util=%d",
		width,height,words[3],words[4],len(order),len(sheets),rotated,area*100/(len(sheets)*width*height)))
	for i,s:=range sheets {
		l.emit(fmt.Sprintf("SHEET %d placed=%d area=%d",i+1,len(s.placed),s.area))
		for _,p:=range s.placed {
			line:=fmt.Sprintf("PLACE %c x=%d y=%d w=%d h=%d",p.rect.letter(),p.x,p.y,p.w,p.h)
			if p.rotated {line+=" rotated"}
			l.emit(line)
		}
		if len(s.free)==0 {l.emit("FREE none")} else {
			parts:=make([]string,len(s.free))
			for j,f:=range s.free {parts[j]=f.text()}
			l.emit("FREE "+strings.Join(parts," "))
		}
		l.draw(width,height,s.placed)
	}
}

func (l *lab) process(words []string) {
	defer func(){
		if x:=recover();x!=nil {
			if err,ok:=x.(commandError);ok {l.emit("ERROR "+string(err));return}
			panic(x)
		}
	}()
	cmd:=words[0]
	switch cmd {
	case "ITEMS": l.itemsCommand(words)
	case "RANDOM": l.randomCommand(words)
	case "CUTSTOCK": l.cutstock(words)
	case "SHELF": l.shelfCommand(words)
	case "GUILLOTINE": l.guillotine(words)
	default:
		if l.items==nil {fail("NO ITEMS")}
		switch cmd {
		case "NEXTFIT","FIRSTFIT","BESTFIT","WORSTFIT","ALMOSTWORST",
			"HARMONIC","KBOUNDED","FFD","BFD","WFD":
			l.methodCommand(cmd,parameter(cmd,words,1))
		case "TRACE": l.trace(words[1],parameter(words[1],words,2))
		case "REDUCE": l.reduce(words[1],parameter(words[1],words,2))
		case "BOUNDS": l.boundsCommand()
		case "COMPARE": l.compare(number(words[1]))
		case "EXACT": l.exact(number(words[1]))
		case "CHECK": l.check(words)
		case "COVER": l.cover()
		case "MULTIFIT": l.multifit(number(words[1]))
		}
	}
}

func main() {
	scanner:=bufio.NewScanner(os.Stdin)
	if !scanner.Scan() {return}
	n:=number(scanner.Text())
	l:=&lab{}
	for i:=0;i<n && scanner.Scan();i++ {
		l.process(strings.Split(scanner.Text()," "))
	}
	fmt.Print(l.out.String())
}
