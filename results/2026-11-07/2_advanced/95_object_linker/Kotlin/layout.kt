data class MergedPosition(val reference: Reference, val offset: Int, val merged: Int)
data class MergedData(val sections: Int, val strings: Int, val unique: Int, val saved: Int, val positions: List<MergedPosition>)
sealed interface ComponentKind {
    data class Input(val reference: Reference) : ComponentKind
    data class Merged(val data: MergedData) : ComponentKind
    data class Common(val name: String) : ComponentKind
    data class Veneer(val name: String) : ComponentKind
}
class Component(val kind: ComponentKind, val size: Int, val alignment: Int, val data: List<Int> = emptyList()) {
    var address = 0L
}
class OutputSection(val name: String) {
    var components: List<Component> = emptyList()
    var address = 0L
    var size = 0L
    var alignment = 1
}
class Segment(val name: String, val base: Long, val length: Long, val fill: Int, val outputs: List<Int>) {
    var memsz = 0L
    var filesz = 0L
    var paddr = 0L
    var used = 0L
    var image = mutableListOf<Int>()
}
fun mod(value: Long, divisor: Long): Long = Math.floorMod(value, divisor)
fun align(value: Long, alignment: Long): Long = value + mod(alignment - mod(value, alignment), alignment)
fun align(value: Long, alignment: Int): Long = align(value, alignment.toLong())
object Layout {
    fun output(name: String, outputs: List<OutputSection>): Int? = outputs.indexOfFirst {
        belongs(name, it.name)
    }.takeIf {
        it >= 0
    }
    fun assign(segment: Segment, outputs: List<OutputSection>) {
        var cursor = segment.base
        segment.filesz = 0
        for (i in segment.outputs) {
            val output = outputs[i]
            output.alignment = output.components.maxOfOrNull {
                it.alignment
            } ?: 1
            cursor = align(cursor, output.alignment)
            output.address = cursor
            for (component in output.components) {
                cursor = align(cursor, component.alignment)
                component.address = cursor
                cursor += component.size
            }
            output.size = cursor - output.address
            if (!nobits(output.name)) segment.filesz = cursor - segment.base
        }
        segment.memsz = cursor - segment.base
        segment.paddr = segment.base
        segment.used = segment.memsz
    }
}
