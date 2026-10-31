belongs(name,prefix) = name == prefix || startswith(name,prefix * ".")
is_nobits(name) = belongs(name,".bss")
is_string_section(name) = belongs(name,".rodata.str")
read_lines(path) = readlines(path)
abstract type LinkObjectBase end
abstract type LinkRelocationBase end
abstract type LinkOutputBase end
abstract type LinkComponent end
mutable struct LinkSection <: LinkComponent
    kind::String
    owner::LinkObjectBase
    name::String
    alignment::Int
    size::Int
    contents::Vector{UInt8}
    nobits::Bool
    string::Bool
    relocations::Vector{LinkRelocationBase}
    discard_reason::Union{Nothing,String}
    output::Union{Nothing,LinkOutputBase}
    live::Bool
    address::Int64
    merged::Union{Nothing,LinkComponent}
    merged_positions::Dict{Int,Int}
end
LinkSection(owner,name,alignment,size) = LinkSection("input",owner,name,alignment,size,UInt8[],is_nobits(name),is_string_section(name),LinkRelocationBase[],nothing,nothing,false,0,nothing,Dict{Int,Int}())
mutable struct LinkSymbol
    owner::LinkObjectBase
    name::String
    binding::String
    kind::String
    section::Union{Nothing,LinkSection}
    offset::Int
    size::Int
    alignment::Int
end
LinkSymbol(owner,name,binding,kind) = LinkSymbol(owner,name,binding,kind,nothing,0,0,1)
mutable struct Relocation <: LinkRelocationBase
    section::LinkSection
    offset::Int
    type::String
    symbol::LinkSymbol
    addend::Int64
    place::Int64
    unpaired::Bool
    symbol_value::Union{Nothing,Int64}
    value::Union{Nothing,Int64}
    field::Union{Nothing,Int64}
    status::String
end
Relocation(section,offset,type,symbol,addend) = Relocation(section,offset,type,symbol,addend,0,false,nothing,nothing,nothing,"")
mutable struct LinkObject <: LinkObjectBase
    name::String
    order::Int
    sections::Vector{LinkSection}
    section_names::Dict{String,LinkSection}
    comdats::Vector{Tuple{String,Vector{LinkSection}}}
    symbols::Vector{LinkSymbol}
    symbol_names::Dict{String,LinkSymbol}
end
LinkObject(name) = LinkObject(name,-1,LinkSection[],Dict{String,LinkSection}(),Tuple{String,Vector{LinkSection}}[],LinkSymbol[],Dict{String,LinkSymbol}())
function parse_object(lines,index,name)
    object = LinkObject(name)
    while lines[index] != "end"
        words = split(lines[index],' ')
        index += 1
        if words[1] == "section"
            section = LinkSection(object,words[2],parse(Int,words[3]),parse(Int,words[4]))
            push!(object.sections,section)
            object.section_names[section.name] = section
            if !section.nobits
                while length(section.contents) < section.size
                    append!(section.contents,hex2bytes(split(lines[index],' ')[2]))
                    index += 1
                end
            end
        elseif words[1] == "comdat"
            push!(object.comdats,(words[2],[object.section_names[name] for name in words[3:end]]))
        elseif words[1] == "symbol"
            kind = words[4] == "undef" ? "undefined" : words[4] == "common" ? "common" : "defined"
            symbol = LinkSymbol(object,words[2],words[3],kind)
            if kind == "common"
                symbol.size,symbol.alignment = parse(Int,words[5]),parse(Int,words[6])
            elseif kind == "defined"
                symbol.section = object.section_names[words[4]]
                symbol.offset = parse(Int,words[5])
            end
            push!(object.symbols,symbol)
            object.symbol_names[symbol.name] = symbol
        elseif words[1] == "reloc"
            section = object.section_names[words[2]]
            symbol = object.symbol_names[words[5]]
            push!(section.relocations,Relocation(section,parse(Int,words[3]),words[4],symbol,parse(Int64,words[6])))
        end
    end
    object,index+1
end
read_object(path) = parse_object(read_lines(path),1,basename(path))[1]
