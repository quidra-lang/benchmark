import java.io.File
fun number(text: String): Long = if (text.startsWith("0x")) text.drop(2).toLong(16) else text.toLong()
fun hex(value: Long, width: Int = 8, uppercase: Boolean = false): String {
    val text = value.toString(16).padStart(width, '0')
    return if (uppercase) text.uppercase() else text
}
data class VeneerPair(val output: Int, val name: String)
sealed interface LiveUnit {
    data class SectionUnit(val reference: Reference) : LiveUnit
    data class Common(val name: String) : LiveUnit
}
data class Comdat(val signature: String, val keeper: String, val discarded: MutableList<String> = mutableListOf())
class Linker {
    var entry = ""
    var gc = true
    val segments = mutableListOf<Segment>()
    val outputs = mutableListOf<OutputSection>()
    val loads = mutableListOf<Pair<String, String>>()
    val keeps = mutableSetOf<String>()
    val sorts = mutableSetOf<String>()
    val wraps = mutableSetOf<String>()
    val defines = mutableListOf<Pair<String, String>>()
    var checksum: Pair<String, String>? = null
    val inputs = mutableListOf<List<String>>()
    val objects = mutableListOf<LinkObject>()
    val archives = mutableMapOf<String, Archive>()
    val entries = mutableMapOf<String, MutableList<Reference>>()
    val names = mutableMapOf<String, Resolution>()
    val comdats = mutableListOf<Comdat>()
    val extractions = mutableListOf<Triple<String, String, String>>()
    val veneers = mutableSetOf<VeneerPair>()
    init {
        for (line in ObjectParser.lines("link.txt")) {
            val f = line.split(' ')
            when (f[0]) {
                "entry" -> entry = f[1]
                "gc" -> gc = f[1] == "on"
                "segment" -> {
                    val indices = mutableListOf<Int>()
                    for (name in f.drop(5)) {
                        indices.add(outputs.size)
                        outputs.add(OutputSection(name))
                    }
                    segments.add(Segment(f[1], number(f[2]), number(f[3]), number(f[4]).toInt(), indices))
                }
                "load" -> loads.add(Pair(f[1], f[2]))
                "keep" -> keeps.add(f[1])
                "sort" -> sorts.add(f[1])
                "wrap" -> wraps.add(f[1])
                "define" -> {
                    val parts = line.split(" = ", limit = 2)
                    defines.add(Pair(parts[0].drop(7), parts[1]))
                }
                "checksum" -> checksum = Pair(f[1], f[2])
                else -> inputs.add(f)
            }
        }
    }
    fun undefined(name: String): Boolean {
        if (defines.any {
            it.first == name
        }) return false
        val references = entries[name].orEmpty()
        if (references.any {
            objects[it.objectIndex].symbols[it.index].definition != Definition.Undefined
        }) return false
        return name == entry || references.any {
            objects[it.objectIndex].symbols[it.index].binding == "global"
        }
    }
    fun load(objectFile: LinkObject) {
        for ((signature, sections) in objectFile.groups) {
            val old = comdats.firstOrNull {
                it.signature == signature
            }
            if (old != null) {
                for (s in sections) objectFile.sections[s].discard = "comdat"
                old.discarded.add(objectFile.name)
            } else comdats.add(Comdat(signature, objectFile.name))
        }
        for (symbol in objectFile.symbols) {
            val definition = symbol.definition
            if (symbol.binding != "local" && definition is Definition.SectionDef && objectFile.sections[definition.section].discard == "comdat") symbol.definition = Definition.Undefined
            if (symbol.definition == Definition.Undefined) {
                if (symbol.name in wraps) symbol.name = "__wrap_" + symbol.name else if (symbol.name.startsWith("__real_") && symbol.name.drop(7) in wraps) symbol.name = symbol.name.drop(7)
            }
        }
        val o = objects.size
        for ((i, symbol) in objectFile.symbols.withIndex()) if (symbol.binding != "local") entries.getOrPut(symbol.name) {
            mutableListOf()
        }.add(Reference(o, i))
        objects.add(objectFile)
    }
    fun scan(name: String): Boolean {
        val archive = archives.getOrPut(name) {
            Archive(name)
        }
        return archive.scan {
            member ->
            val reason = member.exports.firstOrNull {
                undefined(it)
            }
            if (reason == null) false else {
                val referrer = entries[reason].orEmpty().firstOrNull {
                    val symbol = objects[it.objectIndex].symbols[it.index]
                    symbol.definition == Definition.Undefined && symbol.binding == "global"
                }?.let {
                    objects[it.objectIndex].name
                } ?: "*entry*"
                extractions.add(Triple(member.objectFile.name, referrer, reason))
                load(member.objectFile)
                true
            }
        }
    }
    fun loadInputs() {
        for (f in inputs) {
            when (f[0]) {
                "object" -> load(ObjectParser.parse(f[1], ObjectParser.lines(f[1])))
                "library" -> scan(f[1])
                else -> {
                    while (true) {
                        var changed = false
                        for (name in f.drop(1)) if (scan(name)) changed = true
                        if (!changed) break
                    }
                }
            }
        }
        val scripts = defines.map {
            it.first
        }.toSet()
        for (name in (entries.keys + scripts).sorted()) names[name] = Resolver.resolve(objects, entries[name].orEmpty(), name in scripts)
        for (objectFile in objects) for (section in objectFile.sections) if (section.discard == null) {
            section.output = Layout.output(section.name, outputs)
            if (section.output == null) section.discard = "orphan"
        }
    }
    fun definitionUnit(name: String, resolution: Resolution): LiveUnit? {
        if (resolution.kind == "common") return LiveUnit.Common(name)
        val reference = resolution.definition ?: return null
        val definition = objects[reference.objectIndex].symbols[reference.index].definition
        return if (definition is Definition.SectionDef) LiveUnit.SectionUnit(Reference(reference.objectIndex, definition.section)) else null
    }
    fun target(objectIndex: Int, relocation: Relocation): LiveUnit? {
        val symbol = objects[objectIndex].symbols[relocation.symbol]
        val definition = symbol.definition
        if (symbol.binding == "local" && definition is Definition.SectionDef) return LiveUnit.SectionUnit(Reference(objectIndex, definition.section))
        return if (symbol.binding != "local") definitionUnit(symbol.name, names.getValue(symbol.name)) else null
    }
    fun collect() {
        val pending = mutableListOf<LiveUnit>()
        for ((o, objectFile) in objects.withIndex()) for ((s, section) in objectFile.sections.withIndex()) if (section.discard == null && (!gc || outputs[section.output!!].name in keeps)) pending.add(LiveUnit.SectionUnit(Reference(o, s)))
        if (!gc) {
            for (name in names.keys.sorted()) if (names.getValue(name).kind == "common") pending.add(LiveUnit.Common(name))
        }
        names[entry]?.let {
            definitionUnit(entry, it)
        }?.let {
            pending.add(it)
        }
        var i = 0
        while (i < pending.size) {
            when (val unit = pending[i++]) {
                is LiveUnit.Common -> names.getValue(unit.name).live = true
                is LiveUnit.SectionUnit -> {
                    val reference = unit.reference
                    val objectFile = objects[reference.objectIndex]
                    val section = objectFile.sections[reference.index]
                    if (section.live || section.discard != null) continue
                    section.live = true
                    for (relocation in objectFile.relocations) if (relocation.section == reference.index) target(reference.objectIndex, relocation)?.let {
                        pending.add(it)
                    }
                }
            }
        }
        for (objectFile in objects) for (section in objectFile.sections) if (section.discard == null && !section.live) section.discard = "gc"
        for (resolution in names.values) {
            val reference = resolution.definition ?: continue
            val definition = objects[reference.objectIndex].symbols[reference.index].definition
            if (definition is Definition.SectionDef) resolution.live = objects[reference.objectIndex].sections[definition.section].live
        }
    }
    fun merged(sections: List<Reference>): Component {
        val unique = mutableMapOf<List<Int>, Int>()
        val data = mutableListOf<Int>()
        val positions = mutableListOf<MergedPosition>()
        var strings = 0
        var total = 0
        for (reference in sections) {
            val section = objects[reference.objectIndex].sections[reference.index]
            total += section.size
            var start = 0
            for (end in section.data.indices) if (section.data[end] == 0) {
                val string = section.data.subList(start, end + 1).toList()
                val offset = unique.getOrPut(string) {
                    val offset = data.size
                    data.addAll(string)
                    offset
                }
                positions.add(MergedPosition(reference, start, offset))
                strings++
                start = end + 1
            }
        }
        return Component(ComponentKind.Merged(MergedData(sections.size, strings, unique.size, total - data.size, positions)), data.size, 1, data)
    }
    fun layout() {
        for ((index, output) in outputs.withIndex()) {
            var sections = objects.flatMapIndexed {
                o, objectFile -> objectFile.sections.mapIndexedNotNull {
                    s, section -> if (section.live && section.output == index) Reference(o, s) else null
                }
            }
            if (output.name in sorts) sections = sections.sortedBy {
                reference -> val name = objects[reference.objectIndex].sections[reference.index].name
                if (name == output.name) 65536 else name.drop(output.name.length + 1).toInt()
            }
            val strings = sections.filter {
                stringSection(objects[it.objectIndex].sections[it.index].name)
            }
            var emitted = false
            val components = mutableListOf<Component>()
            for (reference in sections) {
                val section = objects[reference.objectIndex].sections[reference.index]
                if (stringSection(section.name)) {
                    if (!emitted) {
                        components.add(merged(strings))
                        emitted = true
                    }
                } else components.add(Component(ComponentKind.Input(reference), section.size, section.alignment, section.data))
            }
            if (output.name == ".bss") {
                val commons = names.keys.filter {
                    names.getValue(it).kind == "common" && names.getValue(it).live
                }.sortedWith(compareByDescending<String> {
                    names.getValue(it).alignment
                }.thenBy {
                    it
                })
                for (name in commons) {
                    val resolution = names.getValue(name)
                    components.add(Component(ComponentKind.Common(name), resolution.size, resolution.alignment))
                }
            }
            for (pair in veneers.filter {
                it.output == index
            }.sortedBy {
                it.name
            }) components.add(Component(ComponentKind.Veneer(pair.name), 8, 4))
            output.components = components
        }
        for (segment in segments) Layout.assign(segment, outputs)
        for (output in outputs) for (component in output.components) {
            when (val kind = component.kind) {
                is ComponentKind.Input -> objects[kind.reference.objectIndex].sections[kind.reference.index].address = component.address
                is ComponentKind.Merged -> for (position in kind.data.positions) objects[position.reference.objectIndex].sections[position.reference.index].strings[position.offset] = component.address + position.merged
                is ComponentKind.Common -> names.getValue(kind.name).address = component.address
                is ComponentKind.Veneer -> Unit
            }
        }
        for (resolution in names.values) {
            val reference = resolution.definition ?: continue
            val definition = objects[reference.objectIndex].symbols[reference.index].definition
            if (definition is Definition.SectionDef) {
                val section = objects[reference.objectIndex].sections[definition.section]
                resolution.address = if (stringSection(section.name) && section.live) section.strings.getValue(definition.offset) else section.address + definition.offset
            }
        }
    }
    fun isFar(objectIndex: Int, relocation: Relocation): Boolean {
        val section = objects[objectIndex].sections[relocation.section]
        val symbol = objects[objectIndex].symbols[relocation.symbol]
        val resolution = names[symbol.name]
        return section.live && relocation.kind == "CALL24" && symbol.binding != "local" && resolution != null && resolution.kind in listOf("global", "weak") && !Relocator.fits("CALL24", resolution.address + relocation.addend - section.address - relocation.offset)
    }
    fun farPairs(): Set<VeneerPair> = objects.flatMapIndexed {
        o, objectFile -> objectFile.relocations.filter {
            isFar(o, it)
        }.map {
            VeneerPair(objectFile.sections[it.section].output!!, objectFile.symbols[it.symbol].name)
        }
    }.toSet()
    fun finishLayout() {
        while (true) {
            layout()
            val far = farPairs()
            if (veneers.containsAll(far)) break
            veneers.addAll(far)
        }
        val storage = segments.map {
            it.base + it.memsz
        }.toMutableList()
        for ((a, b) in loads) {
            val first = segments.indexOfFirst {
                it.name == a
            }
            val second = segments.indexOfFirst {
                it.name == b
            }
            segments[first].paddr = align(storage[second], 4)
            storage[second] = segments[first].paddr + segments[first].filesz
        }
        for ((i, segment) in segments.withIndex()) segment.used = storage[i] - segment.base
        val values = mutableMapOf<String, Long>()
        for ((name, expression) in defines) {
            val value = ScriptParser(expression, values, outputs, segments).expression()
            values[name] = value
            names.getValue(name).address = value
        }
    }
    fun symbolValue(objectIndex: Int, index: Int): Long? {
        val symbol = objects[objectIndex].symbols[index]
        val definition = symbol.definition
        if (symbol.binding == "local" && definition is Definition.SectionDef) {
            val section = objects[objectIndex].sections[definition.section]
            return if (stringSection(section.name)) section.strings.getValue(definition.offset) else section.address + definition.offset
        }
        val resolution = names.getValue(symbol.name)
        return if (resolution.kind == "undefined") null else resolution.address
    }
    fun diagnostics(): MutableList<String> {
        val lines = mutableListOf<String>()
        val orphans = objects.flatMap {
            it.sections
        }.filter {
            it.discard == "orphan"
        }.groupingBy {
            it.name
        }.eachCount()
        for (name in orphans.keys.sorted()) lines.add("warning: orphan section $name discarded from ${orphans.getValue(name)} object(s)")
        for (name in names.keys.sorted()) {
            val resolution = names.getValue(name)
            val definers = (if (resolution.kind == "script") listOf("*script*") else emptyList()) + resolution.strong.map {
                objects[it].name
            }
            if (definers.size >= 2) lines.add("error: multiple definition of $name: " + definers.joinToString(" "))
            if (resolution.common.isNotEmpty() && resolution.kind in listOf("global", "script")) lines.add("warning: common symbol $name overridden by ${resolution.definer}")
            if (resolution.kind == "common" && resolution.common.toSet().size >= 2) lines.add("warning: common symbol $name merged to size ${resolution.size} align ${resolution.alignment}")
        }
        if (names[entry] == null || names.getValue(entry).kind in listOf("undefined", "weakundef")) lines.add("error: entry symbol $entry is undefined")
        for (name in names.keys.sorted()) if (names.getValue(name).kind == "undefined") {
            val referrers = objects.filter {
                objectFile -> objectFile.relocations.any {
                    r -> objectFile.sections[r.section].live && objectFile.symbols[r.symbol].binding != "local" && objectFile.symbols[r.symbol].name == name
                }
            }.map {
                it.name
            }
            if (referrers.isNotEmpty()) lines.add("error: undefined symbol $name referenced by " + referrers.joinToString(" "))
        }
        for (segment in segments) if (segment.used > segment.length) lines.add("error: segment ${segment.name} overflows its length by ${segment.used - segment.length} bytes")
        for ((i, a) in segments.withIndex()) for (b in segments.drop(i + 1)) if (a.memsz > 0 && b.memsz > 0 && a.base < b.base + b.memsz && b.base < a.base + a.memsz) lines.add("error: segments ${a.name} and ${b.name} overlap")
        return lines
    }
    fun relocate(diagnostics: MutableList<String>): List<String> {
        val lines = mutableListOf<String>()
        val counts = Relocator.types.associateWith {
            IntArray(4)
        }
        val addresses = mutableMapOf<VeneerPair, Long>()
        val order = mutableListOf<Reference>()
        for ((i, output) in outputs.withIndex()) for (component in output.components) {
            when (val kind = component.kind) {
                is ComponentKind.Veneer -> addresses[VeneerPair(i, kind.name)] = component.address
                is ComponentKind.Input -> order.add(kind.reference)
                else -> Unit
            }
        }
        val gp = names["_gp"]?.address ?: 0L
        for (reference in order) {
            val o = reference.objectIndex
            val objectFile = objects[o]
            val section = objectFile.sections[reference.index]
            val relocations = objectFile.relocations.filter {
                it.section == reference.index
            }
            for ((index, relocation) in relocations.withIndex()) {
                val symbolName = objectFile.symbols[relocation.symbol].name
                val location = "${objectFile.name} ${section.name}+${relocation.offset}"
                val position = section.address + relocation.offset
                if (Relocator.unpaired(relocations, index)) diagnostics.add("error: unpaired HI16 at $location against $symbolName")
                var symbol = symbolValue(o, relocation.symbol)
                var status = "ok"
                if (isFar(o, relocation)) {
                    symbol = addresses.getValue(VeneerPair(section.output!!, symbolName))
                    status = "veneer"
                }
                if (symbol != null) {
                    val value = Relocator.value(relocation.kind, symbol, relocation.addend, position, gp)
                    val field = Relocator.field(relocation.kind, value)
                    val width = Relocator.width(relocation.kind)
                    if (!Relocator.fits(relocation.kind, value)) {
                        status = "overflow"
                        diagnostics.add("error: relocation overflow at $location: ${relocation.kind} value $value against $symbolName")
                    }
                    for ((i, byte) in Relocator.little(field, width).withIndex()) section.data[relocation.offset + i] = byte
                    lines.add("${hex(position)} ${objectFile.name} ${section.name}+${relocation.offset} ${relocation.kind} $symbolName ${relocation.addend} ${hex(symbol)} $value ${hex(field, width * 2)} $status")
                } else {
                    status = "undefined"
                    lines.add("${hex(position)} ${objectFile.name} ${section.name}+${relocation.offset} ${relocation.kind} $symbolName ${relocation.addend} - - - undefined")
                }
                counts.getValue(relocation.kind)[when (status) {
                    "ok" -> 0
                    "veneer" -> 1
                    "overflow" -> 2
                    else -> 3
                }]++
            }
        }
        for (kind in Relocator.types) {
            val c = counts.getValue(kind)
            lines.add("summary $kind total ${c.sum()} ok ${c[0]} veneer ${c[1]} overflow ${c[2]} undefined ${c[3]}")
        }
        return lines
    }
    fun images() {
        for (segment in segments) {
            val image = MutableList(segment.filesz.toInt()) {
                segment.fill
            }
            for (i in segment.outputs) if (!nobits(outputs[i].name)) for (component in outputs[i].components) {
                val data = when (val kind = component.kind) {
                    is ComponentKind.Input -> objects[kind.reference.objectIndex].sections[kind.reference.index].data
                    is ComponentKind.Veneer -> listOf(4, 240, 31, 229) + Relocator.little(names.getValue(kind.name).address, 4)
                    else -> component.data
                }
                val offset = (component.address - segment.base).toInt()
                for ((k, byte) in data.withIndex()) image[offset + k] = byte
            }
            segment.image = image
        }
        checksum?.let {
            (name, symbol) -> val segment = segments.first {
                it.name == name
            }
            val offset = (names.getValue(symbol).address - segment.base).toInt()
            for (k in 0..3) segment.image[offset + k] = 0
            var sum = 0L
            for ((i, byte) in segment.image.withIndex()) sum += byte.toLong() shl (8 * (i % 4))
            for ((i, byte) in Relocator.little(mod(-sum, 4294967296L), 4).withIndex()) segment.image[offset + i] = byte
        }
    }
    fun mapLines(): List<String> {
        val lines = extractions.map {
            "member ${it.first} ${it.second} ${it.third}"
        }.toMutableList()
        val symbols = mutableListOf<SymbolLine>()
        for (group in comdats) lines.add("comdat ${group.signature} ${group.keeper} ${if (group.discarded.isEmpty()) "-" else group.discarded.joinToString(",")}")
        for (segment in segments) {
            lines.add("segment ${segment.name} vaddr ${hex(segment.base)} paddr ${hex(segment.paddr)} filesz ${segment.filesz} memsz ${segment.memsz} used ${segment.used} length ${segment.length} ${100 * segment.used / segment.length}%")
            for (i in segment.outputs) {
                val output = outputs[i]
                lines.add("section ${output.name} ${hex(output.address)} ${output.size} ${output.alignment}")
                for (component in output.components) {
                    when (val kind = component.kind) {
                        is ComponentKind.Input -> lines.add("input ${hex(component.address)} ${component.size} ${component.alignment} ${objects[kind.reference.objectIndex].name} ${objects[kind.reference.objectIndex].sections[kind.reference.index].name}")
                        is ComponentKind.Merged -> lines.add("merged ${hex(component.address)} ${component.size} sections ${kind.data.sections} strings ${kind.data.strings} unique ${kind.data.unique} saved ${kind.data.saved}")
                        is ComponentKind.Common -> lines.add("common ${hex(component.address)} ${component.size} ${component.alignment} ${names.getValue(kind.name).definer} ${kind.name}")
                        is ComponentKind.Veneer -> {
                            lines.add("veneer ${hex(component.address)} 8 ${kind.name}")
                            symbols.add(SymbolLine(component.address, "__veneer_" + kind.name, "veneer", "*linker*"))
                        }
                    }
                }
            }
        }
        for (objectFile in objects) for (section in objectFile.sections) section.discard?.let {
            lines.add("discard ${objectFile.name} ${section.name} ${section.size} $it")
        }
        for (name in names.keys.sorted()) {
            val resolution = names.getValue(name)
            if (resolution.kind == "common" && !resolution.live) lines.add("discard ${resolution.definer} COMMON($name) ${resolution.size} gc")
            if (resolution.live && resolution.kind in listOf("global", "weak", "common", "script")) symbols.add(SymbolLine(resolution.address, name, resolution.kind, resolution.definer))
        }
        for (symbol in symbols.sortedWith(compareBy<SymbolLine> {
            it.address
        }.thenBy {
            it.name
        })) lines.add("symbol ${hex(symbol.address)} ${symbol.name} ${symbol.kind} ${symbol.definer}")
        return lines
    }
    fun xref(): List<String> = names.keys.sorted().map {
        name -> val r = names.getValue(name)
        val status = if (r.kind in listOf("undefined", "weakundef")) "-" else if (r.live) "kept" else "discarded"
        "$name ${r.kind} $status ${r.definer} ${if (r.referrers.isEmpty()) "-" else r.referrers.joinToString(",") { objects[it].name }}"
    }
    fun output(relocations: List<String>, diagnostics: MutableList<String>) {
        val resolution = names[entry]
        val address = if (resolution != null && resolution.kind in listOf("global", "weak", "common")) resolution.address else 0L
        val image = mutableListOf("entry ${hex(address)} $entry")
        for (segment in segments) {
            image.add("segment ${segment.name} vaddr ${hex(segment.base)} paddr ${hex(segment.paddr)} filesz ${segment.filesz} memsz ${segment.memsz}")
            for (k in segment.image.indices step 16) image.add(hex(segment.base + k) + " " + segment.image.subList(k, minOf(k + 16, segment.image.size)).joinToString(" ") {
                hex(it.toLong(), 2)
            })
        }
        val ihex = mutableListOf<String>()
        var upper = 0L
        for (segment in segments.withIndex().filter {
            it.value.filesz > 0
        }.sortedWith(compareBy<IndexedValue<Segment>> {
            it.value.paddr
        }.thenBy {
            it.index
        }).map {
            it.value
        }) {
            var k = 0
            while (k < segment.filesz) {
                val a = segment.paddr + k
                val n = minOf(16L, segment.filesz - k, 65536L - mod(a, 65536L)).toInt()
                if (a / 65536L != upper) {
                    upper = a / 65536L
                    ihex.add(record(0, 4, listOf((upper / 256).toInt(), (upper % 256).toInt())))
                }
                ihex.add(record(mod(a, 65536L).toInt(), 0, segment.image.subList(k, k + n)))
                k += n
            }
        }
        ihex.add(record(0, 5, listOf(24, 16, 8, 0).map {
            ((address ushr it) and 255L).toInt()
        }))
        ihex.add(record(0, 1, emptyList()))
        val errors = diagnostics.count {
            it.startsWith("error")
        }
        val warnings = diagnostics.count {
            it.startsWith("warning")
        }
        diagnostics.add("errors $errors warnings $warnings")
        write("image.hex", image)
        write("flash.ihex", ihex)
        write("link.map", mapLines())
        write("xref.txt", xref())
        write("relocations.txt", relocations)
        write("diagnostics.txt", diagnostics)
    }
    fun run() {
        loadInputs()
        collect()
        finishLayout()
        val diagnostics = diagnostics()
        val relocations = relocate(diagnostics)
        images()
        output(relocations, diagnostics)
    }
}
data class SymbolLine(val address: Long, val name: String, val kind: String, val definer: String)
class ScriptParser(expression: String, val values: Map<String, Long>, val outputs: List<OutputSection>, val segments: List<Segment>) {
    val tokens = mutableListOf<String>()
    var index = 0
    init {
        var i = 0
        while (i < expression.length) {
            if (expression[i] == ' ') {
                i++
                continue
            }
            val start = i
            if (expression[i] in "(),+-") {
                i++
            } else {
                while (i < expression.length && expression[i] != ' ' && expression[i] !in "(),+-") i++
            }
            tokens.add(expression.substring(start, i))
        }
    }
    val peek: String get() = tokens.getOrNull(index) ?: ""
    fun expression(): Long {
        var value = term()
        while (peek in listOf("+", "-")) {
            val op = tokens[index++]
            val right = term()
            value = if (op == "+") value + right else value - right
        }
        return value
    }
    fun term(): Long {
        val token = tokens[index++]
        if (token == "(") {
            val value = expression()
            index++
            return value
        }
        if (token[0] in '0'..'9') return number(token)
        if (peek != "(") return values.getValue(token)
        index++
        if (token == "align") {
            val value = expression()
            index++
            val alignment = expression()
            index++
            return align(value, alignment)
        }
        val name = tokens[index]
        index += 2
        val i = outputs.indexOfFirst {
            it.name == name
        }
        val output = outputs[i]
        return when (token) {
            "start" -> output.address
            "end" -> output.address + output.size
            "size" -> output.size
            else -> {
                val segment = segments.first {
                    i in it.outputs
                }
                segment.paddr + output.address - segment.base
            }
        }
    }
}
fun record(address: Int, type: Int, data: List<Int>): String {
    val bytes = (listOf(data.size, (address ushr 8) and 255, address and 255, type) + data).toMutableList()
    bytes.add(mod(-bytes.sum().toLong(), 256).toInt())
    return ":" + bytes.joinToString("") {
        hex(it.toLong(), 2, true)
    }
}
fun write(name: String, lines: List<String>) {
    File("output").mkdirs()
    File("output/$name").writeText(if (lines.isEmpty()) "" else lines.joinToString("\n") + "\n")
}
fun main() {
    Linker().run()
}
