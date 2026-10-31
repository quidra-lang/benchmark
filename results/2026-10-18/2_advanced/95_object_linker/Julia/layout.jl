align_address(value,alignment) = cld(value,alignment)*alignment
abstract type LinkSegmentBase end
mutable struct OutputSection <: LinkOutputBase
    name::String
    segment::LinkSegmentBase
    nobits::Bool
    sections::Vector{LinkSection}
    base_components::Vector{LinkComponent}
    components::Vector{LinkComponent}
    address::Int64
    size::Int
    alignment::Int
end
OutputSection(name,segment) = OutputSection(name,segment,is_nobits(name),LinkSection[],LinkComponent[],LinkComponent[],0,0,1)
mutable struct Segment <: LinkSegmentBase
    name::String
    base::Int64
    length::Int64
    fill::UInt8
    outputs::Vector{OutputSection}
    paddr::Int64
    filesz::Int
    memsz::Int
    used::Int64
    image::Vector{UInt8}
end
function Segment(name,base,length,fill,output_names)
    segment = Segment(name,base,length,UInt8(fill),OutputSection[],base,0,0,0,UInt8[])
    segment.outputs = [OutputSection(output,segment) for output in output_names]
    segment
end
function find_output(section_name,outputs)
    index = findfirst(output -> belongs(section_name,output.name),outputs)
    index === nothing ? nothing : outputs[index]
end
function assign_segment!(segment)
    cursor = segment.base
    segment.filesz = 0
    for output in segment.outputs
        output.alignment = isempty(output.components) ? 1 : maximum(component.alignment for component in output.components)
        cursor = align_address(cursor,output.alignment)
        output.address = cursor
        for component in output.components
            cursor = align_address(cursor,component.alignment)
            component.address = cursor
            cursor += component.size
        end
        output.size = cursor-output.address
        output.nobits || (segment.filesz = cursor-segment.base)
    end
    segment.memsz = cursor-segment.base
end
