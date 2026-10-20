module MemoryShell

abstract type Node end
mutable struct Directory <: Node
    inode::Int
    modified::Int
    parent::Directory
    name::String
    entries::Dict{String,Node}
    function Directory(inode::Int, modified::Int)
        node = new()
        node.inode, node.modified = inode, modified
        node.parent, node.name = node, ""
        node.entries = Dict{String,Node}()
        node
    end
end
mutable struct RegularFile <: Node
    inode::Int
    modified::Int
    parent::Directory
    name::String
    lines::Vector{String}
end
mutable struct SymbolicLink <: Node
    inode::Int
    modified::Int
    parent::Directory
    name::String
    target::String
end

mutable struct Shell
    root::Directory
    current::Directory
    previous::Union{Nothing,String}
    clock::Int
    next_inode::Int
end
function Shell()
    root = Directory(1, 0)
    Shell(root, root, nothing, 0, 2)
end
struct Resolution
    node::Union{Nothing,Node}
    reason::String
    parent::Union{Nothing,Directory}
    name::String
end
found(node::Node) = Resolution(node, "", nothing, "")
failure(reason::String) = Resolution(nothing, reason, nothing, "")
absent(parent::Directory, name::AbstractString) = Resolution(nothing, "No such file or directory", parent, String(name))
struct Options
    flags::Set{Char}
    paths::Vector{String}
end
struct Output
    direct::Bool
    lines::Vector{String}
end
Output(direct::Bool) = Output(direct, String[])
function emit!(output::Output, line::AbstractString)
    if output.direct
        println(line)
    else
        push!(output.lines, String(line))
    end
end

tag(::Directory) = "d"
tag(::RegularFile) = "f"
tag(::SymbolicLink) = "l"
node_size(node::Directory) = length(node.entries)
node_size(node::RegularFile) = sum(line -> ncodeunits(line) + 1, node.lines; init=0)
node_size(node::SymbolicLink) = ncodeunits(node.target)
link_count(::Node) = 1
link_count(node::Directory) = 2 + count(child -> child isa Directory, values(node.entries))
children(node::Directory) = Node[node.entries[name] for name in sort!(collect(keys(node.entries)))]
last_component(path::AbstractString) = String(last(split(path, '/'; keepempty=true)))
invalid_source(path::AbstractString) = last_component(path) in ("", ".", "..")
join_path(path::AbstractString, name::AbstractString) = path == "/" ? "/$name" : "$path/$name"
function absolute(shell::Shell, node::Node)
    names = String[]
    while node !== shell.root
        push!(names, node.name)
        node = node.parent
    end
    "/" * join(reverse!(names), '/')
end
function descendant(node::Node, ancestor::Node)
    while true
        node === ancestor && return true
        node.parent === node && return false
        node = node.parent
    end
end
function options(arguments::Vector{String})
    flags = Set{Char}()
    at = 1
    while at <= length(arguments) && startswith(arguments[at], "-")
        union!(flags, arguments[at][2:end])
        at += 1
    end
    Options(flags, arguments[at:end])
end
function attach!(shell::Shell, parent::Directory, name::AbstractString, node::Node)
    parent.entries[String(name)] = node
    parent.modified = shell.clock
    node.parent, node.name = parent, String(name)
    node
end
function add_new!(shell::Shell, parent::Directory, name::AbstractString, node::Node)
    shell.next_inode += 1
    attach!(shell, parent, name, node)
end
create_directory!(shell::Shell, parent::Directory, name::AbstractString) =
    add_new!(shell, parent, name, Directory(shell.next_inode, shell.clock))
create_file!(shell::Shell, parent::Directory, name::AbstractString, lines::Vector{String}=String[]) =
    add_new!(shell, parent, name, RegularFile(shell.next_inode, shell.clock, parent, String(name), copy(lines)))
create_link!(shell::Shell, parent::Directory, name::AbstractString, target::AbstractString) =
    add_new!(shell, parent, name, SymbolicLink(shell.next_inode, shell.clock, parent, String(name), String(target)))
function detach!(shell::Shell, node::Node)
    delete!(node.parent.entries, node.name)
    node.parent.modified = shell.clock
end
function write_file!(shell::Shell, node::RegularFile, lines::Vector{String}; append::Bool=false)
    node.lines = append ? vcat(node.lines, lines) : copy(lines)
    node.modified = shell.clock
end

function resolve(shell::Shell, path::AbstractString; follow::Bool=true, parents::Bool=false)
    expansions = 0
    function walk(text::AbstractString, base::Directory, follow_final::Bool, original::Bool)
        node = startswith(text, "/") ? shell.root : base
        parts = split(text, '/'; keepempty=false)
        for (index, part) in enumerate(parts)
            node isa Directory || return failure("Not a directory")
            part == "." && continue
            if part == ".."
                node = node.parent
                continue
            end
            final = index == length(parts)
            child = get(node.entries, part, nothing)
            if child === nothing
                original && final && return absent(node, part)
                original && parents || return failure("No such file or directory")
                child = create_directory!(shell, node, part)
            end
            if child isa SymbolicLink && (!final || follow_final)
                expansions += 1
                expansions > 8 && return failure("Too many levels of symbolic links")
                result = walk(child.target, node, true, false)
                result.node === nothing && return result
                child = result.node
            end
            node = child
        end
        found(node)
    end
    walk(path, shell.current, follow, true)
end
function clone_node!(shell::Shell, source::Node, parent::Directory, name::AbstractString)
    if source isa Directory
        copied = create_directory!(shell, parent, name)
        for child in children(source)
            clone_node!(shell, child, copied, child.name)
        end
    elseif source isa RegularFile
        create_file!(shell, parent, name, source.lines)
    else
        create_link!(shell, parent, name, source.target)
    end
end
function move_one!(shell::Shell, path::String, destination::String)
    problem(target, reason) = println("mv: cannot move '$path' to '$target': $reason")
    invalid_source(path) && return problem(destination, "Invalid argument")
    result = resolve(shell, path; follow=false)
    source = result.node
    source === nothing && return println("mv: cannot stat '$path': $(result.reason)")
    destination_node = resolve(shell, destination).node
    if destination_node isa Directory
        parent, name = destination_node, last_component(path)
        target = join_path(destination, name)
    else
        result = resolve(shell, destination; follow=false)
        if result.parent !== nothing
            parent, name = result.parent, result.name
        elseif result.node !== nothing
            parent, name = result.node.parent, result.node.name
        else
            return problem(destination, result.reason)
        end
        target = destination
    end
    existing = get(parent.entries, name, nothing)
    if source isa Directory && descendant(parent, source)
        println("mv: cannot move '$path' to a subdirectory of itself, '$target'")
    elseif existing === source
        println("mv: '$path' and '$target' are the same file")
    elseif existing !== nothing && source isa Directory && !(existing isa Directory)
        println("mv: cannot overwrite non-directory '$target' with directory '$path'")
    elseif !(source isa Directory) && existing isa Directory
        println("mv: cannot overwrite directory '$target' with non-directory '$path'")
    elseif existing isa Directory && !isempty(existing.entries)
        problem(target, "Directory not empty")
    elseif existing === shell.current
        problem(target, "Device or resource busy")
    else
        existing !== nothing && detach!(shell, existing)
        detach!(shell, source)
        attach!(shell, parent, name, source)
    end
end
function copy_one!(shell::Shell, path::String, destination::String, recursive::Bool)
    problem(target, reason) = println("cp: cannot copy '$path' to '$target': $reason")
    invalid_source(path) && return problem(destination, "Invalid argument")
    result = resolve(shell, path)
    source = result.node
    source === nothing && return println("cp: cannot stat '$path': $(result.reason)")
    source isa Directory && !recursive && return println("cp: -r not specified; omitting directory '$path'")
    result = resolve(shell, destination)
    result.node === nothing && result.parent === nothing && return problem(destination, result.reason)
    target = result.node isa Directory ? join_path(destination, last_component(path)) : destination
    result = resolve(shell, target; follow=!(source isa Directory))
    if source isa Directory
        if result.node !== nothing
            problem(target, "File exists")
        elseif descendant(result.parent, source)
            println("cp: cannot copy a directory, '$path', into itself, '$target'")
        else
            clone_node!(shell, source, result.parent, result.name)
        end
    elseif result.parent !== nothing
        create_file!(shell, result.parent, result.name, source.lines)
    elseif result.node === source
        println("cp: '$path' and '$target' are the same file")
    elseif result.node isa Directory
        println("cp: cannot overwrite directory '$target' with non-directory '$path'")
    elseif result.node isa RegularFile
        write_file!(shell, result.node, source.lines)
    else
        problem(target, result.reason)
    end
end

function listing(shell::Shell, opts::Options, output::Output)
    paths = isempty(opts.paths) ? ["."] : opts.paths
    for path in paths
        result = resolve(shell, path; follow=!('l' in opts.flags))
        node = result.node
        if node === nothing
            println("ls: cannot access '$path': $(result.reason)")
            continue
        end
        entries = Tuple{String,Node}[]
        if node isa Directory
            length(paths) > 1 && emit!(output, "$path:")
            if 'a' in opts.flags
                push!(entries, (".", node), ("..", node.parent))
            end
            for child in children(node)
                ('a' in opts.flags || !startswith(child.name, ".")) && push!(entries, (child.name, child))
            end
        else
            push!(entries, (path, node))
        end
        't' in opts.flags && sort!(entries; by=entry -> -entry[2].modified)
        'r' in opts.flags && reverse!(entries)
        widths = [1, 1, 1]
        for (_, child) in entries
            widths = max.(widths, ndigits.([link_count(child), node_size(child), child.modified]))
        end
        for (name, child) in entries
            if 'l' in opts.flags
                numbers = [link_count(child), node_size(child), child.modified]
                columns = join([lpad(string(numbers[i]), widths[i]) for i in 1:3], ' ')
                kind = child isa RegularFile ? "-" : tag(child)
                suffix = child isa SymbolicLink ? " -> $(child.target)" : ""
                emit!(output, "$kind $columns $name$suffix")
            else
                emit!(output, name)
            end
        end
    end
end
function walk_nodes(visit::Function, node::Node, path::AbstractString, depth::Int=0, limit::Int=1000)
    visit(node, path, depth)
    if node isa Directory && depth < limit
        for child in children(node)
            walk_nodes(visit, child, join_path(path, child.name), depth + 1, limit)
        end
    end
end
function glob_match(pattern::String, text::String)
    previous = falses(ncodeunits(text) + 1)
    previous[1] = true
    for character in codeunits(pattern)
        following = falses(length(previous))
        following[1] = character == UInt8('*') && previous[1]
        for (i, byte) in enumerate(codeunits(text))
            following[i + 1] = character == UInt8('*') ? previous[i + 1] || following[i] :
                previous[i] && (character == UInt8('?') || character == byte)
        end
        previous = following
    end
    previous[end]
end
function find_nodes(shell::Shell, arguments::Vector{String}, output::Output)
    explicit = !isempty(arguments) && !startswith(arguments[1], "-")
    path = explicit ? arguments[1] : "."
    start = explicit ? 2 : 1
    tests = Dict{String,String}(arguments[i] => arguments[i + 1] for i in start:2:length(arguments))
    result = resolve(shell, path)
    result.node === nothing && return println("find: '$path': $(result.reason)")
    limit = parse(Int, get(tests, "-maxdepth", "1000"))
    walk_nodes(result.node, path, 0, limit) do node, display, depth
        name = depth == 0 ? (path == "/" ? "/" : last_component(path)) : node.name
        if (!haskey(tests, "-name") || glob_match(tests["-name"], name)) &&
           (!haskey(tests, "-type") || tests["-type"] == tag(node))
            emit!(output, display)
        end
    end
end
function usage(node::Node, path::AbstractString, show::Bool, opts::Options, output::Output)
    total = node isa Directory ? 0 : node_size(node)
    if node isa Directory
        for child in children(node)
            visible = show && !('s' in opts.flags) && (child isa Directory || 'a' in opts.flags)
            total += usage(child, join_path(path, child.name), visible, opts, output)
        end
    end
    show && emit!(output, "$total $path")
    total
end
function disk_usage(shell::Shell, opts::Options, output::Output)
    for path in (isempty(opts.paths) ? ["."] : opts.paths)
        result = resolve(shell, path)
        if result.node === nothing
            println("du: cannot access '$path': $(result.reason)")
        else
            usage(result.node, path, true, opts, output)
        end
    end
end
function draw_tree(node::Directory, prefix::String, all::Bool, output::Output)
    selected = filter(child -> all || !startswith(child.name, "."), children(node))
    directories, files = 0, 0
    for (i, child) in enumerate(selected)
        last = i == length(selected)
        suffix = child isa SymbolicLink ? " -> $(child.target)" : ""
        emit!(output, prefix * (last ? "`-- " : "|-- ") * child.name * suffix)
        if child isa Directory
            d, f = draw_tree(child, prefix * (last ? "    " : "|   "), all, output)
            directories += 1 + d
            files += f
        else
            files += 1
        end
    end
    directories, files
end
function tree(shell::Shell, opts::Options, output::Output)
    path = isempty(opts.paths) ? "." : opts.paths[1]
    result = resolve(shell, path)
    result.node === nothing && return println("tree: $path: $(result.reason)")
    result.node isa Directory || return println("tree: $path: Not a directory")
    emit!(output, path)
    directories, files = draw_tree(result.node, "", 'a' in opts.flags, output)
    emit!(output, "$directories $(directories == 1 ? "directory" : "directories"), $files $(files == 1 ? "file" : "files")")
end

function read_inputs(consume::Function, shell::Shell, command::String, paths::Vector{String}, input::Vector{String})
    if isempty(paths)
        consume(input, nothing)
        return
    end
    for path in paths
        result = resolve(shell, path)
        if result.node === nothing
            println("$command: $path: $(result.reason)")
        elseif result.node isa Directory
            println("$command: $path: Is a directory")
        else
            consume(result.node.lines, path)
        end
    end
end
function numeric_prefix(text::String)
    matched = match(r"^-?[0-9]+", text)
    matched === nothing ? 0 : parse(Int, matched.match)
end
function word_count(text::String)
    total, inside = 0, false
    for byte in codeunits(text)
        byte != 0x20 && !inside && (total += 1)
        inside = byte != 0x20
    end
    total
end
function text_command(shell::Shell, command::String, arguments::Vector{String}, input::Vector{String}, output::Output)
    opts = options(arguments)
    if command == "grep"
        insensitive = 'i' in opts.flags
        pattern = insensitive ? lowercase(opts.paths[1]) : opts.paths[1]
        paths = opts.paths[2:end]
        named = 'r' in opts.flags || length(paths) > 1
        function consume(lines, name)
            prefix = named ? "$name:" : ""
            selected = 0
            for (i, line) in enumerate(lines)
                compared = insensitive ? lowercase(line) : line
                occursin(pattern, compared) == ('v' in opts.flags) && continue
                selected += 1
                if !('c' in opts.flags)
                    emit!(output, prefix * ('n' in opts.flags ? "$i:" : "") * line)
                end
            end
            'c' in opts.flags && emit!(output, prefix * string(selected))
        end
        if !('r' in opts.flags)
            read_inputs(consume, shell, command, paths, input)
        else
            for path in (isempty(paths) ? ["."] : paths)
                result = resolve(shell, path)
                if result.node === nothing
                    println("grep: $path: $(result.reason)")
                else
                    walk_nodes(result.node, path) do node, display, _
                        node isa RegularFile && consume(node.lines, display)
                    end
                end
            end
        end
    elseif command == "sort"
        lines = String[]
        read_inputs(shell, command, opts.paths, input) do part, _
            append!(lines, part)
        end
        if 'n' in opts.flags
            sort!(lines; by=line -> (numeric_prefix(line), line))
        else
            sort!(lines)
        end
        'r' in opts.flags && reverse!(lines)
        foreach(line -> emit!(output, line), lines)
    elseif command == "wc"
        all = !any(flag -> flag in opts.flags, "lwc")
        function report(counts, name)
            fields = [string(counts[i]) for i in 1:3 if all || "lwc"[i] in opts.flags]
            emit!(output, join(fields, ' ') * (name === nothing ? "" : " $name"))
        end
        totals = zeros(Int, 3)
        read_inputs(shell, command, opts.paths, input) do lines, name
            counts = [length(lines), sum(word_count, lines; init=0), sum(line -> ncodeunits(line) + 1, lines; init=0)]
            totals .+= counts
            report(counts, name)
        end
        length(opts.paths) > 1 && report(totals, "total")
    elseif command in ("head", "tail")
        explicit = !isempty(arguments) && arguments[1] == "-n"
        raw = explicit ? arguments[2] : "10"
        special = startswith(raw, "-") || startswith(raw, "+")
        amount = parse(Int, special ? raw[2:end] : raw)
        paths = arguments[(explicit ? 3 : 1):end]
        read_inputs(shell, command, paths, input) do lines, _
            start, stop = 1, length(lines)
            if command == "head"
                stop = special ? max(0, stop - amount) : min(stop, amount)
            else
                start = special ? min(stop + 1, max(1, amount)) : max(1, stop - amount + 1)
            end
            for i in start:stop
                emit!(output, lines[i])
            end
        end
    else
        read_inputs(shell, command, opts.paths, input) do lines, _
            if command == "cat"
                foreach(line -> emit!(output, line), lines)
                return
            end
            start = 1
            while start <= length(lines)
                stop = start + 1
                while stop <= length(lines) && lines[stop] == lines[start]
                    stop += 1
                end
                emit!(output, ('c' in opts.flags ? "$(stop - start) " : "") * lines[start])
                start = stop
            end
        end
    end
end

function execute!(shell::Shell, text::AbstractString, input::Vector{String}, output::Output)
    words = String.(split(text))
    command, arguments = words[1], words[2:end]
    opts = options(arguments)
    if command == "pwd"
        emit!(output, absolute(shell, shell.current))
    elseif command == "echo"
        emit!(output, text[6:end])
    elseif command == "cd"
        path = isempty(arguments) ? "/" : arguments[1]
        back = path == "-"
        if back
            shell.previous === nothing && return println("cd: OLDPWD not set")
            path = shell.previous
        end
        result = resolve(shell, path)
        if result.node === nothing
            println("cd: $path: $(result.reason)")
        elseif !(result.node isa Directory)
            println("cd: $path: Not a directory")
        else
            shell.previous = absolute(shell, shell.current)
            shell.current = result.node
            back && emit!(output, absolute(shell, shell.current))
        end
    elseif command == "mkdir"
        for path in opts.paths
            result = resolve(shell, path; follow=false, parents='p' in opts.flags)
            if result.parent !== nothing
                create_directory!(shell, result.parent, result.name)
            elseif result.node === nothing
                println("mkdir: cannot create directory '$path': $(result.reason)")
            elseif !('p' in opts.flags) || !(resolve(shell, path).node isa Directory)
                println("mkdir: cannot create directory '$path': File exists")
            end
        end
    elseif command == "touch"
        for path in arguments
            result = resolve(shell, path)
            if result.parent !== nothing
                create_file!(shell, result.parent, result.name)
            elseif result.node !== nothing
                result.node.modified = shell.clock
            else
                println("touch: cannot touch '$path': $(result.reason)")
            end
        end
    elseif command == "ls"
        listing(shell, opts, output)
    elseif command == "stat"
        for path in arguments
            result = resolve(shell, path; follow=false)
            node = result.node
            if node === nothing
                println("stat: cannot stat '$path': $(result.reason)")
                continue
            end
            kind = node isa Directory ? "directory" : node isa SymbolicLink ? "symbolic link" :
                isempty(node.lines) ? "regular empty file" : "regular file"
            emit!(output, "$path: $kind, size $(node_size(node)), inode $(node.inode), links $(link_count(node)), modified $(node.modified)")
        end
    elseif command in ("rm", "rmdir")
        directory_only = command == "rmdir"
        for path in opts.paths
            dot = last_component(path) in (".", "..")
            if dot && !directory_only
                println("rm: refusing to remove '.' or '..' directory: skipping '$path'")
                continue
            end
            reason = ""
            if dot
                reason = "Invalid argument"
            else
                result = resolve(shell, path; follow=false)
                node = result.node
                if node === nothing
                    !directory_only && 'f' in opts.flags && result.reason == "No such file or directory" && continue
                    reason = result.reason
                elseif directory_only && !(node isa Directory)
                    reason = "Not a directory"
                elseif !directory_only && node isa Directory && !('r' in opts.flags)
                    reason = "Is a directory"
                elseif descendant(shell.current, node)
                    reason = "Device or resource busy"
                elseif directory_only && !isempty(node.entries)
                    reason = "Directory not empty"
                else
                    detach!(shell, node)
                end
            end
            if !isempty(reason)
                println(directory_only ? "rmdir: failed to remove '$path': $reason" : "rm: cannot remove '$path': $reason")
            end
        end
    elseif command in ("mv", "cp")
        destination = opts.paths[end]
        if length(opts.paths) > 2 && !(resolve(shell, destination).node isa Directory)
            return println("$command: target '$destination' is not a directory")
        end
        for path in opts.paths[1:end-1]
            if command == "mv"
                move_one!(shell, path, destination)
            else
                copy_one!(shell, path, destination, 'r' in opts.flags)
            end
        end
    elseif command == "ln"
        path = arguments[3]
        result = resolve(shell, path; follow=false)
        if result.parent !== nothing
            create_link!(shell, result.parent, result.name, arguments[2])
        else
            reason = result.node === nothing ? result.reason : "File exists"
            println("ln: failed to create symbolic link '$path': $reason")
        end
    elseif command in ("readlink", "realpath")
        path = arguments[1]
        result = resolve(shell, path; follow=command == "realpath")
        if result.node === nothing
            println("$command: $path: $(result.reason)")
        elseif command == "realpath"
            emit!(output, absolute(shell, result.node))
        elseif result.node isa SymbolicLink
            emit!(output, result.node.target)
        else
            println("readlink: $path: Invalid argument")
        end
    elseif command == "find"
        find_nodes(shell, arguments, output)
    elseif command == "du"
        disk_usage(shell, opts, output)
    elseif command == "tree"
        tree(shell, opts, output)
    elseif command in ("cat", "wc", "head", "tail", "grep", "sort", "uniq")
        text_command(shell, command, arguments, input, output)
    else
        println("$command: command not found")
    end
end
function process_line!(shell::Shell, line::String)
    shell.clock += 1
    println(absolute(shell, shell.current), "\$ ", line)
    pipeline = line
    redirect = nothing
    marker = findfirst(" >", line)
    if marker !== nothing
        position = first(marker)
        pipeline = line[1:position-1]
        append = startswith(line[position:end], " >> ")
        path = line[position + (append ? 4 : 3):end]
        result = resolve(shell, path)
        if result.parent !== nothing
            redirect = create_file!(shell, result.parent, result.name)
        elseif result.node isa RegularFile
            redirect = result.node
            !append && write_file!(shell, redirect, String[])
        else
            reason = result.node === nothing ? result.reason : "Is a directory"
            return println("sh: $path: $reason")
        end
    end
    commands = split(pipeline, " | ")
    input = String[]
    for (index, text) in enumerate(commands)
        output = Output(redirect === nothing && index == length(commands))
        execute!(shell, text, input, output)
        input = output.lines
    end
    redirect !== nothing && !isempty(input) && write_file!(shell, redirect, input; append=true)
end
function main()
    shell = Shell()
    for line in eachline()
        line == "exit" && break
        process_line!(shell, line)
    end
end
main()

end
