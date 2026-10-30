mutable struct ArchiveMember
    object::LinkObject
    exports::Vector{String}
    loaded::Bool
end
function read_archive(path)
    lines,members,index = read_lines(path),ArchiveMember[],1
    while index <= length(lines)
        header = split(lines[index],' ')
        name = basename(path) * "(" * header[2] * ")"
        object,index = parse_object(lines,index+1,name)
        push!(members,ArchiveMember(object,String.(header[3:end]),false))
    end
    members
end
function scan_archive!(members,is_undefined,extract)
    extracted = 0
    while true
        changed = false
        for member in members
            member.loaded && continue
            reason = findfirst(is_undefined,member.exports)
            reason === nothing && continue
            member.loaded = true
            extract(member.object,member.exports[reason])
            extracted += 1
            changed = true
        end
        changed || return extracted
    end
end
