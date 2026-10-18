package main

import (
    "bufio"
    "fmt"
    "os"
    "sort"
    "strconv"
    "strings"
)

type grid struct {
    precision int
    width, height int64
}
type cell struct {
    precision int
    x, y int64
}
type invalid struct{}

var systems = []string{"GEOHASH", "MAIDENHEAD", "PLUSCODE", "GARS", "GEOREF", "MESH"}
const hashAlphabet = "0123456789bcdefghjkmnpqrstuvwxyz"
const plusAlphabet = "23456789CFGHJMPQRVWX"
const letters24 = "ABCDEFGHJKLMNPQRSTUVWXYZ"
const osLetters = "ABCDEFGHJKLMNOPQRSTUVWXYZ"
const bands = "CDEFGHJKLMNPQRSTUVWX"
const mgrsRows = "ABCDEFGHJKLMNPQRSTUV"
var meshScale = []int64{1, 8, 80, 160, 320, 640}
var grids = [6][]grid{
    {},
    {{2,18,18}, {4,180,180}, {6,4320,4320}, {8,43200,43200}},
    {{2,18,9}, {4,360,180}, {6,7200,3600}, {8,144000,72000}, {10,2880000,1440000}, {11,11520000,7200000}},
    {{5,720,360}, {6,1440,720}, {7,4320,2160}},
    {{2,24,12}, {4,360,180}, {8,21600,10800}, {10,216000,108000}, {12,2160000,1080000}},
    {{4,360,270}, {6,2880,2160}, {8,28800,21600}, {9,57600,43200}, {10,115200,86400}, {11,230400,172800}},
}

func require(ok bool) {
    if !ok { panic(invalid{}) }
}
func floorRatio(a, b int64) int64 {
    q := a / b
    if a % b < 0 { q-- }
    return q
}
func modulo(a, b int64) int64 { return a - floorRatio(a,b)*b }
func absolute(a int64) int64 {
    if a < 0 { return -a }
    return a
}
func minimum(a,b int64) int64 {
    if a < b { return a }
    return b
}
func maximum(a,b int64) int64 {
    if a > b { return a }
    return b
}
func number(v int64) string { return strconv.FormatInt(v, 10) }
func padded(v int64, width int) string {
    s := number(v)
    if len(s) < width { s = strings.Repeat("0", width-len(s)) + s }
    return s
}
func coordinate(v int64) string {
    sign := ""
    if v < 0 { sign = "-" }
    v = absolute(v)
    return sign + number(v/1000000) + "." + padded(v%1000000,6)
}
func digits(s string, low, high int) bool {
    if len(s) < low || len(s) > high { return false }
    for i := range s {
        if s[i] < '0' || s[i] > '9' { return false }
    }
    return true
}
func integer(s string, low, high int64) int64 {
    negative := strings.HasPrefix(s,"-")
    if negative { s = s[1:] }
    require(digits(s,1,9))
    var v int64
    for i := range s { v = 10*v + int64(s[i]-'0') }
    if negative { v = -v }
    require(v >= low && v <= high)
    return v
}
func location(s string, latitude bool) int64 {
    negative := strings.HasPrefix(s,"-")
    if negative { s = s[1:] }
    parts := strings.Split(s,".")
    require(len(parts) == 1 || len(parts) == 2)
    require(digits(parts[0],1,3))
    fraction := ""
    if len(parts) == 2 {
        fraction = parts[1]
        require(digits(fraction,1,6))
    }
    v := integer(parts[0],0,999)*1000000
    fraction += strings.Repeat("0",6-len(fraction))
    v += integer(fraction,0,999999)
    if negative { v = -v }
    if latitude { require(v >= -90000000 && v <= 90000000) } else { require(v >= -180000000 && v < 180000000) }
    return v
}
func systemID(s string) int {
    for i, name := range systems {
        if s == name { return i }
    }
    panic(invalid{})
}
func precisionID(system int, p int64) int {
    for i, g := range grids[system] {
        if int64(g.precision) == p { return i }
    }
    panic(invalid{})
}
func precisionArgument(system int, s string) int { return precisionID(system,integer(s,0,999999999)) }
func digit(alphabet string, c byte) int64 {
    i := strings.IndexByte(alphabet,c)
    require(i >= 0)
    return int64(i)
}
func point(system, precision int, latitude, longitude int64) cell {
    g := grids[system][precision]
    return cell{precision, (longitude+180000000)*g.width/360000000, minimum((latitude+90000000)*g.height/180000000,g.height-1)}
}
func ancestor(system int, c cell, precision int) cell {
    g, parent := grids[system][c.precision], grids[system][precision]
    return cell{precision,c.x*parent.width/g.width,c.y*parent.height/g.height}
}
func encode(system int, c cell) string {
    p := grids[system][c.precision].precision
    x,y := c.x,c.y
    result := ""
    switch system {
    case 0:
        a,b,value := (5*p+1)/2,5*p/2,int64(0)
        for i:=0; i<5*p; i++ {
            var bit int64
            if i%2 == 0 {
                bit = x >> (a-1-i/2) & 1
            } else {
                bit = y >> (b-1-i/2) & 1
            }
            value = value*2 + bit
            if i%5 == 4 {
                result += string(hashAlphabet[value])
                value = 0
            }
        }
    case 1,2:
        count := p/2
        if system == 2 && p == 11 { count = 5 }
        tail := int64(-1)
        if system == 2 && p == 11 {
            tail = 4*(y%5)+x%4
            x /= 4
            y /= 5
        }
        xd,yd := make([]int64,count),make([]int64,count)
        alphabets := []string{"ABCDEFGHIJKLMNOPQR","0123456789","abcdefghijklmnopqrstuvwx","0123456789"}
        for i:=count-1; i>=0; i-- {
            rx,ry := int64(20),int64(20)
            if system == 1 {
                rx = int64(len(alphabets[i]))
                ry = rx
            } else if i == 0 {
                rx,ry = 18,9
            }
            xd[i],yd[i] = x%rx,y%ry
            x /= rx
            y /= ry
        }
        for i:=0; i<count; i++ {
            if system == 1 {
                result += string(alphabets[i][xd[i]]) + string(alphabets[i][yd[i]])
            } else {
                result += string(plusAlphabet[yd[i]]) + string(plusAlphabet[xd[i]])
            }
        }
        if tail >= 0 { result += string(plusAlphabet[tail]) }
        if system == 2 {
            if p < 8 { result += strings.Repeat("0",8-p) }
            result = result[:8] + "+" + result[8:]
        }
    case 3:
        scale := int64(1)
        if p == 6 { scale = 2 } else if p == 7 { scale = 6 }
        baseY := y/scale
        result = padded(x/scale+1,3) + string(letters24[baseY/24]) + string(letters24[baseY%24])
        if p >= 6 {
            xx,yy := x,y
            if p == 7 { xx,yy = x/3,y/3 }
            result += string(byte('1'+xx%2+2*(1-yy%2)))
        }
        if p == 7 { result += string(byte('1'+x%3+3*(2-y%3))) }
    case 4:
        if p == 2 { return string(letters24[x])+string(letters24[y]) }
        m,scale := (p-4)/2,int64(1)
        if p >= 8 {
            scale = 60
            if m == 3 { scale = 600 } else if m == 4 { scale = 6000 }
        }
        xx,yy := x/scale,y/scale
        result = string(letters24[xx/15])+string(letters24[yy/15])+string(letters24[xx%15])+string(letters24[yy%15])
        if p >= 8 { result += padded(x%scale,m)+padded(y%scale,m) }
    case 5:
        scale := meshScale[c.precision]
        x -= 280*scale
        y -= 135*scale
        if x < 0 || x >= 80*scale || y < 0 || y >= 100*scale { return "" }
        count := c.precision+1
        radices := []int64{0,8,10,2,2,2}
        xd,yd := make([]int64,count),make([]int64,count)
        for i:=count-1; i>=1; i-- {
            xd[i],yd[i] = x%radices[i],y%radices[i]
            x /= radices[i]
            y /= radices[i]
        }
        result = padded(y,2)+padded(x,2)
        for i:=1; i<count; i++ {
            if i <= 2 {
                result += string(byte('0'+yd[i]))+string(byte('0'+xd[i]))
            } else {
                result += string(byte('1'+xd[i]+2*yd[i]))
            }
        }
    }
    return result
}
func decode(system int, code string) cell {
    p := len(code)
    var x,y int64
    switch system {
    case 0:
        require(p >= 1 && p <= 9)
        position := 0
        for i:=range code {
            value := digit(hashAlphabet,code[i])
            for bit:=4; bit>=0; bit-- {
                if position%2 == 0 {
                    x = 2*x+(value>>bit&1)
                } else {
                    y = 2*y+(value>>bit&1)
                }
                position++
            }
        }
    case 1:
        precisionID(system,int64(p))
        alphabets := []string{"ABCDEFGHIJKLMNOPQR","0123456789","abcdefghijklmnopqrstuvwx","0123456789"}
        for i:=0; i<p/2; i++ {
            x = x*int64(len(alphabets[i]))+digit(alphabets[i],code[2*i])
            y = y*int64(len(alphabets[i]))+digit(alphabets[i],code[2*i+1])
        }
    case 2:
        require(p >= 9 && code[8] == '+' && strings.Count(code,"+") == 1)
        prefix := 0
        for prefix < 8 && code[prefix] != '0' {
            digit(plusAlphabet,code[prefix])
            prefix++
        }
        require(prefix == 2 || prefix == 4 || prefix == 6 || prefix == 8)
        for i:=prefix; i<8; i++ { require(code[i] == '0') }
        suffix := p-9
        require(prefix == 8 && (suffix == 0 || suffix == 2 || suffix == 3) || prefix < 8 && suffix == 0)
        require(digit(plusAlphabet,code[0]) <= 8 && digit(plusAlphabet,code[1]) <= 17)
        sequence := code[:prefix]+code[9:]
        p = len(sequence)
        count := p/2
        if p == 11 { count = 5 }
        for i:=0; i<count; i++ {
            rx,ry := int64(20),int64(20)
            if i == 0 { rx,ry = 18,9 }
            y = y*ry+digit(plusAlphabet,sequence[2*i])
            x = x*rx+digit(plusAlphabet,sequence[2*i+1])
        }
        if p == 11 {
            tail := digit(plusAlphabet,sequence[10])
            x = x*4+tail%4
            y = y*5+tail/4
        }
    case 3:
        require(p >= 5 && p <= 7 && digits(code[:3],3,3))
        x = integer(code[:3],1,720)-1
        a,b := digit(letters24,code[3]),digit(letters24,code[4])
        require(a < 15)
        y = 24*a+b
        if p >= 6 {
            require(code[5] >= '1' && code[5] <= '4')
            q := int64(code[5]-'1')
            x,y = 2*x+q%2,2*y+1-q/2
        }
        if p == 7 {
            require(code[6] >= '1' && code[6] <= '9')
            q := int64(code[6]-'1')
            x,y = 3*x+q%3,3*y+2-q/3
        }
    case 4:
        precisionID(system,int64(p))
        x,y = digit(letters24,code[0]),digit(letters24,code[1])
        require(y < 12)
        if p >= 4 {
            a,b := digit(letters24,code[2]),digit(letters24,code[3])
            require(a < 15 && b < 15)
            x,y = 15*x+a,15*y+b
        }
        if p >= 8 {
            m,scale := (p-4)/2,int64(60)
            if m == 3 { scale = 600 } else if m == 4 { scale = 6000 }
            require(digits(code[4:4+m],m,m) && digits(code[4+m:],m,m))
            x = x*scale+integer(code[4:4+m],0,scale-1)
            y = y*scale+integer(code[4+m:],0,scale-1)
        }
    case 5:
        precision := precisionID(system,int64(p))
        require(digits(code,p,p))
        y,x = integer(code[:2],0,99),integer(code[2:4],0,79)
        if p >= 6 {
            require(code[4] <= '7' && code[5] <= '7')
            y,x = y*8+int64(code[4]-'0'),x*8+int64(code[5]-'0')
        }
        if p >= 8 { y,x = y*10+int64(code[6]-'0'),x*10+int64(code[7]-'0') }
        for i:=8; i<p; i++ {
            require(code[i] >= '1' && code[i] <= '4')
            q := int64(code[i]-'1')
            x,y = 2*x+q%2,2*y+q/2
        }
        x += 280*meshScale[precision]
        y += 135*meshScale[precision]
    }
    return cell{precisionID(system,int64(p)),x,y}
}
func display(system int, c cell) string {
    code := encode(system,c)
    if code == "" { return "-" }
    return code
}
func centerNumerator(position, divisions, span int64) int64 { return span*(2*position+1-divisions) }
func compare(a,b,c,d int64) int {
    left,right := a*d,c*b
    if left < right { return -1 }
    if left > right { return 1 }
    return 0
}
func relation(sa int, a cell, sb int, b cell) string {
    ga,gb := grids[sa][a.precision],grids[sb][b.precision]
    west,east := compare(a.x,ga.width,b.x,gb.width),compare(a.x+1,ga.width,b.x+1,gb.width)
    south,north := compare(a.y,ga.height,b.y,gb.height),compare(a.y+1,ga.height,b.y+1,gb.height)
    if west == 0 && east == 0 && south == 0 && north == 0 { return "EQUAL" }
    if west >= 0 && east <= 0 && south >= 0 && north <= 0 { return "INSIDE" }
    if west <= 0 && east >= 0 && south <= 0 && north >= 0 { return "CONTAINS" }
    x1,x2 := compare(a.x,ga.width,b.x+1,gb.width),compare(b.x,gb.width,a.x+1,ga.width)
    y1,y2 := compare(a.y,ga.height,b.y+1,gb.height),compare(b.y,gb.height,a.y+1,ga.height)
    if x1 < 0 && x2 < 0 && y1 < 0 && y2 < 0 { return "OVERLAP" }
    wrap := a.x == 0 && b.x+1 == gb.width || b.x == 0 && a.x+1 == ga.width
    if y1 <= 0 && y2 <= 0 && (x1 <= 0 && x2 <= 0 || wrap) { return "TOUCH" }
    return "DISJOINT"
}
func prune(system int, cells map[cell]bool) {
    removed := []cell{}
    for c := range cells {
        for other := range cells {
            if other.precision < c.precision && ancestor(system,c,other.precision) == other {
                removed = append(removed,c)
                break
            }
        }
    }
    for _,c := range removed { delete(cells,c) }
}
func compact(system int, codes []string) string {
    cells := map[cell]bool{}
    for _,code := range codes { cells[decode(system,code)] = true }
    prune(system,cells)
    for {
        changed := false
        for c := range cells {
            if c.precision == 0 { continue }
            parent := ancestor(system,c,c.precision-1)
            g,pg := grids[system][c.precision],grids[system][parent.precision]
            needed := g.width/pg.width*(g.height/pg.height)
            if needed > int64(len(cells)) { continue }
            children := []cell{}
            for other := range cells {
                if other.precision == c.precision && ancestor(system,other,parent.precision) == parent { children = append(children,other) }
            }
            if int64(len(children)) != needed { continue }
            for _,child := range children { delete(cells,child) }
            cells[parent] = true
            prune(system,cells)
            changed = true
            break
        }
        if !changed { break }
    }
    ordered := []cell{}
    for c := range cells { ordered = append(ordered,c) }
    sort.Slice(ordered,func(i,j int) bool {
        a,b := ordered[i],ordered[j]
        if a.precision != b.precision { return a.precision < b.precision }
        if a.y != b.y { return a.y > b.y }
        return a.x < b.x
    })
    result := []string{}
    for _,c := range ordered { result = append(result,encode(system,c)) }
    return strings.Join(result," ")
}
func mgrsColumns(zone int64) string {
    if zone%3 == 1 { return "ABCDEFGH" }
    if zone%3 == 2 { return "JKLMNPQR" }
    return "STUVWXYZ"
}
func squareDigits(a []string, start int, e,n *int64) int64 {
    if len(a) == start { return 100000 }
    require(digits(a[start],1,5) && digits(a[start+1],1,5) && len(a[start]) == len(a[start+1]))
    scale := int64(1)
    for i:=len(a[start]); i<5; i++ { scale *= 10 }
    *e += integer(a[start],0,99999)*scale
    *n += integer(a[start+1],0,99999)*scale
    return scale
}
func execute(a []string) string {
    names := []string{
        "ENCODE", "DECODE", "NEIGHBORS", "PARENT", "CHILDREN", "COMMON",
        "COMPACT", "CONTAINS", "COVER", "CONVERT", "STEPS", "PATH", "RELATE",
        "SIZE", "SHORTEN", "RECOVER", "UTMZONE", "OSGB", "UNOSGB", "MGRS",
        "UNMGRS", "QUADKEY", "UNQUADKEY",
    }
    command := -1
    for i,name := range names {
        if a[0] == name { command = i }
    }
    require(command >= 0)
    lengths := []int{5,3,3,3,3,4,0,5,7,6,4,4,5,3,4,4,3,4,0,6,0,4,2}
    switch command {
    case 6: require(len(a) >= 3 && len(a) <= 102)
    case 18: require(len(a) == 2 || len(a) == 4)
    case 20: require(len(a) == 3 || len(a) == 5)
    default: require(len(a) == lengths[command])
    }
    if command <= 13 {
        system := systemID(a[1])
        if command == 0 {
            lat,lon := location(a[2],true),location(a[3],false)
            precision := precisionArgument(system,a[4])
            code := encode(system,point(system,precision,lat,lon))
            if code == "" { return "OUT OF AREA" }
            return code
        }
        if command == 8 {
            precision := precisionArgument(system,a[2])
            lat1,lon1,lat2,lon2 := location(a[3],true),location(a[4],false),location(a[5],true),location(a[6],false)
            require(lat1 <= lat2)
            first,last := point(system,precision,lat1,lon1),point(system,precision,lat2,lon2)
            g := grids[system][precision]
            columns := last.x-first.x+1
            if lon1 > lon2 { columns = minimum(g.width,columns+g.width) }
            if (last.y-first.y+1)*columns > 100 { return "TOO MANY" }
            result := []string{}
            for y:=last.y; y>=first.y; y-- {
                for i:=int64(0); i<columns; i++ { result = append(result,display(system,cell{precision,(first.x+i)%g.width,y})) }
            }
            return strings.Join(result," ")
        }
        if command == 13 {
            precision := precisionArgument(system,a[2])
            g := grids[system][precision]
            count := g.width*g.height
            if system == 5 { count = 8000*meshScale[precision]*meshScale[precision] }
            return "w="+coordinate(360000000/g.width)+" h="+coordinate(180000000/g.height)+" cells="+number(count)
        }
        if command == 6 { return compact(system,a[2:]) }
        c := decode(system,a[2])
        g := grids[system][c.precision]
        switch command {
        case 1:
            south,west := -90000000+180000000*c.y/g.height,-180000000+360000000*c.x/g.width
            north,east := -90000000+180000000*(c.y+1)/g.height,-180000000+360000000*(c.x+1)/g.width
            cy,cx := floorRatio(centerNumerator(c.y,g.height,180000000),2*g.height),floorRatio(centerNumerator(c.x,g.width,360000000),2*g.width)
            return "sw="+coordinate(south)+","+coordinate(west)+" ne="+coordinate(north)+","+coordinate(east)+" c="+coordinate(cy)+","+coordinate(cx)
        case 2:
            dx,dy := []int64{0,1,1,1,0,-1,-1,-1},[]int64{1,1,0,-1,-1,-1,0,1}
            result := []string{}
            for i:=0; i<8; i++ {
                code := "-"
                if c.y+dy[i] >= 0 && c.y+dy[i] < g.height { code = display(system,cell{c.precision,modulo(c.x+dx[i],g.width),c.y+dy[i]}) }
                result = append(result,code)
            }
            return strings.Join(result," ")
        case 3:
            if c.precision == 0 { return "NONE" }
            return encode(system,ancestor(system,c,c.precision-1))
        case 4:
            if c.precision+1 == len(grids[system]) { return "NONE" }
            next := grids[system][c.precision+1]
            rx,ry := next.width/g.width,next.height/g.height
            if rx*ry > 100 { return "TOO MANY" }
            result := []string{}
            for j:=ry-1; j>=0; j-- {
                for i:=int64(0); i<rx; i++ { result = append(result,display(system,cell{c.precision+1,rx*c.x+i,ry*c.y+j})) }
            }
            return strings.Join(result," ")
        case 7:
            lat,lon := location(a[3],true),location(a[4],false)
            if point(system,c.precision,lat,lon) == c { return "YES" }
            return "NO"
        case 9:
            require(a[3] == "TO")
            destination := systemID(a[4])
            precision := precisionArgument(destination,a[5])
            next := grids[destination][precision]
            code := encode(destination,cell{precision,(2*c.x+1)*next.width/(2*g.width),(2*c.y+1)*next.height/(2*g.height)})
            if code == "" { return "OUT OF AREA" }
            return code
        case 12:
            otherSystem := systemID(a[3])
            return relation(system,c,otherSystem,decode(otherSystem,a[4]))
        }
        other := decode(system,a[3])
        if command == 5 {
            for p:=int(minimum(int64(c.precision),int64(other.precision))); p>=0; p-- {
                parent := ancestor(system,c,p)
                if parent == ancestor(system,other,p) { return encode(system,parent) }
            }
            return "NONE"
        }
        if c.precision != other.precision { return "MISMATCH" }
        dx,dy := modulo(other.x-c.x,g.width),other.y-c.y
        if dx > g.width/2 { dx -= g.width }
        if command == 10 { return "dx="+number(dx)+" dy="+number(dy) }
        n := maximum(absolute(dx),absolute(dy))
        if n+1 > 100 { return "TOO MANY" }
        result := []string{}
        for i:=int64(0); i<=n; i++ {
            x,y := c.x,c.y
            if n != 0 {
                x += floorRatio(2*i*dx+n,2*n)
                y += floorRatio(2*i*dy+n,2*n)
            }
            result = append(result,display(system,cell{c.precision,modulo(x,g.width),y}))
        }
        return strings.Join(result," ")
    }
    if command == 14 || command == 15 {
        lat,lon := location(a[2],true),location(a[3],false)
        full,removed := a[1],0
        if command == 15 {
            plus := strings.IndexByte(full,'+')
            require((plus == 2 || plus == 4) && strings.Count(full,"+") == 1)
            suffix := len(full)-plus-1
            require(suffix == 0 || suffix == 2 || suffix == 3)
            for i:=range full {
                if full[i] != '+' { digit(plusAlphabet,full[i]) }
            }
            removed = 8-plus
            full = encode(2,point(2,precisionID(2,10),lat,lon))[:removed]+full
        }
        c := decode(2,full)
        g := grids[2][c.precision]
        require(g.precision >= 8)
        cy,cx := centerNumerator(c.y,g.height,180000000),centerNumerator(c.x,g.width,360000000)
        yd,xd := 2*g.height,2*g.width
        if command == 14 {
            if absolute(cy-lat*yd) < 15000*yd && absolute(cx-lon*xd) < 15000*xd { return full[6:] }
            if absolute(cy-lat*yd) < 300000*yd && absolute(cx-lon*xd) < 300000*xd { return full[4:] }
            return full
        }
        distance := int64(50000)
        if removed == 4 { distance = 1000000 }
        my,mx := distance*g.height/180000000,distance*g.width/360000000
        if (lat+distance/2)*yd < cy && cy-distance*yd >= -90000000*yd {
            c.y -= my
        } else if (lat-distance/2)*yd > cy && cy+distance*yd <= 90000000*yd {
            c.y += my
        }
        if (lon+distance/2)*xd < cx {
            c.x = modulo(c.x-mx,g.width)
        } else if (lon-distance/2)*xd > cx {
            c.x = modulo(c.x+mx,g.width)
        }
        return encode(2,c)
    }
    if command == 16 {
        lat,lon := location(a[1],true),location(a[2],false)
        if lat < -80000000 || lat >= 84000000 { return "NONE" }
        band := bands[minimum((lat+80000000)/8000000,19)]
        zone := (lon+180000000)/6000000+1
        if band == 'V' && lon >= 3000000 && lon < 12000000 { zone = 32 }
        if band == 'X' && lon >= 0 && lon < 42000000 {
            zone = 37
            if lon < 9000000 {
                zone = 31
            } else if lon < 21000000 {
                zone = 33
            } else if lon < 33000000 {
                zone = 35
            }
        }
        return number(zone)+string(band)
    }
    if command == 17 || command == 19 {
        var e,n int64
        var d int
        var prefix string
        if command == 17 {
            e,n,d = integer(a[1],0,699999),integer(a[2],0,1299999),int(integer(a[3],0,5))
            prefix = string(osLetters[5*(3-n/500000)+2+e/500000])+string(osLetters[5*(4-n/100000%5)+e/100000%5])
        } else {
            zone := integer(a[1],1,60)
            require(len(a[2]) == 1)
            digit(bands,a[2][0])
            e,n,d = integer(a[3],100000,899999),integer(a[4],0,9999999),int(integer(a[5],0,5))
            offset := int64(0)
            if zone%2 == 0 { offset = 5 }
            prefix = number(zone)+a[2]+" "+string(mgrsColumns(zone)[e/100000-1])+string(mgrsRows[(n/100000+offset)%20])
        }
        if d > 0 { prefix += " "+padded(e%100000,5)[:d]+" "+padded(n%100000,5)[:d] }
        return prefix
    }
    if command == 18 || command == 20 {
        var e,n,scale int64
        prefix := ""
        if command == 18 {
            require(len(a[1]) == 2)
            first,second := digit(osLetters,a[1][0]),digit(osLetters,a[1][1])
            e = 500000*(first%5-2)+100000*(second%5)
            n = 500000*(3-first/5)+100000*(4-second/5)
            require(e >= 0 && e < 700000 && n >= 0 && n < 1300000)
            scale = squareDigits(a,2,&e,&n)
        } else {
            require(len(a[1]) == 2 || len(a[1]) == 3)
            zoneText := a[1][:len(a[1])-1]
            require(digits(zoneText,1,2) && zoneText[0] != '0')
            zone := integer(zoneText,1,60)
            digit(bands,a[1][len(a[1])-1])
            require(len(a[2]) == 2)
            e = 100000*(digit(mgrsColumns(zone),a[2][0])+1)
            offset := int64(0)
            if zone%2 == 0 { offset = 5 }
            n = 100000*modulo(digit(mgrsRows,a[2][1])-offset,20)
            scale = squareDigits(a,3,&e,&n)
            prefix = a[1]+" "
        }
        return prefix+"sw="+number(e)+","+number(n)+" size="+number(scale)
    }
    if command == 21 {
        z := integer(a[3],1,23)
        x,y := integer(a[1],0,(int64(1)<<z)-1),integer(a[2],0,(int64(1)<<z)-1)
        key := ""
        for i:=z-1; i>=0; i-- { key += string(byte('0'+(x>>i&1)+2*(y>>i&1))) }
        return key
    }
    require(len(a[1]) >= 1 && len(a[1]) <= 23)
    var x,y int64
    for i:=range a[1] {
        require(a[1][i] >= '0' && a[1][i] <= '3')
        q := int64(a[1][i]-'0')
        x,y = 2*x+q%2,2*y+q/2
    }
    return "x="+number(x)+" y="+number(y)+" z="+number(int64(len(a[1])))
}
func answer(line string) (result string) {
    defer func() {
        if failure := recover(); failure != nil {
            if _,ok := failure.(invalid); ok {
                result = "INVALID"
            } else {
                panic(failure)
            }
        }
    }()
    return execute(strings.Split(line," "))
}
func main() {
    for p:=1; p<=9; p++ { grids[0] = append(grids[0],grid{p,int64(1)<<((5*p+1)/2),int64(1)<<(5*p/2)}) }
    scanner := bufio.NewScanner(os.Stdin)
    scanner.Scan()
    count,_ := strconv.Atoi(scanner.Text())
    out := bufio.NewWriter(os.Stdout)
    defer out.Flush()
    for i:=0; i<count; i++ {
        scanner.Scan()
        fmt.Fprintln(out,answer(scanner.Text()))
    }
}
