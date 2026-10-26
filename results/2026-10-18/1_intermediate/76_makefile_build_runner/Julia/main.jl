struct MakeError <: Exception
    message::String
end
struct BuildAborted <: Exception end
fail(s) = throw(MakeError(s))
words(s) = String.(split(s, ' '; keepempty = false))
function trimleft(s)
    i=1
    while i<=length(s) && s[i]==' '
        i+=1
    end
    String(s[i:end])
end
function trimright(s)
    i=length(s)
    while i>0 && s[i]==' '
        i-=1
    end
    String(s[1:i])
end
trimspaces(s) = trimright(trimleft(s))
numerictext(s) = !isempty(s) && all(c->'0'<=c<='9', s)
function closingindex(text, start)
    opening=text[start]
    closing=opening=='(' ? ')' : '}'
    depth=0
    for i in start:length(text)
        if text[i]==opening
            depth+=1
        elseif text[i]==closing
            depth-=1
            depth==0 && return i
        end
    end
    0
end
function outsideindex(text, wanted)
    found=0
    i=1
    while i<=length(text)
        if text[i]!='$'
            text[i]==wanted && found==0 && (found=i)
            i+=1
        elseif i<length(text) && text[i+1] in ('(', '{')
            last=closingindex(text, i+1)
            last==0 && fail("unterminated variable reference")
            i=last+1
        else
            i+=2
        end
    end
    found
end
function patternstem(pattern, word)
    at=findfirst(==('%'), pattern)
    at===nothing && return pattern==word ? "" : nothing
    first=pattern[1:(at-1)]
    last=pattern[(at+1):end]
    length(word)>=length(first)+length(last) && startswith(word, first) && endswith(word, last) ?
    String(word[(length(first)+1):(end-length(last))]) : nothing
end
substitute(text, stem) = replace(text, "%"=>stem; count = 1)
function replaceword(word, pattern, replacement)
    stem=patternstem(pattern, word)
    stem===nothing ? word : occursin('%', pattern) ? substitute(replacement, stem) : replacement
end
function splitarguments(text, opening, limit)
    closing=opening=='(' ? ')' : '}'
    depth=0
    start=1
    result=String[]
    for i in eachindex(text)
        if text[i]==opening
            depth+=1
        elseif text[i]==closing
            depth-=1
        elseif text[i]==',' && depth==0 && (limit==0 || length(result)<limit-1)
            push!(result, String(text[start:(i-1)]))
            start=i+1
        end
    end
    push!(result, String(text[start:end]))
    result
end
function globmatches(pattern, name)
    previous=falses(length(name)+1)
    previous[1]=true
    for token in pattern
        next=falses(length(name)+1)
        if token=='*'
            next[1]=previous[1]
            for i in eachindex(name)
                next[i+1]=previous[i+1] || (name[i]!='/' && next[i])
            end
        else
            for i in eachindex(name)
                next[i+1]=previous[i] && (token==name[i] || (token=='?' && name[i]!='/'))
            end
        end
        previous=next
    end
    last(previous)
end
const FUNCTIONS=Dict(
    "subst"=>(3, 3),
    "patsubst"=>(3, 3),
    "strip"=>(1, 1),
    "findstring"=>(2, 2),
    "filter"=>(2, 2),
    "filter-out"=>(2, 2),
    "sort"=>(1, 1),
    "word"=>(2, 2),
    "wordlist"=>(3, 3),
    "words"=>(1, 1),
    "firstword"=>(1, 1),
    "lastword"=>(1, 1),
    "dir"=>(1, 1),
    "notdir"=>(1, 1),
    "suffix"=>(1, 1),
    "basename"=>(1, 1),
    "addsuffix"=>(2, 2),
    "addprefix"=>(2, 2),
    "wildcard"=>(1, 1),
    "foreach"=>(3, 3),
    "if"=>(2, 3),
    "call"=>(1, 0),
    "value"=>(1, 1),
    "info"=>(1, 1),
    "warning"=>(1, 1),
    "error"=>(1, 1),
)
mutable struct Variable
    recursive::Bool
    value::String
end
struct RecipeLine
    number::Int
    command::String
end
mutable struct Rule
    prerequisites::Vector{String}
    recipe::Union{Nothing,Vector{RecipeLine}}
    stem::String
end
Rule() = Rule(String[], nothing, "")
mutable struct PatternRule
    target::String
    prerequisites::Vector{String}
    recipe::Union{Nothing,Vector{RecipeLine}}
end
mutable struct Makefile
    loaded::Bool
    variables::Dict{String,Variable}
    rules::Dict{String,Rule}
    patterns::Vector{PatternRule}
    phony::Set{String}
    goal::String
end
Makefile() =
    Makefile(false, Dict{String,Variable}(), Dict{String,Rule}(), PatternRule[], Set{String}(), "")
mutable struct RuleGroup
    targets::Vector{String}
    patterns::Vector{PatternRule}
    recipe::Union{Nothing,Vector{RecipeLine}}
end
RuleGroup() = RuleGroup(String[], PatternRule[], nothing)
mutable struct MakeCondition
    outer::Bool
    value::Bool
    seenelse::Bool
    number::Int
end
struct ExpansionScope
    name::Union{Nothing,String}
    values::Vector{String}
end
mutable struct Simulator
    files::Dict{String,Int}
    clock::Int
    makefile::Makefile
    scopes::Vector{ExpansionScope}
    expanding::Set{String}
    automatic::Dict{String,String}
    location::String
end
Simulator(files) = Simulator(
    files,
    maximum(values(files); init = 0),
    Makefile(),
    ExpansionScope[],
    Set{String}(),
    Dict{String,String}(),
    "make",
)
function touch!(s, name)
    s.clock+=1
    s.files[name]=s.clock
end
function wildcard(s, pattern)
    if occursin('*', pattern) || occursin('?', pattern)
        return [name for name in sort!(collect(keys(s.files))) if globmatches(pattern, name)]
    end
    haskey(s.files, pattern) ? [pattern] : String[]
end
function expand(s, text)
    result=IOBuffer()
    i=1
    while i<=length(text)
        if text[i]!='$'
            print(result, text[i])
            i+=1
        elseif i==length(text)
            break
        elseif text[i+1]=='$'
            print(result, '$')
            i+=2
        elseif text[i+1] in ('(', '{')
            last=closingindex(text, i+1)
            last==0 && fail("unterminated variable reference")
            print(result, reference(s, String(text[(i+2):(last-1)]), text[i+1]))
            i=last+1
        else
            print(result, referencevalue(s, string(text[i+1])))
            i+=2
        end
    end
    String(take!(result))
end
function reference(s, content, opening)
    space=findfirst(==(' '), content)
    if space!==nothing && haskey(FUNCTIONS, content[1:(space-1)])
        return callfunction(s, content[1:(space-1)], trimleft(content[(space+1):end]), opening)
    end
    name=expand(s, content)
    colon=findfirst(==(':'), name)
    if colon!==nothing
        equals=findnext(==('='), name, colon+1)
        if equals!==nothing
            pattern=name[(colon+1):(equals-1)]
            replacement=name[(equals+1):end]
            if !occursin('%', pattern)
                pattern="%"*pattern
                replacement="%"*replacement
            end
            return join(
                [
                    replaceword(word, pattern, replacement) for
                    word in words(referencevalue(s, name[1:(colon-1)]))
                ],
                ' ',
            )
        end
    end
    referencevalue(s, name)
end
function referencevalue(s, name)
    for scope in reverse(s.scopes)
        if scope.name!==nothing
            scope.name==name && return scope.values[1]
        elseif numerictext(name)
            index=parse(Int, name)
            return index<length(scope.values) ? scope.values[index+1] : ""
        end
    end
    haskey(s.automatic, name) ? s.automatic[name] : variablevalue(s, name)
end
function variablevalue(s, name)
    haskey(s.makefile.variables, name) || return ""
    variable=s.makefile.variables[name]
    variable.recursive || return variable.value
    name in s.expanding && fail("Recursive variable '$name' references itself (eventually)")
    push!(s.expanding, name)
    try
        expand(s, variable.value)
    finally
        delete!(s.expanding, name)
    end
end
function callfunction(s, name, argument, opening)
    minimum, maximum=FUNCTIONS[name]
    args=splitarguments(argument, opening, maximum)
    length(args)>=minimum ||
        fail("insufficient number of arguments ($(length(args))) to function '$name'")
    if name=="foreach"
        variable=trimspaces(expand(s, args[1]))
        items=words(expand(s, args[2]))
        result=String[]
        for word in items
            push!(s.scopes, ExpansionScope(variable, [word]))
            try
                push!(result, expand(s, args[3]))
            finally
                pop!(s.scopes)
            end
        end
        return join(result, ' ')
    elseif name=="if"
        if !isempty(trimspaces(expand(s, args[1])))
            return expand(s, args[2])
        end
        return length(args)==3 ? expand(s, args[3]) : ""
    end
    vals=[expand(s, arg) for arg in args]
    !(name in ("subst", "call")) && (vals=trimspaces.(vals))
    if name=="subst"
        return isempty(vals[1]) ? vals[3] : replace(vals[3], vals[1]=>vals[2])
    elseif name=="patsubst"
        return join([replaceword(word, vals[1], vals[2]) for word in words(vals[3])], ' ')
    elseif name=="strip"
        return join(words(vals[1]), ' ')
    elseif name=="findstring"
        return occursin(vals[1], vals[2]) ? vals[1] : ""
    elseif name in ("filter", "filter-out")
        return join(
            [
                word for word in words(vals[2]) if
                any(p->patternstem(p, word)!==nothing, words(vals[1]))==(name=="filter")
            ],
            ' ',
        )
    elseif name=="sort"
        return join(sort!(unique(words(vals[1]))), ' ')
    elseif name=="word"
        numerictext(vals[1]) || fail("non-numeric first argument to 'word' function: '$(vals[1])'")
        index=parse(Int, vals[1])
        index>0 || fail("first argument to 'word' function must be greater than 0")
        items=words(vals[2])
        return index<=length(items) ? items[index] : ""
    elseif name=="wordlist"
        numerictext(vals[1]) ||
            fail("non-numeric first argument to 'wordlist' function: '$(vals[1])'")
        numerictext(vals[2]) ||
            fail("non-numeric second argument to 'wordlist' function: '$(vals[2])'")
        startindex=parse(Int, vals[1])
        endindex=parse(Int, vals[2])
        startindex>0 || fail("invalid first argument to 'wordlist' function: '$(vals[1])'")
        items=words(vals[3])
        return startindex>min(endindex, length(items)) ? "" :
               join(items[startindex:min(endindex, length(items))], ' ')
    elseif name=="words"
        return string(length(words(vals[1])))
    elseif name in ("firstword", "lastword")
        items=words(vals[1])
        return isempty(items) ? "" : name=="firstword" ? first(items) : last(items)
    elseif name in ("dir", "notdir", "suffix", "basename")
        result=String[]
        for word in words(vals[1])
            slash=something(findlast(==('/'), word), 0)
            dot=something(findlast(==('.'), word), 0)
            if name=="dir"
                push!(result, slash==0 ? "./" : word[1:slash])
            elseif name=="notdir"
                push!(result, word[(slash+1):end])
            elseif name=="suffix"
                dot>slash && push!(result, word[dot:end])
            else
                push!(result, dot>slash ? word[1:(dot-1)] : word)
            end
        end
        return join(result, ' ')
    elseif name=="addsuffix"
        return join([word*vals[1] for word in words(vals[2])], ' ')
    elseif name=="addprefix"
        return join([vals[1]*word for word in words(vals[2])], ' ')
    elseif name=="wildcard"
        return join([found for pattern in words(vals[1]) for found in wildcard(s, pattern)], ' ')
    elseif name=="call"
        variable=trimspaces(vals[1])
        haskey(s.makefile.variables, variable) || return ""
        value=s.makefile.variables[variable]
        value.recursive || return value.value
        push!(s.scopes, ExpansionScope(nothing, [variable; vals[2:end]]))
        try
            return expand(s, value.value)
        finally
            pop!(s.scopes)
        end
    elseif name=="value"
        return haskey(s.makefile.variables, vals[1]) ? s.makefile.variables[vals[1]].value : ""
    elseif name=="info"
        println(vals[1])
    elseif name=="warning"
        println("$(s.location): $(vals[1])")
    elseif name=="error"
        fail(vals[1])
    end
    ""
end
active(conditions) = isempty(conditions) || (last(conditions).outer && last(conditions).value)
function evaluatecondition(s, keyword, rest)
    if keyword in ("ifdef", "ifndef")
        name=trimspaces(expand(s, rest))
        defined=haskey(s.makefile.variables, name) && !isempty(s.makefile.variables[name].value)
        return defined==(keyword=="ifdef")
    end
    length(rest)>=2 && first(rest)=='(' && last(rest)==')' || fail("invalid syntax in conditional")
    inner=rest[2:(end-1)]
    depth=0
    for i in eachindex(inner)
        if inner[i]=='('
            depth+=1
        elseif inner[i]==')'
            depth-=1
        elseif inner[i]==',' && depth==0
            left=trimspaces(expand(s, inner[1:(i-1)]))
            right=trimspaces(expand(s, inner[(i+1):end]))
            return (left==right)==(keyword=="ifeq")
        end
    end
    fail("invalid syntax in conditional")
end
function assign!(s, text, equals)
    op=equals>1 && text[equals-1] in (':', '+', '?') ? string(text[equals-1]) : ""
    name=trimspaces(text[1:(equals-1-length(op))])
    value=trimspaces(text[(equals+1):end])
    isempty(name) && fail("empty variable name")
    variables=s.makefile.variables
    if op==":"
        variables[name]=Variable(false, expand(s, value))
    elseif op=="+" && haskey(variables, name)
        old=variables[name]
        addition=old.recursive ? value : expand(s, value)
        old.value=isempty(old.value) ? addition : old.value*" "*addition
    elseif op!="?" || !haskey(variables, name)
        variables[name]=Variable(true, value)
    end
end
function register!(s, target, prerequisites)
    rule=get!(s.makefile.rules, target, Rule())
    rule.prerequisites=unique([rule.prerequisites; prerequisites])
    isempty(s.makefile.goal) && !startswith(target, ".") && (s.makefile.goal=target)
end
function addrecipe!(s, group, line)
    if group.recipe===nothing
        group.recipe=RecipeLine[]
        for target in group.targets
            rule=s.makefile.rules[target]
            if rule.recipe!==nothing
                println("Makefile:$(line.number): warning: overriding recipe for target '$target'")
                println(
                    "Makefile:$(first(rule.recipe).number): warning: ignoring old recipe for target '$target'",
                )
            end
            rule.recipe=group.recipe
        end
        for rule in group.patterns
            rule.recipe=group.recipe
        end
    end
    push!(group.recipe, line)
end
function definerule!(s, targettext, rest, number)
    targets=unique(words(expand(s, targettext)))
    inline=nothing
    semicolon=outsideindex(rest, ';')
    if semicolon!=0
        inline=trimleft(rest[(semicolon+1):end])
        rest=rest[1:(semicolon-1)]
    end
    colon=outsideindex(rest, ':')
    pattern=nothing
    if colon!=0
        pattern=trimspaces(expand(s, rest[1:(colon-1)]))
        rest=rest[(colon+1):end]
    end
    prerequisites=words(expand(s, rest))
    group=RuleGroup()
    if targets==[".PHONY"]
        union!(s.makefile.phony, prerequisites)
    elseif pattern!==nothing
        occursin('%', pattern) || fail("target pattern contains no '%'")
        for target in targets
            stem=patternstem(pattern, target)
            if stem!==nothing && !isempty(stem)
                register!(s, target, [substitute(p, stem) for p in prerequisites])
                s.makefile.rules[target].stem=stem
                push!(group.targets, target)
            else
                println("Makefile:$number: target '$target' doesn't match the target pattern")
            end
        end
    elseif any(t->occursin('%', t), targets)
        all(t->occursin('%', t), targets) || fail("mixed implicit and normal rules")
        for target in targets
            rule=PatternRule(target, prerequisites, nothing)
            push!(s.makefile.patterns, rule)
            push!(group.patterns, rule)
        end
    else
        for target in targets
            register!(s, target, prerequisites)
        end
        group.targets=targets
    end
    inline!==nothing && addrecipe!(s, group, RecipeLine(number, inline))
    group
end
function loadmakefile!(s, lines)
    s.makefile=Makefile()
    conditions=MakeCondition[]
    group=nothing
    i=1
    try
        while i<=length(lines)
            number=i
            line=lines[i]
            i+=1
            s.location="Makefile:$number"
            if startswith(line, ">")
                if active(conditions)
                    group===nothing && fail("recipe commences before first target")
                    addrecipe!(s, group, RecipeLine(number, trimleft(line[2:end])))
                end
                continue
            end
            while endswith(line, "\\") && i<=length(lines)
                line=trimright(line[1:(end-1)])*" "*trimleft(lines[i])
                i+=1
            end
            hash=findfirst(==('#'), line)
            text=trimspaces(hash===nothing ? line : line[1:(hash-1)])
            parts=split(text, ' '; limit = 2)
            keyword=isempty(parts) ? "" : parts[1]
            rest=length(parts)==2 ? trimspaces(parts[2]) : ""
            if keyword in ("ifeq", "ifneq", "ifdef", "ifndef", "else", "endif")
                if keyword=="else"
                    isempty(conditions) && fail("extraneous 'else'")
                    last(conditions).seenelse && fail("only one 'else' per conditional")
                    last(conditions).value=!last(conditions).value
                    last(conditions).seenelse=true
                elseif keyword=="endif"
                    isempty(conditions) && fail("extraneous 'endif'")
                    pop!(conditions)
                else
                    outer=active(conditions)
                    value=outer && evaluatecondition(s, keyword, rest)
                    push!(conditions, MakeCondition(outer, value, false, number))
                end
            elseif !isempty(text) && active(conditions)
                equals=outsideindex(text, '=')
                colon=outsideindex(text, ':')
                if equals!=0 && (colon==0 || colon>=equals-1)
                    assign!(s, text, equals)
                    group=nothing
                elseif colon!=0
                    group=definerule!(s, text[1:(colon-1)], text[(colon+1):end], number)
                else
                    isempty(trimspaces(expand(s, text))) || fail("missing separator")
                end
            end
        end
        if !isempty(conditions)
            s.location="Makefile:$(last(conditions).number)"
            fail("missing 'endif'")
        end
        filter!(r->r.recipe!==nothing, s.makefile.patterns)
        s.makefile.loaded=true
        println(
            "Makefile loaded: lines=$(length(lines)) variables=$(length(s.makefile.variables)) targets=$(length(s.makefile.rules)) patterns=$(length(s.makefile.patterns)) goal=$(isempty(s.makefile.goal) ? "(none)" : s.makefile.goal)",
        )
    catch e
        e isa MakeError || rethrow()
        println("$(s.location): *** $(e.message).  Stop.")
        s.makefile=Makefile()
    finally
        s.location="make"
    end
end
struct ResolvedRule
    prerequisites::Vector{String}
    recipe::Union{Nothing,Vector{RecipeLine}}
    stem::String
    source::Bool
end
function resolverule(s, target)
    m=s.makefile
    explicit=get(m.rules, target, nothing)
    explicit!==nothing &&
        explicit.recipe!==nothing &&
        return ResolvedRule(explicit.prerequisites, explicit.recipe, explicit.stem, false)
    if !(target in m.phony)
        candidates=Tuple{String,Int}[]
        for (i, rule) in enumerate(m.patterns)
            stem=patternstem(rule.target, target)
            stem!==nothing && !isempty(stem) && push!(candidates, (stem, i))
        end
        sort!(candidates; by = x->(length(x[1]), x[2]))
        for (stem, i) in candidates
            rule=m.patterns[i]
            prerequisites=[substitute(p, stem) for p in rule.prerequisites]
            if all(p->haskey(s.files, p) || haskey(m.rules, p), prerequisites)
                explicit!==nothing && append!(prerequisites, explicit.prerequisites)
                return ResolvedRule(unique(prerequisites), rule.recipe, stem, false)
            end
        end
    end
    explicit!==nothing && return ResolvedRule(explicit.prerequisites, nothing, explicit.stem, false)
    target in m.phony && return ResolvedRule(String[], nothing, "", false)
    haskey(s.files, target) ? ResolvedRule(String[], nothing, "", true) : nothing
end
targettime(s, target) = target in s.makefile.phony ? nothing : get(s.files, target, nothing)
function executerecipe!(s, command)
    parts=words(command)
    name=parts[1]
    args=parts[2:end]
    if name=="echo"
        println(join(args, ' '))
    elseif name=="touch"
        for arg in args
            touch!(s, arg)
        end
    elseif name=="false"
        return 1
    elseif name=="exit"
        return isempty(args) ? 0 : parse(Int, args[1])
    elseif name=="rm"
        forced=!isempty(args) && args[1]=="-f"
        forced && (args=args[2:end])
        status=0
        for arg in args
            matches=wildcard(s, arg)
            isempty(matches) && (matches=[arg])
            for name in matches
                if haskey(s.files, name)
                    delete!(s.files, name)
                elseif !forced
                    println("rm: cannot remove '$name': No such file or directory")
                    status=1
                end
            end
        end
        return status
    end
    0
end
function make!(s, arguments)
    options=Set{Char}()
    goals=String[]
    for arg in arguments
        if !startswith(arg, "-")
            push!(goals, arg)
            continue
        end
        for option in arg[2:end]
            if !(option in "nBkis")
                println("make: invalid option -- '$option'")
                return
            end
            push!(options, option)
        end
    end
    if isempty(goals)
        if !s.makefile.loaded
            println("make: *** No targets specified and no makefile found.  Stop.")
            return
        elseif isempty(s.makefile.goal)
            println("make: *** No targets.  Stop.")
            return
        end
        goals=[s.makefile.goal]
    end
    savedfiles=copy(s.files)
    savedclock=s.clock
    results=Dict{String,Symbol}()
    resolved=Dict{String,ResolvedRule}()
    building=Set{String}()
    runs=0
    function runrecipe(target, rule, prerequisites, changed)
        s.automatic=Dict(
            "@"=>target,
            "<"=>(isempty(prerequisites) ? "" : first(prerequisites)),
            "^"=>join(prerequisites, ' '),
            "?"=>join(changed, ' '),
            "*"=>rule.stem,
        )
        expanded=String[]
        try
            for line in rule.recipe
                s.location="Makefile:$(line.number)"
                push!(expanded, expand(s, line.command))
            end
        catch e
            e isa MakeError || rethrow()
            println("$(s.location): *** $(e.message).  Stop.")
            throw(BuildAborted())
        finally
            empty!(s.automatic)
            s.location="make"
        end
        for (line, text) in zip(rule.recipe, expanded)
            firstcommand=1
            while firstcommand<=length(text) && text[firstcommand] in (' ', '@', '-')
                firstcommand+=1
            end
            prefix=text[1:(firstcommand-1)]
            command=trimright(text[firstcommand:end])
            isempty(command) && continue
            ('n' in options || (!occursin('@', prefix) && !('s' in options))) && println(command)
            'n' in options && continue
            status=executerecipe!(s, command)
            status==0 && continue
            if occursin('-', prefix) || 'i' in options
                println("make: [Makefile:$(line.number): $target] Error $status (ignored)")
            else
                println("make: *** [Makefile:$(line.number): $target] Error $status")
                'k' in options || throw(BuildAborted())
                return false
            end
        end
        true
    end
    function build(target, parent)
        haskey(results, target) && return results[target]
        rule=resolverule(s, target)
        if rule===nothing
            results[target]=:failure
            message="make: *** No rule to make target '$target'"*(
                parent===nothing ? "." : ", needed by '$parent'."
            )
            if !('k' in options)
                println(message*"  Stop.")
                throw(BuildAborted())
            end
            println(message)
            return :failure
        end
        resolved[target]=rule
        if rule.source
            results[target]=:success
            return :success
        end
        push!(building, target)
        prerequisites=String[]
        failed=false
        for dep in rule.prerequisites
            if dep in building
                println("make: Circular $target <- $dep dependency dropped.")
                continue
            end
            push!(prerequisites, dep)
            build(dep, target)!=:success && (failed=true)
        end
        delete!(building, target)
        result=:success
        if failed
            result=:dependency
        else
            timestamp=targettime(s, target)
            changed=String[]
            for dep in prerequisites
                value=targettime(s, dep)
                ('B' in options || timestamp===nothing || value===nothing || value>timestamp) &&
                    push!(changed, dep)
            end
            if rule.recipe!==nothing && ('B' in options || timestamp===nothing || !isempty(changed))
                runs+=1
                if runrecipe(target, rule, prerequisites, changed)
                    !(target in s.makefile.phony) && touch!(s, target)
                else
                    result=:failure
                end
            end
        end
        results[target]=result
        result
    end
    try
        for goal in goals
            before=runs
            result=build(goal, nothing)
            if result==:success && runs==before
                if goal in s.makefile.phony || resolved[goal].recipe===nothing
                    println("make: Nothing to be done for '$goal'.")
                else
                    println("make: '$goal' is up to date.")
                end
            elseif result==:dependency
                println("make: Target '$goal' not remade because of errors.")
            end
        end
    catch e
        e isa BuildAborted || rethrow()
    finally
        if 'n' in options
            s.files=savedfiles
            s.clock=savedclock
        end
    end
end
function printrule(target, prerequisites, recipe)
    println(join([target*":"; prerequisites], ' '))
    recipe===nothing || foreach(line->println(">"*line.command), recipe)
end
function main()
    lines=readlines()
    files=Dict{String,Int}()
    i=2
    while lines[i]!="END FILES"
        name, timestamp=split(lines[i], ' ')
        files[name]=parse(Int, timestamp)
        i+=1
    end
    i+=1
    simulator=Simulator(files)
    while lines[i]!="QUIT"
        line=lines[i]
        i+=1
        println("\$ ", line)
        parts=split(line, ' '; limit = 2)
        command=parts[1]
        argument=length(parts)==2 ? String(parts[2]) : ""
        if command=="MAKEFILE"
            body=String[]
            while lines[i]!="END MAKEFILE"
                push!(body, lines[i])
                i+=1
            end
            i+=1
            loadmakefile!(simulator, body)
        elseif command=="MAKE"
            make!(simulator, words(argument))
        elseif command=="TOUCH"
            for name in words(argument)
                touch!(simulator, name)
            end
        elseif command=="RM"
            for name in words(argument)
                if haskey(simulator.files, name)
                    delete!(simulator.files, name)
                else
                    println("rm: cannot remove '$name': No such file or directory")
                end
            end
        elseif command=="FILES"
            println("clock $(simulator.clock)")
            for name in sort!(collect(keys(simulator.files)))
                println("$name $(simulator.files[name])")
            end
        elseif command=="VARS"
            try
                for name in sort!(collect(keys(simulator.makefile.variables)))
                    symbol=simulator.makefile.variables[name].recursive ? "=" : ":="
                    value=trimspaces(variablevalue(simulator, name))
                    println("$name $symbol"*(isempty(value) ? "" : " "*value))
                end
            catch e
                e isa MakeError || rethrow()
                println("make: *** $(e.message).  Stop.")
            end
        elseif command=="RULES"
            m=simulator.makefile
            for target in sort!(collect(keys(m.rules)))
                rule=m.rules[target]
                printrule(target, rule.prerequisites, rule.recipe)
            end
            for rule in m.patterns
                printrule(rule.target, rule.prerequisites, rule.recipe)
            end
            !isempty(m.phony) && println(join([".PHONY:"; sort!(collect(m.phony))], ' '))
        elseif command=="EXPAND"
            try
                println("[", expand(simulator, argument), "]")
            catch e
                e isa MakeError || rethrow()
                println("make: *** $(e.message).  Stop.")
            end
        end
    end
end
main()
