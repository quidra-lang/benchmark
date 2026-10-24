package main

import (
    "bufio"
    "fmt"
    "os"
    "strconv"
    "strings"
)

type Attributes struct {
    Flags uint8
    FG, BG string
}
type Cell struct {
    Char byte
    Attr Attributes
}
type SavedCursor struct {
    Row, Col int
    Attr Attributes
    Origin, G0, G1, GL bool
}
type Terminal struct {
    W, H, Row, Col, Top, Bottom, Display, Shape int
    Pending bool
    Attr Attributes
    G0, G1, GL bool
    Modes map[string]bool
    Screens [2][][]Cell
    Saved [2]*SavedCursor
    Tabs []bool
    Scrollback []string
    Title *string
    Last byte
    HasLast bool
    State int
    Marker, Params, Intermediate, OSC string
    Bytes, Printed, Sequences, Bells, Replies, Dumps int
    Ignored [4]int
    Out *bufio.Writer
}
const (
    ground = iota
    escape
    escapeIntermediate
    csiEntry
    csiParam
    csiIntermediate
    csiIgnore
    oscString
)
var modeNames = []string{"IRM","LNM","DECCKM","DECSCNM","DECOM","DECAWM","DECTCEM","DECKPAM","BRACKETED"}
var flagNames = []string{"bold","dim","italic","underline","blink","reverse","hidden","strike"}
var ansiModes = map[int]string{4:"IRM",20:"LNM"}
var decModes = map[int]string{1:"DECCKM",5:"DECSCNM",6:"DECOM",7:"DECAWM",25:"DECTCEM",2004:"BRACKETED"}
var blank = Cell{Char:' '}
func initial(name string) bool {
    return name=="DECAWM" || name=="DECTCEM"
}
func (t *Terminal) emit(line string) {
    fmt.Fprintln(t.Out,line)
}
func (t *Terminal) blankRow() []Cell {
    row:=make([]Cell,t.W)
    for c:=range row {
        row[c]=blank
    }
    return row
}
func (t *Terminal) clearScreen(display int) {
    t.Screens[display]=make([][]Cell,t.H)
    for r:=0;r<t.H;r++ {
        t.Screens[display][r]=t.blankRow()
    }
}
func (t *Terminal) reset() {
    t.clearScreen(0); t.clearScreen(1)
    t.Row,t.Col,t.Top,t.Bottom,t.Display,t.Shape=1,1,1,t.H,0,1
    t.Pending=false; t.Attr=Attributes{}
    t.G0,t.G1,t.GL=false,false,false
    t.Modes=make(map[string]bool)
    for _,name:=range modeNames {
        t.Modes[name]=initial(name)
    }
    t.Saved=[2]*SavedCursor{}
    t.Tabs=make([]bool,t.W+1)
    for c:=9;c<=t.W;c+=8 {
        t.Tabs[c]=true
    }
    t.Scrollback=nil; t.Title=nil; t.HasLast=false
    t.State=ground; t.clearSequence()
}
func (t *Terminal) clearSequence() {
    t.Marker,t.Params,t.Intermediate,t.OSC="","","",""
}
func rowText(row []Cell) string {
    bytes:=make([]byte,len(row))
    for c,cell:=range row {
        bytes[c]=cell.Char
    }
    return strings.TrimRight(string(bytes)," ")
}
func (t *Terminal) scrollUp(top,bottom int, history bool) {
    rows:=t.Screens[t.Display]
    removed:=rows[top-1]
    copy(rows[top-1:bottom-1],rows[top:bottom])
    rows[bottom-1]=t.blankRow()
    if history && t.Display==0 && top==1 {
        t.Scrollback=append(t.Scrollback,rowText(removed))
        if len(t.Scrollback)>100 {
            t.Scrollback=t.Scrollback[1:]
        }
    }
}
func (t *Terminal) scrollDown(top,bottom int) {
    rows:=t.Screens[t.Display]
    copy(rows[top:bottom],rows[top-1:bottom-1])
    rows[top-1]=t.blankRow()
}
func (t *Terminal) lineFeed() {
    if t.Row==t.Bottom { t.scrollUp(t.Top,t.Bottom,true) } else if t.Row<t.H { t.Row++ }
}
func (t *Terminal) reverseFeed() {
    if t.Row==t.Top { t.scrollDown(t.Top,t.Bottom) } else if t.Row>1 { t.Row-- }
}
func (t *Terminal) tab(reverse bool) {
    if reverse {
        for c:=t.Col-1;c>=1;c-- { if t.Tabs[c] { t.Col=c; return } }
        t.Col=1
    } else {
        for c:=t.Col+1;c<=t.W;c++ { if t.Tabs[c] { t.Col=c; return } }
        t.Col=t.W
    }
}
func (t *Terminal) address(v int) int {
    if t.Modes["DECOM"] {
        return min(t.Top+v-1,t.Bottom)
    }
    return min(v,t.H)
}
func (t *Terminal) home() {
    t.Row,t.Col=t.address(1),1
}
func (t *Terminal) save() {
    t.Saved[t.Display]=&SavedCursor{t.Row,t.Col,t.Attr,t.Modes["DECOM"],t.G0,t.G1,t.GL}
}
func (t *Terminal) restore() {
    t.Pending=false
    s:=t.Saved[t.Display]
    if s==nil { s=&SavedCursor{Row:1,Col:1} }
    t.Row,t.Col,t.Attr=s.Row,s.Col,s.Attr
    t.Modes["DECOM"],t.G0,t.G1,t.GL=s.Origin,s.G0,s.G1,s.GL
}
func (t *Terminal) insertCells(count int) {
    row:=t.Screens[t.Display][t.Row-1]
    copy(row[t.Col-1+count:],row[t.Col-1:t.W-count])
    for c:=t.Col-1;c<t.Col-1+count;c++ {
        row[c]=blank
    }
}
func (t *Terminal) deleteCells(count int) {
    row:=t.Screens[t.Display][t.Row-1]
    copy(row[t.Col-1:],row[t.Col-1+count:])
    for c:=t.W-count;c<t.W;c++ {
        row[c]=blank
    }
}
func (t *Terminal) write(c byte) {
    t.Printed++; t.Last=c; t.HasLast=true
    if t.Pending {
        t.Pending=false
        t.Col=1
        t.lineFeed()
    }
    if t.Modes["IRM"] {
        t.insertCells(1)
    }
    t.Screens[t.Display][t.Row-1][t.Col-1]=Cell{c,t.Attr}
    if t.Col<t.W { t.Col++ } else if t.Modes["DECAWM"] { t.Pending=true }
}
func (t *Terminal) printChar(c byte) {
    graphics:=t.G0
    if t.GL {
        graphics=t.G1
    }
    if graphics {
        switch c {
        case '`':
            c='*'
        case 'a':
            c='#'
        case 'j','k','l','m','n','t','u','v','w':
            c='+'
        case 'q':
            c='-'
        case 'x':
            c='|'
        case '~':
            c='o'
        }
    }
    t.write(c)
}
func (t *Terminal) control(c byte) {
    switch c {
    case 7:
        t.Bells++
    case 8:
        t.Pending=false; t.Col=max(t.Col-1,1)
    case 9:
        t.Pending=false; t.tab(false)
    case 10,11,12:
        t.Pending=false; t.lineFeed(); if t.Modes["LNM"] { t.Col=1 }
    case 13:
        t.Pending=false; t.Col=1
    case 14:
        t.GL=true
    case 15:
        t.GL=false
    }
}
func (t *Terminal) executeESC(key string) {
    switch key {
    case "7":
        t.save()
    case "8":
        t.restore()
    case "D":
        t.Pending=false; t.lineFeed()
    case "E":
        t.Pending=false; t.Col=1; t.lineFeed()
    case "M":
        t.Pending=false; t.reverseFeed()
    case "H":
        t.Tabs[t.Col]=true
    case "c":
        t.reset()
    case "=":
        t.Modes["DECKPAM"]=true
    case ">":
        t.Modes["DECKPAM"]=false
    case "\\":
    case "(0":
        t.G0=true
    case "(B":
        t.G0=false
    case ")0":
        t.G1=true
    case ")B":
        t.G1=false
    case "#8":
        t.Pending=false
        for _,row:=range t.Screens[t.Display] { for c:=range row { row[c]=Cell{Char:'E'} } }
        t.Top,t.Bottom,t.Row,t.Col=1,t.H,1,1
        t.Modes["DECOM"]=false
    default:
        t.Ignored[0]++; return
    }
    t.Sequences++
}
func (t *Terminal) executeOSC() {
    if strings.HasPrefix(t.OSC,"0;") || strings.HasPrefix(t.OSC,"2;") {
        title:=t.OSC[2:]; t.Title=&title; t.Sequences++
    } else { t.Ignored[0]++ }
}
func palette(number int) string {
    names:=[]string{"black","red","green","yellow","blue","magenta","cyan","white"}
    if number<8 {
        return names[number]
    }
    if number<16 {
        return "bright-"+names[number-8]
    }
    return strconv.Itoa(number)
}
func (t *Terminal) sgr(params []int) bool {
    if len(params)==0 { params=[]int{0} }
    a:=t.Attr
    on:=map[int]uint{1:0,2:1,3:2,4:3,5:4,7:5,8:6,9:7}
    off:=map[int]uint{23:2,24:3,25:4,27:5,28:6,29:7}
    for i:=0;i<len(params);i++ {
        v:=params[i]
        if v==0 { a=Attributes{} } else if bit,ok:=on[v];ok { a.Flags|=1<<bit } else if v==22 {
            a.Flags &^= 3
        } else if bit,ok:=off[v];ok { a.Flags &^=1<<bit } else {
            switch {
            case v>=30 && v<=37:
                a.FG=palette(v-30)
            case v>=90 && v<=97:
                a.FG=palette(v-82)
            case v>=40 && v<=47:
                a.BG=palette(v-40)
            case v>=100 && v<=107:
                a.BG=palette(v-92)
            case v==39:
                a.FG=""
            case v==49:
                a.BG=""
            case v==38 || v==48:
                color:=""
                if i+2<len(params) && params[i+1]==5 && params[i+2]<=255 {
                    color=palette(params[i+2]); i+=2
                } else if i+4<len(params) && params[i+1]==2 && params[i+2]<=255 && params[i+3]<=255 && params[i+4]<=255 {
                    color=fmt.Sprintf("#%02x%02x%02x",params[i+2],params[i+3],params[i+4]); i+=4
                } else { return false }
                if v==38 { a.FG=color } else { a.BG=color }
            default:
                return false
            }
        }
    }
    t.Attr=a
    return true
}
func (t *Terminal) setModes(params []int,dec,enabled bool) bool {
    if len(params)==0 { params=[]int{0} }
    for _,v:=range params {
        if dec {
            if _,ok:=decModes[v]; !ok && v!=47 && v!=1047 && v!=1048 && v!=1049 {
                return false
            }
        } else if _,ok:=ansiModes[v];!ok { return false }
    }
    for _,v:=range params {
        if !dec {
            t.Modes[ansiModes[v]]=enabled
            continue
        }
        if name,ok:=decModes[v];ok {
            if v==6 || v==7 && !enabled {
                t.Pending=false
            }
            t.Modes[name]=enabled
            if v==6 {
                t.home()
            }
        } else if v==1048 {
            if enabled { t.save() } else { t.restore() }
        } else {
            t.Pending=false
            if enabled && t.Display==0 {
                if v==1049 {
                    t.save()
                }
                t.Display=1
                if v==1049 {
                    t.clearScreen(1)
                }
            } else if !enabled && t.Display==1 {
                if v==1047 {
                    t.clearScreen(1)
                }
                t.Display=0
                if v==1049 {
                    t.restore()
                }
            }
        }
    }
    return true
}
func (t *Terminal) erase(row,first,last int) {
    for c:=first;c<=last;c++ {
        t.Screens[t.Display][row-1][c-1]=blank
    }
}
func (t *Terminal) moveUp(n int) {
    limit:=1
    if t.Row>=t.Top {
        limit=t.Top
    }
    t.Row=max(t.Row-n,limit)
}
func (t *Terminal) moveDown(n int) {
    limit:=t.H
    if t.Row<=t.Bottom {
        limit=t.Bottom
    }
    t.Row=min(t.Row+n,limit)
}
func (t *Terminal) reply(text string) {
    t.Replies++
    t.emit("REPLY "+text)
}
func modeState(enabled bool) int { if enabled { return 1 }; return 2 }
// Return an ignored reason, or -1 for an executed sequence.
func (t *Terminal) csi(key string,params []int) int {
    p1,p2:=0,0
    if len(params)>0 {
        p1=params[0]
    }
    if len(params)>1 {
        p2=params[1]
    }
    n:=max(p1,1)
    switch key {
    case "J":
        if p1>3 {
            return 0
        }
    case "K":
        if p1>2 {
            return 0
        }
    case "g":
        if p1!=0 && p1!=3 {
            return 0
        }
    case " q":
        if p1>6 {
            return 0
        }
    case "n":
        if p1!=5 && p1!=6 {
            return 0
        }
    case "?n":
        if p1!=6 {
            return 0
        }
    case "c",">c":
        if p1!=0 {
            return 0
        }
    case "t":
        if p1!=18 {
            return 0
        }
    }
    if len(key)==1 && strings.Contains("ABCDEFGHIJKLMPSTXZ`adef@",key) {
        t.Pending=false
    }
    switch key {
    case "A":
        t.moveUp(n)
    case "B","e":
        t.moveDown(n)
    case "C","a":
        t.Col=min(t.Col+n,t.W)
    case "D":
        t.Col=max(t.Col-n,1)
    case "E":
        t.moveDown(n)
        t.Col = 1
    case "F":
        t.moveUp(n)
        t.Col = 1
    case "G","`":
        t.Col=min(n,t.W)
    case "H","f":
        t.Row = t.address(n)
        t.Col = min(max(p2, 1), t.W)
    case "d":
        t.Row=t.address(n)
    case "I","Z":
        for i:=0;i<n;i++ {
            t.tab(key=="Z")
        }
    case "J":
        switch p1 {
        case 0:
            t.erase(t.Row, t.Col, t.W)
            for r := t.Row + 1; r <= t.H; r++ {
                t.erase(r, 1, t.W)
            }
        case 1:
            for r := 1; r < t.Row; r++ {
                t.erase(r, 1, t.W)
            }
            t.erase(t.Row, 1, t.Col)
        case 2:
            t.clearScreen(t.Display)
        case 3:
            t.Scrollback=nil
        }
    case "K":
        first,last:=t.Col,t.W
        if p1==1 || p1==2 {
            first=1
        }
        if p1==1 {
            last=t.Col
        }
        t.erase(t.Row,first,last)
    case "X":
        t.erase(t.Row,t.Col,min(t.Col+n-1,t.W))
    case "@":
        t.insertCells(min(n,t.W-t.Col+1))
    case "P":
        t.deleteCells(min(n,t.W-t.Col+1))
    case "L","M":
        if t.Row>=t.Top && t.Row<=t.Bottom {
            for i:=0;i<min(n,t.Bottom-t.Row+1);i++ {
                if key == "L" {
                    t.scrollDown(t.Row, t.Bottom)
                } else {
                    t.scrollUp(t.Row, t.Bottom, false)
                }
            }
            t.Col=1
        }
    case "S","T":
        for i:=0;i<min(n,t.Bottom-t.Top+1);i++ {
            if key == "S" {
                t.scrollUp(t.Top, t.Bottom, true)
            } else {
                t.scrollDown(t.Top, t.Bottom)
            }
        }
    case "b":
        if t.HasLast {
            c := t.Last
            for i := 0; i < n; i++ {
                t.write(c)
            }
        }
    case "g":
        if p1 == 0 {
            t.Tabs[t.Col] = false
        } else {
            t.Tabs = make([]bool, t.W+1)
        }
    case "m":
        if !t.sgr(params) {
            return 0
        }
    case "h","l","?h","?l":
        if !t.setModes(params,key[0]=='?',strings.HasSuffix(key,"h")) {
            return 0
        }
    case " q":
        t.Shape=n
    case "r":
        bottom:=p2
        if bottom==0 {
            bottom=t.H
        }
        bottom=min(bottom,t.H)
        if n>=bottom {
            return 3
        }
        t.Pending = false
        t.Top, t.Bottom = n, bottom
        t.home()
    case "s":
        t.save()
    case "u":
        t.restore()
    case "!p":
        t.Pending=false
        for _, name := range []string{"IRM", "DECCKM", "DECOM", "DECAWM", "DECTCEM", "DECKPAM"} {
            t.Modes[name] = initial(name)
        }
        t.Top, t.Bottom = 1, t.H
        t.Attr = Attributes{}
        t.G0, t.G1, t.GL = false, false, false
        t.Saved[t.Display] = nil
    case "n","?n":
        row:=t.Row
        if t.Modes["DECOM"] {
            row=max(t.Row-t.Top+1,1)
        }
        if key == "?n" {
            t.reply(fmt.Sprintf("^[[?%d;%d;1R", row, t.Col))
        } else if p1 == 5 {
            t.reply("^[[0n")
        } else {
            t.reply(fmt.Sprintf("^[[%d;%dR", row, t.Col))
        }
    case "c":
        t.reply("^[[?1;2c")
    case ">c":
        t.reply("^[[>0;95;0c")
    case "t":
        t.reply(fmt.Sprintf("^[[8;%d;%dt",t.H,t.W))
    case "$p","?$p":
        state,prefix:=0,""
        if key == "$p" {
            if name, ok := ansiModes[p1]; ok {
                state = modeState(t.Modes[name])
            }
        } else {
            prefix="?"
            if name, ok := decModes[p1]; ok {
                state = modeState(t.Modes[name])
            } else if p1 == 47 || p1 == 1047 || p1 == 1049 {
                state = modeState(t.Display == 1)
            }
        }
        t.reply(fmt.Sprintf("^[[%s%d;%d$y",prefix,p1,state))
    default:
        return 0
    }
    return -1
}
func (t *Terminal) executeCSI(final byte) {
    fields:=[]string{}
    if t.Params!="" {
        fields=strings.Split(t.Params,";")
    }
    if len(fields)>16 {
        t.Ignored[3]++
        return
    }
    params:=make([]int,len(fields))
    for i,field:=range fields {
        for _,digit:=range field {
            params[i]=min(9999,params[i]*10+int(digit-'0'))
        }
    }
    reason:=t.csi(t.Marker+t.Intermediate+string(final),params)
    if reason<0 { t.Sequences++ } else { t.Ignored[reason]++ }
}
func intermediate(c byte) bool {
    return c>=0x20 && c<=0x2f
}
func final(c byte) bool {
    return c>=0x40 && c<=0x7e
}
func (t *Terminal) receive(c byte) {
    t.Bytes++
    if c < 0x20 {
        switch c {
        case 27:
            if t.State == oscString {
                t.executeOSC()
            } else if t.State != ground {
                t.Ignored[2]++
            }
            t.clearSequence()
            t.State = escape
        case 24, 26:
            if t.State != ground {
                t.Ignored[2]++
                t.State = ground
            }
        default:
            if t.State == oscString {
                if c == 7 {
                    t.executeOSC()
                    t.State = ground
                }
            } else {
                t.control(c)
            }
        }
        return
    }
    switch t.State {
    case ground:
        t.printChar(c)
    case escape, escapeIntermediate:
        if intermediate(c) {
            t.Intermediate += string(c)
            t.State = escapeIntermediate
        } else if t.State == escape && c == '[' {
            t.State = csiEntry
        } else if t.State == escape && c == ']' {
            t.State = oscString
        } else {
            t.executeESC(t.Intermediate + string(c))
            t.State = ground
        }
    case oscString:
        t.OSC += string(c)
    case csiIgnore:
        if final(c) {
            t.Ignored[1]++
            t.State = ground
        }
    case csiIntermediate:
        if intermediate(c) {
            t.Intermediate += string(c)
        } else if final(c) {
            t.executeCSI(c)
            t.State = ground
        } else {
            t.State = csiIgnore
        }
    default:
        if t.State == csiEntry && c >= 0x3c && c <= 0x3f {
            t.Marker = string(c)
            t.State = csiParam
        } else if c >= '0' && c <= '9' || c == ';' {
            t.Params += string(c)
            t.State = csiParam
        } else if intermediate(c) {
            t.Intermediate += string(c)
            t.State = csiIntermediate
        } else if final(c) {
            t.executeCSI(c)
            t.State = ground
        } else {
            t.State = csiIgnore
        }
    }
}
func (t *Terminal) key(name string) string {
    cursor:=map[string]string{"UP":"A","DOWN":"B","RIGHT":"C","LEFT":"D","HOME":"H","END":"F"}
    if suffix,ok:=cursor[name];ok { if t.Modes["DECCKM"] { return "^[O"+suffix }; return "^[["+suffix }
    fixed := map[string]string{
        "INSERT": "^[[2~", "DELETE": "^[[3~", "PAGEUP": "^[[5~", "PAGEDOWN": "^[[6~",
        "F1": "^[OP", "F2": "^[OQ", "F3": "^[OR", "F4": "^[OS",
        "F5": "^[[15~", "F6": "^[[17~", "F7": "^[[18~", "F8": "^[[19~",
        "F9": "^[[20~", "F10": "^[[21~", "F11": "^[[23~", "F12": "^[[24~",
        "TAB": "^I", "BACKSPACE": "^?", "ESCAPE": "^[",
    }
    if value,ok:=fixed[name];ok {
        return value
    }
    enter:="^M"
    if t.Modes["LNM"] {
        enter+="^J"
    }
    if name=="ENTER" {
        return enter
    }
    if name=="KPENTER" { if t.Modes["DECKPAM"] { return "^[OM" }; return enter }
    digit:=name[2]-'0'
    if t.Modes["DECKPAM"] {
        return "^[O"+string(byte(0x70)+digit)
    }
    return string(name[2])
}
func (t *Terminal) screenOutput(label string) {
    name:="main"
    if t.Display==1 {
        name="alt"
    }
    line:=fmt.Sprintf("%s %s cursor %d,%d scrollback %d",label,name,t.Row,t.Col,len(t.Scrollback))
    if t.Pending {
        line+=" pending"
    }
    t.emit(line)
    for _,row:=range t.Screens[t.Display] {
        t.emit("|"+rowText(row))
    }
}
func describe(a Attributes) string {
    parts:=[]string{}
    for bit,name:=range flagNames { if a.Flags&(1<<uint(bit))!=0 { parts=append(parts,name) } }
    if a.FG!="" {
        parts=append(parts,"fg="+a.FG)
    }
    if a.BG!="" {
        parts=append(parts,"bg="+a.BG)
    }
    return strings.Join(parts," ")
}
func (t *Terminal) finish() {
    if t.State!=ground {
        t.Ignored[2]++
        t.State=ground
    }
    t.screenOutput("FINAL")
    if t.Title==nil { t.emit("TITLE none") } else { t.emit("TITLE \""+*t.Title+"\"") }
    modes:=[]string{}
    for _,name:=range modeNames { if t.Modes[name]!=initial(name) { value:="off"; if t.Modes[name] { value="on" }; modes=append(modes,name+"="+value) } }
    if t.G0 {
        modes=append(modes,"G0=graphics")
    }
    if t.G1 {
        modes=append(modes,"G1=graphics")
    }
    if t.GL {
        modes=append(modes,"GL=G1")
    }
    if t.Shape!=1 {
        modes=append(modes,fmt.Sprintf("CURSOR=%d",t.Shape))
    }
    if len(modes)==0 {
        modes=append(modes,"default")
    }
    t.emit("MODES "+strings.Join(modes," "))
    t.emit(fmt.Sprintf("REGION %d-%d",t.Top,t.Bottom))
    tabs:=[]string{}
    for c:=1;c<=t.W;c++ { if t.Tabs[c] { tabs=append(tabs,strconv.Itoa(c)) } }
    if len(tabs)==0 {
        tabs=append(tabs,"none")
    }
    t.emit("TABS "+strings.Join(tabs,","))
    t.emit(fmt.Sprintf("SCROLLBACK %d",len(t.Scrollback)))
    for _,line:=range t.Scrollback[max(0,len(t.Scrollback)-5):] {
        t.emit("|"+line)
    }
    runs:=[]string{}
    for r,row:=range t.Screens[t.Display] {
        for start:=0;start<t.W; {
            end:=start+1
            for end<t.W && row[end].Attr==row[start].Attr {
                end++
            }
            if row[start].Attr!=(Attributes{}) { runs=append(runs,fmt.Sprintf("row %d col %d-%d %s",r+1,start+1,end,describe(row[start].Attr))) }
            start=end
        }
    }
    t.emit(fmt.Sprintf("ATTRS %d",len(runs)))
    for _,line:=range runs {
        t.emit(line)
    }
    t.emit(fmt.Sprintf("BELL %d",t.Bells)); t.emit(fmt.Sprintf("REPLIES %d",t.Replies))
    t.emit(fmt.Sprintf("STATS bytes=%d printed=%d sequences=%d",t.Bytes,t.Printed,t.Sequences))
    v:=t.Ignored
    t.emit(fmt.Sprintf("IGNORED %d unsupported=%d malformed=%d canceled=%d invalid=%d",v[0]+v[1]+v[2]+v[3],v[0],v[1],v[2],v[3]))
}
func main() {
    input:=bufio.NewScanner(os.Stdin)
    // A stream line contains at most 200 bytes; all directives are shorter.
    input.Buffer(make([]byte,256),256)
    input.Scan(); dimensions:=strings.Fields(input.Text())
    w,_:=strconv.Atoi(dimensions[0]); h,_:=strconv.Atoi(dimensions[1])
    output:=bufio.NewWriter(os.Stdout); defer output.Flush()
    t:=Terminal{W:w,H:h,Out:output}; t.reset()
    caret:=map[byte]byte{'@':0,'G':7,'H':8,'I':9,'J':10,'K':11,'L':12,'M':13,'N':14,'O':15,'X':24,'Z':26,'[':27,'^':94}
    for input.Scan() {
        line:=input.Text()
        if line=="%%END" {
            break
        }
        if line=="%%DUMP" { t.Dumps++; t.screenOutput(fmt.Sprintf("DUMP %d",t.Dumps)) } else if strings.HasPrefix(line,"%%KEY ") {
            name:=line[6:]; t.emit("KEY "+name+" "+t.key(name))
        } else if strings.HasPrefix(line,"%%PASTE ") {
            sent:=strings.ReplaceAll(line[8:],"^","^^")
            if t.Modes["BRACKETED"] {
                sent="^[[200~"+sent+"^[[201~"
            }
            t.emit("PASTE "+sent)
        } else {
            for i:=0;i<len(line);i++ { c:=line[i]; if c=='^' { i++; c=caret[line[i]] }; t.receive(c) }
        }
    }
    t.finish()
}
