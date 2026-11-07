include("charset.jl")
include("formatter.jl")

struct PatternError <: Exception
    message::String
    column::Int
end

Base.@kwdef mutable struct RegexNode
    kind::String
    value::Union{Nothing,Char,String} = nothing
    child::Union{Nothing,RegexNode} = nothing
    elements::Vector{RegexNode} = RegexNode[]
    lower::Int = 0
    upper::Union{Nothing,Int} = nothing
    mode::String = "greedy"
    number::Int = 0
    name::Union{Nothing,String} = nothing
    column::Int = 0
    codes::BitSet = BitSet()
    negated::Bool = false
    positive::Bool = true
end

Base.@kwdef mutable struct RegexInstruction
    op::String
    character::Char = '\0'
    codes::BitSet = BitSet()
    negated::Bool = false
    x::Int = 0
    y::Int = 0
    slot::Int = 0
    kind::String = ""
    group::Int = 0
end

mutable struct PatternParser
    text::String
    index::Int
    groups::Int
    named::Dict{String,Int}
    backrefs::Vector{RegexNode}
end
PatternParser(text) = PatternParser(text,1,0,Dict{String,Int}(),RegexNode[])
parser_peek(parser,offset=0) = parser.index+offset <= length(parser.text) ? parser.text[parser.index+offset] : nothing
function read_character!(parser)
    character = parser_peek(parser)
    character !== nothing && (parser.index += 1)
    character
end
pattern_error(parser,message,column=parser.index) = throw(PatternError(message,column))
function read_digits!(parser)
    beginning = parser.index
    while is_digit(parser_peek(parser))
        read_character!(parser)
    end
    parser.text[beginning:parser.index-1]
end
function read_name!(parser)
    initial = parser_peek(parser)
    if initial === nothing || !(is_letter(initial) || initial == '_')
        pattern_error(parser,"invalid group name")
    end
    beginning = parser.index
    while parser_peek(parser) !== nothing && (is_letter(parser_peek(parser)) || is_digit(parser_peek(parser)) || parser_peek(parser) == '_')
        read_character!(parser)
    end
    name = parser.text[beginning:parser.index-1]
    parser_peek(parser) == '>' || pattern_error(parser,"invalid group name")
    read_character!(parser)
    name
end
function parse_pattern!(parser)
    root = parse_alternation!(parser)
    parser_peek(parser) === nothing || pattern_error(parser,"unmatched )")
    for reference in parser.backrefs
        if reference.name !== nothing
            haskey(parser.named,reference.name) || pattern_error(parser,"unknown group name",reference.column)
            reference.number = parser.named[reference.name]
        elseif reference.number > parser.groups
            pattern_error(parser,"invalid group reference",reference.column)
        end
    end
    root
end
function parse_alternation!(parser)
    elements = RegexNode[parse_concatenation!(parser)]
    while parser_peek(parser) == '|'
        read_character!(parser)
        push!(elements,parse_concatenation!(parser))
    end
    length(elements) == 1 ? elements[1] : RegexNode(kind="alternation",elements=elements)
end
function parse_concatenation!(parser)
    elements = RegexNode[]
    while parser_peek(parser) !== nothing && !(parser_peek(parser) in ('|',')'))
        push!(elements,parse_quantified!(parser))
    end
    length(elements) == 1 ? elements[1] : RegexNode(kind="concat",elements=elements)
end
is_quantifier(character) = character in ('*','+','?','{')
function parse_quantified!(parser)
    is_quantifier(parser_peek(parser)) && pattern_error(parser,"nothing to repeat")
    element = parse_element!(parser)
    is_quantifier(parser_peek(parser)) || return element
    element.kind in ("assert","look") && pattern_error(parser,"nothing to repeat")
    beginning = parser.index
    character = read_character!(parser)
    if character == '*'
        lower,upper = 0,nothing
    elseif character == '+'
        lower,upper = 1,nothing
    elseif character == '?'
        lower,upper = 0,1
    else
        digits = read_digits!(parser)
        isempty(digits) && pattern_error(parser,"invalid quantifier",beginning)
        lower = parse(Int,digits)
        if parser_peek(parser) == '}'
            upper = lower
        elseif parser_peek(parser) == ','
            read_character!(parser)
            if parser_peek(parser) == '}'
                upper = nothing
            else
                digits = read_digits!(parser)
                isempty(digits) && pattern_error(parser,"invalid quantifier",beginning)
                upper = parse(Int,digits)
            end
        else
            pattern_error(parser,"invalid quantifier",beginning)
        end
        parser_peek(parser) == '}' || pattern_error(parser,"invalid quantifier",beginning)
        read_character!(parser)
        (lower > 100 || (upper !== nothing && upper > 100)) && pattern_error(parser,"quantifier too large",beginning)
        upper !== nothing && lower > upper && pattern_error(parser,"quantifier range out of order",beginning)
    end
    mode = "greedy"
    if parser_peek(parser) == '?'
        read_character!(parser)
        mode = "lazy"
    elseif parser_peek(parser) == '+'
        read_character!(parser)
        mode = "possessive"
    end
    is_quantifier(parser_peek(parser)) && pattern_error(parser,"nested quantifier")
    RegexNode(kind="repeat",child=element,lower=lower,upper=upper,mode=mode)
end
function parse_element!(parser)
    character = parser_peek(parser)
    character == '(' && return parse_group!(parser)
    character == '[' && return parse_class!(parser)
    character == '\\' && return parse_escape!(parser)
    read_character!(parser)
    character == '.' && return RegexNode(kind="any")
    character == '^' && return RegexNode(kind="assert",value="BOL")
    character == '$' && return RegexNode(kind="assert",value="EOL")
    RegexNode(kind="literal",value=character)
end
function parse_group!(parser)
    column = parser.index
    read_character!(parser)
    kind,name = "capture",nothing
    if parser_peek(parser) == '?'
        read_character!(parser)
        special = read_character!(parser)
        if special == ':'
            kind = "noncapture"
        elseif special == '='
            kind = "positive"
        elseif special == '!'
            kind = "negative"
        elseif special == '<'
            beginning = parser.index
            name = read_name!(parser)
            haskey(parser.named,name) && pattern_error(parser,"duplicate group name",beginning)
        else
            pattern_error(parser,"invalid group",column)
        end
    end
    number = 0
    if kind == "capture"
        parser.groups += 1
        number = parser.groups
        name !== nothing && (parser.named[name] = number)
    end
    child = parse_alternation!(parser)
    parser_peek(parser) == ')' || pattern_error(parser,"missing )",column)
    read_character!(parser)
    kind == "noncapture" && return child
    kind in ("positive","negative") && return RegexNode(kind="look",child=child,positive=kind == "positive")
    RegexNode(kind="group",number=number,name=name,child=child)
end
function read_class_item!(parser)
    character = read_character!(parser)
    character != '\\' && return Int(character)
    column = parser.index-1
    parser_peek(parser) === nothing && pattern_error(parser,"trailing backslash",column)
    character = read_character!(parser)
    character in ('d','D','w','W','s','S') && return escaped_set(character)
    character == 'n' && return 10
    character == 't' && return 9
    (is_letter(character) || is_digit(character)) && pattern_error(parser,"invalid escape",column)
    Int(character)
end
function parse_class!(parser)
    column = parser.index
    read_character!(parser)
    negated = parser_peek(parser) == '^'
    negated && read_character!(parser)
    parser_peek(parser) == ']' && pattern_error(parser,"empty class")
    codes = BitSet()
    while true
        parser_peek(parser) === nothing && pattern_error(parser,"missing ]",column)
        if parser_peek(parser) == ']'
            read_character!(parser)
            break
        end
        initial = read_class_item!(parser)
        if parser_peek(parser) == '-' && parser_peek(parser,1) !== nothing && parser_peek(parser,1) != ']'
            hyphen = parser.index
            read_character!(parser)
            initial isa BitSet && pattern_error(parser,"invalid range",hyphen)
            final = read_class_item!(parser)
            (final isa BitSet || initial > final) && pattern_error(parser,"invalid range",hyphen)
            union!(codes,initial:final)
        elseif initial isa BitSet
            union!(codes,initial)
        else
            push!(codes,initial)
        end
    end
    RegexNode(kind="class",codes=codes,negated=negated)
end
function parse_escape!(parser)
    column = parser.index
    read_character!(parser)
    parser_peek(parser) === nothing && pattern_error(parser,"trailing backslash",column)
    character = read_character!(parser)
    if character in ('d','D','w','W','s','S')
        return RegexNode(kind="class",codes=copy(STANDARD[lowercase(character)]),negated=isuppercase(character))
    end
    character == 'b' && return RegexNode(kind="assert",value="WORD")
    character == 'B' && return RegexNode(kind="assert",value="NOTWORD")
    character == 'n' && return RegexNode(kind="literal",value='\n')
    character == 't' && return RegexNode(kind="literal",value='\t')
    if '1' <= character <= '9'
        beginning = parser.index-1
        read_digits!(parser)
        reference = RegexNode(kind="backref",number=parse(Int,parser.text[beginning:parser.index-1]),column=column)
        push!(parser.backrefs,reference)
        return reference
    elseif character == 'k'
        parser_peek(parser) == '<' || pattern_error(parser,"invalid escape",column)
        read_character!(parser)
        reference = RegexNode(kind="backref",name=read_name!(parser),column=column)
        push!(parser.backrefs,reference)
        return reference
    end
    (is_letter(character) || is_digit(character)) && pattern_error(parser,"invalid escape",column)
    RegexNode(kind="literal",value=character)
end
function emit!(program,op;kwargs...)
    push!(program,RegexInstruction(;op=op,kwargs...))
    length(program)-1
end
function compile_node!(program,node)
    kind = node.kind
    if kind == "literal"
        emit!(program,"CHAR";character=node.value)
    elseif kind == "any"
        emit!(program,"ANY")
    elseif kind == "class"
        emit!(program,"CLASS";codes=copy(node.codes),negated=node.negated)
    elseif kind == "assert"
        emit!(program,"ASSERT";kind=node.value)
    elseif kind == "backref"
        emit!(program,"BACKREF";group=node.number)
    elseif kind == "group"
        emit!(program,"SAVE";slot=2*node.number)
        compile_node!(program,node.child)
        emit!(program,"SAVE";slot=2*node.number+1)
    elseif kind == "look"
        address = emit!(program,"LOOK";kind=node.positive ? "AHEAD" : "NOT")
        compile_node!(program,node.child)
        emit!(program,"MATCH")
        program[address+1].x = length(program)
    elseif kind == "concat"
        for child in node.elements
            compile_node!(program,child)
        end
    elseif kind == "alternation"
        jumps = Int[]
        for child in node.elements[1:end-1]
            address = emit!(program,"SPLIT")
            program[address+1].x = length(program)
            compile_node!(program,child)
            push!(jumps,emit!(program,"JMP"))
            program[address+1].y = length(program)
        end
        compile_node!(program,node.elements[end])
        for address in jumps
            program[address+1].x = length(program)
        end
    elseif node.mode == "possessive"
        address = emit!(program,"LOOK";kind="ATOMIC")
        compile_repeat!(program,node.child,node.lower,node.upper,"greedy")
        emit!(program,"MATCH")
        program[address+1].x = length(program)
    else
        compile_repeat!(program,node.child,node.lower,node.upper,node.mode)
    end
end
function patch_split!(entry,continuation,finish,mode)
    entry.x,entry.y = mode == "lazy" ? (finish,continuation) : (continuation,finish)
end
function compile_repeat!(program,child,lower,upper,mode)
    if upper === nothing && lower == 0
        address = emit!(program,"SPLIT")
        compile_node!(program,child)
        emit!(program,"JMP";x=address)
        patch_split!(program[address+1],address+1,length(program),mode)
    elseif upper === nothing
        for _ in 1:lower-1
            compile_node!(program,child)
        end
        beginning = length(program)
        compile_node!(program,child)
        address = emit!(program,"SPLIT")
        patch_split!(program[address+1],beginning,length(program),mode)
    else
        for _ in 1:lower
            compile_node!(program,child)
        end
        splits = Int[]
        for _ in 1:upper-lower
            push!(splits,emit!(program,"SPLIT"))
            compile_node!(program,child)
        end
        for address in splits
            patch_split!(program[address+1],address+1,length(program),mode)
        end
    end
end
function compile_pattern(root)
    program = RegexInstruction[]
    emit!(program,"SAVE";slot=0)
    compile_node!(program,root)
    emit!(program,"SAVE";slot=1)
    emit!(program,"MATCH")
    program
end
function length_range(node)
    node.kind in ("literal","any","class") && return (1,1)
    node.kind in ("assert","look") && return (0,0)
    node.kind == "backref" && return (0,nothing)
    node.kind == "group" && return length_range(node.child)
    if node.kind == "repeat"
        low,high = length_range(node.child)
        max_length = high == 0 ? 0 : high === nothing || node.upper === nothing ? nothing : high*node.upper
        return (low*node.lower,max_length)
    end
    ranges = [length_range(child) for child in node.elements]
    if node.kind == "concat"
        return (sum((range[1] for range in ranges);init=0),any(range->range[2] === nothing,ranges) ? nothing : sum((range[2] for range in ranges);init=0))
    end
    minimum(range[1] for range in ranges),any(range->range[2] === nothing,ranges) ? nothing : maximum(range[2] for range in ranges)
end
function first_characters(node,flags)
    kind = node.kind
    if kind == "literal"
        codes = BitSet([Int(node.value)])
        'i' in flags && is_letter(node.value) && push!(codes,Int(switched(node.value)))
        return codes,false
    elseif kind == "any"
        return 's' in flags ? copy(ASCII) : setdiff(ASCII,BitSet([10])),false
    elseif kind == "class"
        return BitSet(code for code in 0:127 if test_class(string(Char(code)),0,node.codes,node.negated,flags)),false
    elseif kind in ("assert","look")
        return BitSet(),true
    elseif kind == "backref"
        return copy(ASCII),true
    elseif kind == "group"
        return first_characters(node.child,flags)
    elseif kind == "repeat"
        node.upper == 0 && return BitSet(),true
        codes,nullable = first_characters(node.child,flags)
        return codes,nullable || node.lower == 0
    end
    codes = BitSet()
    nullable = kind == "concat"
    for child in node.elements
        child_codes,child_nullable = first_characters(child,flags)
        union!(codes,child_codes)
        if kind == "concat"
            if !child_nullable
                nullable = false
                break
            end
        else
            nullable |= child_nullable
        end
    end
    codes,nullable
end

include("backtrack_vm.jl")
include("pike_vm.jl")

struct PatternInfo
    name::String
    original_flags::String
    flags::String
    text::String
    groups::Int
    named::Dict{String,Int}
    root::Union{Nothing,RegexNode}
    program::Vector{RegexInstruction}
    error::Union{Nothing,PatternError}
    compatible::Bool
end
function read_pattern(line)
    name,flag_text,text = split(line,' ';limit=3)
    flags = flag_text == "-" ? "" : String(flag_text)
    parser = PatternParser(String(text))
    try
        root = parse_pattern!(parser)
        program = compile_pattern(root)
        PatternInfo(name,flag_text,flags,text,parser.groups,parser.named,root,program,nothing,all(entry->!(entry.op in ("LOOK","BACKREF")),program))
    catch error
        error isa PatternError || rethrow()
        PatternInfo(name,flag_text,flags,text,parser.groups,parser.named,nothing,RegexInstruction[],error,false)
    end
end
function decode_quoted(encoded)
    buffer = IOBuffer()
    index = 2
    while index < length(encoded)
        character = encoded[index]
        if character == '\\'
            index += 1
            escaped = encoded[index]
            character = escaped == 'n' ? '\n' : escaped == 't' ? '\t' : escaped
        end
        print(buffer,character)
        index += 1
    end
    String(take!(buffer))
end
subject_slice(text,beginning,finish) = beginning == finish ? "" : text[beginning+1:finish]
function parse_template(template,pattern)
    parts = Union{Char,Int}[]
    index = 1
    while index <= length(template)
        character = template[index]
        index += 1
        if character != '$'
            push!(parts,character)
            continue
        end
        index <= length(template) || return nothing
        character = template[index]
        index += 1
        if character == '$'
            push!(parts,'$')
            continue
        elseif is_digit(character)
            group = Int(character)-Int('0')
        elseif character == '{'
            beginning = index
            while index <= length(template) && template[index] != '}'
                index += 1
            end
            index <= length(template) || return nothing
            content = template[beginning:index-1]
            index += 1
            if !isempty(content) && all(is_digit,content)
                group = parse(Int,content)
            elseif haskey(pattern.named,content)
                group = pattern.named[content]
            else
                return nothing
            end
        else
            return nothing
        end
        group <= pattern.groups || return nothing
        push!(parts,group)
    end
    parts
end
group_is_set(captures,group) = captures[2*group+1] >= 0 && captures[2*group+2] >= 0
function expand_template(parts,captures,text)
    buffer = IOBuffer()
    for part in parts
        if part isa Char
            print(buffer,part)
        elseif group_is_set(captures,part)
            print(buffer,subject_slice(text,captures[2*part+1],captures[2*part+2]))
        end
    end
    String(take!(buffer))
end
function command_matches(vm,kind,mode,text)
    if kind in ("MATCH","SEARCH") || (kind == "REPLACE" && mode == "FIRST")
        found = search!(vm,0)
        return found === nothing ? Vector{Int}[] : [found]
    end
    matches = Vector{Int}[]
    position = 0
    while position <= length(text)
        found = search!(vm,position)
        found === nothing && break
        push!(matches,found)
        position = found[2] > found[1] ? found[2] : found[2]+1
    end
    matches
end
function span_text(captures,group,text)
    beginning,finish = captures[2*group+1],captures[2*group+2]
    "$(beginning)-$(finish) " * quoted(subject_slice(text,beginning,finish))
end
function append_match!(lines,captures,pattern,text)
    push!(lines,"match " * span_text(captures,0,text))
    for group in 1:pattern.groups
        push!(lines,"group $group " * (group_is_set(captures,group) ? span_text(captures,group,text) : "-"))
    end
end
function append_results!(lines,kind,matches,pattern,text,parts)
    if kind in ("MATCH","SEARCH")
        isempty(matches) ? push!(lines,"no match") : append_match!(lines,matches[1],pattern,text)
    elseif kind == "FINDALL"
        push!(lines,"matches $(length(matches))")
        for captures in matches
            append_match!(lines,captures,pattern,text)
        end
    elseif kind == "REPLACE"
        buffer = IOBuffer()
        position = 0
        for captures in matches
            print(buffer,subject_slice(text,position,captures[1]),expand_template(parts,captures,text))
            position = captures[2]
        end
        print(buffer,subject_slice(text,position,length(text)))
        push!(lines,"replacements $(length(matches))","result " * quoted(String(take!(buffer))))
    else
        push!(lines,"pieces $(length(matches)+1)")
        position = 0
        for captures in matches
            push!(lines,"piece " * quoted(subject_slice(text,position,captures[1])))
            for group in 1:pattern.groups
                value = group_is_set(captures,group) ? quoted(subject_slice(text,captures[2*group+1],captures[2*group+2])) : "-"
                push!(lines,"group $group " * value)
            end
            position = captures[2]
        end
        push!(lines,"piece " * quoted(subject_slice(text,position,length(text))))
    end
end
function append_program!(lines,pattern)
    low,high = length_range(pattern.root)
    codes,_ = first_characters(pattern.root,pattern.flags)
    names = join(("$name:$(pattern.named[name])" for name in sort(collect(keys(pattern.named));by=name->pattern.named[name])),",")
    isempty(names) && (names = "-")
    maximum_text = high === nothing ? "inf" : string(high)
    first_text = isempty(codes) ? "-" : set_notation(codes)
    compatible = pattern.compatible ? "yes" : "no"
    push!(lines,"=== $(pattern.name)")
    push!(lines,"flags=$(pattern.original_flags) groups=$(pattern.groups) names=$names length=$low..$maximum_text first=$first_text pike=$compatible size=$(length(pattern.program))")
    for (index,instruction) in enumerate(pattern.program)
        push!(lines,"$(index-1) " * instruction_notation(instruction))
    end
end
function main()
    patterns = read_pattern.(readlines("input/patterns.txt"))
    by_name = Dict(pattern.name=>pattern for pattern in patterns)
    subjects = Dict{String,String}()
    for line in readlines("input/subjects.txt")
        name,encoded = split(line,' ';limit=2)
        subjects[name] = decode_quoted(encoded)
    end
    results,programs,errors = String[],String[],String[]
    steps = ["command,engine,steps"]
    for pattern in patterns
        pattern.error === nothing && continue
        error = pattern.error
        push!(errors,"$(pattern.name): $(error.message) at column $(error.column)","  " * pattern.text," "^(error.column+1) * "^")
    end
    for (number,line) in enumerate(readlines("input/commands.txt"))
        fields = split(line,' ';limit=5)
        kind = fields[1]
        mode = kind == "REPLACE" ? fields[2] : ""
        name = fields[kind == "REPLACE" ? 3 : 2]
        pattern = by_name[name]
        push!(results,"#$number $line")
        if pattern.error !== nothing
            push!(results,"invalid pattern")
            continue
        elseif kind == "LIST"
            push!(results,"instructions $(length(pattern.program))")
            append_program!(programs,pattern)
            continue
        end
        parts = kind == "REPLACE" ? parse_template(decode_quoted(fields[5]),pattern) : nothing
        if kind == "REPLACE" && parts === nothing
            push!(results,"invalid template")
            continue
        end
        text = subjects[fields[kind == "REPLACE" ? 4 : 3]]
        backtrack = BacktrackingVM(pattern.program,pattern.flags,pattern.groups,text,kind == "MATCH",0)
        backtrack_matches = Vector{Int}[]
        aborted = false
        try
            backtrack_matches = command_matches(backtrack,kind,mode,text)
        catch error
            error isa TooManySteps || rethrow()
            aborted = true
        end
        push!(steps,"$number,backtrack,$(backtrack.steps)")
        matches,label = backtrack_matches,"backtrack"
        if pattern.compatible
            pike = PikeVM(pattern.program,pattern.flags,pattern.groups,text,kind == "MATCH",0)
            pike_matches = command_matches(pike,kind,mode,text)
            push!(steps,"$number,pike,$(pike.steps)")
            if !aborted && backtrack_matches != pike_matches
                push!(results,"MISMATCH")
                continue
            end
            matches = pike_matches
            label = aborted ? "pike (backtrack: TOO_MANY_STEPS)" : "both"
        elseif aborted
            push!(results,"TOO_MANY_STEPS")
            continue
        end
        push!(results,"engine " * label)
        append_results!(results,kind,matches,pattern,text,parts)
    end
    isempty(programs) && push!(programs,"no programs")
    isempty(errors) && push!(errors,"no errors")
    for (name,lines) in (("results.txt",results),("programs.txt",programs),("steps.csv",steps),("errors.txt",errors))
        write(joinpath("output",name),join(lines,"\n") * "\n")
    end
end
main()
