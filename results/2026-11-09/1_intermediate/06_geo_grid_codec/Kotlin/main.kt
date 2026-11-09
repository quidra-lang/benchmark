import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

private const val GH = "0123456789bcdefghjkmnpqrstuvwxyz"
private const val L24 = "ABCDEFGHJKLMNPQRSTUVWXYZ"
private const val PLUS = "23456789CFGHJMPQRVWX"
private const val G25 = "ABCDEFGHJKLMNOPQRSTUVWXYZ"
private const val BANDS = "CDEFGHJKLMNPQRSTUVWX"
private const val MROWS = "ABCDEFGHJKLMNPQRSTUV"
private val precisionTable = mapOf(
    "GEOHASH" to intArrayOf(1,2,3,4,5,6,7,8,9), "MAIDENHEAD" to intArrayOf(2,4,6,8),
    "PLUSCODE" to intArrayOf(2,4,6,8,10,11), "GARS" to intArrayOf(5,6,7),
    "GEOREF" to intArrayOf(2,4,8,10,12), "MESH" to intArrayOf(4,6,8,9,10,11)
)
private val counts = mapOf("ENCODE" to 4,"DECODE" to 2,"NEIGHBORS" to 2,"PARENT" to 2,"CHILDREN" to 2,
        "COMMON" to 3,"CONTAINS" to 4,"COVER" to 6,"CONVERT" to 5,"STEPS" to 3,"PATH" to 3,
        "RELATE" to 4,"SIZE" to 2,"SHORTEN" to 3,"RECOVER" to 3)
private val meshScale = longArrayOf(1,8,80,160,320,640)
private val maiden = arrayOf("ABCDEFGHIJKLMNOPQR","0123456789","abcdefghijklmnopqrstuvwx","0123456789")
private data class Cell(val system: String, val level: Int, val x: Long, val y: Long, val w: Long, val h: Long)
private class Invalid : RuntimeException()
private fun need(condition: Boolean) { if (!condition) throw Invalid() }
private fun integer(s: String): Long {
    need(s.matches(Regex("-?[0-9]{1,9}")))
    return s.toLong()
}
private fun range(s: String, low: Long, high: Long): Long = integer(s).also { need(it in low..high) }
private fun coordinate(s: String, latitude: Boolean): Long {
    need(s.matches(Regex("-?[0-9]{1,3}(\\.[0-9]{1,6})?")))
    val negative = s.startsWith('-')
    val pieces = s.removePrefix("-").split('.')
    var value = pieces[0].toLong()*1000000
    if (pieces.size == 2) value += pieces[1].padEnd(6,'0').toLong()
    if (negative) value = -value
    need(if (latitude) value in -90000000L..90000000L else value >= -180000000 && value < 180000000)
    return value
}
private fun precisions(system: String): IntArray = precisionTable[system] ?: throw Invalid()
private fun level(system: String, precision: Long): Int {
    val result = precisions(system).indexOf(precision.toInt())
    need(result >= 0)
    return result
}
private fun grid(system: String, level: Int, x: Long = 0, y: Long = 0): Cell {
    val p = precisions(system)[level]
    val widths = when (system) {
        "GEOHASH" -> longArrayOf(1L shl ((5*p+1)/2),1L shl (5*p/2))
        "MAIDENHEAD" -> longArrayOf(longArrayOf(18,180,4320,43200)[level],longArrayOf(18,180,4320,43200)[level])
        "PLUSCODE" -> longArrayOf(longArrayOf(18,360,7200,144000,2880000,11520000)[level],longArrayOf(9,180,3600,72000,1440000,7200000)[level])
        "GARS" -> longArrayOf(longArrayOf(720,1440,4320)[level],longArrayOf(360,720,2160)[level])
        "GEOREF" -> longArrayOf(longArrayOf(24,360,21600,216000,2160000)[level],longArrayOf(12,180,10800,108000,1080000)[level])
        else -> longArrayOf(360*meshScale[level],270*meshScale[level])
    }
    return Cell(system,level,x,y,widths[0],widths[1])
}
private fun point(system: String, level: Int, lat: Long, lon: Long): Cell {
    val g = grid(system,level)
    return grid(system,level,(lon+180000000)*g.w/360000000,min((lat+90000000)*g.h/180000000,g.h-1))
}
private fun digit(c: Char, alphabet: String): Int = alphabet.indexOf(c).also { need(it >= 0) }
private fun digits(s: String): Long {
    need(s.isNotEmpty() && s.all { it in '0'..'9' })
    return s.toLong()
}
private fun pad(n: Long, width: Int) = n.toString().padStart(width,'0')
private fun power(n: Int): Long {
    var value = 1L
    repeat(n) { value *= 10 }
    return value
}
private fun radix(value: Long, bases: LongArray, count: Int): LongArray {
    var rest = value
    val result = LongArray(count)
    for (i in count-1 downTo 0) {
        result[i] = rest%bases[i]
        rest /= bases[i]
    }
    return result
}
private fun code(c: Cell): String? {
    val p = precisions(c.system)[c.level]
    var x = c.x
    var y = c.y
    val result = StringBuilder()
    when (c.system) {
        "GEOHASH" -> {
            var ax = (5*p+1)/2
            var ay = 5*p/2
            var group = 0
            for (bit in 0 until 5*p) {
                val b = if (bit%2 == 0) (x shr --ax) and 1 else (y shr --ay) and 1
                group = group*2+b.toInt()
                if (bit%5 == 4) {
                    result.append(GH[group])
                    group = 0
                }
            }
        }
        "MAIDENHEAD" -> {
            val a = radix(x,longArrayOf(18,10,24,10),p/2)
            val b = radix(y,longArrayOf(18,10,24,10),p/2)
            for (i in a.indices) result.append(maiden[i][a[i].toInt()]).append(maiden[i][b[i].toInt()])
        }
        "PLUSCODE" -> {
            val extra = if (p == 11) (4*(y%5)+x%4).toInt() else -1
            if (p == 11) {
                x /= 4
                y /= 5
            }
            val count = min(p,10)/2
            val a = radix(x,longArrayOf(18,20,20,20,20),count)
            val b = radix(y,longArrayOf(9,20,20,20,20),count)
            for (i in 0 until count) result.append(PLUS[b[i].toInt()]).append(PLUS[a[i].toInt()])
            if (extra >= 0) result.append(PLUS[extra])
            val text = result.toString()
            return if (p < 8) text+"0".repeat(8-p)+"+" else text.take(8)+"+"+text.drop(8)
        }
        "GARS" -> {
            val scale = if (c.level == 0) 1 else if (c.level == 1) 2 else 6
            val bx = x/scale
            val by = y/scale
            result.append(pad(bx+1,3)).append(L24[(by/24).toInt()]).append(L24[(by%24).toInt()])
            if (p >= 6) {
                val divisor = if (p == 7) 3 else 1
                result.append(1+x/divisor%2+2*(1-y/divisor%2))
            }
            if (p == 7) result.append(1+x%3+3*(2-y%3))
        }
        "GEOREF" -> {
            if (p == 2) return "${L24[x.toInt()]}${L24[y.toInt()]}"
            val m = (p-4)/2
            val scale = if (p == 4) 1L else 6*power(m-1)
            val bx = x/scale
            val by = y/scale
            result.append(L24[(bx/15).toInt()]).append(L24[(by/15).toInt()])
                .append(L24[(bx%15).toInt()]).append(L24[(by%15).toInt()])
            if (p >= 8) result.append(pad(x%scale,m)).append(pad(y%scale,m))
        }
        else -> {
            val scale = meshScale[c.level]
            val u = x-280*scale
            val v = y-135*scale
            if (u < 0 || u >= 80*scale || v < 0 || v >= 100*scale) return null
            val count = c.level+1
            val a = radix(u,longArrayOf(80,8,10,2,2,2),count)
            val b = radix(v,longArrayOf(100,8,10,2,2,2),count)
            result.append(pad(b[0],2)).append(pad(a[0],2))
            for (i in 1 until count) {
                if (i <= 2) result.append(b[i]).append(a[i])
                else result.append(1+a[i]+2*b[i])
            }
        }
    }
    return result.toString()
}
private fun decode(system: String, text: String): Cell {
    precisions(system)
    var p = text.length
    var x = 0L
    var y = 0L
    when (system) {
        "GEOHASH" -> {
            need(p in 1..9)
            var bit = 0
            for (ch in text) {
                val d = digit(ch,GH)
                for (i in 4 downTo 0) {
                    if (bit%2 == 0) x = x*2+((d shr i) and 1)
                    else y = y*2+((d shr i) and 1)
                    bit++
                }
            }
        }
        "MAIDENHEAD" -> {
            level(system,p.toLong())
            for (i in 0 until p/2) {
                x = x*maiden[i].length+digit(text[2*i],maiden[i])
                y = y*maiden[i].length+digit(text[2*i+1],maiden[i])
            }
        }
        "PLUSCODE" -> {
            need(p >= 9 && text.indexOf('+') == 8 && text.lastIndexOf('+') == 8)
            val firstZero = text.take(8).indexOf('0')
            val before = if (firstZero < 0) 8 else firstZero
            val after = p-9
            need(before in listOf(2,4,6,8))
            need(if (before == 8) after in listOf(0,2,3) else after == 0)
            for (i in before until 8) need(text[i] == '0')
            val sequence = text.take(before)+text.drop(9)
            p = sequence.length
            need(digit(sequence[0],PLUS) <= 8 && digit(sequence[1],PLUS) <= 17)
            for (i in 0 until min(p,10) step 2) {
                y = y*20+digit(sequence[i],PLUS)
                x = x*20+digit(sequence[i+1],PLUS)
            }
            if (p == 11) {
                val d = digit(sequence[10],PLUS)
                x = x*4+d%4
                y = y*5+d/4
            }
        }
        "GARS" -> {
            need(p in 5..7)
            val e = digits(text.take(3))
            need(e in 1L..720L)
            x = e-1
            y = (digit(text[3],L24.take(15))*24+digit(text[4],L24)).toLong()
            if (p >= 6) {
                val q = digit(text[5],"1234")
                x = x*2+q%2
                y = y*2+1-q/2
            }
            if (p == 7) {
                val q = digit(text[6],"123456789")
                x = x*3+q%3
                y = y*3+2-q/3
            }
        }
        "GEOREF" -> {
            level(system,p.toLong())
            x = digit(text[0],L24).toLong()
            y = digit(text[1],L24.take(12)).toLong()
            if (p >= 4) {
                x = x*15+digit(text[2],L24.take(15))
                y = y*15+digit(text[3],L24.take(15))
            }
            if (p >= 8) {
                val m = (p-4)/2
                val scale = 6*power(m-1)
                val a = digits(text.substring(4,4+m))
                val b = digits(text.drop(4+m))
                need(a < scale && b < scale)
                x = x*scale+a
                y = y*scale+b
            }
        }
        else -> {
            val l = level(system,p.toLong())
            digits(text)
            var v = digits(text.take(2))
            var u = digits(text.substring(2,4))
            need(u < 80)
            if (p >= 6) {
                v = v*8+digit(text[4],"01234567")
                u = u*8+digit(text[5],"01234567")
            }
            if (p >= 8) {
                v = v*10+digit(text[6],"0123456789")
                u = u*10+digit(text[7],"0123456789")
            }
            for (i in 8 until p) {
                val q = digit(text[i],"1234")
                v = v*2+q/2
                u = u*2+q%2
            }
            x = u+280*meshScale[l]
            y = v+135*meshScale[l]
        }
    }
    val result = grid(system,level(system,p.toLong()),x,y)
    need(text == code(result))
    return result
}
private fun ancestor(c: Cell, level: Int): Cell {
    val g = grid(c.system,level)
    return grid(c.system,level,c.x*g.w/c.w,c.y*g.h/c.h)
}
private fun shown(c: Cell) = code(c) ?: "-"
private fun coordinateFormat(n: Long) = (if (n < 0) "-" else "")+"${abs(n)/1000000}.${pad(abs(n)%1000000,6)}"
private fun boundary(c: Cell, latitude: Boolean, offset: Int, center: Boolean): Long {
    val extent = if (latitude) 180000000L else 360000000L
    val total = if (latitude) c.h else c.w
    val value = if (latitude) c.y else c.x
    return -extent/2+if (center) extent*(2*value+1)/(2*total) else extent*(value+offset)/total
}
private fun compare(a: Long, ad: Long, b: Long, bd: Long) = (a*bd).compareTo(b*ad)
private fun inside(a: Cell, b: Cell) = compare(a.x,a.w,b.x,b.w) >= 0 && compare(a.x+1,a.w,b.x+1,b.w) <= 0 &&
    compare(a.y,a.h,b.y,b.h) >= 0 && compare(a.y+1,a.h,b.y+1,b.h) <= 0
private fun steps(a: Cell, b: Cell): LongArray {
    var dx = Math.floorMod(b.x-a.x,a.w)
    if (dx > a.w/2) dx -= a.w
    return longArrayOf(dx,b.y-a.y)
}
private fun detail(a: String, b: String): LongArray {
    need(a.matches(Regex("[0-9]{1,5}")) && b.matches(Regex("[0-9]{1,5}")) && a.length == b.length)
    val size = power(5-a.length)
    return longArrayOf(digits(a)*size,digits(b)*size,size)
}
private fun columns(zone: Long) = if (zone%3 == 1L) "ABCDEFGH" else if (zone%3 == 2L) "JKLMNPQR" else "STUVWXYZ"
private fun auxiliary(t: List<String>): String {
    val n = t.size-1
    when (t[0]) {
        "UTMZONE" -> {
            need(n == 2)
            val lat = coordinate(t[1],true)
            val lon = coordinate(t[2],false)
            if (lat < -80000000 || lat >= 84000000) return "NONE"
            val band = BANDS[min((lat+80000000)/8000000,19).toInt()]
            var zone = (lon+180000000)/6000000+1
            if (band == 'V' && lon >= 3000000 && lon < 12000000) zone = 32
            if (band == 'X') {
                if (lon >= 0 && lon < 9000000) zone = 31
                else if (lon >= 9000000 && lon < 21000000) zone = 33
                else if (lon >= 21000000 && lon < 33000000) zone = 35
                else if (lon >= 33000000 && lon < 42000000) zone = 37
            }
            return "$zone$band"
        }
        "OSGB" -> {
            need(n == 3)
            val e = range(t[1],0,699999)
            val north = range(t[2],0,1299999)
            val d = range(t[3],0,5).toInt()
            val letters = "${G25[((3-north/500000)*5+2+e/500000).toInt()]}${G25[((4-north/100000%5)*5+e/100000%5).toInt()]}"
            return letters+if (d == 0) "" else " ${pad(e%100000,5).take(d)} ${pad(north%100000,5).take(d)}"
        }
        "UNOSGB" -> {
            need(n == 1 || n == 3)
            need(t[1].length == 2)
            val a = digit(t[1][0],G25)
            val b = digit(t[1][1],G25)
            var e = (500000*(a%5-2)+100000*(b%5)).toLong()
            var north = (500000*(3-a/5)+100000*(4-b/5)).toLong()
            var size = 100000L
            need(e >= 0 && e < 700000 && north >= 0 && north < 1300000)
            if (n == 3) {
                val values = detail(t[2],t[3])
                e += values[0]
                north += values[1]
                size = values[2]
            }
            return "sw=$e,$north size=$size"
        }
        "MGRS" -> {
            need(n == 5)
            val zone = range(t[1],1,60)
            val e = range(t[3],100000,899999)
            val north = range(t[4],0,9999999)
            need(t[2].length == 1)
            digit(t[2][0],BANDS)
            val d = range(t[5],0,5).toInt()
            val offset = if (zone%2 == 0L) 5 else 0
            val square = "${columns(zone)[(e/100000-1).toInt()]}${MROWS[((north/100000+offset)%20).toInt()]}"
            return "$zone${t[2]} $square"+if (d == 0) "" else " ${pad(e%100000,5).take(d)} ${pad(north%100000,5).take(d)}"
        }
        "UNMGRS" -> {
            need(n == 2 || n == 4)
            need(t[1].matches(Regex("[1-9][0-9]?[CDEFGHJKLMNPQRSTUVWX]")))
            val zone = t[1].dropLast(1).toLong()
            need(zone <= 60 && t[2].length == 2)
            val a = digit(t[2][0],columns(zone))
            val b = digit(t[2][1],MROWS)
            val offset = if (zone%2 == 0L) 5 else 0
            var e = 100000L*(a+1)
            var north = 100000*Math.floorMod((b-offset).toLong(),20)
            var size = 100000L
            if (n == 4) {
                val values = detail(t[3],t[4])
                e += values[0]
                north += values[1]
                size = values[2]
            }
            return "${t[1]} sw=$e,$north size=$size"
        }
        "QUADKEY" -> {
            need(n == 3)
            val z = range(t[3],1,23).toInt()
            val x = range(t[1],0,(1L shl z)-1)
            val y = range(t[2],0,(1L shl z)-1)
            return (z-1 downTo 0).joinToString("") { (((x shr it) and 1)+2*((y shr it) and 1)).toString() }
        }
        "UNQUADKEY" -> {
            need(n == 1 && t[1].matches(Regex("[0-3]{1,23}")))
            var x = 0L
            var y = 0L
            for (ch in t[1]) {
                val d = ch-'0'
                x = x*2+d%2
                y = y*2+d/2
            }
            return "x=$x y=$y z=${t[1].length}"
        }
        else -> throw Invalid()
    }
}
private fun execute(line: String): String {
    val t = line.split(' ')
    val command = t[0]
    if (command !in counts && command != "COMPACT") return auxiliary(t)
    need(if (command == "COMPACT") t.size in 3..102 else t.size == counts.getValue(command)+1)
    if (command == "SHORTEN" || command == "RECOVER") {
        val lat = coordinate(t[2],true)
        val lon = coordinate(t[3],false)
        if (command == "SHORTEN") {
            val c = decode("PLUSCODE",t[1])
            need(precisions(c.system)[c.level] >= 8)
            val yn = -90000000*2*c.h+180000000*(2*c.y+1)
            val xn = -180000000*2*c.w+360000000*(2*c.x+1)
            if (abs(yn-lat*2*c.h) < 15000*2*c.h && abs(xn-lon*2*c.w) < 15000*2*c.w) return t[1].drop(6)
            if (abs(yn-lat*2*c.h) < 300000*2*c.h && abs(xn-lon*2*c.w) < 300000*2*c.w) return t[1].drop(4)
            return t[1]
        }
        val plus = t[1].indexOf('+')
        need(plus == 2 || plus == 4)
        need(t[1].lastIndexOf('+') == plus)
        need(t[1].length-plus-1 in listOf(0,2,3))
        for (ch in t[1].replace("+","")) digit(ch,PLUS)
        val missing = 8-plus
        val prefix = code(point("PLUSCODE",4,lat,lon))!!.take(missing)
        val c = decode("PLUSCODE",prefix+t[1])
        val d = if (missing == 4) 1000000L else 50000L
        var x = c.x
        var y = c.y
        val yn = -90000000*2*c.h+180000000*(2*y+1)
        val xn = -180000000*2*c.w+360000000*(2*x+1)
        val my = d*c.h/180000000
        val mx = d*c.w/360000000
        if ((lat+d/2)*2*c.h < yn && yn-d*2*c.h >= -90000000*2*c.h) y -= my
        else if ((lat-d/2)*2*c.h > yn && yn+d*2*c.h <= 90000000*2*c.h) y += my
        if ((lon+d/2)*2*c.w < xn) x = Math.floorMod(x-mx,c.w)
        else if ((lon-d/2)*2*c.w > xn) x = Math.floorMod(x+mx,c.w)
        return code(grid("PLUSCODE",c.level,x,y))!!
    }
    val system = t[1]
    precisions(system)
    when (command) {
        "ENCODE" -> return code(point(system,level(system,integer(t[4])),coordinate(t[2],true),coordinate(t[3],false))) ?: "OUT OF AREA"
        "SIZE" -> {
            val l = level(system,integer(t[2]))
            val c = grid(system,l)
            val count = if (system == "MESH") 8000*meshScale[l]*meshScale[l] else c.w*c.h
            return "w=${coordinateFormat(360000000/c.w)} h=${coordinateFormat(180000000/c.h)} cells=$count"
        }
        "COVER" -> {
            val l = level(system,integer(t[2]))
            val lat1 = coordinate(t[3],true)
            val lon1 = coordinate(t[4],false)
            val lat2 = coordinate(t[5],true)
            val lon2 = coordinate(t[6],false)
            need(lat1 <= lat2)
            val a = point(system,l,lat1,lon1)
            val b = point(system,l,lat2,lon2)
            val columns = if (lon1 <= lon2) b.x-a.x+1 else min(a.w,b.x-a.x+1+a.w)
            if (columns*(b.y-a.y+1) > 100) return "TOO MANY"
            val result = mutableListOf<String>()
            for (y in b.y downTo a.y) {
                for (i in 0 until columns) result.add(shown(grid(system,l,(a.x+i)%a.w,y)))
            }
            return result.joinToString(" ")
        }
        "COMPACT" -> {
            val cells = t.drop(2).map { decode(system,it) }.toMutableSet()
            val covered = cells.filter { c -> cells.any { a -> a.level < c.level && ancestor(c,a.level) == a } }
            cells.removeAll(covered.toSet())
            var changed = true
            while (changed) {
                changed = false
                for (child in cells.toList()) {
                    if (child.level == 0) continue
                    val parent = ancestor(child,child.level-1)
                    val g = grid(system,child.level)
                    val rx = g.w/parent.w
                    val ry = g.h/parent.h
                    if (rx*ry > cells.size) continue
                    val siblings = mutableSetOf<Cell>()
                    for (j in 0 until ry) {
                        for (i in 0 until rx) siblings.add(grid(system,child.level,parent.x*rx+i,parent.y*ry+j))
                    }
                    if (cells.containsAll(siblings)) {
                        cells.removeAll(siblings)
                        cells.add(parent)
                        changed = true
                        break
                    }
                }
            }
            return cells.sortedWith(compareBy<Cell> { it.level }.thenByDescending { it.y }.thenBy { it.x }).joinToString(" ") { code(it)!! }
        }
    }
    val a = decode(system,t[2])
    when (command) {
        "DECODE" -> return "sw=${coordinateFormat(boundary(a,true,0,false))},${coordinateFormat(boundary(a,false,0,false))}"+
            " ne=${coordinateFormat(boundary(a,true,1,false))},${coordinateFormat(boundary(a,false,1,false))}"+
            " c=${coordinateFormat(boundary(a,true,0,true))},${coordinateFormat(boundary(a,false,0,true))}"
        "NEIGHBORS" -> {
            val dx = intArrayOf(0,1,1,1,0,-1,-1,-1)
            val dy = intArrayOf(1,1,0,-1,-1,-1,0,1)
            return (0..7).joinToString(" ") { i -> if (a.y+dy[i] < 0 || a.y+dy[i] >= a.h) "-" else shown(grid(system,a.level,Math.floorMod(a.x+dx[i],a.w),a.y+dy[i])) }
        }
        "PARENT" -> return if (a.level == 0) "NONE" else code(ancestor(a,a.level-1))!!
        "CHILDREN" -> {
            if (a.level+1 == precisions(system).size) return "NONE"
            val g = grid(system,a.level+1)
            val rx = g.w/a.w
            val ry = g.h/a.h
            if (rx*ry > 100) return "TOO MANY"
            val result = mutableListOf<String>()
            for (j in ry-1 downTo 0) {
                for (i in 0 until rx) result.add(shown(grid(system,g.level,a.x*rx+i,a.y*ry+j)))
            }
            return result.joinToString(" ")
        }
        "COMMON" -> {
            val b = decode(system,t[3])
            for (l in min(a.level,b.level) downTo 0) {
                val parent = ancestor(a,l)
                if (parent == ancestor(b,l)) return code(parent)!!
            }
            return "NONE"
        }
        "CONTAINS" -> return if (a == point(system,a.level,coordinate(t[3],true),coordinate(t[4],false))) "YES" else "NO"
        "CONVERT" -> {
            need(t[3] == "TO")
            val g = grid(t[4],level(t[4],integer(t[5])))
            return code(grid(g.system,g.level,(2*a.x+1)*g.w/(2*a.w),(2*a.y+1)*g.h/(2*a.h))) ?: "OUT OF AREA"
        }
        "STEPS", "PATH" -> {
            val b = decode(system,t[3])
            if (a.level != b.level) return "MISMATCH"
            val delta = steps(a,b)
            if (command == "STEPS") return "dx=${delta[0]} dy=${delta[1]}"
            val n = max(abs(delta[0]),abs(delta[1]))
            if (n+1 > 100) return "TOO MANY"
            return (0L..n).joinToString(" ") { i ->
                val dx = if (n == 0L) 0 else Math.floorDiv(2*i*delta[0]+n,2*n)
                val dy = if (n == 0L) 0 else Math.floorDiv(2*i*delta[1]+n,2*n)
                shown(grid(system,a.level,Math.floorMod(a.x+dx,a.w),a.y+dy))
            }
        }
        "RELATE" -> {
            val b = decode(t[3],t[4])
            val ab = inside(a,b)
            val ba = inside(b,a)
            if (ab && ba) return "EQUAL"
            if (ab) return "INSIDE"
            if (ba) return "CONTAINS"
            val ew = compare(a.x+1,a.w,b.x,b.w)
            val we = compare(b.x+1,b.w,a.x,a.w)
            val ns = compare(a.y+1,a.h,b.y,b.h)
            val sn = compare(b.y+1,b.h,a.y,a.h)
            if (ew > 0 && we > 0 && ns > 0 && sn > 0) return "OVERLAP"
            val dateline = a.x+1 == a.w && b.x == 0L || b.x+1 == b.w && a.x == 0L
            return if (ns >= 0 && sn >= 0 && (ew >= 0 && we >= 0 || dateline)) "TOUCH" else "DISJOINT"
        }
        else -> throw Invalid()
    }
}
fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    repeat(input.readLine().toInt()) {
        val result = try { execute(input.readLine()) } catch (_: Invalid) { "INVALID" }
        output.write(result)
        output.newLine()
    }
    output.flush()
}
