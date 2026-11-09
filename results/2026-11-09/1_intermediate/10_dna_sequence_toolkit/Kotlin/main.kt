import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

private const val BASES = "ACGT"
private const val SYMBOLS = "ACGTRYSWKMBDHVN"
private const val COMPLEMENTS = "TGCAYRSWMKVHDBN"
private val masks = intArrayOf(1,2,4,8,5,10,6,9,12,3,14,13,11,7,15)
private const val AMINO = "ACDEFGHIKLMNPQRSTVWY"
private val residues = intArrayOf(71079,103139,115089,129116,147177,57052,137141,113160,128174,113160,131193,114104,97117,128131,156188,87078,101105,99133,186213,163176)
private val baseMass = intArrayOf(331222,307197,347221,322208)
private val enzymes = listOf("EcoRI","BamHI","HindIII","PstI","SmaI","KpnI","XbaI","NotI","EcoRV","HaeIII","AluI","TaqI","Sau3AI","HincII","AvaI")
private val sites = listOf("GAATTC","GGATCC","AAGCTT","CTGCAG","CCCGGG","GGTACC","TCTAGA","GCGGCCGC","GATATC","GGCC","AGCT","TCGA","GATC","GTYRAC","CYCGRG")
private val cuts = intArrayOf(1,1,1,5,3,5,1,2,3,2,2,1,0,3,1)
private val genetic = buildMap<String,Char> {
    val groups = listOf("A GCT GCC GCA GCG",
            "C TGT TGC",
            "D GAT GAC",
            "E GAA GAG",
            "F TTT TTC",
            "G GGT GGC GGA GGG",
            "H CAT CAC",
            "I ATT ATC ATA",
            "K AAA AAG",
            "L TTA TTG CTT CTC CTA CTG",
            "M ATG",
            "N AAT AAC",
            "P CCT CCC CCA CCG",
            "Q CAA CAG",
            "R CGT CGC CGA CGG AGA AGG",
            "S TCT TCC TCA TCG AGT AGC",
            "T ACT ACC ACA ACG",
            "V GTT GTC GTA GTG",
            "W TGG",
            "Y TAT TAC",
            "* TAA TAG TGA")
    for (group in groups) {
        val t = group.split(' ')
        for (codon in t.drop(1)) put(codon,t[0][0])
    }
}
private class Fault(reason: String) : RuntimeException(reason)
private fun error(condition: Boolean, reason: String) { if (condition) throw Fault(reason) }
private fun number(s: String, low: Int, high: Int): Int {
    error(!s.matches(Regex("-?[0-9]{1,6}")),"invalid number $s")
    return s.toInt().also { error(it !in low..high,"invalid number $s") }
}
private fun complement(s: String) = s.map { COMPLEMENTS[SYMBOLS.indexOf(it)] }.joinToString("")
private fun revcomp(s: String) = complement(s).reversed()
private fun complementBase(c: Char) = BASES[3-BASES.indexOf(c)]
private fun gc(s: String) = s.count { it == 'G' || it == 'C' }
private fun fixed(n: Int, divisor: Int, width: Int) = "${n/divisor}."+(n%divisor).toString().padStart(width,'0')
private fun pct(a: Int, b: Int) = fixed(10000*a/b,100,2)
private fun milli(n: Int) = fixed(n,1000,3)
private fun list(values: Collection<*>) = if (values.isEmpty()) "none" else values.joinToString(" ")
private fun codons(s: String, frame: Int): List<String> {
    val strand = if (frame > 0) s else revcomp(s)
    val result = mutableListOf<String>()
    var i = abs(frame)-1
    while (i+3 <= s.length) {
        result.add(strand.substring(i,i+3))
        i += 3
    }
    return result
}
private fun translation(codons: List<String>) = codons.map { genetic.getValue(it) }.joinToString("")
private fun wordCounts(words: List<String>) = words.groupingBy { it }.eachCount()
private fun frequency(counts: Map<String,Int>) = counts.keys.sortedWith(compareByDescending<String> { counts.getValue(it) }.thenBy { it })
private fun occurrences(s: String, motif: String): List<Int> {
    return (0..s.length-motif.length).filter { i ->
        motif.indices.all { j -> masks[SYMBOLS.indexOf(motif[j])] and (1 shl BASES.indexOf(s[i+j])) != 0 }
    }.map { it+1 }
}
private fun transition(a: Char, b: Char) = a != b && (a in "AG" && b in "AG" || a in "CT" && b in "CT")
private fun repeatCount(s: String, i: Int, u: Int): Int {
    val unit = s.substring(i,i+u)
    var count = 1
    while (i+(count+1)*u <= s.length && s.substring(i+count*u,i+(count+1)*u) == unit) count++
    return count
}
private fun primitive(s: String) = (1 until s.length).none { s.length%it == 0 && s.take(it).repeat(s.length/it) == s }
private fun selfcomp(s: String): Int {
    var maximum = 0
    for (center in 1 until s.length) {
        var left = center-1
        var right = center
        while (left >= 0 && right < s.length && complementBase(s[left]) == s[right]) {
            maximum = max(maximum,right-left+1)
            left--
            right++
        }
    }
    return maximum
}
private fun tm(s: String): Int {
    val n = s.length
    val g = gc(s)
    return if (n < 14) 10*(2*(n-g)+4*g) else (649*n+410*g-6724)/n
}
private fun mass(s: String) = s.sumOf { baseMass[BASES.indexOf(it)] }-(s.length-1)*18015
private fun overlap(a: String, b: String): Int {
    val joined = b+"#"+a
    val prefix = IntArray(joined.length)
    for (i in 1 until joined.length) {
        var j = prefix[i-1]
        while (j > 0 && joined[i] != joined[j]) j = prefix[j-1]
        if (joined[i] == joined[j]) j++
        prefix[i] = j
    }
    var result = prefix.last()
    val limit = min(a.length,b.length)
    while (result >= limit) result = prefix[result-1]
    return result
}
private data class Orf(val frame: Int, val left: Int, val right: Int, val protein: String)
private data class Repeat(val start: Int, val end: Int, val unitLength: Int, val unit: String, val count: Int)
private class Toolkit {
    val registry = sortedMapOf<String,String>()
    val schemas = mutableMapOf<String,List<String>>()
    val arities = mutableMapOf<String,IntRange>()
    var output = mutableListOf<String>()
    init {
        schema("SEQ",2,2,"NEW","SEQ")
        schema("SLICE",4,4,"NAME","POS","POS","NEW")
        schema("JOIN",3,9,"NEW","NAME")
        schema("MUTATE",3,3,"NAME","POS","BASE")
        for (c in listOf("DEL","REVCOMP","COMPLEMENT","REVERSE","TRANSCRIBE","GC","SKEW","TM","MASS","PRIMER","PACK")) schema(c,1,1,"NAME")
        schema("LIST",0,0)
        for (c in listOf("TRANSLATE","CODONS","PROTEIN")) schema(c,2,2,"NAME","FRAME")
        schema("ORFS",2,2,"NAME","1:200")
        schema("GCWINDOW",3,3,"NAME","1:500","1:500")
        schema("KMERS",3,3,"NAME","1:12","1:100")
        schema("FIND",2,2,"NAME","MOTIF")
        schema("RESTRICT",2,7,"NAME","ENZYME")
        schema("PALINDROMES",3,3,"NAME","2:20","2:20")
        schema("REPEATS",4,4,"NAME","1:6","1:6","2:50")
        schema("HAMMING",2,2,"NAME","NAME")
        schema("ALIGN",6,6,"NAME","NAME","MODE","1:20","-20:0","-20:-1")
        schema("CONSENSUS",2,10,"NAME")
        schema("FOLD",2,2,"NAME","0:10")
        schema("ASSEMBLE",4,10,"NEW","1:100","NAME")
        schema("UNPACK",3,3,"NEW","1:500","HEX")
    }
    fun schema(c: String, low: Int, high: Int, vararg args: String) {
        schemas[c] = args.toList()
        arities[c] = low..high
    }
    fun store(name: String, sequence: String) {
        error(sequence.length > 500,"too long")
        val replacing = name in registry
        registry[name] = sequence
        output.add((if (replacing) "replaced " else "stored ")+"$name ${sequence.length} nt")
    }
    fun validate(command: String, a: List<String>, nums: IntArray, sequences: Array<String>) {
        val schema = schemas[command] ?: throw Fault("unknown command $command")
        error(a.size !in arities.getValue(command),"wrong argument count")
        val seen = mutableSetOf<String>()
        for ((i,value) in a.withIndex()) {
            when (val kind = schema[min(i,schema.lastIndex)]) {
                "NAME" -> sequences[i] = registry[value] ?: throw Fault("unknown sequence $value")
                "NEW" -> error(!value.matches(Regex("[a-z][a-z0-9]{0,9}")),"invalid name $value")
                "SEQ" -> for ((j,c) in value.withIndex()) error(c !in BASES,"invalid base $c at ${j+1}")
                "BASE" -> error(value.length != 1 || value[0] !in BASES,"invalid base $value")
                "MOTIF" -> error(!value.matches(Regex("[ACGTRYSWKMBDHVN]{1,30}")),"invalid motif $value")
                "ENZYME" -> {
                    error(value !in enzymes,"unknown enzyme $value")
                    error(!seen.add(value),"duplicate enzyme $value")
                }
                "MODE" -> error(value != "GLOBAL" && value != "LOCAL","invalid mode $value")
                "HEX" -> error(value.length != 2*((nums[1]+3)/4) || !value.matches(Regex("[0-9A-F]+")),"invalid hex")
                "FRAME" -> {
                    nums[i] = number(value,-3,3)
                    error(nums[i] == 0,"invalid number $value")
                }
                "POS" -> nums[i] = number(value,1,sequences[0].length)
                else -> {
                    val bounds = kind.split(':')
                    nums[i] = number(value,bounds[0].toInt(),bounds[1].toInt())
                }
            }
        }
    }
    fun align(a: String, b: String, local: Boolean, match: Int, mismatch: Int, gap: Int) {
        val m = a.length
        val n = b.length
        val h = Array(m+1) { IntArray(n+1) }
        if (!local) {
            for (i in 0..m) h[i][0] = i*gap
            for (j in 0..n) h[0][j] = j*gap
        }
        var best = 0
        var bi = 0
        var bj = 0
        for (i in 1..m) {
            for (j in 1..n) {
                val value = max(h[i-1][j-1]+(if (a[i-1] == b[j-1]) match else mismatch),max(h[i-1][j]+gap,h[i][j-1]+gap))
                h[i][j] = if (local) max(0,value) else value
                if (local && h[i][j] > best) {
                    best = h[i][j]
                    bi = i
                    bj = j
                }
            }
        }
        if (!local) {
            bi = m
            bj = n
            best = h[m][n]
        }
        if (local && best == 0) {
            output.add("score 0")
            return
        }
        var i = bi
        var j = bj
        val x = StringBuilder()
        val y = StringBuilder()
        while (if (local) h[i][j] != 0 else i != 0 || j != 0) {
            if (i > 0 && j > 0 && h[i][j] == h[i-1][j-1]+(if (a[i-1] == b[j-1]) match else mismatch)) {
                x.append(a[--i])
                y.append(b[--j])
            } else if (i > 0 && h[i][j] == h[i-1][j]+gap) {
                x.append(a[--i])
                y.append('-')
            } else {
                x.append('-')
                y.append(b[--j])
            }
        }
        val left = x.reverse().toString()
        val right = y.reverse().toString()
        val middle = left.indices.map { k -> if (left[k] == '-' || right[k] == '-') '-' else if (left[k] == right[k]) '|' else '*' }.joinToString("")
        output.add("score $best a ${i+1}-$bi b ${j+1}-$bj identity ${middle.count { it == '|' }}/${left.length} gaps ${middle.count { it == '-' }}")
        output.add(left)
        output.add(middle)
        output.add(right)
    }
    fun pair(a: Char, b: Char) = complementBase(a) == b || a == 'G' && b == 'T' || a == 'T' && b == 'G'
    fun value(f: Array<IntArray>, i: Int, j: Int) = if (i > j) 0 else f[i][j]
    fun fold(s: String, loop: Int) {
        val n = s.length
        error(n > 100,"too long")
        val f = Array(n) { IntArray(n) }
        for (length in 1..n) {
            for (i in 0..n-length) {
                val j = i+length-1
                f[i][j] = value(f,i,j-1)
                for (k in i..j-loop-1) {
                    if (pair(s[k],s[j])) f[i][j] = max(f[i][j],value(f,i,k-1)+1+value(f,k+1,j-1))
                }
            }
        }
        val structure = CharArray(n) { '.' }
        val intervals = ArrayDeque<Pair<Int,Int>>()
        intervals.addLast(0 to n-1)
        while (intervals.isNotEmpty()) {
            val (i,j) = intervals.removeLast()
            if (value(f,i,j) == 0) continue
            if (f[i][j] == value(f,i,j-1)) intervals.addLast(i to j-1)
            else {
                for (k in i..j-loop-1) {
                    if (pair(s[k],s[j]) && value(f,i,k-1)+1+value(f,k+1,j-1) == f[i][j]) {
                        structure[k] = '('
                        structure[j] = ')'
                        intervals.addLast(i to k-1)
                        intervals.addLast(k+1 to j-1)
                        break
                    }
                }
            }
        }
        output.add(structure.concatToString())
        output.add("pairs ${f[0][n-1]}")
    }
    fun primer(s: String) {
        val n = s.length
        val g = gc(s)
        val temperature = tm(s)
        val clamp = gc(s.takeLast(5))
        var run = 1
        var bestRun = 1
        var repeats = 0
        for (i in 1 until n) {
            run = if (s[i] == s[i-1]) run+1 else 1
            bestRun = max(bestRun,run)
        }
        for (i in 0 until n-1) if (s[i] != s[i+1]) repeats = max(repeats,repeatCount(s,i,2))
        val self = selfcomp(s)
        val names = listOf("length","gc","tm","clamp","run","repeat","selfcomp")
        val values = listOf(n.toString(),pct(g,n),fixed(temperature,10,1),clamp.toString(),bestRun.toString(),repeats.toString(),self.toString())
        val ok = listOf(n in 18..25,40*n <= 100*g && 100*g <= 60*n,temperature in 520..620,clamp in 1..3,bestRun <= 4,repeats <= 4,self <= 6)
        val failed = mutableListOf<String>()
        for (i in 0..6) {
            output.add("${names[i]} ${values[i]} "+(if (ok[i]) "OK" else "FAIL"))
            if (!ok[i]) failed.add(names[i])
        }
        output.add(if (failed.isEmpty()) "PASS" else "FAIL "+list(failed))
    }
    fun assemble(name: String, minimum: Int, sequences: Array<String>) {
        val unique = sequences.drop(2).distinct()
        val fragments = unique.filter { s -> unique.none { it != s && it.contains(s) } }.toMutableList()
        while (fragments.size >= 2) {
            var best = -1
            var bx = 0
            var by = 0
            for (x in fragments.indices) {
                for (y in fragments.indices) {
                    if (x == y) continue
                    val a = fragments[x]
                    val b = fragments[y]
                    val overlap = overlap(a,b)
                    if (overlap > best) {
                        best = overlap
                        bx = x
                        by = y
                    }
                }
            }
            if (best < minimum) break
            val merged = fragments[bx]+fragments[by].drop(best)
            fragments[bx] = merged
            fragments.removeAt(by)
            var keep = bx-(if (by < bx) 1 else 0)
            for (i in fragments.lastIndex downTo 0) {
                if (i != keep && merged.contains(fragments[i])) {
                    fragments.removeAt(i)
                    if (i < keep) keep--
                }
            }
        }
        val longest = fragments.maxBy { it.length }
        error(longest.length > 500,"too long")
        output.add("contigs ${fragments.size}")
        for (s in fragments) output.add("${s.length} $s")
        store(name,longest)
    }
    fun execute(line: String) {
        val t = line.split(' ')
        val a = t.drop(1)
        val nums = IntArray(a.size)
        val sequences = Array(a.size) { "" }
        val command = t[0]
        validate(command,a,nums,sequences)
        val s = sequences.firstOrNull() ?: ""
        val n = s.length
        when (command) {
            "SEQ" -> store(a[0],a[1])
            "SLICE" -> {
                val part = s.substring(min(nums[1],nums[2])-1,max(nums[1],nums[2]))
                store(a[3],if (nums[1] <= nums[2]) part else revcomp(part))
            }
            "JOIN" -> store(a[0],sequences.drop(1).joinToString(""))
            "MUTATE" -> {
                val old = s[nums[1]-1]
                val next = a[2][0]
                error(old == next,"no change")
                registry[a[0]] = s.take(nums[1]-1)+next+s.drop(nums[1])
                output.add("${a[0]} $old${nums[1]}$next "+(if (transition(old,next)) "transition" else "transversion"))
            }
            "DEL" -> {
                registry.remove(a[0])
                output.add("deleted ${a[0]}")
            }
            "LIST" -> {
                if (registry.isEmpty()) output.add("no sequences")
                for ((name,sequence) in registry) output.add("$name ${sequence.length} nt")
            }
            "REVCOMP" -> output.add(revcomp(s))
            "COMPLEMENT" -> output.add(complement(s))
            "REVERSE" -> output.add(s.reversed())
            "TRANSCRIBE" -> output.add(s.replace('T','U'))
            "TRANSLATE" -> output.add(translation(codons(s,nums[1])).ifEmpty { "none" })
            "CODONS" -> {
                val counts = wordCounts(codons(s,nums[1]))
                if (counts.isEmpty()) output.add("none")
                for (c in frequency(counts)) output.add("$c ${genetic[c]} ${counts[c]}")
            }
            "PROTEIN" -> {
                val protein = translation(codons(s,nums[1])).substringBefore('*')
                error(protein.isEmpty(),"empty protein")
                val mass = 18015+protein.sumOf { residues[AMINO.indexOf(it)] }
                val charge = protein.count { it in "KR" }-protein.count { it in "DE" }
                val counts = wordCounts(protein.map { it.toString() })
                output.add(protein)
                output.add("length ${protein.length} mass ${milli(mass)} charge "+(if (charge > 0) "+" else "")+charge)
                output.add(frequency(counts).joinToString(" ") { "$it=${counts[it]}" })
            }
            "ORFS" -> {
                val found = mutableListOf<Orf>()
                for (frame in intArrayOf(1,2,3,-1,-2,-3)) {
                    val codons = codons(s,frame)
                    var start = -1
                    for (i in codons.indices) {
                        if (start < 0 && codons[i] == "ATG") start = i
                        else if (start >= 0 && genetic[codons[i]] == '*') {
                            if (i-start >= nums[1]) {
                                val left = abs(frame)-1+3*start
                                val right = abs(frame)-1+3*(i+1)-1
                                found.add(Orf(frame,if (frame > 0) left+1 else n-right,if (frame > 0) right+1 else n-left,translation(codons.subList(start,i))))
                            }
                            start = -1
                        }
                    }
                }
                if (found.isEmpty()) output.add("none")
                for (o in found.sortedBy { it.left }) output.add((if (o.frame > 0) "+" else "")+"${o.frame} ${o.left} ${o.right} ${o.protein.length} ${o.protein}")
            }
            "GC" -> output.add(BASES.map { "$it=${s.count { c -> c == it }}" }.joinToString(" ")+" GC=${pct(gc(s),n)}%")
            "GCWINDOW" -> {
                error(nums[1] > n,"window too large")
                for (i in 0..n-nums[1] step nums[2]) output.add("${i+1}-${i+nums[1]} ${pct(gc(s.substring(i,i+nums[1])),nums[1])}%")
            }
            "SKEW" -> {
                val skew = IntArray(n+1)
                for (i in 0 until n) skew[i+1] = skew[i]+(if (s[i] == 'G') 1 else if (s[i] == 'C') -1 else 0)
                val low = skew.minOrNull()!!
                val high = skew.maxOrNull()!!
                output.add("min $low at "+list(skew.indices.filter { skew[it] == low }))
                output.add("max $high at "+list(skew.indices.filter { skew[it] == high }))
            }
            "KMERS" -> {
                error(nums[1] > n,"k too large")
                val words = (0..n-nums[1]).map { s.substring(it,it+nums[1]) }
                val counts = wordCounts(words)
                output.add("${words.size} windows ${counts.size} distinct")
                for (word in frequency(counts).take(nums[2])) output.add("$word ${counts[word]}")
            }
            "FIND" -> {
                output.add("forward "+list(occurrences(s,a[1])))
                output.add("reverse "+list(occurrences(s,revcomp(a[1]))))
            }
            "RESTRICT" -> {
                val allCuts = sortedSetOf<Int>()
                for (enzyme in a.drop(1)) {
                    val e = enzymes.indexOf(enzyme)
                    val found = occurrences(s,sites[e]).map { it+cuts[e]-1 }.filter { it in 1 until n }
                    allCuts.addAll(found)
                    output.add("$enzyme "+list(found))
                }
                val ends = allCuts.toList()+n
                var previous = 0
                val fragments = mutableListOf<String>()
                val sizes = mutableListOf<Int>()
                for (end in ends) {
                    fragments.add("${previous+1}-$end")
                    sizes.add(end-previous)
                    previous = end
                }
                output.add("fragments "+list(fragments))
                output.add("sizes "+list(sizes.sortedDescending()))
            }
            "PALINDROMES" -> {
                error(nums[1] > nums[2],"invalid range")
                var count = 0
                for (i in 0 until n) {
                    for (length in nums[1]..min(nums[2],n-i)) {
                        val part = s.substring(i,i+length)
                        if (part == revcomp(part)) {
                            output.add("${i+1} $length $part")
                            count++
                        }
                    }
                }
                if (count == 0) output.add("none")
            }
            "REPEATS" -> {
                error(nums[1] > nums[2],"invalid range")
                val found = mutableListOf<Repeat>()
                for (u in nums[1]..nums[2]) {
                    var i = 0
                    while (i+u <= n) {
                        val unit = s.substring(i,i+u)
                        val count = repeatCount(s,i,u)
                        if (primitive(unit) && count >= nums[3]) {
                            found.add(Repeat(i+1,i+count*u,u,unit,count))
                            i += count*u
                        } else i++
                    }
                }
                if (found.isEmpty()) output.add("none")
                for (r in found.sortedWith(compareBy<Repeat> { it.start }.thenBy { it.unitLength })) output.add("${r.start}-${r.end} ${r.unit}x${r.count}")
            }
            "HAMMING" -> {
                val b = sequences[1]
                error(n != b.length,"length mismatch")
                val pairs = s.zip(b)
                val distance = pairs.count { (a,b) -> a != b }
                val transitions = pairs.count { (a,b) -> transition(a,b) }
                output.add("distance $distance transitions $transitions transversions ${distance-transitions}")
            }
            "ALIGN" -> align(s,sequences[1],a[2] == "LOCAL",nums[3],nums[4],nums[5])
            "CONSENSUS" -> {
                error(sequences.any { it.length != n },"length mismatch")
                val profile = Array(4) { IntArray(n) }
                val consensus = StringBuilder()
                val iupac = StringBuilder()
                for (i in 0 until n) {
                    for (sequence in sequences) profile[BASES.indexOf(sequence[i])][i]++
                    val maximum = (0..3).maxOf { profile[it][i] }
                    val winners = (0..3).filter { profile[it][i] == maximum }
                    consensus.append(BASES[winners[0]])
                    val mask = winners.sumOf { 1 shl it }
                    iupac.append(SYMBOLS[masks.indexOf(mask)])
                }
                for (b in 0..3) output.add("${BASES[b]} "+list(profile[b].toList()))
                output.add("consensus $consensus")
                output.add("iupac $iupac")
            }
            "TM" -> output.add("Tm ${fixed(tm(s),10,1)} "+(if (n < 14) "wallace" else "gc"))
            "MASS" -> output.add("ss ${milli(mass(s))} ds ${milli(mass(s)+mass(revcomp(s)))}")
            "PRIMER" -> primer(s)
            "FOLD" -> fold(s,nums[1])
            "ASSEMBLE" -> assemble(a[0],nums[1],sequences)
            "PACK" -> {
                val hex = StringBuilder()
                for (i in 0 until n step 4) {
                    var value = 0
                    for (j in 0..3) value = 4*value+(if (i+j < n) BASES.indexOf(s[i+j]) else 0)
                    hex.append(value.toString(16).uppercase().padStart(2,'0'))
                }
                output.add("$n $hex")
            }
            "UNPACK" -> {
                val decoded = StringBuilder()
                for (i in a[2].indices step 2) {
                    val value = a[2].substring(i,i+2).toInt(16)
                    for (shift in intArrayOf(6,4,2,0)) decoded.append(BASES[(value shr shift) and 3])
                }
                for (i in nums[1] until decoded.length) error(decoded[i] != 'A',"invalid padding")
                store(a[0],decoded.substring(0,nums[1]))
            }
        }
    }
    fun process(line: String): List<String> {
        output = mutableListOf()
        try { execute(line) }
        catch (f: Fault) {
            output.clear()
            output.add("ERROR ${f.message}")
        }
        return output
    }
}
fun main() {
    val input = System.`in`.bufferedReader()
    val output = System.out.bufferedWriter()
    val toolkit = Toolkit()
    repeat(input.readLine().toInt()) {
        for (line in toolkit.process(input.readLine())) {
            output.write(line)
            output.newLine()
        }
    }
    output.flush()
}
