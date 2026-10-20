import java.io.PrintWriter
import java.util.Locale
import java.util.TreeMap

private sealed class Node(val inode: Int, var modified: Int) {
    lateinit var parent: Directory
    var name = ""
    abstract val size: Long
    abstract val tag: Char
    open val links: Int get() = 1
}

private class Directory(inode: Int, modified: Int) : Node(inode, modified) {
    val entries = TreeMap<String, Node>()
    override val size: Long get() = entries.size.toLong()
    override val tag = 'd'
    override val links: Int get() = 2 + entries.values.count { it is Directory }
}

private class FileNode(inode: Int, modified: Int, lines: List<String> = emptyList()) : Node(inode, modified) {
    var lines = lines.toMutableList()
    override val size: Long get() = lines.sumOf { it.length.toLong() + 1 }
    override val tag = 'f'
}

private class Link(inode: Int, modified: Int, val target: String) : Node(inode, modified) {
    override val size: Long get() = target.length.toLong()
    override val tag = 'l'
}

private enum class Failure(val reason: String) {
    NONE(""), MISSING("No such file or directory"),
    NOT_DIRECTORY("Not a directory"), LOOP("Too many levels of symbolic links")
}

private data class Resolution(
    val node: Node? = null,
    val failure: Failure = Failure.NONE,
    val creationParent: Directory? = null,
    val creationName: String = ""
) {
    val absent: Boolean get() = creationParent != null
    val reason: String get() = failure.reason
}

private data class Options(val flags: Set<Char>, val paths: List<String>) {
    operator fun contains(flag: Char) = flag in flags
}
private data class Listed(val name: String, val node: Node)
private data class Input(val lines: List<String>, val name: String? = null)

private class Output(private val terminal: PrintWriter, private val direct: Boolean) {
    val lines = mutableListOf<String>()
    fun emit(line: String) {
        if (direct) terminal.print("$line\n") else lines.add(line)
    }
    fun print(format: String, vararg args: Any) = emit(String.format(Locale.ROOT, format, *args))
    fun error(format: String, vararg args: Any) { terminal.printf(Locale.ROOT, "$format\n", *args) }
}

private fun options(args: List<String>): Options {
    val flags = mutableSetOf<Char>()
    var at = 0
    while (at < args.size && args[at].startsWith('-')) {
        flags.addAll(args[at++].drop(1).toList())
    }
    return Options(flags, args.drop(at))
}
private fun lastComponent(path: String) = path.substringAfterLast('/')
private fun invalidSource(path: String) = lastComponent(path) in listOf("", ".", "..")
private fun joinPath(path: String, name: String) = if (path == "/") "/$name" else "$path/$name"

private class Shell {
    val root = Directory(1, 0).also { it.parent = it }
    var current = root
    var previous: String? = null
    var clock = 0
    var nextInode = 2

    fun absolute(node: Node): String {
        val names = mutableListOf<String>()
        var cursor = node
        while (cursor !== root) { names.add(cursor.name); cursor = cursor.parent }
        return "/" + names.asReversed().joinToString("/")
    }
    fun descendant(node: Node, ancestor: Node): Boolean {
        var cursor = node
        while (true) {
            if (cursor === ancestor) return true
            if (cursor === root) return false
            cursor = cursor.parent
        }
    }
    fun add(parent: Directory, name: String, node: Node) {
        parent.entries[name] = node
        parent.modified = clock
        node.parent = parent
        node.name = name
    }
    fun makeDirectory(parent: Directory, name: String): Directory = Directory(nextInode++, clock).also { add(parent, name, it) }
    fun makeFile(parent: Directory, name: String, lines: List<String> = emptyList()): FileNode =
        FileNode(nextInode++, clock, lines).also { add(parent, name, it) }
    fun detach(node: Node) {
        node.parent.entries.remove(node.name)
        node.parent.modified = clock
    }
    fun write(file: FileNode, lines: List<String>, append: Boolean = false) {
        if (append) file.lines.addAll(lines) else file.lines = lines.toMutableList()
        file.modified = clock
    }

    private inner class Resolver(val parents: Boolean) {
        var expansions = 0
        fun walk(path: String, base: Directory, follow: Boolean, original: Boolean): Resolution {
            var node: Node = if (path.startsWith('/')) root else base
            val parts = path.split('/')
            for ((i, part) in parts.withIndex()) {
                if (part.isEmpty()) continue
                val directory = node as? Directory ?: return Resolution(failure = Failure.NOT_DIRECTORY)
                if (part == ".") continue
                if (part == "..") { node = node.parent; continue }
                val last = i + 1 == parts.size
                var child = directory.entries[part]
                if (child == null) {
                    if (original && last) return Resolution(failure = Failure.MISSING, creationParent = directory, creationName = part)
                    if (original && parents) child = makeDirectory(directory, part)
                    else return Resolution(failure = Failure.MISSING)
                }
                if (child is Link && (!last || follow)) {
                    if (++expansions > 8) return Resolution(failure = Failure.LOOP)
                    val result = walk(child.target, directory, true, false)
                    child = result.node ?: return result
                }
                node = child
            }
            return Resolution(node)
        }
    }
    fun resolve(path: String, follow: Boolean = true, parents: Boolean = false): Resolution =
        Resolver(parents).walk(path, current, follow, true)

    fun cloneNode(source: Node, parent: Directory, name: String) {
        when (source) {
            is Directory -> {
                val copy = makeDirectory(parent, name)
                for (child in source.entries.values) cloneNode(child, copy, child.name)
            }
            is FileNode -> makeFile(parent, name, source.lines)
            is Link -> add(parent, name, Link(nextInode++, clock, source.target))
        }
    }
    fun move(sourcePath: String, destination: String, out: Output) {
        fun problem(path: String, reason: String) = out.error("mv: cannot move '%s' to '%s': %s", sourcePath, path, reason)
        if (invalidSource(sourcePath)) { problem(destination, "Invalid argument"); return }
        var result = resolve(sourcePath, false)
        val source = result.node
        if (source == null) { out.error("mv: cannot stat '%s': %s", sourcePath, result.reason); return }
        val parent: Directory
        val name: String
        val target: String
        val destinationNode = resolve(destination).node
        if (destinationNode is Directory) {
            parent = destinationNode
            name = lastComponent(sourcePath)
            target = joinPath(destination, name)
        } else {
            result = resolve(destination, false)
            val existing = result.node
            if (result.absent) { parent = result.creationParent!!; name = result.creationName }
            else if (existing != null) { parent = existing.parent; name = existing.name }
            else { problem(destination, result.reason); return }
            target = destination
        }
        val existing = parent.entries[name]
        when {
            source is Directory && descendant(parent, source) -> out.error("mv: cannot move '%s' to a subdirectory of itself, '%s'", sourcePath, target)
            existing === source -> out.error("mv: '%s' and '%s' are the same file", sourcePath, target)
            existing != null && source is Directory && existing !is Directory -> out.error("mv: cannot overwrite non-directory '%s' with directory '%s'", target, sourcePath)
            source !is Directory && existing is Directory -> out.error("mv: cannot overwrite directory '%s' with non-directory '%s'", target, sourcePath)
            existing is Directory && existing.entries.isNotEmpty() -> problem(target, "Directory not empty")
            existing === current -> problem(target, "Device or resource busy")
            else -> {
                if (existing != null) detach(existing)
                detach(source)
                add(parent, name, source)
            }
        }
    }
    fun copy(sourcePath: String, destination: String, recursive: Boolean, out: Output) {
        fun problem(path: String, reason: String) = out.error("cp: cannot copy '%s' to '%s': %s", sourcePath, path, reason)
        if (invalidSource(sourcePath)) { problem(destination, "Invalid argument"); return }
        var result = resolve(sourcePath)
        val source = result.node
        if (source == null) { out.error("cp: cannot stat '%s': %s", sourcePath, result.reason); return }
        if (source is Directory && !recursive) { out.error("cp: -r not specified; omitting directory '%s'", sourcePath); return }
        result = resolve(destination)
        if (result.node == null && !result.absent) { problem(destination, result.reason); return }
        val target = if (result.node is Directory) joinPath(destination, lastComponent(sourcePath)) else destination
        result = resolve(target, source !is Directory)
        val targetNode = result.node
        when {
            source is Directory -> {
                if (targetNode != null) problem(target, "File exists")
                else if (descendant(result.creationParent!!, source)) out.error("cp: cannot copy a directory, '%s', into itself, '%s'", sourcePath, target)
                else cloneNode(source, result.creationParent!!, result.creationName)
            }
            result.absent -> makeFile(result.creationParent!!, result.creationName, (source as FileNode).lines)
            targetNode === source -> out.error("cp: '%s' and '%s' are the same file", sourcePath, target)
            targetNode is Directory -> out.error("cp: cannot overwrite directory '%s' with non-directory '%s'", target, sourcePath)
            targetNode is FileNode -> write(targetNode, (source as FileNode).lines)
            else -> problem(target, result.reason)
        }
    }

    fun listing(options: Options, out: Output) {
        val paths = options.paths.ifEmpty { listOf(".") }
        for (path in paths) {
            val result = resolve(path, 'l' !in options)
            val node = result.node
            if (node == null) { out.error("ls: cannot access '%s': %s", path, result.reason); continue }
            val entries = mutableListOf<Listed>()
            if (node is Directory) {
                if (paths.size > 1) out.emit("$path:")
                if ('a' in options) { entries.add(Listed(".", node)); entries.add(Listed("..", node.parent)) }
                for (child in node.entries.values) if ('a' in options || !child.name.startsWith('.')) entries.add(Listed(child.name, child))
            } else entries.add(Listed(path, node))
            if ('t' in options) entries.sortByDescending { it.node.modified }
            if ('r' in options) entries.reverse()
            val widths = intArrayOf(1, 1, 1)
            for (entry in entries) {
                val numbers = longArrayOf(entry.node.links.toLong(), entry.node.size, entry.node.modified.toLong())
                for (i in 0..2) widths[i] = maxOf(widths[i], numbers[i].toString().length)
            }
            for (entry in entries) {
                if ('l' !in options) { out.emit(entry.name); continue }
                val item = entry.node
                val numbers = longArrayOf(item.links.toLong(), item.size, item.modified.toLong())
                val fields = numbers.mapIndexed { i, value -> value.toString().padStart(widths[i]) }.joinToString(" ")
                val suffix = if (item is Link) " -> ${item.target}" else ""
                out.emit("${if (item is FileNode) '-' else item.tag} $fields ${entry.name}$suffix")
            }
        }
    }
    fun walk(node: Node, path: String, depth: Int, limit: Int, visit: (Node, String, Int) -> Unit) {
        visit(node, path, depth)
        if (node is Directory && depth < limit) {
            for (child in node.entries.values) walk(child, joinPath(path, child.name), depth + 1, limit, visit)
        }
    }
    fun find(args: List<String>, out: Output) {
        val explicit = args.isNotEmpty() && !args.first().startsWith('-')
        val path = if (explicit) args.first() else "."
        val tests = mutableMapOf<String, String>()
        var at = if (explicit) 1 else 0
        while (at < args.size) { tests[args[at]] = args[at + 1]; at += 2 }
        val result = resolve(path)
        val node = result.node
        if (node == null) { out.error("find: '%s': %s", path, result.reason); return }
        walk(node, path, 0, tests["-maxdepth"]?.toInt() ?: 1000) { item, display, depth ->
            val name = if (depth == 0) { if (path == "/") "/" else lastComponent(path) } else item.name
            if ((tests["-name"]?.let { globMatch(it, name) } != false) &&
                (tests["-type"]?.first()?.let { it == item.tag } != false)) out.emit(display)
        }
    }
    fun usage(node: Node, path: String, show: Boolean, options: Options, out: Output): Long {
        var total = if (node is Directory) 0L else node.size
        if (node is Directory) for (child in node.entries.values) {
            total += usage(child, joinPath(path, child.name),
                show && 's' !in options && (child is Directory || 'a' in options), options, out)
        }
        if (show) out.print("%d %s", total, path)
        return total
    }
    fun diskUsage(options: Options, out: Output) {
        for (path in options.paths.ifEmpty { listOf(".") }) {
            val result = resolve(path)
            val node = result.node
            if (node == null) out.error("du: cannot access '%s': %s", path, result.reason)
            else usage(node, path, true, options, out)
        }
    }
    fun drawTree(directory: Directory, prefix: String, all: Boolean, counts: IntArray, out: Output) {
        val children = directory.entries.values.filter { all || !it.name.startsWith('.') }
        for ((i, child) in children.withIndex()) {
            val last = i + 1 == children.size
            out.emit(prefix + (if (last) "`-- " else "|-- ") + child.name + (if (child is Link) " -> ${child.target}" else ""))
            if (child is Directory) {
                counts[0]++
                drawTree(child, prefix + (if (last) "    " else "|   "), all, counts, out)
            } else counts[1]++
        }
    }
    fun tree(options: Options, out: Output) {
        val path = options.paths.firstOrNull() ?: "."
        val result = resolve(path)
        val node = result.node
        if (node == null) { out.error("tree: %s: %s", path, result.reason); return }
        if (node !is Directory) { out.error("tree: %s: Not a directory", path); return }
        out.emit(path)
        val counts = intArrayOf(0, 0)
        drawTree(node, "", 'a' in options, counts, out)
        out.print("%d %s, %d %s", counts[0], if (counts[0] == 1) "directory" else "directories",
            counts[1], if (counts[1] == 1) "file" else "files")
    }
    fun readInputs(command: String, paths: List<String>, input: List<String>, out: Output, consume: (Input) -> Unit) {
        if (paths.isEmpty()) { consume(Input(input)); return }
        for (path in paths) {
            val result = resolve(path)
            when (val node = result.node) {
                null -> out.error("%s: %s: %s", command, path, result.reason)
                is FileNode -> consume(Input(node.lines, path))
                else -> out.error("%s: %s: Is a directory", command, path)
            }
        }
    }
    fun textCommand(command: String, args: List<String>, input: List<String>, out: Output) {
        val options = options(args)
        when (command) {
            "grep" -> {
                val pattern = options.paths.first().let { if ('i' in options) it.lowercase(Locale.ROOT) else it }
                val paths = options.paths.drop(1)
                val named = 'r' in options || paths.size > 1
                val consume: (Input) -> Unit = { part ->
                    val prefix = if (named) "${part.name!!}:" else ""
                    var selected = 0L
                    for ((i, line) in part.lines.withIndex()) {
                        val comparison = if ('i' in options) line.lowercase(Locale.ROOT) else line
                        if (comparison.contains(pattern) != ('v' in options)) {
                            selected++
                            if ('c' !in options) out.emit(prefix + (if ('n' in options) "${i + 1}:" else "") + line)
                        }
                    }
                    if ('c' in options) out.emit("$prefix$selected")
                }
                if ('r' !in options) readInputs(command, paths, input, out, consume)
                else for (path in paths.ifEmpty { listOf(".") }) {
                    val result = resolve(path)
                    val node = result.node
                    if (node == null) out.error("grep: %s: %s", path, result.reason)
                    else walk(node, path, 0, 1000) { item, display, _ ->
                        if (item is FileNode) consume(Input(item.lines, display))
                    }
                }
            }
            "sort" -> {
                val lines = mutableListOf<String>()
                readInputs(command, options.paths, input, out) { lines.addAll(it.lines) }
                lines.sortWith { a, b ->
                    val comparison = if ('n' in options) numericPrefix(a).compareTo(numericPrefix(b)) else 0
                    if (comparison != 0) comparison else a.compareTo(b)
                }
                if ('r' in options) lines.reverse()
                lines.forEach(out::emit)
            }
            "wc" -> {
                val all = "lwc".none { it in options }
                val report: (LongArray, String?) -> Unit = { counts, name ->
                    val values = (0..2).filter { all || "lwc"[it] in options }.joinToString(" ") { counts[it].toString() }
                    out.emit(values + (if (name != null) " $name" else ""))
                }
                val totals = LongArray(3)
                readInputs(command, options.paths, input, out) { part ->
                    val counts = longArrayOf(part.lines.size.toLong(), 0, 0)
                    for (line in part.lines) {
                        counts[2] += line.length.toLong() + 1
                        var inside = false
                        for (character in line) {
                            if (character != ' ' && !inside) counts[1]++
                            inside = character != ' '
                        }
                    }
                    for (i in 0..2) totals[i] += counts[i]
                    report(counts, part.name)
                }
                if (options.paths.size > 1) report(totals, "total")
            }
            "head", "tail" -> {
                val explicit = args.firstOrNull() == "-n"
                val raw = if (explicit) args[1] else "10"
                val special = raw.startsWith('-') || raw.startsWith('+')
                val count = (if (special) raw.drop(1) else raw).toInt()
                readInputs(command, args.drop(if (explicit) 2 else 0), input, out) { part ->
                    var first = 0
                    var end = part.lines.size
                    if (command == "head") end = if (special) maxOf(0, end - count) else minOf(end, count)
                    else first = if (special) minOf(end, maxOf(0, count - 1)) else maxOf(0, end - count)
                    for (i in first until end) out.emit(part.lines[i])
                }
            }
            else -> readInputs(command, options.paths, input, out) { part ->
                if (command == "cat") part.lines.forEach(out::emit)
                else {
                    var first = 0
                    while (first < part.lines.size) {
                        var end = first + 1
                        while (end < part.lines.size && part.lines[first] == part.lines[end]) end++
                        out.emit((if ('c' in options) "${end - first} " else "") + part.lines[first])
                        first = end
                    }
                }
            }
        }
    }
    fun execute(text: String, input: List<String>, out: Output) {
        val words = text.split(' ')
        val command = words.first()
        val args = words.drop(1)
        val options = options(args)
        when (command) {
            "pwd" -> out.emit(absolute(current))
            "echo" -> out.emit(text.substring(5))
            "cd" -> {
                var path = args.firstOrNull() ?: "/"
                val back = path == "-"
                if (back) {
                    val old = previous
                    if (old == null) { out.error("cd: OLDPWD not set"); return }
                    path = old
                }
                val result = resolve(path)
                when (val node = result.node) {
                    null -> out.error("cd: %s: %s", path, result.reason)
                    is Directory -> {
                        previous = absolute(current)
                        current = node
                        if (back) out.emit(absolute(current))
                    }
                    else -> out.error("cd: %s: Not a directory", path)
                }
            }
            "mkdir" -> for (path in options.paths) {
                val result = resolve(path, false, 'p' in options)
                when {
                    result.absent -> makeDirectory(result.creationParent!!, result.creationName)
                    result.node == null -> out.error("mkdir: cannot create directory '%s': %s", path, result.reason)
                    'p' !in options || resolve(path).node !is Directory -> out.error("mkdir: cannot create directory '%s': File exists", path)
                }
            }
            "touch" -> for (path in args) {
                val result = resolve(path)
                when {
                    result.absent -> makeFile(result.creationParent!!, result.creationName)
                    result.node != null -> result.node.modified = clock
                    else -> out.error("touch: cannot touch '%s': %s", path, result.reason)
                }
            }
            "ls" -> listing(options, out)
            "stat" -> for (path in args) {
                val result = resolve(path, false)
                val node = result.node
                if (node == null) { out.error("stat: cannot stat '%s': %s", path, result.reason); continue }
                val kind = when (node) {
                    is Directory -> "directory"
                    is Link -> "symbolic link"
                    is FileNode -> if (node.lines.isEmpty()) "regular empty file" else "regular file"
                }
                out.print("%s: %s, size %d, inode %d, links %d, modified %d", path, kind, node.size, node.inode, node.links, node.modified)
            }
            "rm", "rmdir" -> {
                val directoryOnly = command == "rmdir"
                for (path in options.paths) {
                    val dot = lastComponent(path) in listOf(".", "..")
                    if (dot && !directoryOnly) {
                        out.error("rm: refusing to remove '.' or '..' directory: skipping '%s'", path)
                        continue
                    }
                    val problem = if (dot) "Invalid argument" else {
                        val result = resolve(path, false)
                        val node = result.node
                        when {
                            node == null -> {
                                if (!directoryOnly && 'f' in options && result.failure == Failure.MISSING) continue
                                result.reason
                            }
                            directoryOnly && node !is Directory -> "Not a directory"
                            !directoryOnly && node is Directory && 'r' !in options -> "Is a directory"
                            descendant(current, node) -> "Device or resource busy"
                            directoryOnly && (node as Directory).entries.isNotEmpty() -> "Directory not empty"
                            else -> { detach(node); "" }
                        }
                    }
                    if (problem.isNotEmpty()) out.error(if (directoryOnly) "rmdir: failed to remove '%s': %s" else "rm: cannot remove '%s': %s", path, problem)
                }
            }
            "mv", "cp" -> {
                val destination = options.paths.last()
                if (options.paths.size > 2 && resolve(destination).node !is Directory) {
                    out.error("%s: target '%s' is not a directory", command, destination)
                    return
                }
                for (source in options.paths.dropLast(1)) {
                    if (command == "mv") move(source, destination, out)
                    else copy(source, destination, 'r' in options, out)
                }
            }
            "ln" -> {
                val path = args[2]
                val result = resolve(path, false)
                if (result.absent) add(result.creationParent!!, result.creationName, Link(nextInode++, clock, args[1]))
                else out.error("ln: failed to create symbolic link '%s': %s", path, if (result.node == null) result.reason else "File exists")
            }
            "readlink", "realpath" -> {
                val path = args.first()
                val result = resolve(path, command == "realpath")
                val node = result.node
                when {
                    node == null -> out.error("%s: %s: %s", command, path, result.reason)
                    command == "realpath" -> out.emit(absolute(node))
                    node is Link -> out.emit(node.target)
                    else -> out.error("readlink: %s: Invalid argument", path)
                }
            }
            "find" -> find(args, out)
            "du" -> diskUsage(options, out)
            "tree" -> tree(options, out)
            "cat", "wc", "head", "tail", "grep", "sort", "uniq" -> textCommand(command, args, input, out)
            else -> out.error("%s: command not found", command)
        }
    }
    fun process(line: String, terminal: PrintWriter) {
        clock++
        terminal.print("${absolute(current)}\$ $line\n")
        var pipeline = line
        var redirect: FileNode? = null
        val marker = line.indexOf(" >")
        if (marker >= 0) {
            pipeline = line.substring(0, marker)
            val append = line.startsWith(" >> ", marker)
            val path = line.substring(marker + (if (append) 4 else 3))
            val result = resolve(path)
            val node = result.node
            if (result.absent) redirect = makeFile(result.creationParent!!, result.creationName)
            else if (node is FileNode) {
                redirect = node
                if (!append) write(node, emptyList())
            } else {
                terminal.print("sh: $path: ${if (node == null) result.reason else "Is a directory"}\n")
                return
            }
        }
        val commands = pipeline.split(" | ")
        var input: List<String> = emptyList()
        for ((i, command) in commands.withIndex()) {
            val out = Output(terminal, i + 1 == commands.size && redirect == null)
            execute(command, input, out)
            input = out.lines
        }
        if (redirect != null && input.isNotEmpty()) write(redirect, input, true)
    }
}

private fun globMatch(pattern: String, text: String): Boolean {
    var previous = BooleanArray(text.length + 1)
    previous[0] = true
    for (character in pattern) {
        val next = BooleanArray(previous.size)
        next[0] = character == '*' && previous[0]
        for (i in text.indices) next[i + 1] = if (character == '*') previous[i + 1] || next[i]
            else previous[i] && (character == '?' || character == text[i])
        previous = next
    }
    return previous[text.length]
}
private fun numericPrefix(text: String): Long {
    val negative = text.startsWith('-')
    var at = if (negative) 1 else 0
    var value = 0L
    while (at < text.length && text[at] in '0'..'9') value = value * 10 + (text[at++] - '0')
    return if (negative) -value else value
}

fun main() {
    val shell = Shell()
    val input = System.`in`.bufferedReader(Charsets.UTF_8)
    val output = PrintWriter(System.out.bufferedWriter(Charsets.UTF_8))
    while (true) {
        val line = input.readLine() ?: break
        if (line == "exit") break
        shell.process(line, output)
    }
    output.flush()
}
