include("lexer.jl")
include("definitions.jl")
include("expression.jl")
include("include_manager.jl")
include("expander.jl")
const CONDITIONALS = (STARTS...,BRANCHES...,"endif")
struct HeaderSpecification
    rendering::String
    name::String
    quoted::Bool
end
struct DirectiveError <: Exception
    message::String
end
mutable struct ConditionalBlock
    kind::String
    position::Tuple{String,Int}
    parent::Bool
    chosen::Bool
    active::Bool
    else_seen::Bool
    skip_start::Union{Nothing,Int}
end
mutable struct Inclusion
    source::PPSourceFile
    depth::Int
    display_file::String
    offset::Int
    stack::Vector{ConditionalBlock}
    segment::Vector{PPToken}
end
Inclusion(source,depth) = Inclusion(source,depth,source.path,0,ConditionalBlock[],PPToken[])
display_position(context,physical) = (context.display_file,physical+context.offset)
skipping(context) = !isempty(context.stack) && !context.stack[end].active
function separator_needed(left,right)
    left == "/" && right[1] in ('/','*') && return true
    kind,spelling,last = read_token(left * right)
    last != length(left)+1
end
function output_render(tokens)
    pieces = String[]
    previous = nothing
    for token in tokens
        previous !== nothing && (token.space || separator_needed(previous,token.spelling)) && push!(pieces," ")
        push!(pieces,token.spelling)
        previous = token.spelling
    end
    join(pieces)
end
following(heading,items) = heading * join([" " * item for item in items])
function header_specification(tokens,index=1)
    index > length(tokens) && return (nothing,index)
    token = tokens[index]
    if token.kind in ("string","header")
        text = token.spelling
        return HeaderSpecification(text,text[2:end-1],startswith(text,"\"")),index+1
    elseif token.spelling == "<"
        closing = index+1
        while closing <= length(tokens) && tokens[closing].spelling != ">"
            closing += 1
        end
        closing > length(tokens) && throw(DirectiveError("missing terminating > character"))
        text = "<" * render(tokens[index+1:closing-1]) * ">"
        return HeaderSpecification(text,text[2:end-1],false),closing+1
    end
    nothing,index
end
decimal_token(token) = token.kind == "number" && all(digit,token.spelling)
mutable struct Preprocessor
    macros::Dict{String,MacroDefinition}
    ever_defined::Set{String}
    saved::Dict{String,Vector{Union{Nothing,MacroDefinition}}}
    poisoned::Set{String}
    manager::IncludeManager
    expander::Union{Nothing,Expander}
    output::Vector{String}
    history::Vector{String}
    diagnostics::Vector{String}
    tree::Vector{String}
    conditional_records::Vector{String}
    regions::Vector{String}
    diagnostic_counts::Dict{String,Int}
    condition_counts::Dict{String,Int}
    previous::Tuple{String,Int}
end
function Preprocessor()
    processor = Preprocessor(Dict{String,MacroDefinition}(),Set{String}(),Dict{String,Vector{Union{Nothing,MacroDefinition}}}(),Set{String}(),IncludeManager(),nothing,
        String[],String[],String[],["main.c"],String[],String[],Dict{String,Int}(),Dict{String,Int}(),("main.c",0))
    processor.expander = Expander(processor.macros,(position,kind,message) -> diagnostic!(processor,position,kind,message))
    processor
end
function diagnostic!(processor,position,kind,message)
    filename,line = position
    push!(processor.diagnostics,"$filename:$line: $kind: $message")
    processor.diagnostic_counts[kind] = get(processor.diagnostic_counts,kind,0)+1
end
function event!(processor,position,content)
    filename,line = position
    push!(processor.history,"$filename:$line: $content")
end
function poison_check!(processor,context,tokens)
    for token in tokens
        if token.kind == "identifier" && token.spelling in processor.poisoned
            diagnostic!(processor,display_position(context,token.line),"error","attempt to use poisoned \"$(token.spelling)\"")
        end
    end
end
function unused_check!(processor,definition)
    definition.main_file && definition.expanded == 0 && definition.tested == 0 && diagnostic!(processor,definition.position,"warning","macro \"$(definition.name)\" is not used")
end
function define_macro!(processor,tokens,position,main_file)
    definition = nothing
    try
        definition = parse_definition(tokens,position,main_file)
    catch error
        error isa DefinitionError || rethrow()
        diagnostic!(processor,position,"error",error.message)
        return
    end
    previous = get(processor.macros,definition.name,nothing)
    if previous === nothing
        processor.macros[definition.name] = definition
        push!(processor.ever_defined,definition.name)
        operation = "define"
    elseif identical_definition(previous,definition)
        operation = "identical"
    else
        unused_check!(processor,previous)
        filename,line = previous.position
        diagnostic!(processor,position,"warning","\"$(definition.name)\" redefined (previous definition at $filename:$line)")
        processor.macros[definition.name] = definition
        push!(processor.ever_defined,definition.name)
        operation = "redefine"
    end
    event!(processor,position,operation * " " * signature(definition))
end
function undefine_macro!(processor,tokens,position)
    error = check_macro_name(tokens,"undef")
    if error !== nothing
        diagnostic!(processor,position,"error",error)
        return
    end
    length(tokens) >= 2 && diagnostic!(processor,position,"warning","extra tokens at end of #undef directive")
    name = tokens[1].spelling
    if haskey(processor.macros,name)
        unused_check!(processor,processor.macros[name])
        delete!(processor.macros,name)
        event!(processor,position,"undef " * name)
    else
        event!(processor,position,"undef " * name * " (not defined)")
    end
end
function process_defines!(processor)
    for (number,line) in enumerate(readlines("input/defines.txt"))
        isempty(line) && continue
        if occursin('=',line)
            name,value = split(line,'=';limit=2)
            text = name * " " * value
        else
            text = line * " 1"
        end
        define_macro!(processor,lex_definition(text,number),("defines.txt",number),false)
    end
end
function marker!(processor,filename,line,flag=nothing)
    text = "# $line \"$filename\""
    flag === nothing || (text *= " $flag")
    push!(processor.output,text)
    processor.previous = (filename,line-1)
end
function output_line!(processor,context,physical,text)
    filename,line = display_position(context,physical)
    previous_file,previous_line = processor.previous
    if filename == previous_file && previous_line < line <= previous_line+8
        append!(processor.output,fill("",line-previous_line-1))
    else
        marker!(processor,filename,line)
    end
    push!(processor.output,text)
    processor.previous = (filename,line)
    context.source.output_lines += 1
end
function flush_segment!(processor,context)
    segment = context.segment
    context.segment = PPToken[]
    isempty(segment) && return
    poison_check!(processor,context,segment)
    expanded = expand!(processor.expander,segment,context)
    index = 1
    while index <= length(expanded)
        last = index+1
        while last <= length(expanded) && expanded[last].line == expanded[index].line
            last += 1
        end
        output_line!(processor,context,expanded[index].line,output_render(expanded[index:last-1]))
        index = last
    end
end
function macro_defined!(processor,name)
    if haskey(processor.macros,name)
        processor.macros[name].tested += 1
        return true
    end
    name in BUILTINS || name == "__has_include"
end
function replace_operators!(processor,context,operands)
    replaced,index = PPToken[],1
    while index <= length(operands)
        token = operands[index]
        if token.kind == "identifier" && token.spelling == "defined"
            next = index+1
            parenthesized = next <= length(operands) && operands[next].spelling == "("
            parenthesized && (next += 1)
            (next > length(operands) || operands[next].kind != "identifier") && throw(DirectiveError("operator \"defined\" requires an identifier"))
            name = operands[next].spelling
            next += 1
            if parenthesized
                (next > length(operands) || operands[next].spelling != ")") && throw(DirectiveError("missing ')' after \"defined\""))
                next += 1
            end
            value = macro_defined!(processor,name)
        elseif token.kind == "identifier" && token.spelling == "__has_include"
            next = index+1
            (next > length(operands) || operands[next].spelling != "(") && throw(DirectiveError("missing '(' after \"__has_include\""))
            header,next = header_specification(operands,next+1)
            (header === nothing || isempty(header.name)) && throw(DirectiveError("operator \"__has_include\" requires a header-name"))
            (next > length(operands) || operands[next].spelling != ")") && throw(DirectiveError("missing ')' after \"__has_include\" operand"))
            next += 1
            value = search_header(header.name,header.quoted) !== nothing
        else
            push!(replaced,token)
            index += 1
            continue
        end
        push!(replaced,PPToken("number",string(Int(value)),token.line,token.space))
        index = next
    end
    replaced
end
function test_condition!(processor,context,logical,name,operands)
    position = display_position(context,logical.tokens[1].line)
    poison_check!(processor,context,operands)
    if !(name in ("if","elif"))
        if isempty(operands)
            diagnostic!(processor,position,"error","no macro name given in #$name directive")
            return nothing,nothing
        elseif operands[1].kind != "identifier"
            diagnostic!(processor,position,"error","macro names must be identifiers")
            return nothing,nothing
        end
        length(operands) >= 2 && diagnostic!(processor,position,"warning","extra tokens at end of #$name directive")
        defined = macro_defined!(processor,operands[1].spelling)
        return Int(name in ("ifndef","elifndef") ? !defined : defined),nothing
    end
    replaced = PPToken[]
    try
        replaced = replace_operators!(processor,context,operands)
    catch error
        error isa DirectiveError || rethrow()
        diagnostic!(processor,position,"error",error.message)
        return nothing,nothing
    end
    expanded = expand!(processor.expander,replaced,context)
    try
        tree = parse_expression(expanded,name)
        value = evaluate_expression(tree,message -> diagnostic!(processor,position,"warning",message))
        return value,expanded
    catch error
        error isa ExpressionError || rethrow()
        diagnostic!(processor,position,"error",error.message)
        return nothing,expanded
    end
end
function test_description(name,value,expanded)
    if value === nothing
        description = "not taken (error)"
    else
        description = value != 0 ? "taken" : "not taken"
        name in ("if","elif") && (description *= " (value $value)")
    end
    expanded === nothing || (description *= " [" * output_render(expanded) * "]")
    description
end
function close_region!(processor,context,block,last)
    start = block.skip_start
    if start !== nothing && last >= start
        filename,first = display_position(context,start)
        stop = display_position(context,last)[2]
        push!(processor.regions,"$filename:$first-$stop lines=$(last-start+1)")
        context.source.skipped_lines += last-start+1
    end
    block.skip_start = nothing
end
function conditional_record!(processor,position,depth,name,operands,description)
    filename,line = position
    directive = "#" * name * (isempty(operands) ? "" : " " * render(operands))
    push!(processor.conditional_records,"$filename:$line: " * repeat("  ",depth) * directive * " => " * description)
    for (prefix,category) in [("taken","taken"),("not taken","not_taken"),("skipped","skipped"),("not evaluated","not_evaluated"),("closes","endif")]
        if startswith(description,prefix)
            processor.condition_counts[category] = get(processor.condition_counts,category,0)+1
            break
        end
    end
end
function process_conditional!(processor,context,logical,name,operands)
    position = display_position(context,logical.tokens[1].line)
    if name in STARTS
        parent = isempty(context.stack) || context.stack[end].active
        block = ConditionalBlock(name,position,parent,false,false,false,nothing)
        if parent
            value,expanded = test_condition!(processor,context,logical,name,operands)
            if value !== nothing && value != 0
                block.chosen,block.active = true,true
            else
                block.skip_start = logical.stop+1
            end
            description = test_description(name,value,expanded)
        else
            description = "skipped"
        end
        conditional_record!(processor,position,length(context.stack),name,operands,description)
        push!(context.stack,block)
        return
    end
    if isempty(context.stack)
        diagnostic!(processor,position,"error","#$name without #if")
        return
    end
    block,depth = context.stack[end],length(context.stack)-1
    close_region!(processor,context,block,logical.start-1)
    if name == "endif"
        pop!(context.stack)
        block.parent && !isempty(operands) && diagnostic!(processor,position,"warning","extra tokens at end of #endif directive")
        description = "closes #$(block.kind) at line $(block.position[2])"
    else
        block.else_seen && diagnostic!(processor,position,"error","#$name after #else")
        if name == "else"
            block.parent && !isempty(operands) && diagnostic!(processor,position,"warning","extra tokens at end of #else directive")
            block.else_seen = true
            if block.parent
                block.active,block.chosen = !block.chosen,true
                description = block.active ? "taken" : "not taken"
            else
                block.active,description = false,"skipped"
            end
        elseif !block.parent
            block.active,description = false,"skipped"
        elseif block.chosen
            block.active,description = false,"not evaluated"
        else
            value,expanded = test_condition!(processor,context,logical,name,operands)
            block.active = value !== nothing && value != 0
            block.active && (block.chosen = true)
            description = test_description(name,value,expanded)
        end
        block.parent && !block.active && (block.skip_start = logical.stop+1)
    end
    conditional_record!(processor,position,depth,name,operands,description)
end
function include_file!(processor,context,logical,operands)
    position = display_position(context,logical.tokens[1].line)
    header = nothing
    try
        sequence = operands
        header,consumed = header_specification(sequence)
        if header === nothing && !isempty(sequence)
            sequence = expand!(processor.expander,sequence,context)
            header,consumed = header_specification(sequence)
        end
        header === nothing && throw(DirectiveError("#include expects \"FILENAME\" or <FILENAME>"))
        consumed <= length(sequence) && diagnostic!(processor,position,"warning","extra tokens at end of #include directive")
        isempty(header.name) && throw(DirectiveError("empty filename in #include"))
    catch error
        error isa DirectiveError || rethrow()
        diagnostic!(processor,position,"error",error.message)
        return
    end
    prefix = repeat("  ",context.depth+1) * string(logical.tokens[1].line) * ": "
    path = search_header(header.name,header.quoted)
    if path === nothing
        push!(processor.tree,prefix * header.rendering * " [not found]")
        diagnostic!(processor,position,"error","cannot find include file " * header.rendering)
        return
    end
    previous = get(processor.manager.files,path,nothing)
    if previous !== nothing && previous.once
        push!(processor.tree,prefix * path * " [skipped: pragma once]")
        previous.skipped += 1
        return
    elseif previous !== nothing && previous.guard !== nothing && haskey(processor.macros,previous.guard)
        push!(processor.tree,prefix * path * " [skipped: guard $(previous.guard)]")
        previous.skipped += 1
        return
    elseif context.depth+1 > 8
        push!(processor.tree,prefix * path * " [too deep]")
        diagnostic!(processor,position,"error","#include nested too deeply")
        return
    end
    push!(processor.tree,prefix * path)
    marker!(processor,path,1,1)
    process_file!(processor,path,context.depth+1)
    filename,line = display_position(context,logical.stop+1)
    marker!(processor,filename,line,2)
end
function line_directive!(processor,context,logical,operands)
    position = display_position(context,logical.tokens[1].line)
    if isempty(operands) || !decimal_token(operands[1])
        operands = expand!(processor.expander,operands,context)
    end
    if !(length(operands) in (1,2)) || !decimal_token(operands[1]) || (length(operands) == 2 && operands[2].kind != "string")
        diagnostic!(processor,position,"error","invalid #line directive")
        return
    end
    line = parse(Int64,operands[1].spelling)
    if !(1 <= line <= 2147483647)
        diagnostic!(processor,position,"error","line number out of range")
        return
    end
    context.offset = line-(logical.stop+1)
    length(operands) == 2 && (context.display_file = operands[2].spelling[2:end-1])
end
function macro_pragma!(processor,position,operands,operation)
    if length(operands) != 4 || operands[2].spelling != "(" || operands[3].kind != "string" || operands[4].spelling != ")"
        diagnostic!(processor,position,"error","invalid #pragma $operation directive")
        return
    end
    name = operands[3].spelling[2:end-1]
    saved = get!(() -> Union{Nothing,MacroDefinition}[],processor.saved,name)
    if operation == "push_macro"
        push!(saved,get(processor.macros,name,nothing))
        event!(processor,position,"push " * name)
    elseif isempty(saved)
        diagnostic!(processor,position,"warning","no matching push_macro for \"$name\"")
    else
        definition = pop!(saved)
        if definition === nothing
            delete!(processor.macros,name)
            event!(processor,position,"pop " * name * " (undefined)")
        else
            processor.macros[name] = definition
            event!(processor,position,"pop " * name)
        end
    end
end
function pragma_directive!(processor,context,logical,operands)
    position = display_position(context,logical.tokens[1].line)
    name = !isempty(operands) && operands[1].kind == "identifier" ? operands[1].spelling : nothing
    if name == "once"
        length(operands) >= 2 && diagnostic!(processor,position,"warning","extra tokens at end of #pragma once directive")
        context.depth == 0 && diagnostic!(processor,position,"warning","#pragma once in main file")
        context.source.once = true
    elseif length(operands) >= 2 && operands[1].spelling == "GCC" && operands[2].spelling == "poison"
        if any(token.kind != "identifier" for token in operands[3:end])
            diagnostic!(processor,position,"error","invalid #pragma GCC poison directive")
            return
        end
        for token in operands[3:end]
            haskey(processor.macros,token.spelling) && diagnostic!(processor,position,"warning","poisoning existing macro \"$(token.spelling)\"")
            push!(processor.poisoned,token.spelling)
        end
    elseif name in ("push_macro","pop_macro")
        macro_pragma!(processor,position,operands,name)
    else
        output_line!(processor,context,logical.tokens[1].line,"#pragma" * (isempty(operands) ? "" : " " * render(operands)))
    end
end
function process_directive!(processor,context,logical,name,operands)
    length(logical.tokens) == 1 && return
    poisoning = name == "pragma" && length(operands) >= 2 && operands[1].spelling == "GCC" && operands[2].spelling == "poison"
    poisoning || poison_check!(processor,context,operands)
    position = display_position(context,logical.tokens[1].line)
    if name == "define"
        define_macro!(processor,operands,position,context.depth == 0)
    elseif name == "undef"
        undefine_macro!(processor,operands,position)
    elseif name == "include"
        include_file!(processor,context,logical,operands)
    elseif name == "line"
        line_directive!(processor,context,logical,operands)
    elseif name in ("error","warning")
        diagnostic!(processor,position,name,"#" * name * (isempty(operands) ? "" : " " * render(operands)))
    elseif name == "pragma"
        pragma_directive!(processor,context,logical,operands)
    else
        diagnostic!(processor,position,"error","invalid preprocessing directive #" * logical.tokens[2].spelling)
    end
end
function process_file!(processor,path,depth)
    source = load_source!(processor.manager,path)
    source.entered += 1
    context = Inclusion(source,depth)
    for logical in source.lines
        tokens = logical.tokens
        is_directive = !isempty(tokens) && tokens[1].spelling == "#"
        name = directive_name(tokens)
        operands = tokens[min(3,length(tokens)+1):end]
        if is_directive && name in CONDITIONALS
            flush_segment!(processor,context)
            process_conditional!(processor,context,logical,name,operands)
        elseif skipping(context)
            continue
        elseif is_directive
            flush_segment!(processor,context)
            process_directive!(processor,context,logical,name,operands)
        else
            append!(context.segment,tokens)
        end
    end
    flush_segment!(processor,context)
    for block in context.stack
        close_region!(processor,context,block,source.physical_lines)
    end
    for block in context.stack
        diagnostic!(processor,block.position,"error","unterminated #" * block.kind)
    end
end
function include_report(processor)
    lines = [processor.tree;"";"== files =="]
    for path in sort(collect(keys(processor.manager.files)))
        source = processor.manager.files[path]
        guard = source.guard === nothing ? "-" : source.guard
        once = source.once ? "yes" : "no"
        push!(lines,"$path entered=$(source.entered) skipped=$(source.skipped) lines=$(source.physical_lines) output_lines=$(source.output_lines) skipped_lines=$(source.skipped_lines) guard=$guard once=$once")
    end
    push!(lines,"")
    current,has_path = "main.o:",false
    for path in processor.manager.order
        if length(current)+1+length(path) > 76 && has_path
            push!(lines,current * " \\")
            current,has_path = " ",false
        end
        current *= " " * path
        has_path = true
    end
    push!(lines,current)
    lines
end
function macro_references(processor)
    references = Dict{String,Vector{String}}()
    for (name,definition) in processor.macros
        parameters = definition.parameters === nothing ? Set{String}() : Set(definition.parameters)
        references[name] = sort(unique([token.spelling for token in definition.replacement if token.kind == "identifier" && haskey(processor.macros,token.spelling) && !(token.spelling in parameters)]))
    end
    references
end
function macro_recursive(name,references)
    pending,seen = copy(references[name]),Set{String}()
    while !isempty(pending)
        current = pop!(pending)
        current == name && return true
        if !(current in seen)
            push!(seen,current)
            append!(pending,references[current])
        end
    end
    false
end
function macro_report(processor)
    lines = ["== history ==";processor.history;"";"== table =="]
    references = macro_references(processor)
    for name in sort(collect(keys(processor.macros)))
        definition = processor.macros[name]
        text = "#define " * signature(definition)
        isempty(definition.replacement) || (text *= " " * render(definition.replacement))
        push!(lines,text)
        filename,line = definition.position
        recursive = macro_recursive(name,references) ? "yes" : "no"
        push!(lines,"  at $filename:$line expanded=$(definition.expanded) tested=$(definition.tested) recursive=$recursive")
        push!(lines,following("  refs:",references[name]))
    end
    object_like = count(definition -> definition.parameters === nothing,values(processor.macros))
    append!(lines,["","macros=$(length(processor.macros)) object_like=$object_like function_like=$(length(processor.macros)-object_like)"])
    push!(lines,following("undefined:",sort(collect(setdiff(processor.ever_defined,keys(processor.macros))))))
    counts = processor.expander.builtin_counts
    push!(lines,"builtins: __COUNTER__=$(get(counts,"__COUNTER__",0)) __FILE__=$(get(counts,"__FILE__",0)) __LINE__=$(get(counts,"__LINE__",0))")
    lines
end
function conditional_report(processor)
    lines = [processor.conditional_records;"";"== skipped regions ==";processor.regions;""]
    counts = processor.condition_counts
    push!(lines,"directives=$(length(processor.conditional_records)) taken=$(get(counts,"taken",0)) not_taken=$(get(counts,"not_taken",0)) skipped=$(get(counts,"skipped",0)) not_evaluated=$(get(counts,"not_evaluated",0)) endif=$(get(counts,"endif",0)) regions=$(length(processor.regions))")
    lines
end
function write_reports(processor)
    diagnostic_lines = [processor.diagnostics;"errors=$(get(processor.diagnostic_counts,"error",0)) warnings=$(get(processor.diagnostic_counts,"warning",0))"]
    reports = [("preprocessed.txt",processor.output),("includes.txt",include_report(processor)),("macros.txt",macro_report(processor)),
        ("conditionals.txt",conditional_report(processor)),("diagnostics.txt",diagnostic_lines)]
    mkpath("output")
    for (name,lines) in reports
        write(joinpath("output",name),join([rstrip(c -> c == ' ',line) for line in lines],"\n") * "\n")
    end
end
function main()
    processor = Preprocessor()
    process_defines!(processor)
    marker!(processor,"main.c",1)
    process_file!(processor,"main.c",0)
    for name in sort(collect(keys(processor.macros)))
        unused_check!(processor,processor.macros[name])
    end
    write_reports(processor)
end
main()
