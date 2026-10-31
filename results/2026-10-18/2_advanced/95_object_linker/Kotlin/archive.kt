class Member(val objectFile: LinkObject, val exports: List<String>) {
    var loaded = false
}
class Archive(name: String) {
    val members = mutableListOf<Member>()
    init {
        val lines = ObjectParser.lines(name)
        var i = 0
        while (i < lines.size) {
            val f = lines[i++].split(' ')
            val start = i
            while (lines[i] != "end") i++
            i++
            members.add(Member(ObjectParser.parse("$name(${f[1]})", lines.subList(start, i)), f.drop(2)))
        }
    }
    fun scan(extract: (Member) -> Boolean): Boolean {
        var any = false
        while (true) {
            var changed = false
            for (member in members) if (!member.loaded && extract(member)) {
                member.loaded = true
                changed = true
                any = true
            }
            if (!changed) return any
        }
    }
}
