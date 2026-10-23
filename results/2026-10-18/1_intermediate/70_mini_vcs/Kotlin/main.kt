private typealias Tree = Map<String, String>
private class Problem(val text: String) : RuntimeException(text)
private fun fail(reason: String): Nothing = throw Problem("error: $reason")
private data class Commit(val id: String, val parents: List<Int>, val tree: Tree, val message: String)
private data class Stash(val label: String, val base: Int, val tree: Tree)
private fun paths(vararg trees: Tree) = trees.flatMap {
    it.keys
}.toSortedSet()
private fun differences(a: Tree, b: Tree) = paths(a,b).filter {
    a[it] != b[it]
}.toSortedSet()
private fun matchPath(target: MutableMap<String,String>, source: Tree, path: String) {
    val value = source[path]
    if (value == null) target.remove(path) else target[path] = value
}
private fun changes(a: Tree, b: Tree): List<String> = differences(a,b).map {
    p -> when {
        p !in a -> "A $p: ${b[p]}"
        p !in b -> "D $p: ${a[p]}"
        else -> "M $p: ${a[p]} -> ${b[p]}"
    }
}.ifEmpty {
    listOf("(no changes)")
}
private fun threeWay(base: Tree, ours: Tree, theirs: Tree): Pair<Tree,Map<String,String>> {
    val merged = sortedMapOf<String,String>()
    val conflicts = sortedMapOf<String,String>()
    for (p in paths(base,ours,theirs)) {
        val b = base[p]
        val o = ours[p]
        val t = theirs[p]
        if (t == b || o == t) matchPath(merged,ours,p)
        else if (o == b) matchPath(merged,theirs,p)
        else {
            matchPath(merged,ours,p)
            conflicts[p] = "<<<<<<< ${o ?: "(deleted)"} ======= ${t ?: "(deleted)"} >>>>>>>"
        }
    }
    return merged to conflicts
}
private fun glob(pattern: String, path: String): Boolean {
    var previous = BooleanArray(path.length+1)
    previous[0] = true
    for (c in pattern) {
        val next = BooleanArray(path.length+1)
        if (c == '*') next[0] = previous[0]
        for (i in path.indices) next[i+1] = if (c == '*') previous[i+1] || next[i] else previous[i] && (c == '?' || c == path[i])
        previous = next
    }
    return previous[path.length]
}
private class Repository {
    val commits = mutableListOf<Commit?>()
    val branches = sortedMapOf<String,Int>()
    val tags = sortedMapOf<String,Int>()
    var head = 0
    var attached: String? = "main"
    val work = sortedMapOf<String,String>()
    var index = mutableMapOf<String,String>()
    val conflicts = sortedSetOf<String>()
    var pending: Pair<String,Int>? = null
    val stashes = mutableListOf<Stash>()
    val ignores = mutableListOf<String>()
    init {
        create(emptyList(),emptyMap(),"init")
        branches["main"] = 0
    }
    fun commit(i: Int) = commits[i]!!
    fun h() = commit(head).tree
    fun create(parents: List<Int>, tree: Tree, message: String): Int {
        val sequence = commits.size
        val text = buildString {
            append("commit $sequence\n")
            for (p in parents) append("parent ${commit(p).id}\n")
            for ((p,v) in tree.toSortedMap()) append("file $p $v\n")
            append("message $message\n")
        }
        var hash = 0L
        for (c in text) hash = (hash*131+c.code)%2147483647
        commits.add(Commit(hash.toString(16).padStart(8,'0'),parents.toList(),tree.toMap(),message))
        return sequence
    }
    fun moveHead(target: Int) {
        head = target
        attached?.let {
            branches[it] = target
        }
    }
    fun record(parents: List<Int>, tree: Tree, message: String): String {
        val old = commit(parents[0]).tree
        val counts = IntArray(3)
        for (p in differences(old,tree)) counts[if (p !in old) 0 else if (p !in tree) 2 else 1]++
        val target = create(parents,tree,message)
        moveHead(target)
        return "[${attached ?: "detached HEAD"} ${commit(target).id}] $message (${counts[0]} added, ${counts[1]} modified, ${counts[2]} deleted)"
    }
    fun resolve(revision: String): Int {
        val anchor = revision.substringBefore('~')
        val count = if ('~' in revision) revision.substringAfter('~').toInt() else 0
        var target: Int? = if (anchor == "HEAD") head else branches[anchor] ?: tags[anchor] ?: commits.indexOfFirst {
            it?.id == anchor
        }.takeIf {
            it >= 0
        }
        repeat(count) {
            target = target?.let {
                commit(it).parents.firstOrNull()
            }
        }
        return target ?: fail("unknown revision '$revision'")
    }
    fun distances(start: Int): Map<Int,Int> {
        val result = mutableMapOf(start to 0)
        val queue = ArrayDeque<Int>()
        queue.addLast(start)
        while (queue.isNotEmpty()) {
            val i = queue.removeFirst()
            for (p in commit(i).parents) if (p !in result) {
                result[p] = result.getValue(i)+1
                queue.addLast(p)
            }
        }
        return result
    }
    fun ancestor(a: Int, b: Int) = a in distances(b)
    fun mergeBase(x: Int, y: Int): Int {
        val a = distances(x)
        val b = distances(y)
        val common = a.keys.intersect(b.keys)
        return common.filter {
            z -> common.none {
                w -> z != w && ancestor(z,w)
            }
        }.minWith(compareBy<Int> {
            maxOf(a.getValue(it),b.getValue(it))
        }.thenByDescending {
            it
        })
    }
    fun inProgress() {
        pending?.let {
            fail("${it.first} in progress")
        }
    }
    fun uncommitted() = index != h() || index.keys.any {
        work[it] != index[it]
    }
    fun clean() {
        if (uncommitted()) fail("uncommitted changes")
    }
    fun overwrite(selected: Set<String>) {
        for (p in selected.sorted()) if (index[p] != h()[p] || work[p] != h()[p]) fail("local changes to '$p' would be overwritten")
    }
    fun switchTree(tree: Tree) {
        val changed = differences(h(),tree)
        overwrite(changed)
        for (p in changed) {
            matchPath(work,tree,p)
            matchPath(index,tree,p)
        }
    }
    fun ignored(p: String) = p !in index && p !in conflicts && ignores.any {
        glob(it,p)
    }
    fun summary(i: Int): String {
        val refs = mutableListOf<String>()
        if (head == i) refs.add(attached?.let {
            "HEAD -> $it"
        } ?: "HEAD")
        for ((b,target) in branches) if (target == i && attached != b) refs.add(b)
        for ((tag,target) in tags) if (target == i) refs.add("tag: $tag")
        return commit(i).id+(if (refs.isEmpty()) "" else " (${refs.joinToString(", ")})")+" "+commit(i).message
    }
    fun apply(base: Tree, theirs: Tree, kind: String, target: Int, message: String, parents: List<Int>, mergeBase: Int? = null): List<String> {
        val (merged,clashes) = threeWay(base,h(),theirs)
        overwrite(differences(h(),merged)+clashes.keys)
        val out = mutableListOf<String>()
        if (mergeBase != null) out.add("Merge base ${commit(mergeBase).id}")
        if (kind != "merge" && clashes.isEmpty() && merged == h()) return out+"nothing to commit"
        for (p in differences(h(),merged)) {
            matchPath(work,merged,p)
            matchPath(index,merged,p)
        }
        if (clashes.isEmpty()) out.add(record(parents,merged,message))
        else {
            for ((p,value) in clashes) {
                work[p] = value
                out.add("CONFLICT $p")
            }
            conflicts.clear()
            conflicts.addAll(clashes.keys)
            pending = kind to target
            out.add(if (kind == "merge") "Automatic merge failed; fix conflicts and then commit the result." else "error: could not ${if (kind == "revert") "revert" else "apply"} ${commit(target).id}")
        }
        return out
    }
    fun reachable(includeSaved: Boolean): Set<Int> {
        val starts = mutableListOf(head)
        starts.addAll(branches.values)
        starts.addAll(tags.values)
        if (includeSaved) {
            starts.addAll(stashes.map {
                it.base
            })
            pending?.let {
                starts.add(it.second)
            }
        }
        return starts.flatMap {
            distances(it).keys
        }.toSet()
    }
    fun command(line: String): List<String> {
        val words = line.split(' ')
        val c = words[0]
        val a = words.drop(1)
        val out = mutableListOf<String>()
        when(c) {
            "WRITE" -> work[a[0]] = line.split(' ',limit=3)[2]
            "REMOVE" -> if (work.remove(a[0]) == null) fail("no such file '${a[0]}'")
            "ADD" -> if (a[0] == "ALL") {
                val selected = paths(work,index).filter {
                    !ignored(it)
                }
                for (p in selected) matchPath(index,work,p)
                conflicts.clear()
            }
            else {
                val p = a[0]
                if (p in work && ignored(p)) fail("path '$p' is ignored")
                if (p !in work && p !in index && p !in conflicts) fail("pathspec '$p' did not match any files")
                matchPath(index,work,p)
                conflicts.remove(p)
            }
            "RM" -> {
                if (index.remove(a[0]) == null) fail("pathspec '${a[0]}' did not match any files")
                work.remove(a[0])
                conflicts.remove(a[0])
            }
            "UNSTAGE" -> {
                if (a[0] !in index && a[0] !in h()) fail("pathspec '${a[0]}' did not match any files")
                matchPath(index,h(),a[0])
            }
            "RESTORE" -> if (a.size == 1) {
                val value = index[a[0]] ?: fail("pathspec '${a[0]}' did not match any files")
                work[a[0]] = value
            }
            else {
                val target = resolve(a[1])
                val value = commit(target).tree[a[0]] ?: fail("path '${a[0]}' does not exist in '${a[1]}'")
                work[a[0]] = value
                index[a[0]] = value
                conflicts.remove(a[0])
            }
            "IGNORE" -> ignores.add(a[0])
            "COMMIT","AMEND" -> {
                val message = line.substringAfter(' ')
                val parents = if (c == "AMEND") {
                    inProgress()
                    if (commit(head).parents.isEmpty()) fail("cannot amend the root commit")
                    commit(head).parents
                }
                else {
                    if (conflicts.isNotEmpty()) fail("unresolved conflicts")
                    if (pending?.first == "merge") listOf(head,pending!!.second) else listOf(head)
                }
                if (c == "COMMIT" && parents.size != 2 && index == h()) out.add("nothing to commit") else {
                    out.add(record(parents,index,message))
                    pending = null
                }
            }
            "STATUS" -> {
                out.add(attached?.let {
                    "On branch $it"
                } ?: "HEAD detached at ${commit(head).id}")
                pending?.let {
                    (kind,i) -> out.add("${when(kind) { "merge" -> "Merging"; "revert" -> "Reverting"; else -> "Cherry-picking" }} ${commit(i).id}")
                }
                val start = out.size
                for (p in (paths(h(),index,work)+conflicts).sorted()) {
                    if (p in conflicts) out.add("UU $p")
                    else if (p in index) {
                        val x = if (p !in h()) 'A' else if (h()[p] != index[p]) 'M' else '.'
                        val y = if (p !in work) 'D' else if (work[p] != index[p]) 'M' else '.'
                        if (x != '.' || y != '.') out.add("$x$y $p")
                    }
                    else {
                        if (p in h()) out.add("D. $p")
                        if (p in work && !ignored(p)) out.add("?? $p")
                    }
                }
                if (out.size == start) out.add("nothing to commit, working tree clean")
            }
            "LS","CAT" -> {
                val revision = if (c == "LS") a.firstOrNull() else a.getOrNull(1)
                val tree = revision?.let {
                    commit(resolve(it)).tree
                } ?: work
                if (c == "CAT") out.add(tree[a[0]] ?: if (revision == null) fail("no such file '${a[0]}'") else fail("path '${a[0]}' does not exist in '$revision'"))
                else out.addAll(tree.toSortedMap().map {
                    (p,v) -> "$p $v"
                }.ifEmpty {
                    listOf("(empty)")
                })
            }
            "DIFF" -> out.addAll(if (a.isEmpty()) changes(index,work.filterKeys {
                it in index
            }) else if (a[0] == "STAGED") changes(h(),index) else {
                val x = resolve(a[0])
                val y = resolve(a[1])
                changes(commit(x).tree,commit(y).tree)
            })
            "LOG" -> {
                val limit = a.firstOrNull()?.toInt() ?: Int.MAX_VALUE
                var current = head
                var count = 0
                while (count < limit) {
                    out.add(summary(current))
                    count++
                    current = commit(current).parents.firstOrNull() ?: break
                }
            }
            "SHOW" -> {
                val target = resolve(a.firstOrNull() ?: "HEAD")
                val original = commit(target)
                out.add("commit ${summary(target)}")
                out.add("parents: ${original.parents.map { commit(it).id }.joinToString(" ").ifEmpty { "none" }}")
                out.addAll(changes(original.parents.firstOrNull()?.let {
                    commit(it).tree
                } ?: emptyMap(),original.tree))
            }
            "BLAME" -> {
                val value = h()[a[0]] ?: fail("path '${a[0]}' does not exist in 'HEAD'")
                var i = head
                while (commit(i).parents.isNotEmpty()) {
                    val p = commit(i).parents[0]
                    if (commit(p).tree[a[0]] != value) break
                    i = p
                }
                out.add("${commit(i).id} (${commit(i).message}) $value")
            }
            "BRANCH","TAG" -> {
                val branch = c == "BRANCH"
                val noun = if (branch) "branch" else "tag"
                val refs = if (branch) branches else tags
                if (a[0] == "-d") {
                    val name = a[1]
                    val target = refs[name] ?: fail("no such $noun '$name'")
                    if (branch && attached == name) fail("cannot delete current branch '$name'")
                    if (branch && !ancestor(target,head)) fail("branch '$name' is not fully merged")
                    refs.remove(name)
                    out.add("Deleted $noun $name (was ${commit(target).id})")
                }
                else {
                    val name = a[0]
                    if (name in refs) fail("$noun '$name' already exists")
                    val target = resolve(a.getOrNull(1) ?: "HEAD")
                    refs[name] = target
                    out.add("Created $noun $name at ${commit(target).id}")
                }
            }
            "BRANCHES" -> {
                if (attached == null) out.add("* (HEAD detached at ${commit(head).id})")
                for ((b,i) in branches) out.add("${if (attached == b) "*" else " "} $b ${commit(i).id} ${commit(i).message}")
            }
            "TAGS" -> out.addAll(tags.map {
                (tag,i) -> "$tag ${commit(i).id} ${commit(i).message}"
            }.ifEmpty {
                listOf("(no tags)")
            })
            "SWITCH" -> {
                val target = branches[a[0]] ?: fail("no such branch '${a[0]}'")
                if (attached == a[0]) out.add("Already on '${a[0]}'") else {
                    inProgress()
                    switchTree(commit(target).tree)
                    attached = a[0]
                    head = target
                    out.add("Switched to branch '${a[0]}'")
                }
            }
            "DETACH" -> {
                val target = resolve(a[0])
                inProgress()
                switchTree(commit(target).tree)
                attached = null
                head = target
                out.add("HEAD is now at ${commit(target).id} ${commit(target).message}")
            }
            "MERGE" -> {
                val target = resolve(a[0])
                inProgress()
                if (ancestor(target,head)) out.add("Already up to date") else if (ancestor(head,target)) {
                    val old = head
                    switchTree(commit(target).tree)
                    moveHead(target)
                    out.add("Fast-forward ${commit(old).id}..${commit(target).id}")
                } else {
                    clean()
                    val base = mergeBase(head,target)
                    out.addAll(apply(commit(base).tree,commit(target).tree,"merge",target,"Merge ${a[0]}",listOf(head,target),base))
                }
            }
            "MERGEBASE" -> {
                val x = resolve(a[0])
                val y = resolve(a[1])
                out.add(commit(mergeBase(x,y)).id)
            }
            "REBASE" -> {
                val target = resolve(a[0])
                inProgress()
                if (ancestor(target,head)) return listOf("Already up to date")
                clean()
                val list = mutableListOf<Int>()
                var current = head
                while (!ancestor(current,target)) {
                    list.add(current)
                    current = commit(current).parents[0]
                }
                list.reverse()
                var tree = commit(target).tree
                val planned = mutableListOf<Tree?>()
                for (i in list) {
                    val original = commit(i)
                    val (merged,clashes) = threeWay(commit(original.parents[0]).tree,tree,original.tree)
                    if (clashes.isNotEmpty()) fail("could not rebase ${original.id}: conflict in '${clashes.keys.first()}'")
                    if (merged == tree) planned.add(null) else {
                        planned.add(merged)
                        tree = merged
                    }
                }
                switchTree(tree)
                var parent = target
                for ((position,i) in list.withIndex()) {
                    val original = commit(i)
                    val picked = planned[position]
                    if (picked == null) out.add("skip ${original.id} ${original.message}") else {
                        val next = create(listOf(parent),picked,original.message)
                        out.add("pick ${original.id} -> ${commit(next).id} ${original.message}")
                        parent = next
                    }
                }
                moveHead(parent)
                out.add("HEAD is now at ${commit(parent).id} ${commit(parent).message}")
            }
            "RESET" -> {
                val target = resolve(a[1])
                val tree = commit(target).tree
                if (a[0] == "HARD") for (p in paths(index,tree)+conflicts) matchPath(work,tree,p)
                if (a[0] != "SOFT") index = tree.toMutableMap()
                moveHead(target)
                conflicts.clear()
                pending = null
                out.add("HEAD is now at ${commit(target).id} ${commit(target).message}")
            }
            "REVERT","CHERRYPICK" -> {
                val target = resolve(a[0])
                inProgress()
                clean()
                val original = commit(target)
                val parent = original.parents.firstOrNull()?.let {
                    commit(it).tree
                } ?: emptyMap()
                if (c == "REVERT") out.addAll(apply(original.tree,parent,"revert",target,"Revert \"${original.message}\"",listOf(head))) else out.addAll(apply(parent,original.tree,"cherry-pick",target,original.message,listOf(head)))
            }
            "STASH" -> {
                if (a.isEmpty()) {
                    inProgress()
                    if (!uncommitted()) out.add("No local changes to save") else {
                        val all = paths(index,h())
                        val saved = work.filterKeys {
                            it in all
                        }.toMap()
                        val tree = h()
                        for (p in all) matchPath(work,tree,p)
                        index = tree.toMutableMap()
                        val label = "WIP on ${attached ?: "(no branch)"}: ${commit(head).id} ${commit(head).message}"
                        stashes.add(0,Stash(label,head,saved))
                        out.add("Saved stash@{0}: $label")
                    }
                }
                else if (a[0] == "LIST") out.addAll(stashes.mapIndexed {
                    i,s -> "stash@{$i}: ${s.label}"
                }.ifEmpty {
                    listOf("(no stash entries)")
                })
                else {
                    val stash = stashes.firstOrNull() ?: fail("no stash entries")
                    if (a[0] == "DROP") {
                        stashes.removeAt(0)
                        out.add("Dropped stash@{0}: ${stash.label}")
                    } else {
                        inProgress()
                        clean()
                        val (merged,clashes) = threeWay(commit(stash.base).tree,h(),stash.tree)
                        if (clashes.isNotEmpty()) fail("stash conflict in '${clashes.keys.first()}'")
                        val changed = differences(h(),merged)
                        overwrite(changed)
                        for (p in changed) matchPath(work,merged,p)
                        stashes.removeAt(0)
                        out.add("Restored stash@{0}: ${stash.label}")
                        out.addAll(changes(h(),merged))
                    }
                }
            }
            "GRAPH" -> {
                val lanes = mutableListOf<Int>()
                for (i in reachable(false).sortedDescending()) {
                    if (i !in lanes) lanes.add(i)
                    val k = lanes.indexOf(i)
                    out.add(lanes.mapIndexed {
                        j,v -> if (j == k) "*" else if (v == i) "/" else "|"
                    }.joinToString(" ")+" "+summary(i))
                    for (j in lanes.lastIndex downTo k+1) if (lanes[j] == i) lanes.removeAt(j)
                    val parents = commit(i).parents
                    if (parents.isEmpty()) lanes.removeAt(k) else {
                        lanes[k] = parents[0]
                        if (parents.size == 2 && parents[1] !in lanes) lanes.add(k+1,parents[1])
                    }
                }
            }
            "DESCRIBE" -> {
                val target = resolve(a.firstOrNull() ?: "HEAD")
                val distance = distances(target)
                val choice = tags.mapNotNull {
                    (tag,i) -> distance[i]?.let {
                        it to tag
                    }
                }.minWithOrNull(compareBy<Pair<Int,String>> {
                    it.first
                }.thenBy {
                    it.second
                }) ?: fail("no tag can describe '${commit(target).id}'")
                out.add(if (choice.first == 0) choice.second else "${choice.second}-${choice.first}-g${commit(target).id}")
            }
            "GC" -> {
                val keep = reachable(true)
                var count = 0
                for (i in commits.indices) if (commits[i] != null && i !in keep) {
                    commits[i] = null
                    count++
                }
                out.add("Removed unreachable commits: $count")
            }
        }
        return out
    }
}
fun main() {
    val repository = Repository()
    while (true) {
        val line = readLine() ?: break
        if (line == "EXIT") break
        try {
            repository.command(line).forEach(::println)
        } catch (p: Problem) {
            println(p.text)
        }
    }
}
