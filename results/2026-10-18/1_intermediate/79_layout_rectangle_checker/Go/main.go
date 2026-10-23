package main

import (
    "bufio"
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

type geometry struct { x1,y1,x2,y2 int64 }
type rectangle struct { name,layer string; geometry }
type relation struct { geometry; ox,oy,gap int64; kind,direction string }
type rule struct { kind,inner,outer string; value int64 }
type snapshot struct { rectangles map[string]rectangle; command string }
type grid struct { xs,ys []int64; counts [][]int }
type violation struct { a,b string; gap int64; direction string }
type hole struct { geometry; area,ax,ay int64 }
type checker struct {
    rectangles map[string]rectangle
    rules map[string]rule
    history []snapshot
    output []string
}
type commandError string
func number(s string) int64 { n,_:=strconv.ParseInt(s,10,64); return n }
func min(a,b int64) int64 { if a<b{return a};return b }
func max(a,b int64) int64 { if a>b{return a};return b }
func abs(n int64) int64 { if n<0{return -n};return n }
func notation(r geometry) string { return fmt.Sprintf("(%d,%d)-(%d,%d)",r.x1,r.y1,r.x2,r.y2) }
func point(x,y int64) string { return fmt.Sprintf("(%d,%d)",x,y) }
func area(r geometry) int64 { return (r.x2-r.x1)*(r.y2-r.y1) }
func encloses(a,b geometry) bool { return a.x1<=b.x1&&a.y1<=b.y1&&a.x2>=b.x2&&a.y2>=b.y2 }
func compare(a,b geometry) relation {
    r:=relation{geometry:geometry{max(a.x1,b.x1),max(a.y1,b.y1),min(a.x2,b.x2),min(a.y2,b.y2)}}
    r.ox,r.oy=r.x2-r.x1,r.y2-r.y1
    r.gap=max(0,max(-r.ox,-r.oy))
    if r.ox>0&&r.oy>0 {r.kind="overlap"} else if r.ox==0&&r.oy==0 {r.kind="corner"} else if r.ox>=0&&r.oy>=0 {r.kind="edge"} else {
        r.kind="separate"
        if r.ox<0&&r.oy<0 {r.direction="diagonal"} else if r.ox<0 {r.direction="x"} else {r.direction="y"}
    }
    return r
}
func connected(a,b rectangle) bool { r:=compare(a.geometry,b.geometry);return a.layer==b.layer&&(r.kind=="overlap"||r.kind=="edge") }
func margins(a,b geometry) [4]int64 { return [4]int64{b.x1-a.x1,b.y1-a.y1,a.x2-b.x2,a.y2-b.y2} }
func minimum(values [4]int64) int64 { v:=values[0];for _,x:=range values[1:] {v=min(v,x)};return v }
func decimal(numerator,denominator int64) string { h:=numerator*100/denominator;return fmt.Sprintf("%d.%02d",h/100,h%100) }
func bounds(list []rectangle) geometry {
    r:=list[0].geometry
    for _,item:=range list[1:] {r.x1=min(r.x1,item.x1);r.y1=min(r.y1,item.y1);r.x2=max(r.x2,item.x2);r.y2=max(r.y2,item.y2)}
    return r
}
func distinct(values []int64) []int64 {
    sort.Slice(values,func(i,j int)bool{return values[i]<values[j]})
    result:=[]int64{}
    for _,value:=range values {if len(result)==0||value!=result[len(result)-1] {result=append(result,value)}}
    return result
}
func makeGrid(list []rectangle) grid {
    g:=grid{}
    for _,r:=range list {g.xs=append(g.xs,r.x1,r.x2);g.ys=append(g.ys,r.y1,r.y2)}
    g.xs,g.ys=distinct(g.xs),distinct(g.ys)
    if len(list)==0{return g}
    xi,yi:=map[int64]int{},map[int64]int{}
    for i,x:=range g.xs {xi[x]=i};for i,y:=range g.ys {yi[y]=i}
    differences:=make([][]int,len(g.ys))
    for y:=range differences {differences[y]=make([]int,len(g.xs))}
    for _,r:=range list {
        a,b,c,d:=xi[r.x1],yi[r.y1],xi[r.x2],yi[r.y2]
        differences[b][a]++;differences[b][c]--;differences[d][a]--;differences[d][c]++
    }
    g.counts=make([][]int,len(g.ys)-1)
    for y:=range differences {
        for x:=range differences[y] {
            if y>0 {differences[y][x]+=differences[y-1][x]}
            if x>0 {differences[y][x]+=differences[y][x-1]}
            if y>0&&x>0 {differences[y][x]-=differences[y-1][x-1]}
        }
        if y<len(g.counts) {g.counts[y]=differences[y][:len(g.xs)-1]}
    }
    return g
}
func (g grid) covered(k int,window *geometry) int64 {
    total:=int64(0)
    for y,row:=range g.counts {for x,count:=range row {
        if count<k {continue}
        r:=geometry{g.xs[x],g.ys[y],g.xs[x+1],g.ys[y+1]}
        if window!=nil {r=compare(r,*window).geometry}
        if r.x1<r.x2&&r.y1<r.y2 {total+=area(r)}
    }}
    return total
}
func (g grid) perimeter() int64 {
    total:=int64(0)
    for y,row:=range g.counts {for x,count:=range row {
        if count==0 {continue}
        width,height:=g.xs[x+1]-g.xs[x],g.ys[y+1]-g.ys[y]
        if x==0||row[x-1]==0 {total+=height}
        if x+1==len(row)||row[x+1]==0 {total+=height}
        if y==0||g.counts[y-1][x]==0 {total+=width}
        if y+1==len(g.counts)||g.counts[y+1][x]==0 {total+=width}
    }}
    return total
}
func (g grid) empty() *geometry {
    var best *geometry
    for left:=0;left+1<len(g.xs);left++ {
        blocked:=make([]bool,len(g.counts))
        for right:=left;right+1<len(g.xs);right++ {
            for y:=range blocked {blocked[y]=blocked[y]||g.counts[y][right]>0}
            for y:=0;y<len(blocked); {
                if blocked[y] {y++;continue}
                start:=y
                for y<len(blocked)&&!blocked[y] {y++}
                r:=geometry{g.xs[left],g.ys[start],g.xs[right+1],g.ys[y]}
                if best==nil||area(r)>area(*best)||area(r)==area(*best)&&(r.x1<best.x1||r.x1==best.x1&&(r.y1<best.y1||r.y1==best.y1&&r.x2-r.x1<best.x2-best.x1)) {
                    value:=r;best=&value
                }
            }
        }
    }
    return best
}
func (g grid) holes() []hole {
    result:=[]hole{}
    seen:=make([][]bool,len(g.counts))
    for y:=range seen {seen[y]=make([]bool,len(g.xs)-1)}
    for y,row:=range g.counts {for x,count:=range row {
        if count>0||seen[y][x] {continue}
        queue:=[][2]int{{x,y}};seen[y][x]=true;outside:=false
        h:=hole{geometry:geometry{g.xs[x],g.ys[y],g.xs[x+1],g.ys[y+1]},ax:g.xs[x],ay:g.ys[y]}
        for i:=0;i<len(queue);i++ {
            p:=queue[i];xx,yy:=p[0],p[1]
            if xx==0||yy==0||xx+1==len(row)||yy+1==len(g.counts) {outside=true}
            h.area+=(g.xs[xx+1]-g.xs[xx])*(g.ys[yy+1]-g.ys[yy])
            h.x1=min(h.x1,g.xs[xx]);h.y1=min(h.y1,g.ys[yy]);h.x2=max(h.x2,g.xs[xx+1]);h.y2=max(h.y2,g.ys[yy+1])
            if g.ys[yy]<h.ay||g.ys[yy]==h.ay&&g.xs[xx]<h.ax {h.ax,h.ay=g.xs[xx],g.ys[yy]}
            for _,d:=range [][2]int{{1,0},{-1,0},{0,1},{0,-1}} {
                a,b:=xx+d[0],yy+d[1]
                if a>=0&&a<len(row)&&b>=0&&b<len(g.counts)&&!seen[b][a]&&g.counts[b][a]==0 {seen[b][a]=true;queue=append(queue,[2]int{a,b})}
            }
        }
        if !outside {result=append(result,h)}
    }}
    sort.Slice(result,func(i,j int)bool{return result[i].ay<result[j].ay||result[i].ay==result[j].ay&&result[i].ax<result[j].ax})
    return result
}
func (g grid) pieces() []geometry {
    active:=map[[2]int64]geometry{}
    result:=[]geometry{}
    for y,row:=range g.counts {
        next:=map[[2]int64]geometry{}
        for x:=0;x<len(row); {
            if row[x]==0 {x++;continue}
            start:=x
            for x<len(row)&&row[x]>0 {x++}
            key:=[2]int64{g.xs[start],g.xs[x]}
            r,exists:=active[key]
            if !exists {r=geometry{key[0],g.ys[y],key[1],g.ys[y+1]}} else {r.y2=g.ys[y+1]}
            next[key]=r
        }
        for key,r:=range active {if _,exists:=next[key];!exists {result=append(result,r)}}
        active=next
    }
    for _,r:=range active {result=append(result,r)}
    sort.Slice(result,func(i,j int)bool{return result[i].y1<result[j].y1||result[i].y1==result[j].y1&&result[i].x1<result[j].x1})
    return result
}
func (c *checker) emit(format string,args ...any) {c.output=append(c.output,fmt.Sprintf(format,args...))}
func fail(format string,args ...any) {panic(commandError(fmt.Sprintf(format,args...)))}
func (c *checker) get(name string) rectangle {r,exists:=c.rectangles[name];if !exists {fail("unknown rectangle %s",name)};return r}
func (c *checker) list(layer string) []rectangle {
    result:=[]rectangle{}
    for _,r:=range c.rectangles {if layer==""||r.layer==layer {result=append(result,r)}}
    sort.Slice(result,func(i,j int)bool{return result[i].name<result[j].name})
    return result
}
func (c *checker) require(layer string) []rectangle {list:=c.list(layer);if len(list)==0 {fail("no rectangles on %s",layer)};return list}
func (c *checker) remember(line string) {
    state:=map[string]rectangle{};for name,r:=range c.rectangles {state[name]=r}
    c.history=append(c.history,snapshot{state,line})
}
func checkBounds(r geometry) {if abs(r.x1)>10000||abs(r.y1)>10000||abs(r.x2)>10000||abs(r.y2)>10000 {fail("out of bounds")}}
func names(list []rectangle) string {parts:=[]string{};for _,r:=range list {parts=append(parts,r.name)};if len(parts)==0{return "none"};return strings.Join(parts," ")}
func nets(list []rectangle) [][]rectangle {
    result:=[][]rectangle{};seen:=map[string]bool{}
    for _,r:=range list {
        if seen[r.name] {continue}
        group:=[]rectangle{r};seen[r.name]=true
        for i:=0;i<len(group);i++ {for _,q:=range list {if !seen[q.name]&&connected(group[i],q) {seen[q.name]=true;group=append(group,q)}}}
        sort.Slice(group,func(i,j int)bool{return group[i].name<group[j].name});result=append(result,group)
    }
    return result
}
func spacing(list []rectangle,s int64) []violation {
    result:=[]violation{}
    for i,a:=range list {for _,b:=range list[i+1:] {
        r:=compare(a.geometry,b.geometry)
        if r.kind=="corner"||r.kind=="separate"&&r.gap<s {direction:=r.direction;if r.kind=="corner" {direction="corner"};result=append(result,violation{a.name,b.name,r.gap,direction})}
    }}
    sort.Slice(result,func(i,j int)bool {a,b:=result[i],result[j];return a.gap<b.gap||a.gap==b.gap&&(a.a<b.a||a.a==b.a&&a.b<b.b)})
    return result
}
func (c *checker) violationLines(list []violation) {for _,v:=range list {c.emit("%s %s gap %d %s",v.a,v.b,v.gap,v.direction)}}
func (c *checker) execute(line string) {
    defer func() {
        if caught := recover(); caught != nil {
            if message, ok := caught.(commandError); ok {
                c.emit("error: %s", message)
            } else { panic(caught) }
        }
    }()
    fields := strings.Split(line, " ")
    command, args := fields[0], fields[1:]
    if command == "ADD" {
        if _, exists := c.rectangles[args[0]]; exists { fail("duplicate rectangle %s", args[0]) }
        r := rectangle{args[0], args[1], geometry{number(args[2]), number(args[3]), number(args[4]), number(args[5])}}
        if r.x1 >= r.x2 || r.y1 >= r.y2 { fail("invalid rectangle") }
        checkBounds(r.geometry)
        c.remember(line)
        c.rectangles[r.name] = r
        c.emit("added %s %s %s", r.name, r.layer, notation(r.geometry))
        return
    }
    if command == "COPY" || command == "MOVE" || command == "RESIZE" || command == "SPLIT" || command == "LAYER" || command == "DELETE" {
        r := c.get(args[0])
        switch command {
        case "COPY":
            if _, exists := c.rectangles[args[1]]; exists { fail("duplicate rectangle %s", args[1]) }
            q := r
            q.name = args[1]
            dx, dy := number(args[2]), number(args[3])
            q.x1 += dx
            q.x2 += dx
            q.y1 += dy
            q.y2 += dy
            checkBounds(q.geometry)
            c.remember(line)
            c.rectangles[q.name] = q
            c.emit("copied %s to %s %s", r.name, q.name, notation(q.geometry))
        case "MOVE":
            dx, dy := number(args[1]), number(args[2])
            r.x1 += dx
            r.x2 += dx
            r.y1 += dy
            r.y2 += dy
            checkBounds(r.geometry)
            c.remember(line)
            c.rectangles[r.name] = r
            c.emit("moved %s to %s", r.name, notation(r.geometry))
        case "RESIZE":
            w, h := number(args[1]), number(args[2])
            if w <= 0 || h <= 0 { fail("invalid size") }
            r.x2, r.y2 = r.x1+w, r.y1+h
            checkBounds(r.geometry)
            c.remember(line)
            c.rectangles[r.name] = r
            c.emit("resized %s to %s", r.name, notation(r.geometry))
        case "SPLIT":
            if _, exists := c.rectangles[args[3]]; exists { fail("duplicate rectangle %s", args[3]) }
            pos := number(args[2])
            if args[1] == "x" && (pos <= r.x1 || pos >= r.x2) || args[1] == "y" && (pos <= r.y1 || pos >= r.y2) { fail("cut outside %s", r.name) }
            q := r
            q.name = args[3]
            if args[1] == "x" { r.x2, q.x1 = pos, pos } else { r.y2, q.y1 = pos, pos }
            c.remember(line)
            c.rectangles[r.name], c.rectangles[q.name] = r, q
            c.emit("split %s at %s=%d: %s %s, %s %s", r.name, args[1], pos, r.name, notation(r.geometry), q.name, notation(q.geometry))
        case "LAYER":
            if r.layer == args[1] { fail("already on %s", r.layer) }
            old := r.layer
            r.layer = args[1]
            c.remember(line)
            c.rectangles[r.name] = r
            c.emit("layer %s %s -> %s", r.name, old, r.layer)
        case "DELETE":
            c.remember(line)
            delete(c.rectangles, r.name)
            c.emit("deleted %s", r.name)
        }
        return
    }
    if command == "UNDO" {
        if len(c.history) == 0 { fail("nothing to undo") }
        last := c.history[len(c.history)-1]
        c.history = c.history[:len(c.history)-1]
        c.rectangles = last.rectangles
        c.emit("undo: %s", last.command)
        return
    }
    if command == "LIST" {
        c.emit("rectangles: %d", len(c.rectangles))
        for _, r := range c.list("") { c.emit("%s %s %s %dx%d", r.name, r.layer, notation(r.geometry), r.x2-r.x1, r.y2-r.y1) }
        return
    }
    if command == "INFO" {
        r := c.get(args[0])
        c.emit("%s %s %s %dx%d area %d", r.name, r.layer, notation(r.geometry), r.x2-r.x1, r.y2-r.y1, area(r.geometry))
        for _, kind := range []string{"overlap", "edge", "corner", "encloses", "enclosed by"} {
            selected := []rectangle{}
            for _, q := range c.list("") {
                if q.name == r.name { continue }
                relation := compare(r.geometry, q.geometry)
                matched := q.layer == r.layer && relation.kind == kind
                if kind == "encloses" { matched = encloses(r.geometry, q.geometry) }
                if kind == "enclosed by" { matched = encloses(q.geometry, r.geometry) }
                if matched { selected = append(selected, q) }
            }
            heading := map[string]string{"overlap":"overlaps", "edge":"touches", "corner":"corners", "encloses":"encloses", "enclosed by":"enclosed by"}[kind]
            c.emit("%s: %s", heading, names(selected))
        }
        return
    }
    if command == "LAYERS" {
        layers := map[string]bool{}
        for _, r := range c.rectangles { layers[r.layer] = true }
        list := []string{}
        for layer := range layers { list = append(list, layer) }
        sort.Strings(list)
        c.emit("layers: %d", len(list))
        for _, layer := range list {
            rectangles := c.list(layer)
            c.emit("%s: %d rectangles, area %d, nets %d", layer, len(rectangles), makeGrid(rectangles).covered(1, nil), len(nets(rectangles)))
        }
        return
    }
    if command == "OVERLAPS" {
        list := c.list("")
        if len(args) > 0 { list = c.require(args[0]) }
        type pair struct { a, b rectangle; r relation }
        pairs := []pair{}
        for i, a := range list {
            for _, b := range list[i+1:] {
                r := compare(a.geometry, b.geometry)
                if a.layer == b.layer && r.kind == "overlap" { pairs = append(pairs, pair{a, b, r}) }
            }
        }
        sort.Slice(pairs, func(i, j int) bool {
            a, b := pairs[i], pairs[j]
            return a.a.layer < b.a.layer || a.a.layer == b.a.layer && (a.a.name < b.a.name || a.a.name == b.a.name && a.b.name < b.b.name)
        })
        if len(args) == 0 { c.emit("overlaps all layers: %d", len(pairs)) } else { c.emit("overlaps %s: %d", args[0], len(pairs)) }
        for _, p := range pairs {
            prefix := ""
            if len(args) == 0 { prefix = p.a.layer+" " }
            c.emit("%s%s %s %s area %d", prefix, p.a.name, p.b.name, notation(p.r.geometry), p.r.ox*p.r.oy)
        }
        return
    }
    if command == "INTERSECT" || command == "ADJACENT" || command == "ENCLOSE" || command == "PATH" {
        a := c.get(args[0])
        b := c.get(args[1])
        if a.name == b.name { fail("same rectangle %s", a.name) }
        r := compare(a.geometry, b.geometry)
        switch command {
        case "INTERSECT":
            switch r.kind {
            case "overlap": c.emit("intersect %s %s: %s area %d", a.name, b.name, notation(r.geometry), r.ox*r.oy)
            case "edge": c.emit("intersect %s %s: segment %s length %d", a.name, b.name, notation(r.geometry), r.ox+r.oy)
            case "corner": c.emit("intersect %s %s: point %s", a.name, b.name, point(r.x1, r.y1))
            default: c.emit("intersect %s %s: none, gap %d", a.name, b.name, r.gap)
            }
        case "ADJACENT":
            switch r.kind {
            case "overlap": c.emit("adjacent %s %s: overlapping", a.name, b.name)
            case "corner": c.emit("adjacent %s %s: corner only at %s", a.name, b.name, point(r.x1, r.y1))
            case "edge":
                direction := "north"
                if r.ox == 0 {
                    direction = "east"
                    if a.x2 == r.x1 { direction = "west" }
                } else if a.y2 == r.y1 { direction = "south" }
                c.emit("adjacent %s %s: %s is %s of %s, edge %s, length %d", a.name, b.name, a.name, direction, b.name, notation(r.geometry), r.ox+r.oy)
            default: c.emit("adjacent %s %s: not adjacent", a.name, b.name)
            }
        case "ENCLOSE":
            m := margins(a.geometry, b.geometry)
            text := fmt.Sprintf("margins left %d bottom %d right %d top %d", m[0], m[1], m[2], m[3])
            if minimum(m) >= 0 { c.emit("enclose %s %s: yes, %s, min %d", a.name, b.name, text, minimum(m)) } else { c.emit("enclose %s %s: no, %s", a.name, b.name, text) }
        case "PATH":
            if a.layer != b.layer { fail("different layers") }
            queue := []rectangle{a}
            parents := map[string]string{a.name:""}
            for i := 0; i < len(queue); i++ {
                for _, q := range c.list(a.layer) {
                    if _, seen := parents[q.name]; !seen && connected(queue[i], q) { parents[q.name] = queue[i].name; queue = append(queue, q) }
                }
            }
            if _, found := parents[b.name]; !found { c.emit("path %s %s: none", a.name, b.name) } else {
                path := []string{}
                for name := b.name; name != ""; name = parents[name] { path = append(path, name) }
                for i, j := 0, len(path)-1; i < j; i, j = i+1, j-1 { path[i], path[j] = path[j], path[i] }
                c.emit("path %s %s: %s (%d steps)", a.name, b.name, strings.Join(path, " -> "), len(path)-1)
            }
        }
        return
    }
    if command == "AT" {
        x, y := number(args[0]), number(args[1])
        parts := []string{}
        for _, r := range c.list("") {
            if x < r.x1 || x > r.x2 || y < r.y1 || y > r.y2 { continue }
            vertical, horizontal := x == r.x1 || x == r.x2, y == r.y1 || y == r.y2
            position := "inside"
            if vertical && horizontal { position = "corner" } else if vertical || horizontal { position = "edge" }
            parts = append(parts, r.name+" "+r.layer+" "+position)
        }
        text := "none"
        if len(parts) > 0 { text = strings.Join(parts, ", ") }
        c.emit("at %s: %s", point(x, y), text)
        return
    }
    if command == "NEAREST" {
        r := c.get(args[0])
        var nearest *rectangle
        gap := int64(0)
        for _, q := range c.list(r.layer) {
            if q.name == r.name { continue }
            value := compare(r.geometry, q.geometry).gap
            if nearest == nil || value < gap { item := q; nearest = &item; gap = value }
        }
        if nearest == nil { c.emit("nearest %s: none", r.name) } else { c.emit("nearest %s: %s gap %d", r.name, nearest.name, gap) }
        return
    }
    if command == "RULE" {
        kind := strings.ToLower(args[0])
        r := rule{kind:kind, inner:args[1]}
        if kind == "enclose" {
            r.outer, r.value = args[2], number(args[3])
            if r.inner == r.outer { fail("same layer %s", r.inner) }
        } else { r.value = number(args[2]) }
        c.rules[kind+":"+r.inner+":"+r.outer] = r
        if kind == "enclose" { c.emit("rule enclose %s %s %d", r.inner, r.outer, r.value) } else { c.emit("rule %s %s %d", kind, r.inner, r.value) }
        return
    }
    if command == "CHECK" { c.check(); return }
    layer := args[0]
    if command == "COVER" { layer = args[1] }
    list := c.require(layer)
    g := makeGrid(list)
    switch command {
    case "AREA": c.emit("area %s: %d", layer, g.covered(1, nil))
    case "COVER": c.emit("cover %s >= %d: %d", layer, number(args[0]), g.covered(int(number(args[0])), nil))
    case "PERIMETER": c.emit("perimeter %s: %d", layer, g.perimeter())
    case "NETS":
        groups := nets(list)
        c.emit("nets %s: %d", layer, len(groups))
        for i, group := range groups { c.emit("net %d: %s area %d", i+1, names(group), makeGrid(group).covered(1, nil)) }
    case "DRC":
        violations := spacing(list, number(args[1]))
        c.emit("drc %s spacing %d: %d violations", layer, number(args[1]), len(violations))
        c.violationLines(violations)
    case "BBOX":
        r := bounds(list)
        c.emit("bbox %s: %s %dx%d, %d rectangles, density %s%%", layer, notation(r), r.x2-r.x1, r.y2-r.y1, len(list), decimal(100*g.covered(1, nil), area(r)))
    case "DENSITY": c.density(layer, list, g, number(args[1]))
    case "RENDER":
        r := geometry{number(args[1]), number(args[2]), number(args[3]), number(args[4])}
        if r.x1 >= r.x2 || r.y1 >= r.y2 { fail("invalid window") }
        if r.x2-r.x1 > 60 || r.y2-r.y1 > 40 { fail("window too large") }
        c.emit("render %s %s", layer, notation(r))
        for y := r.y2-1; y >= r.y1; y-- {
            var row strings.Builder
            for x := r.x1; x < r.x2; x++ {
                count := 0
                for _, q := range list { if x >= q.x1 && x < q.x2 && y >= q.y1 && y < q.y2 { count++ } }
                character := byte('.')
                if count >= 10 { character = '*' } else if count > 0 { character = byte('0'+count) }
                row.WriteByte(character)
            }
            c.emit("%s", row.String())
        }
    case "EMPTY":
        r := g.empty()
        if r == nil { c.emit("empty %s: none", layer) } else { c.emit("empty %s: %s area %d", layer, notation(*r), area(*r)) }
    case "HOLES":
        holes := g.holes()
        c.emit("holes %s: %d", layer, len(holes))
        for i, h := range holes { c.emit("hole %d: area %d, bbox %s", i+1, h.area, notation(h.geometry)) }
    case "MERGE":
        pieces := g.pieces()
        c.emit("merge %s: %d pieces", layer, len(pieces))
        for _, r := range pieces { c.emit("%s", notation(r)) }
    }
}
func (c *checker) density(layer string, list []rectangle, g grid, w int64) {
    r := bounds(list)
    columns, rows := (r.x2-r.x1+w-1)/w, (r.y2-r.y1+w-1)/w
    if columns > 20 || rows > 20 { fail("too many windows") }
    values := make([][]int64, int(rows))
    var lowest, highest int64
    lowX, lowY, highX, highY := int64(0), int64(0), int64(0), int64(0)
    for y := int64(0); y < rows; y++ {
        values[y] = make([]int64, int(columns))
        for x := int64(0); x < columns; x++ {
            tile := geometry{r.x1+x*w, r.y1+y*w, r.x1+(x+1)*w, r.y1+(y+1)*w}
            v := g.covered(1, &tile)
            values[y][x] = v
            if x == 0 && y == 0 || v < lowest { lowest, lowX, lowY = v, x, y }
            if x == 0 && y == 0 || v > highest { highest, highX, highY = v, x, y }
        }
    }
    c.emit("density %s window %d: %dx%d", layer, w, columns, rows)
    for y := rows-1; y >= 0; y-- {
        parts := []string{}
        for _, v := range values[y] { parts = append(parts, strconv.FormatInt(100*v/(w*w), 10)) }
        c.emit("%s", strings.Join(parts, " "))
    }
    c.emit("min %s%% at %s", decimal(100*lowest, w*w), point(r.x1+lowX*w, r.y1+lowY*w))
    c.emit("max %s%% at %s", decimal(100*highest, w*w), point(r.x1+highX*w, r.y1+highY*w))
}

func (c *checker) check() {
    if len(c.rules) == 0 { fail("no rules") }
    rules := []rule{}
    for _, r := range c.rules { rules = append(rules, r) }
    sort.Slice(rules, func(i, j int) bool {
        a, b := rules[i], rules[j]
        return a.kind < b.kind || a.kind == b.kind && (a.inner < b.inner || a.inner == b.inner && a.outer < b.outer)
    })
    total := 0
    for _, r := range rules {
        list := c.list(r.inner)
        lines := []string{}
        switch r.kind {
        case "spacing":
            for _, v := range spacing(list, r.value) { lines = append(lines, fmt.Sprintf("%s %s gap %d %s", v.a, v.b, v.gap, v.direction)) }
        case "width":
            for _, q := range list {
                w := min(q.x2-q.x1, q.y2-q.y1)
                if w < r.value { lines = append(lines, fmt.Sprintf("%s width %d", q.name, w)) }
            }
        case "enclose":
            outer := c.list(r.outer)
            for _, q := range list {
                best := int64(-1<<62)
                for _, p := range outer { best = max(best, minimum(margins(p.geometry, q.geometry))) }
                if len(outer) == 0 { lines = append(lines, q.name+" best margin none") } else if best < r.value { lines = append(lines, fmt.Sprintf("%s best margin %d", q.name, best)) }
            }
        }
        if r.kind == "enclose" { c.emit("enclose %s %s %d: %d violations", r.inner, r.outer, r.value, len(lines)) } else { c.emit("%s %s %d: %d violations", r.kind, r.inner, r.value, len(lines)) }
        for _, line := range lines { c.emit("%s", line) }
        total += len(lines)
    }
    c.emit("check: %d violations in %d rules", total, len(rules))
}

func main() {
    scanner := bufio.NewScanner(os.Stdin)
    scanner.Scan()
    count := int(number(scanner.Text()))
    c := checker{rectangles:map[string]rectangle{}, rules:map[string]rule{}}
    for i := 0; i < count && scanner.Scan(); i++ { c.execute(scanner.Text()) }
    out := bufio.NewWriter(os.Stdout)
    defer out.Flush()
    for _, line := range c.output { fmt.Fprintln(out, line) }
}
