package main

import (
    "bufio"
    "fmt"
    "os"
    "io"
    "sort"
    "strconv"
    "strings"
)

type declaration struct { property, value string }
type rule struct { selectors []string; declarations []declaration }
type element struct {
    kind, id, text string
    classes map[string]bool
    parent *element
    children []*element
    depth, index int
    inline, style map[string]string
    displayed bool
    cw, ch, rx, ry, x, y int
    lines []string
    containing *element
}
type rectangle struct { x,y,w,h int }
type placement struct { e *element; row,col,rows,cols int }
type track struct { kind string; value int }
type document struct { width,height int; rules []rule; elements []*element; byID map[string]*element; output []string }
var initial=map[string]string{
    "display":"block", "position":"static", "box-sizing":"content-box", "width":"auto", "height":"auto",
    "min-width":"0", "min-height":"0", "max-width":"none", "max-height":"none",
    "top":"auto", "right":"auto", "bottom":"auto", "left":"auto",
    "flex-direction":"row", "flex-wrap":"nowrap", "justify-content":"start", "align-items":"stretch", "align-self":"auto",
    "row-gap":"0", "column-gap":"0", "order":"0", "flex-grow":"0", "flex-shrink":"1", "flex-basis":"auto",
    "grid-template-columns":"none", "grid-template-rows":"none", "grid-column":"auto", "grid-row":"auto",
}
func number(s string) int { n,_:=strconv.Atoi(s); return n }
func pointer(n int) *int { return &n }
func max(a,b int) int { if a>b {return a};return b }
func min(a,b int) int { if a<b {return a};return b }
func contains(value string, choices ...string) bool { for _,choice:=range choices {if value==choice{return true}};return false }
func unsigned(s string) bool { if len(s)<1||len(s)>3{return false};for _,c:=range s {if c<'0'||c>'9'{return false}};return true }
func positive(s string) bool { return unsigned(s)&&number(s)>0 }
func signed(s string) bool { return unsigned(s)||strings.HasPrefix(s,"-")&&unsigned(s[1:]) }
func percentage(s string) bool { return strings.HasSuffix(s,"%")&&unsigned(s[:len(s)-1]) }
func gridValue(value string) bool {
    parts:=strings.Split(value," ")
    if len(parts)==1{return parts[0]=="auto"||positive(parts[0])}
    if len(parts)==2{return parts[0]=="span"&&positive(parts[1])}
    if len(parts)==3{return positive(parts[0])&&parts[1]=="/"&&positive(parts[2])&&number(parts[0])<number(parts[2])}
    return len(parts)==4&&positive(parts[0])&&parts[1]=="/"&&parts[2]=="span"&&positive(parts[3])
}
func valid(property,value string) ([]declaration,bool) {
    parts:=strings.Split(value," ")
    if contains(property,"margin","padding","border","gap") {
        limit:=4;if property=="gap"{limit=2};if len(parts)<1||len(parts)>limit{return nil,false}
        for _,part:=range parts {if !unsigned(part)||property=="border"&&!contains(part,"0","1"){return nil,false}}
        if property=="gap" {second:=parts[0];if len(parts)==2{second=parts[1]};return []declaration{{"row-gap",parts[0]},{"column-gap",second}},true}
        values:=[4]string{parts[0],parts[0],parts[0],parts[0]};if len(parts)>1{values[1],values[3]=parts[1],parts[1]};if len(parts)>2{values[2]=parts[2]};if len(parts)>3{values[3]=parts[3]}
        result:=[]declaration{};for i,side:=range []string{"top","right","bottom","left"}{result=append(result,declaration{property+"-"+side,values[i]})};return result,true
    }
    if _,known:=initial[property];!known{return nil,false}
    good:=false
    if strings.HasPrefix(property,"grid-template-") {
        good=value=="none"
        if !good {good=true;for _,part:=range parts {if !unsigned(part)&&part!="auto"&&!(strings.HasSuffix(part,"fr")&&positive(part[:len(part)-2])) {good=false;break}}}
    }else if property=="grid-column"||property=="grid-row"{good=gridValue(value)}else if len(parts)==1 {
        switch property {
        case "display":good=contains(value,"block","flex","grid","none")
        case "position":good=contains(value,"static","relative","absolute")
        case "box-sizing":good=contains(value,"content-box","border-box")
        case "width","height","flex-basis":good=value=="auto"||unsigned(value)||percentage(value)
        case "min-width","min-height":good=unsigned(value)||percentage(value)
        case "max-width","max-height":good=value=="none"||unsigned(value)||percentage(value)
        case "top","right","bottom","left":good=value=="auto"||signed(value)
        case "flex-direction":good=contains(value,"row","row-reverse","column","column-reverse")
        case "flex-wrap":good=contains(value,"nowrap","wrap")
        case "justify-content":good=contains(value,"start","end","center","space-between","space-around","space-evenly")
        case "align-items":good=contains(value,"stretch","start","end","center")
        case "align-self":good=contains(value,"auto","stretch","start","end","center")
        case "order":good=signed(value)
        default:if strings.HasPrefix(property,"border-"){good=contains(value,"0","1")}else{good=unsigned(value)}
        }
    }
    if !good{return nil,false};return []declaration{{property,value}},true
}
func (e *element) n(property string) int {return number(e.style[property])}
func (e *element) frame(horizontal bool) int {if horizontal{return e.n("padding-left")+e.n("padding-right")+e.n("border-left")+e.n("border-right")};return e.n("padding-top")+e.n("padding-bottom")+e.n("border-top")+e.n("border-bottom")}
func (e *element) margin(horizontal bool) int {if horizontal{return e.n("margin-left")+e.n("margin-right")};return e.n("margin-top")+e.n("margin-bottom")}
func (e *element) resolve(property string,reference *int,horizontal bool) *int {
    value:=e.style[property];if value=="auto"||value=="none"{return nil};n:=0
    if strings.HasSuffix(value,"%") {if reference==nil{return nil};n=*reference*number(value[:len(value)-1])/100}else{n=number(value)}
    if e.style["box-sizing"]=="border-box"{n=max(0,n-e.frame(horizontal))};return pointer(n)
}
func (e *element) clamp(value int,reference *int,horizontal bool) int {
    axis:="height";if horizontal{axis="width"};lower,upper:=e.resolve("min-"+axis,reference,horizontal),e.resolve("max-"+axis,reference,horizontal)
    if upper!=nil{value=min(value,*upper)};if lower!=nil{value=max(value,*lower)};return value
}
func (e *element) flow() []*element {result:=[]*element{};for _,child:=range e.children {if child.displayed&&child.style["position"]!="absolute"{result=append(result,child)}};return result}
func (e *element) items() []*element {result:=e.flow();sort.SliceStable(result,func(i,j int)bool{return result[i].n("order")<result[j].n("order")});return result}
func (e *element) align(parent *element) string {if e.style["align-self"]!="auto"{return e.style["align-self"]};return parent.style["align-items"]}
func (e *element) border() rectangle {return rectangle{e.x,e.y,e.cw+e.frame(true),e.ch+e.frame(false)}}
func (e *element) content() rectangle {return rectangle{e.x+e.n("border-left")+e.n("padding-left"),e.y+e.n("border-top")+e.n("padding-top"),e.cw,e.ch}}
func (e *element) marginBox() rectangle {r:=e.border();r.x-=e.n("margin-left");r.y-=e.n("margin-top");r.w+=e.margin(true);r.h+=e.margin(false);return r}
func distribute(total int,weights []int) []int {
    result:=make([]int,len(weights));sum:=0;for _,w:=range weights{sum+=w};if sum==0{return result};used:=0
    for i,w:=range weights{result[i]=total*w/sum;used+=result[i]};for i,w:=range weights{if used==total{break};if w>0{result[i]++;used++}};return result
}
func gridSpec(value string)(int,int){p:=strings.Split(value," ");if value=="auto"{return 0,1};if p[0]=="span"{return 0,number(p[1])};start:=number(p[0]);if len(p)==1{return start,1};if len(p)==3{return start,number(p[2])-start};return start,number(p[3])}
func tracks(value string,columns bool) []track {
    if value=="none"{if columns{return []track{{kind:"auto"}}};return nil};result:=[]track{}
    for _,word:=range strings.Split(value," "){t:=track{kind:"fixed",value:number(word)};if word=="auto"{t.kind="auto"}else if strings.HasSuffix(word,"fr"){t.kind="fr";t.value=number(word[:len(word)-2])};result=append(result,t)};return result
}
func (d *document) placement(e *element) ([]placement,int,int) {
    columns := len(tracks(e.style["grid-template-columns"],true))
    rows := len(tracks(e.style["grid-template-rows"],false))
    items := []placement{}
    for _,child := range e.items() {
        c,cs := gridSpec(child.style["grid-column"])
        r,rs := gridSpec(child.style["grid-row"])
        items = append(items,placement{child,r,c,rs,cs})
        if c > 0 { columns = max(columns,c+cs-1) } else { columns = max(columns,cs) }
    }
    occupied := map[[2]int]bool{}
    overlaps := func(p placement,r,c int) bool {
        for y := r; y < r+p.rows; y++ {
            for x := c; x < c+p.cols; x++ {
                if occupied[[2]int{y,x}] { return true }
            }
        }
        return false
    }
    mark := func(p placement) {
        for y := p.row; y < p.row+p.rows; y++ {
            for x := p.col; x < p.col+p.cols; x++ { occupied[[2]int{y,x}] = true }
        }
    }
    for _,p := range items { if p.row > 0 && p.col > 0 { mark(p) } }
    cr,cc := 1,1
    for i := range items {
        p := &items[i]
        if p.row > 0 && p.col > 0 { continue }
        if p.row > 0 {
            p.col = 1
            for c := 1; c <= columns-p.cols+1; c++ {
                if !overlaps(*p,p.row,c) { p.col = c; break }
            }
        } else if p.col > 0 {
            if p.col < cc { cr++ }
            r := cr
            for overlaps(*p,r,p.col) { r++ }
            p.row,cr,cc = r,r,p.col+p.cols
        } else {
            r,c := cr,cc
            for {
                if c+p.cols-1 > columns { r++; c = 1 } else if overlaps(*p,r,c) { c++ } else { break }
            }
            p.row,p.col,cr,cc = r,c,r,c+p.cols
        }
        mark(*p)
    }
    for _,p := range items { rows = max(rows,p.row+p.rows-1) }
    return items,columns,rows
}
func trackSizes(spec []track,count int,available *int,gap int,items []placement,contributions []int,horizontal bool) []int {
    sizes,weights := make([]int,count),make([]int,count)
    kinds := make([]string,count)
    hasFR := false
    for i := 0; i < count; i++ {
        t := track{kind:"auto"}
        if i < len(spec) { t = spec[i] }
        kinds[i] = t.kind
        if t.kind == "fixed" {
            sizes[i] = t.value
        } else if t.kind == "auto" || available == nil {
            for j,p := range items {
                start,span := p.col,p.cols
                if !horizontal { start,span = p.row,p.rows }
                if start == i+1 && span == 1 { sizes[i] = max(sizes[i],contributions[j]) }
            }
        }
        if t.kind == "fr" { weights[i],hasFR = t.value,true }
    }
    if available != nil && count > 0 {
        left := *available-sum(sizes)-gap*(count-1)
        if left > 0 {
            if !hasFR { for i,kind := range kinds { if kind == "auto" { weights[i] = 1 } } }
            extra := distribute(left,weights)
            for i := range sizes { sizes[i] += extra[i] }
        }
    }
    return sizes
}
func sum(values []int) int {
    result := 0
    for _,value := range values { result += value }
    return result
}
func (d *document) contribution(e *element) int {
    value := e.resolve("width",nil,true)
    width := 0
    if value == nil { width = d.maxContent(e) } else { width = *value }
    return e.clamp(width,nil,true)+e.frame(true)+e.margin(true)
}
func (d *document) maxContent(e *element) int {
    if e.text != "" { return len(e.text) }
    children := e.flow()
    if e.style["display"] == "flex" && strings.HasPrefix(e.style["flex-direction"],"row") {
        value := 0
        for _,child := range children { value += d.contribution(child) }
        if len(children) > 0 { value += e.n("column-gap")*(len(children)-1) }
        return value
    }
    if e.style["display"] == "grid" {
        items,nc,_ := d.placement(e)
        values := make([]int,len(items))
        for i,p := range items { values[i] = d.contribution(p.e) }
        sizes := trackSizes(tracks(e.style["grid-template-columns"],true),nc,nil,e.n("column-gap"),items,values,true)
        return sum(sizes)+e.n("column-gap")*(nc-1)
    }
    value := 0
    for _,child := range children { value = max(value,d.contribution(child)) }
    return value
}
func wrap(text string,width int) []string {
    lines := []string{}
    for _,word := range strings.Split(text," ") {
        if len(lines) == 0 || len(lines[len(lines)-1])+1+len(word) > width {
            lines = append(lines,word)
        } else {
            lines[len(lines)-1] += " "+word
        }
    }
    return lines
}
func (d *document) layoutElement(e *element,cw int,ch,fw,fh *int) int {
    if fw != nil { e.cw = *fw } else {
        value := e.resolve("width",pointer(cw),true)
        width := max(0,cw-e.margin(true)-e.frame(true))
        if value != nil { width = *value }
        e.cw = e.clamp(width,pointer(cw),true)
    }
    if fh == nil {
        if value := e.resolve("height",ch,false); value != nil { fh = pointer(e.clamp(*value,ch,false)) }
    }
    a := 0
    e.lines = nil
    if e.text != "" { e.lines = wrap(e.text,e.cw); a = len(e.lines) } else {
        switch e.style["display"] {
        case "flex": a = d.flex(e,fh,ch)
        case "grid": a = d.grid(e,fh)
        default: a = d.block(e,fh)
        }
    }
    if fh != nil { e.ch = *fh } else { e.ch = e.clamp(a,ch,false) }
    return a
}
func position(e,child *element,x,y int) {
    child.rx = x+e.n("border-left")+e.n("padding-left")
    child.ry = y+e.n("border-top")+e.n("padding-top")
}
func (d *document) block(e *element,k *int) int {
    bottom,previous,count := 0,0,0
    for _,child := range e.flow() {
        d.layoutElement(child,e.cw,k,nil,nil)
        y := child.n("margin-top")
        if count > 0 { y = bottom+max(previous,y) }
        position(e,child,child.n("margin-left"),y)
        bottom,previous = y+child.ch+child.frame(false),child.n("margin-bottom")
        count++
    }
    if count == 0 { return 0 }
    return bottom+previous
}
type flexItem struct {
    e *element
    base,hypothetical,outer,cross,weight,size int
    frozen bool
}
func (d *document) flex(e *element,k,ch *int) int {
    horizontal := strings.HasPrefix(e.style["flex-direction"],"row")
    reversed := strings.HasSuffix(e.style["flex-direction"],"reverse")
    mainRef,gap := k,e.n("row-gap")
    if horizontal { mainRef,gap = pointer(e.cw),e.n("column-gap") }
    items := []*flexItem{}
    for _,child := range e.items() {
        item := &flexItem{e:child,outer:child.frame(horizontal)+child.margin(horizontal)}
        if !horizontal {
            r := max(0,e.cw-child.frame(true)-child.margin(true))
            c := r
            if child.style["width"] != "auto" { c = *child.resolve("width",pointer(e.cw),true) } else if child.align(e) != "stretch" { c = min(d.maxContent(child),r) }
            item.cross = child.clamp(c,pointer(e.cw),true)
        }
        base := child.resolve("flex-basis",mainRef,horizontal)
        if base == nil {
            property := "height"
            if horizontal { property = "width" }
            base = child.resolve(property,mainRef,horizontal)
        }
        if base != nil { item.base = *base } else if horizontal { item.base = d.maxContent(child) } else { item.base = d.layoutElement(child,e.cw,k,pointer(item.cross),nil) }
        item.hypothetical = child.clamp(item.base,mainRef,horizontal)
        items = append(items,item)
    }
    length := 0
    if horizontal { length = e.cw } else if k != nil { length = *k } else {
        for _,item := range items { length += item.hypothetical+item.outer }
        if len(items) > 0 { length += gap*(len(items)-1) }
        length = e.clamp(length,ch,false)
    }
    lines := [][]*flexItem{}
    used := 0
    for _,item := range items {
        if len(lines) == 0 { lines = append(lines,[]*flexItem{}); used = 0 }
        last := len(lines)-1
        if horizontal && e.style["flex-wrap"] == "wrap" && len(lines[last]) > 0 && used+gap+item.hypothetical+item.outer > length {
            lines = append(lines,[]*flexItem{})
            last++
            used = 0
        }
        if len(lines[last]) > 0 { used += gap }
        lines[last] = append(lines[last],item)
        used += item.hypothetical+item.outer
    }
    crossStart,totalCross := 0,0
    for _,line := range lines {
        gaps := gap*(len(line)-1)
        hypothetical := gaps
        for _,item := range line { hypothetical += item.hypothetical+item.outer }
        growing := hypothetical < length
        for _,item := range line {
            if growing { item.weight = item.e.n("flex-grow") } else { item.weight = item.e.n("flex-shrink")*item.base }
            item.frozen = item.weight == 0 || growing && item.base > item.hypothetical || !growing && item.base < item.hypothetical
            item.size = item.hypothetical
        }
        for {
            free,unfrozen := length-gaps,0
            weights := make([]int,len(line))
            for i,item := range line {
                if item.frozen { free -= item.size+item.outer } else {
                    free -= item.base+item.outer
                    weights[i] = item.weight
                    unfrozen++
                }
            }
            if unfrozen == 0 { break }
            amount := max(0,free)
            if !growing { amount = max(0,-free) }
            assignments := distribute(amount,weights)
            violations := make([]int,len(line))
            totalViolation := 0
            for i,item := range line {
                if item.frozen { continue }
                tentative := item.base+assignments[i]
                if !growing { tentative = item.base-assignments[i] }
                item.size = item.e.clamp(tentative,mainRef,horizontal)
                violations[i] = item.size-tentative
                totalViolation += violations[i]
            }
            for i,item := range line {
                if !item.frozen && (totalViolation == 0 || totalViolation > 0 && violations[i] > 0 || totalViolation < 0 && violations[i] < 0) { item.frozen = true }
            }
        }
        lc := e.cw
        if horizontal {
            lc = 0
            for _,item := range line {
                d.layoutElement(item.e,e.cw,k,pointer(item.size),nil)
                item.cross = item.e.ch
                lc = max(lc,item.cross+item.e.frame(false)+item.e.margin(false))
            }
            if len(lines) == 1 { if k != nil { lc = *k } else { lc = e.clamp(lc,ch,false) } }
        }
        remaining := length-gaps
        for _,item := range line { remaining -= item.size+item.outer }
        spaces := make([]int,len(line))
        if remaining > 0 {
            switch e.style["justify-content"] {
            case "end": spaces[0] = remaining
            case "center": spaces[0] = remaining/2
            case "space-between","space-around","space-evenly":
                weights := make([]int,len(line)+1)
                for i := range weights {
                    switch e.style["justify-content"] {
                    case "space-between": if i > 0 && i < len(line) { weights[i] = 1 }
                    case "space-around": weights[i] = 2; if i == 0 || i == len(line) { weights[i] = 1 }
                    default: weights[i] = 1
                    }
                }
                copy(spaces,distribute(remaining,weights))
            }
        }
        cursor := 0
        for i,item := range line {
            child,c := item.e,item.cross
            align := child.align(e)
            if horizontal {
                if align == "stretch" && child.style["height"] == "auto" {
                    c = child.clamp(max(0,lc-child.frame(false)-child.margin(false)),k,false)
                    d.layoutElement(child,e.cw,k,pointer(item.size),pointer(c))
                } else {
                    d.layoutElement(child,e.cw,k,pointer(item.size),nil)
                    c = child.ch
                }
            } else { d.layoutElement(child,e.cw,k,pointer(c),pointer(item.size)) }
            q := lc-c-child.frame(!horizontal)-child.margin(!horizontal)
            offset := 0
            if q > 0 { if align == "end" { offset = q } else if align == "center" { offset = q/2 } }
            cursor += spaces[i]
            side := "margin-top"
            if horizontal { side = "margin-left" }
            if reversed { if horizontal { side = "margin-right" } else { side = "margin-bottom" } }
            main := cursor+child.n(side)
            if reversed { main = length-cursor-child.n(side)-item.size-child.frame(horizontal) }
            cross := crossStart+offset+child.n("margin-top")
            if !horizontal { cross = offset+child.n("margin-left") }
            if horizontal { position(e,child,main,cross) } else { position(e,child,cross,main) }
            cursor += item.size+item.outer+gap
        }
        crossStart += lc+e.n("row-gap")
        totalCross += lc
    }
    if !horizontal { return length }
    if len(lines) > 0 { totalCross += e.n("row-gap")*(len(lines)-1) }
    return totalCross
}
func area(sizes []int,start,span,gap int) (int,int) {
    return sum(sizes[start-1:start-1+span])+gap*(span-1),sum(sizes[:start-1])+gap*(start-1)
}
func (d *document) grid(e *element,k *int) int {
    items,nc,nr := d.placement(e)
    contributions := make([]int,len(items))
    for i,p := range items { contributions[i] = d.contribution(p.e) }
    columns := trackSizes(tracks(e.style["grid-template-columns"],true),nc,pointer(e.cw),e.n("column-gap"),items,contributions,true)
    widths,positions,actual := make([]int,len(items)),make([]int,len(items)),make([]int,len(items))
    for i,p := range items {
        aw,ax := area(columns,p.col,p.cols,e.n("column-gap"))
        value := p.e.resolve("width",pointer(aw),true)
        gw := max(0,aw-p.e.frame(true)-p.e.margin(true))
        if value != nil { gw = *value }
        gw = p.e.clamp(gw,pointer(aw),true)
        widths[i],positions[i],actual[i] = aw,ax,gw
        d.layoutElement(p.e,aw,nil,pointer(gw),nil)
        contributions[i] = p.e.ch+p.e.frame(false)+p.e.margin(false)
    }
    rows := trackSizes(tracks(e.style["grid-template-rows"],false),nr,k,e.n("row-gap"),items,contributions,false)
    for i,p := range items {
        ah,ay := area(rows,p.row,p.rows,e.n("row-gap"))
        child := p.e
        var fh *int
        if child.align(e) == "stretch" && child.style["height"] == "auto" { fh = pointer(child.clamp(max(0,ah-child.frame(false)-child.margin(false)),pointer(ah),false)) }
        d.layoutElement(child,widths[i],pointer(ah),pointer(actual[i]),fh)
        q := ah-child.ch-child.frame(false)-child.margin(false)
        offset := 0
        if q > 0 { if child.align(e) == "end" { offset = q } else if child.align(e) == "center" { offset = q/2 } }
        position(e,child,positions[i]+child.n("margin-left"),ay+offset+child.n("margin-top"))
    }
    if nr == 0 { return 0 }
    return sum(rows)+e.n("row-gap")*(nr-1)
}
func (d *document) cascade() {
    for _,e := range d.elements {
        e.style = map[string]string{}
        for property,value := range initial { e.style[property] = value }
        specificities := map[string]int{}
        for _,r := range d.rules {
            specificity := -1
            for _,selector := range r.selectors {
                if strings.HasPrefix(selector,"#") {
                    if e.id == selector[1:] { specificity = max(specificity,2) }
                } else if strings.HasPrefix(selector,".") {
                    if e.classes[selector[1:]] { specificity = max(specificity,1) }
                } else if e.kind == selector { specificity = max(specificity,0) }
            }
            if specificity < 0 { continue }
            for _,decl := range r.declarations {
                old,exists := specificities[decl.property]
                if !exists || specificity >= old {
                    e.style[decl.property] = decl.value
                    specificities[decl.property] = specificity
                }
            }
        }
        for property,value := range e.inline { e.style[property] = value }
        e.displayed = e.style["display"] != "none" && (e.parent == nil || e.parent.displayed)
        e.containing = nil
    }
}
func (d *document) layout() {
    d.cascade()
    root := d.elements[0]
    if root.displayed && root.style["position"] != "absolute" {
        d.layoutElement(root,d.width,pointer(d.height),nil,nil)
        root.rx,root.ry = root.n("margin-left"),root.n("margin-top")
    }
    for _,e := range d.elements {
        if !e.displayed || e.style["position"] != "absolute" { continue }
        ancestor := e.parent
        for ancestor != nil && ancestor.style["position"] == "static" { ancestor = ancestor.parent }
        e.containing = ancestor
        cbw,cbh := d.width,d.height
        if ancestor != nil {
            cbw = ancestor.cw+ancestor.n("padding-left")+ancestor.n("padding-right")
            cbh = ancestor.ch+ancestor.n("padding-top")+ancestor.n("padding-bottom")
        }
        value := e.resolve("width",pointer(cbw),true)
        w := 0
        if value != nil { w = *value } else {
            r := cbw-e.margin(true)-e.frame(true)
            if e.style["left"] != "auto" { r -= e.n("left") }
            if e.style["right"] != "auto" { r -= e.n("right") }
            r = max(0,r)
            if e.style["left"] != "auto" && e.style["right"] != "auto" { w = r } else { w = min(d.maxContent(e),r) }
        }
        w = e.clamp(w,pointer(cbw),true)
        var fh *int
        if e.style["height"] == "auto" && e.style["top"] != "auto" && e.style["bottom"] != "auto" {
            fh = pointer(e.clamp(max(0,cbh-e.n("top")-e.n("bottom")-e.margin(false)-e.frame(false)),pointer(cbh),false))
        }
        d.layoutElement(e,cbw,pointer(cbh),pointer(w),fh)
        e.rx = e.n("margin-left")
        if e.style["left"] != "auto" { e.rx += e.n("left") } else if e.style["right"] != "auto" { e.rx = cbw-e.n("right")-e.n("margin-right")-e.cw-e.frame(true) }
        e.ry = e.n("margin-top")
        if e.style["top"] != "auto" { e.ry += e.n("top") } else if e.style["bottom"] != "auto" { e.ry = cbh-e.n("bottom")-e.n("margin-bottom")-e.ch-e.frame(false) }
    }
    for _,e := range d.elements {
        if !e.displayed { continue }
        x,y := 0,0
        if e.style["position"] == "absolute" {
            if e.containing != nil { x,y = e.containing.x+e.containing.n("border-left"),e.containing.y+e.containing.n("border-top") }
        } else if e.parent != nil { x,y = e.parent.x,e.parent.y }
        e.x,e.y = x+e.rx,y+e.ry
        if e.style["position"] == "relative" {
            if e.style["left"] != "auto" { e.x += e.n("left") } else if e.style["right"] != "auto" { e.x -= e.n("right") }
            if e.style["top"] != "auto" { e.y += e.n("top") } else if e.style["bottom"] != "auto" { e.y -= e.n("bottom") }
        }
    }
}
func (d *document) emit(format string,args ...any) { d.output = append(d.output,fmt.Sprintf(format,args...)) }
func (d *document) snapshot() [][5]int {
    result := make([][5]int,len(d.elements))
    for i,e := range d.elements {
        if e.displayed { r := e.border(); result[i] = [5]int{1,r.x,r.y,r.w,r.h} }
    }
    return result
}
func (d *document) changed(before [][5]int) string {
    after := d.snapshot()
    names := []string{}
    for i,e := range d.elements { if before[i] != after[i] { names = append(names,e.id) } }
    if len(names) == 0 { return "no change" }
    return strings.Join(names," ")
}
func (d *document) render() {
    screen := make([][]byte,d.height)
    for y := range screen { screen[y] = []byte(strings.Repeat(".",d.width)) }
    draw := func(x,y int,c byte) { if x >= 0 && x < d.width && y >= 0 && y < d.height { screen[y][x] = c } }
    for _,e := range d.elements {
        if !e.displayed { continue }
        r := e.border()
        for y := max(0,r.y); y < min(d.height,r.y+r.h); y++ {
            for x := max(0,r.x); x < min(d.width,r.x+r.w); x++ {
                horizontal := e.n("border-top") == 1 && y == r.y || e.n("border-bottom") == 1 && y == r.y+r.h-1
                vertical := e.n("border-left") == 1 && x == r.x || e.n("border-right") == 1 && x == r.x+r.w-1
                c := byte(' ')
                if horizontal && vertical { c = '+' } else if horizontal { c = '-' } else if vertical { c = '|' }
                draw(x,y,c)
            }
        }
        content := e.content()
        for i,line := range e.lines {
            for j := 0; j < len(line); j++ { draw(content.x+j,content.y+i,line[j]) }
        }
    }
    d.emit("render %dx%d",d.width,d.height)
    d.emit("%s",strings.Repeat("#",d.width+2))
    for _,row := range screen { d.emit("#%s#",row) }
    d.emit("%s",strings.Repeat("#",d.width+2))
}
func (d *document) command(line string) {
    fields := strings.Split(line," ")
    command,args := fields[0],fields[1:]
    switch command {
    case "LAYOUT":
        d.emit("layout %dx%d",d.width,d.height)
        for _,e := range d.elements {
            indent := strings.Repeat(" ",e.depth*2)
            if e.displayed { r := e.border(); d.emit("%s%s %d %d %d %d",indent,e.id,r.x,r.y,r.w,r.h) } else { d.emit("%s%s none",indent,e.id) }
        }
    case "BOX":
        e := d.byID[args[0]]
        if e == nil { d.emit("error: unknown element %s",args[0]); return }
        if !e.displayed { d.emit("box %s: none",e.id); return }
        d.emit("box %s",e.id)
        r := e.border()
        padding := rectangle{
            r.x+e.n("border-left"),r.y+e.n("border-top"),
            e.cw+e.n("padding-left")+e.n("padding-right"),
            e.ch+e.n("padding-top")+e.n("padding-bottom"),
        }
        names := []string{"margin","border","padding","content"}
        for i,box := range []rectangle{e.marginBox(),r,padding,e.content()} { d.emit("%s %d %d %d %d",names[i],box.x,box.y,box.w,box.h) }
    case "RENDER":
        d.render()
    case "HIT":
        x,y := number(args[0]),number(args[1])
        if x >= d.width || y >= d.height { d.emit("error: point %d %d outside viewport",x,y); return }
        var found *element
        for _,e := range d.elements {
            r := e.border()
            if e.displayed && x >= r.x && x < r.x+r.w && y >= r.y && y < r.y+r.h { found = e }
        }
        path := []string{}
        for found != nil { path = append(path,found.id); found = found.parent }
        for i,j := 0,len(path)-1; i < j; i,j = i+1,j-1 { path[i],path[j] = path[j],path[i] }
        value := "none"
        if len(path) > 0 { value = strings.Join(path," > ") }
        d.emit("hit %d %d: %s",x,y,value)
    case "SET":
        e := d.byID[args[0]]
        property,value := args[1],strings.Join(args[2:]," ")
        if e == nil { d.emit("error: unknown element %s",args[0]); return }
        if _,exists := initial[property]; !exists && !contains(property,"margin","padding","border","gap") { d.emit("error: unknown property %s",property); return }
        declarations,ok := valid(property,value)
        if !ok { d.emit("error: invalid value for %s: %s",property,value); return }
        before := d.snapshot()
        for _,decl := range declarations { e.inline[decl.property] = decl.value }
        d.layout()
        d.emit("set %s %s %s: %s",e.id,property,value,d.changed(before))
    case "VIEWPORT":
        w,h := number(args[0]),number(args[1])
        if w < 1 || w > 80 || h < 1 || h > 40 { d.emit("error: invalid viewport %d %d",w,h); return }
        before := d.snapshot()
        d.width,d.height = w,h
        d.layout()
        d.emit("viewport %d %d: %s",w,h,d.changed(before))
    case "OVERFLOW":
        names := []string{}
        for _,e := range d.elements {
            if !e.displayed { continue }
            overflow := false
            if e.text != "" {
                overflow = len(e.lines) > e.ch
                for _,line := range e.lines { overflow = overflow || len(line) > e.cw }
            } else {
                content := e.content()
                for _,child := range e.flow() {
                    r := child.marginBox()
                    if r.x < content.x || r.y < content.y || r.x+r.w > content.x+content.w || r.y+r.h > content.y+content.h { overflow = true }
                }
            }
            if overflow { names = append(names,e.id) }
        }
        value := "none"
        if len(names) > 0 { value = strings.Join(names," ") }
        d.emit("overflow: %s",value)
    default:
        d.emit("error: unknown command %s",command)
    }
}
func main() {
    for _,prefix := range []string{"margin","padding","border"} {
        for _,side := range []string{"top","right","bottom","left"} { initial[prefix+"-"+side] = "0" }
    }
    input,_ := io.ReadAll(os.Stdin)
    lines := strings.Split(strings.TrimSuffix(string(input),"\n"),"\n")
    index := 0
    next := func() string { line := strings.TrimSuffix(lines[index],"\r"); index++; return line }
    dimensions := strings.Split(next()," ")
    d := document{width:number(dimensions[0]),height:number(dimensions[1]),byID:map[string]*element{}}
    for index < len(lines) {
        line := next()
        if line == "---" { break }
        left,right,_ := strings.Cut(line," { ")
        r := rule{selectors:strings.Split(left,", ")}
        for _,part := range strings.Split(strings.TrimSuffix(right," }"),"; ") {
            property,value,_ := strings.Cut(part,": ")
            if declarations,ok := valid(property,value); ok { r.declarations = append(r.declarations,declarations...) }
        }
        d.rules = append(d.rules,r)
    }
    stack := []*element{}
    for index < len(lines) {
        line := next()
        if line == "===" { break }
        spaces := len(line)-len(strings.TrimLeft(line," "))
        depth := spaces/2
        head,text,_ := strings.Cut(line[spaces:]," ")
        if text != "" { text = text[1:len(text)-1] }
        kind,rest,_ := strings.Cut(head,"#")
        parts := strings.Split(rest,".")
        e := &element{kind:kind,id:parts[0],text:text,classes:map[string]bool{},inline:map[string]string{},depth:depth,index:len(d.elements)}
        for _,class := range parts[1:] { e.classes[class] = true }
        if depth > 0 { e.parent = stack[depth-1]; e.parent.children = append(e.parent.children,e) }
        stack = append(stack[:depth],e)
        d.elements = append(d.elements,e)
        d.byID[e.id] = e
    }
    d.layout()
    for index < len(lines) { line := next(); if line == "END" { break }; d.command(line) }
    out := bufio.NewWriter(os.Stdout)
    defer out.Flush()
    for _,line := range d.output { fmt.Fprintln(out,line) }
}
