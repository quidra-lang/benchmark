include("object_parser.jl")
include("archive.jl")
include("resolver.jl")
include("layout.jl")
include("relocator.jl")
hexadecimal(value,digits=8) = string(value;base=16,pad=digits)
little_bytes(value,width) = UInt8[(value >> (8*index)) & 0xff for index in 0:width-1]
struct LinkScript
    entry::String
    gc::Bool
    segments::Vector{Segment}
    loads::Vector{Tuple{String,String}}
    kept::Set{String}
    sorted::Set{String}
    wrapped::Set{String}
    defines::Vector{Tuple{String,String}}
    checksum::Union{Nothing,Tuple{String,String}}
    inputs::Vector{Tuple{String,Vector{String}}}
    segment_names::Dict{String,Segment}
    outputs::Vector{OutputSection}
    output_names::Dict{String,OutputSection}
    script_names::Set{String}
end
function LinkScript(lines)
    entry,gc = "",false
    segments,loads = Segment[],Tuple{String,String}[]
    kept,sorted,wrapped = Set{String}(),Set{String}(),Set{String}()
    defines,checksum,inputs = Tuple{String,String}[],nothing,Tuple{String,Vector{String}}[]
    for line in lines
        if startswith(line,"define ")
            head,expression = split(line," = ";limit=2)
            push!(defines,(split(head,' ')[2],expression))
            continue
        end
        words = split(line,' ')
        kind = words[1]
        if kind == "entry"
            entry = words[2]
        elseif kind == "gc"
            gc = words[2] == "on"
        elseif kind == "segment"
            push!(segments,Segment(words[2],parse(Int64,words[3][3:end];base=16),parse(Int64,words[4][3:end];base=16),parse(Int,words[5][3:end];base=16),words[6:end]))
        elseif kind == "load"
            push!(loads,(words[2],words[3]))
        elseif kind == "keep"
            push!(kept,words[2])
        elseif kind == "sort"
            push!(sorted,words[2])
        elseif kind == "wrap"
            push!(wrapped,words[2])
        elseif kind == "checksum"
            checksum = (words[2],words[3])
        else
            push!(inputs,(kind,String.(words[2:end])))
        end
    end
    segment_names = Dict(segment.name=>segment for segment in segments)
    outputs = [output for segment in segments for output in segment.outputs]
    output_names = Dict(output.name=>output for output in outputs)
    script_names = Set{String}(name for (name,expression) in defines)
    LinkScript(entry,gc,segments,loads,kept,sorted,wrapped,defines,checksum,inputs,segment_names,outputs,output_names,script_names)
end
mutable struct MergedStrings <: LinkComponent
    kind::String
    sections::Vector{LinkSection}
    alignment::Int
    address::Int64
    contents::Vector{UInt8}
    strings::Int
    size::Int
    unique::Int
    saved::Int
end
function MergedStrings(sections)
    merged = MergedStrings("merged",sections,1,0,UInt8[],0,0,0,0)
    positions = Dict{String,Int}()
    original_size = 0
    for section in sections
        section.merged = merged
        original_size += section.size
        start = 1
        while start <= section.size
            last = findnext(==(0x00),section.contents,start)
            bytes = section.contents[start:last]
            key = bytes2hex(bytes)
            if !haskey(positions,key)
                positions[key] = length(merged.contents)
                append!(merged.contents,bytes)
            end
            section.merged_positions[start-1] = positions[key]
            merged.strings += 1
            start = last+1
        end
    end
    merged.size,merged.unique = length(merged.contents),length(positions)
    merged.saved = original_size-merged.size
    merged
end
mutable struct Veneer <: LinkComponent
    kind::String
    output::OutputSection
    name::String
    size::Int
    alignment::Int
    address::Int64
end
Veneer(output,name) = Veneer("veneer",output,name,8,4,0)
mutable struct ScriptExpression
    tokens::Vector{String}
    index::Int
    outputs::Dict{String,OutputSection}
    values::Dict{String,Int64}
end
ScriptExpression(text,outputs,values) = ScriptExpression([String(match.match) for match in eachmatch(r"0x[0-9a-f]+|[0-9]+|[A-Za-z_.][A-Za-z0-9_.]*|[(),+-]",text)],1,outputs,values)
function take_expression_token!(parser)
    token = parser.tokens[parser.index]
    parser.index += 1
    token
end
function script_expression!(parser)
    value = script_term!(parser)
    while parser.index <= length(parser.tokens) && parser.tokens[parser.index] in ("+","-")
        operator = take_expression_token!(parser)
        right = script_term!(parser)
        value = operator == "+" ? value+right : value-right
    end
    value
end
function script_term!(parser)
    token = take_expression_token!(parser)
    if token == "("
        value = script_expression!(parser)
        take_expression_token!(parser)
        return value
    elseif '0' <= token[1] <= '9'
        return startswith(token,"0x") ? parse(Int64,token[3:end];base=16) : parse(Int64,token)
    elseif parser.index > length(parser.tokens) || parser.tokens[parser.index] != "("
        return parser.values[token]
    end
    take_expression_token!(parser)
    if token == "align"
        value = script_expression!(parser)
        take_expression_token!(parser)
        alignment = script_expression!(parser)
        take_expression_token!(parser)
        return align_address(value,alignment)
    end
    output = parser.outputs[take_expression_token!(parser)]
    take_expression_token!(parser)
    token == "start" && return output.address
    token == "end" && return output.address+output.size
    token == "size" && return output.size
    output.segment.paddr+output.address-output.segment.base
end
mutable struct Linker
    script::LinkScript
    objects::Vector{LinkObject}
    entries::Dict{String,Vector{LinkSymbol}}
    archives::Dict{String,Vector{ArchiveMember}}
    comdats::Dict{String,Tuple{String,Vector{String}}}
    comdat_order::Vector{String}
    extractions::Vector{Tuple{String,String,String}}
    orphans::Dict{String,Int}
    script_values::Dict{String,Int64}
    veneers::Dict{Tuple{String,String},Veneer}
    far_calls::Set{Relocation}
    applied::Vector{Relocation}
    relocation_counts::Dict{String,Dict{String,Int}}
    names::Dict{String,Resolution}
    commons::Vector{Resolution}
    candidates::Vector{LinkSection}
end
function Linker(script)
    Linker(script,LinkObject[],Dict{String,Vector{LinkSymbol}}(),Dict{String,Vector{ArchiveMember}}(),Dict{String,Tuple{String,Vector{String}}}(),String[],
        Tuple{String,String,String}[],Dict{String,Int}(),Dict{String,Int64}(),Dict{Tuple{String,String},Veneer}(),Set{Relocation}(),Relocation[],
        Dict(type=>Dict{String,Int}() for type in TYPES),Dict{String,Resolution}(),Resolution[],LinkSection[])
end
function symbol_defined(linker,name)
    name in linker.script.script_names || any(entry.kind in ("defined","common") for entry in get(linker.entries,name,LinkSymbol[]))
end
function symbol_undefined(linker,name)
    symbol_defined(linker,name) && return false
    name == linker.script.entry || any(entry.kind == "undefined" && entry.binding == "global" for entry in get(linker.entries,name,LinkSymbol[]))
end
function load_object!(linker,object)
    object.order = length(linker.objects)
    for (signature,sections) in object.comdats
        if haskey(linker.comdats,signature)
            push!(linker.comdats[signature][2],object.name)
            for section in sections
                section.discard_reason = "comdat"
            end
        else
            linker.comdats[signature] = (object.name,String[])
            push!(linker.comdat_order,signature)
        end
    end
    for symbol in object.symbols
        if symbol.binding != "local" && symbol.kind == "defined" && symbol.section.discard_reason == "comdat"
            symbol.kind,symbol.section = "undefined",nothing
        end
    end
    for symbol in object.symbols
        if symbol.kind == "undefined"
            if symbol.name in linker.script.wrapped
                symbol.name = "__wrap_" * symbol.name
            elseif startswith(symbol.name,"__real_") && symbol.name[8:end] in linker.script.wrapped
                symbol.name = symbol.name[8:end]
            end
        end
    end
    object.symbol_names = Dict(symbol.name=>symbol for symbol in object.symbols)
    for symbol in object.symbols
        symbol.binding == "local" && continue
        push!(get!(() -> LinkSymbol[],linker.entries,symbol.name),symbol)
    end
    push!(linker.objects,object)
end
function extract_member!(linker,object,reason)
    references = [entry for entry in get(linker.entries,reason,LinkSymbol[]) if entry.kind == "undefined" && entry.binding == "global"]
    referrer = isempty(references) ? "*entry*" : references[1].owner.name
    push!(linker.extractions,(object.name,referrer,reason))
    load_object!(linker,object)
end
function scan_library!(linker,name)
    if !haskey(linker.archives,name)
        linker.archives[name] = read_archive(joinpath("input",name))
    end
    scan_archive!(linker.archives[name],symbol -> symbol_undefined(linker,symbol),(object,reason) -> extract_member!(linker,object,reason))
end
function load_inputs!(linker)
    for (kind,names) in linker.script.inputs
        if kind == "object"
            load_object!(linker,read_object(joinpath("input",names[1])))
        elseif kind == "library"
            scan_library!(linker,names[1])
        else
            while true
                extracted = 0
                for name in names
                    extracted += scan_library!(linker,name)
                end
                extracted == 0 && break
            end
        end
    end
    linker.names = resolve_names(linker.entries,linker.script.script_names)
    linker.commons = [linker.names[name] for name in sort(collect(keys(linker.names))) if linker.names[name].kind == "common"]
end
function assign_outputs!(linker)
    for object in linker.objects, section in object.sections
        section.discard_reason == "comdat" && continue
        section.output = find_output(section.name,linker.script.outputs)
        if section.output === nothing
            section.discard_reason = "orphan"
            linker.orphans[section.name] = get(linker.orphans,section.name,0)+1
        else
            push!(section.output.sections,section)
            push!(linker.candidates,section)
        end
    end
end
function relocation_target(linker,symbol)
    symbol.binding == "local" && return symbol.section
    resolution = linker.names[symbol.name]
    resolution.kind in ("global","weak") && return resolution.definition.section
    resolution.kind == "common" ? resolution : nothing
end
function collect_garbage!(linker)
    units = Set{LinkComponent}([linker.candidates;linker.commons])
    if !linker.script.gc
        for unit in units
            unit.live = true
        end
    else
        pending = Union{Nothing,LinkComponent}[section for section in linker.candidates if section.output.name in linker.script.kept]
        entry = get(linker.names,linker.script.entry,nothing)
        if entry !== nothing
            entry.kind in ("global","weak") && push!(pending,entry.definition.section)
            entry.kind == "common" && push!(pending,entry)
        end
        while !isempty(pending)
            unit = pop!(pending)
            (unit === nothing || !(unit in units) || unit.live) && continue
            unit.live = true
            unit.kind == "input" && append!(pending,[relocation_target(linker,r.symbol) for r in unit.relocations])
        end
    end
    for section in linker.candidates
        section.live || (section.discard_reason = "gc")
    end
    for object in linker.objects
        unresolved = Set{String}()
        for section in object.sections
            section.live || continue
            for relocation in section.relocations
                symbol = relocation.symbol
                symbol.binding != "local" && linker.names[symbol.name].kind == "undefined" && push!(unresolved,symbol.name)
            end
        end
        for name in unresolved
            push!(linker.names[name].unresolved_referrers,object.name)
        end
    end
end
function build_components!(linker)
    for output in linker.script.outputs
        sections = [section for section in output.sections if section.live]
        if output.name in linker.script.sorted
            sort!(sections;by=section -> section.name == output.name ? 65536 : parse(Int,section.name[length(output.name)+2:end]),alg=MergeSort)
        end
        strings = [section for section in sections if section.string]
        merged = isempty(strings) ? nothing : MergedStrings(strings)
        components,inserted = LinkComponent[],false
        for section in sections
            if section.string
                if !inserted
                    push!(components,merged)
                    inserted = true
                end
            else
                push!(components,section)
            end
        end
        if output.name == ".bss"
            commons = [common for common in linker.commons if common.live]
            append!(components,sort(commons;by=common -> (-common.alignment,common.name)))
        end
        output.base_components = components
    end
end
location_address(section,offset) = section.string ? section.merged.address+section.merged_positions[offset] : section.address+offset
definition_address(resolution) = location_address(resolution.definition.section,resolution.definition.offset)
function find_far_calls(linker)
    calls = Set{Relocation}()
    for section in linker.candidates
        section.live || continue
        for relocation in section.relocations
            symbol = relocation.symbol
            (relocation.type != "CALL24" || symbol.binding == "local") && continue
            resolution = linker.names[symbol.name]
            resolution.kind in ("global","weak") || continue
            value = definition_address(resolution)+relocation.addend-section.address-relocation.offset
            -2^25 <= value < 2^25 || push!(calls,relocation)
        end
    end
    calls
end
function perform_layout!(linker)
    build_components!(linker)
    while true
        for output in linker.script.outputs
            veneers = [veneer for ((owner,name),veneer) in linker.veneers if owner == output.name]
            output.components = [output.base_components;sort(veneers;by=veneer -> veneer.name)]
        end
        foreach(assign_segment!,linker.script.segments)
        far_calls = find_far_calls(linker)
        new_pairs = setdiff(Set((r.section.output.name,r.symbol.name) for r in far_calls),Set(keys(linker.veneers)))
        if isempty(new_pairs)
            linker.far_calls = far_calls
            return
        end
        for (output,name) in new_pairs
            linker.veneers[(output,name)] = Veneer(linker.script.output_names[output],name)
        end
    end
end
function load_addresses!(linker)
    storage = Dict(segment.name=>segment.base+segment.memsz for segment in linker.script.segments)
    for (source,destination) in linker.script.loads
        segment = linker.script.segment_names[source]
        segment.paddr = align_address(storage[destination],4)
        storage[destination] = segment.paddr+segment.filesz
    end
    for segment in linker.script.segments
        segment.used = storage[segment.name]-segment.base
    end
end
function evaluate_defines!(linker)
    for (name,text) in linker.script.defines
        parser = ScriptExpression(text,linker.script.output_names,linker.script_values)
        linker.script_values[name] = script_expression!(parser)
    end
end
function symbol_value(linker,symbol)
    symbol.binding == "local" && return location_address(symbol.section,symbol.offset)
    resolution = linker.names[symbol.name]
    resolution.kind in ("global","weak") && return definition_address(resolution)
    resolution.kind == "common" && return resolution.address
    resolution.kind == "script" && return linker.script_values[resolution.name]
    resolution.kind == "weakundef" ? Int64(0) : nothing
end
function entry_address(linker)
    entry = get(linker.names,linker.script.entry,nothing)
    if entry !== nothing
        entry.kind in ("global","weak") && return definition_address(entry)
        entry.kind == "common" && return entry.address
    end
    Int64(0)
end
function apply_relocations!(linker)
    gp = get(linker.script_values,"_gp",Int64(0))
    for output in linker.script.outputs, section in output.components
        section.kind == "input" || continue
        for (index,relocation) in enumerate(section.relocations)
            relocation.place = section.address+relocation.offset
            relocation.unpaired = unpaired_hi16(section.relocations,index)
            relocation.symbol_value = symbol_value(linker,relocation.symbol)
            if relocation.symbol_value === nothing
                relocation.status = "undefined"
            else
                relocation.status = "ok"
                if relocation in linker.far_calls
                    relocation.symbol_value = linker.veneers[(output.name,relocation.symbol.name)].address
                    relocation.status = "veneer"
                end
                value,field,within_range = relocation_value(relocation.type,relocation.symbol_value,relocation.addend,relocation.place,gp)
                relocation.value,relocation.field = value,field
                within_range || (relocation.status = "overflow")
                width = WIDTHS[relocation.type]
                section.contents[relocation.offset+1:relocation.offset+width] = little_bytes(field,width)
            end
            counts = linker.relocation_counts[relocation.type]
            counts[relocation.status] = get(counts,relocation.status,0)+1
            push!(linker.applied,relocation)
        end
    end
end
function build_images!(linker)
    for segment in linker.script.segments
        segment.image = fill(segment.fill,segment.filesz)
        for output in segment.outputs
            output.nobits && continue
            for component in output.components
                if component.kind == "veneer"
                    destination = definition_address(linker.names[component.name])
                    contents = [UInt8[4,240,31,229];little_bytes(destination,4)]
                else
                    contents = component.contents
                end
                start = component.address-segment.base
                segment.image[start+1:start+component.size] = contents
            end
        end
    end
    if linker.script.checksum !== nothing
        segment_name,symbol_name = linker.script.checksum
        segment = linker.script.segment_names[segment_name]
        offset = definition_address(linker.names[symbol_name])-segment.base
        segment.image[offset+1:offset+4] .= 0
        total = Int64(0)
        for start in 0:4:segment.filesz-1
            for index in 0:min(3,segment.filesz-start-1)
                total += Int64(segment.image[start+index+1]) << (8*index)
            end
        end
        segment.image[offset+1:offset+4] = little_bytes(mod(-total,2^32),4)
    end
end
function symbol_rows(linker)
    rows = Tuple{Int64,String,String,String}[]
    for name in sort(collect(keys(linker.names)))
        resolution = linker.names[name]
        if resolution.kind in ("global","weak") && resolution.definition.section.live
            push!(rows,(definition_address(resolution),name,resolution.kind,resolution.definer))
        elseif resolution.kind == "common" && resolution.live
            push!(rows,(resolution.address,name,"common",resolution.definer))
        elseif resolution.kind == "script"
            push!(rows,(linker.script_values[name],name,"script","*script*"))
        end
    end
    for output in linker.script.outputs, component in output.components
        component.kind == "veneer" && push!(rows,(component.address,"__veneer_" * component.name,"veneer","*linker*"))
    end
    sort!(rows;by=row -> (row[1],row[2]))
end
relocation_location(relocation) = "$(relocation.section.owner.name) $(relocation.section.name)+$(relocation.offset)"
segment_heading(segment) = "segment $(segment.name) vaddr $(hexadecimal(segment.base)) paddr $(hexadecimal(segment.paddr)) filesz $(segment.filesz) memsz $(segment.memsz)"
function diagnostics(linker)
    lines = String[]
    for name in sort(collect(keys(linker.orphans)))
        push!(lines,"warning: orphan section $name discarded from $(linker.orphans[name]) object(s)")
    end
    for name in sort(collect(keys(linker.names)))
        resolution = linker.names[name]
        length(resolution.strong_definers) >= 2 && push!(lines,"error: multiple definition of $name: " * join(resolution.strong_definers," "))
        !isempty(resolution.commons) && resolution.kind in ("global","script") && push!(lines,"warning: common symbol $name overridden by $(resolution.definer)")
        pairs = Set((entry.size,entry.alignment) for entry in resolution.commons)
        resolution.kind == "common" && length(pairs) >= 2 && push!(lines,"warning: common symbol $name merged to size $(resolution.size) align $(resolution.alignment)")
    end
    entry = get(linker.names,linker.script.entry,nothing)
    (entry === nothing || entry.kind in ("undefined","weakundef")) && push!(lines,"error: entry symbol $(linker.script.entry) is undefined")
    for name in sort(collect(keys(linker.names)))
        resolution = linker.names[name]
        resolution.kind == "undefined" && !isempty(resolution.unresolved_referrers) && push!(lines,"error: undefined symbol $name referenced by " * join(resolution.unresolved_referrers," "))
    end
    for segment in linker.script.segments
        segment.used > segment.length && push!(lines,"error: segment $(segment.name) overflows its length by $(segment.used-segment.length) bytes")
    end
    for (index,first) in enumerate(linker.script.segments), second in linker.script.segments[index+1:end]
        if first.memsz >= 1 && second.memsz >= 1 && first.base < second.base+second.memsz && second.base < first.base+first.memsz
            push!(lines,"error: segments $(first.name) and $(second.name) overlap")
        end
    end
    for relocation in linker.applied
        location = relocation_location(relocation)
        relocation.unpaired && push!(lines,"error: unpaired HI16 at $location against $(relocation.symbol.name)")
        relocation.status == "overflow" && push!(lines,"error: relocation overflow at $location: $(relocation.type) value $(relocation.value) against $(relocation.symbol.name)")
    end
    errors,warnings = count(line -> startswith(line,"error:"),lines),count(line -> startswith(line,"warning:"),lines)
    push!(lines,"errors $errors warnings $warnings")
    lines
end
function image_dump(linker)
    lines = ["entry $(hexadecimal(entry_address(linker))) $(linker.script.entry)"]
    for segment in linker.script.segments
        push!(lines,segment_heading(segment))
        for start in 0:16:segment.filesz-1
            chunk = segment.image[start+1:min(start+16,segment.filesz)]
            push!(lines,hexadecimal(segment.base+start) * " " * join([hexadecimal(byte,2) for byte in chunk]," "))
        end
    end
    lines
end
function hex_record(type,address,data)
    record = Int64[length(data),fld(address,256),mod(address,256),type,Int64.(data)...]
    push!(record,mod(-sum(record),256))
    ":" * uppercase(join([hexadecimal(byte,2) for byte in record]))
end
function intel_hex(linker)
    lines,upper = String[],0
    for segment in sort(linker.script.segments;by=segment -> segment.paddr,alg=MergeSort)
        start = 0
        while start < segment.filesz
            address = segment.paddr+start
            byte_count = min(16,segment.filesz-start,65536-mod(address,65536))
            if fld(address,65536) != upper
                upper = fld(address,65536)
                push!(lines,hex_record(4,0,[fld(upper,256),mod(upper,256)]))
            end
            push!(lines,hex_record(0,mod(address,65536),segment.image[start+1:start+byte_count]))
            start += byte_count
        end
    end
    push!(lines,hex_record(5,0,reverse(little_bytes(entry_address(linker),4))))
    push!(lines,hex_record(1,0,UInt8[]))
    lines
end
function component_line(component)
    if component.kind == "input"
        return "input $(hexadecimal(component.address)) $(component.size) $(component.alignment) $(component.owner.name) $(component.name)"
    elseif component.kind == "merged"
        return "merged $(hexadecimal(component.address)) $(component.size) sections $(length(component.sections)) strings $(component.strings) unique $(component.unique) saved $(component.saved)"
    elseif component.kind == "common"
        return "common $(hexadecimal(component.address)) $(component.size) $(component.alignment) $(component.definer) $(component.name)"
    end
    "veneer $(hexadecimal(component.address)) 8 $(component.name)"
end
function link_map(linker)
    lines = ["member $name $referrer $reason" for (name,referrer,reason) in linker.extractions]
    for signature in linker.comdat_order
        keeper,discarded = linker.comdats[signature]
        push!(lines,"comdat $signature $keeper " * (isempty(discarded) ? "-" : join(discarded,",")))
    end
    for segment in linker.script.segments
        usage = fld(100*segment.used,segment.length)
        push!(lines,segment_heading(segment) * " used $(segment.used) length $(segment.length) $usage%")
        for output in segment.outputs
            push!(lines,"section $(output.name) $(hexadecimal(output.address)) $(output.size) $(output.alignment)")
            append!(lines,component_line.(output.components))
        end
    end
    for object in linker.objects, section in object.sections
        section.discard_reason === nothing || push!(lines,"discard $(object.name) $(section.name) $(section.size) $(section.discard_reason)")
    end
    for common in sort(linker.commons;by=common -> common.name)
        common.live || push!(lines,"discard $(common.definer) COMMON($(common.name)) $(common.size) gc")
    end
    for (address,name,kind,definer) in symbol_rows(linker)
        push!(lines,"symbol $(hexadecimal(address)) $name $kind $definer")
    end
    lines
end
function cross_references(linker)
    lines = String[]
    for name in sort(collect(keys(linker.names)))
        resolution = linker.names[name]
        if resolution.kind in ("global","weak")
            status = resolution.definition.section.live ? "kept" : "discarded"
        elseif resolution.kind == "common"
            status = resolution.live ? "kept" : "discarded"
        else
            status = resolution.kind == "script" ? "kept" : "-"
        end
        referrers = isempty(resolution.referrers) ? "-" : join(resolution.referrers,",")
        push!(lines,"$name $(resolution.kind) $status $(resolution.definer) $referrers")
    end
    lines
end
function relocation_report(linker)
    lines = String[]
    for relocation in linker.applied
        prefix = "$(hexadecimal(relocation.place)) $(relocation_location(relocation)) $(relocation.type) $(relocation.symbol.name) $(relocation.addend)"
        formatted_values = relocation.status == "undefined" ? "- - -" :
            "$(hexadecimal(relocation.symbol_value)) $(relocation.value) $(hexadecimal(relocation.field,2*WIDTHS[relocation.type]))"
        push!(lines,prefix * " " * formatted_values * " " * relocation.status)
    end
    for type in TYPES
        counts = linker.relocation_counts[type]
        line = "summary $type total $(sum(values(counts)))"
        for status in ("ok","veneer","overflow","undefined")
            line *= " $status $(get(counts,status,0))"
        end
        push!(lines,line)
    end
    lines
end
function main()
    linker = Linker(LinkScript(read_lines("input/link.txt")))
    load_inputs!(linker)
    assign_outputs!(linker)
    collect_garbage!(linker)
    perform_layout!(linker)
    load_addresses!(linker)
    evaluate_defines!(linker)
    apply_relocations!(linker)
    build_images!(linker)
    reports = [("image.hex",image_dump(linker)),("flash.ihex",intel_hex(linker)),("link.map",link_map(linker)),
        ("xref.txt",cross_references(linker)),("relocations.txt",relocation_report(linker)),("diagnostics.txt",diagnostics(linker))]
    mkpath("output")
    for (name,lines) in reports
        write(joinpath("output",name),isempty(lines) ? "" : join(lines,"\n") * "\n")
    end
end
main()
