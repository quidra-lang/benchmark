import java.io.File
data class Reference(val objectIndex: Int, val index: Int)
class Section(val name: String, val alignment: Int, val size: Int) {
    val data = mutableListOf<Int>()
    var discard: String? = null
    var output: Int? = null
    var live = false
    var address = 0L
    val strings = mutableMapOf<Int, Long>()
}
sealed interface Definition {
    data class SectionDef(val section: Int, val offset: Int) : Definition
    data object Undefined : Definition
    data class Common(val size: Int, val alignment: Int) : Definition
}
class Symbol(var name: String, val binding: String, var definition: Definition)
data class Relocation(val section: Int, val offset: Int, val kind: String, val symbol: Int, val addend: Long)
class LinkObject(val name: String) {
    val sections = mutableListOf<Section>()
    val groups = mutableListOf<Pair<String, List<Int>>>()
    val symbols = mutableListOf<Symbol>()
    val relocations = mutableListOf<Relocation>()
}
fun belongs(name: String, output: String): Boolean = name == output || name.startsWith("$output.")
fun nobits(name: String): Boolean = belongs(name, ".bss")
fun stringSection(name: String): Boolean = belongs(name, ".rodata.str")
object ObjectParser {
    fun lines(name: String): List<String> = File("input/$name").readLines()
    fun parse(name: String, lines: List<String>): LinkObject {
        val objectFile = LinkObject(name)
        for (line in lines) {
            val f = line.split(' ')
            when (f[0]) {
                "section" -> objectFile.sections.add(Section(f[1], f[2].toInt(), f[3].toInt()))
                "data" -> for (i in f[1].indices step 2) objectFile.sections.last().data.add(f[1].substring(i, i + 2).toInt(16))
                "comdat" -> objectFile.groups.add(Pair(f[1], f.drop(2).map {
                    section -> objectFile.sections.indexOfFirst {
                        it.name == section
                    }
                }))
                "symbol" -> {
                    val definition = when (f[3]) {
                        "undef" -> Definition.Undefined
                        "common" -> Definition.Common(f[4].toInt(), f[5].toInt())
                        else -> Definition.SectionDef(objectFile.sections.indexOfFirst {
                            it.name == f[3]
                        }, f[4].toInt())
                    }
                    objectFile.symbols.add(Symbol(f[1], f[2], definition))
                }
                "reloc" -> objectFile.relocations.add(Relocation(objectFile.sections.indexOfFirst {
                    it.name == f[1]
                }, f[2].toInt(), f[3], objectFile.symbols.indexOfFirst {
                    it.name == f[4]
                }, f[5].toLong()))
            }
        }
        return objectFile
    }
}
