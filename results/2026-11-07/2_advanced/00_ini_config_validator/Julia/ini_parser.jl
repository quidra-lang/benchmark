is_name(text) = occursin(r"\A[a-z][a-z0-9_]*\z", text)
is_section_name(text) = occursin(r"\A[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*\z", text)

function trimmed_segments(segments)
    result = copy(segments)
    result[1] = String(lstrip(result[1], [' ']))
    result[end] = String(rstrip(result[end], [' ']))
    result
end

struct Statement
    kind::Symbol
    line::Int
    target::String
    value::String
end

struct ParsedDocument
    statements::Vector{Statement}
    diagnostics::Vector{Diagnostic}
end

function parse_document(document, physical)
    statements = Statement[]
    diagnostics = Diagnostic[]
    section = base = nothing
    assigned = Dict{String,Int}()
    report(number, code, message) = push!(diagnostics, (document, number, code, message))
    for line in logical_lines(physical)
        number = line.number
        if line.error !== nothing
            report(number, line.error...)
            continue
        end
        segments = trimmed_segments(line.segments)
        first = segments[1]
        length(segments) == 1 && isempty(first) && continue
        if startswith(first, "[")
            if length(segments) != 1 || !endswith(first, "]")
                report(number, "E_SECTION", "invalid section header")
                section = nothing
                continue
            end
            parts = split(first[2:end-1], ':'; limit=2, keepempty=true)
            header = space_trim(parts[1])
            parent = length(parts) == 2 ? space_trim(parts[2]) : nothing
            relative = startswith(header, ".") && is_section_name(header[2:end])
            if (parent !== nothing && !is_section_name(parent)) ||
               (!relative && !is_section_name(header))
                report(number, "E_SECTION", "invalid section header")
                section = nothing
            elseif relative && base === nothing
                report(number, "E_SECTION", "relative section without base")
                section = nothing
            else
                if relative
                    section = base * header
                else
                    section = base = header
                end
                parent !== nothing && push!(statements, Statement(:inherit, number, section, parent))
            end
            continue
        end
        if startswith(first, "@")
            words = split(first, r" +"; keepempty=false)
            if length(segments) != 1 || length(words) != 2 ||
               !(words[1] in ("@include", "@unset")) || !is_name(words[2])
                report(number, "E_SYNTAX", "invalid directive")
            elseif words[1] == "@include"
                push!(statements, Statement(:include, number, String(words[2]), ""))
            elseif section === nothing
                report(number, "E_NO_SECTION", "no current section")
            else
                push!(statements, Statement(:unset, number, section * "." * words[2], ""))
            end
            continue
        end
        if !any(segment -> occursin('=', segment), segments[1:2:end])
            report(number, "E_SYNTAX", "invalid line")
            continue
        end
        equals = findfirst(==('='), first)
        if equals === nothing
            report(number, "E_SYNTAX", "invalid key")
            continue
        end
        key = space_trim(first[1:equals-1])
        append = endswith(key, "+")
        if append
            key = String(rstrip(key[1:end-1], [' ']))
        end
        if !is_name(key)
            report(number, "E_SYNTAX", "invalid key")
            continue
        end
        segments[1] = first[equals+1:end]
        segments = trimmed_segments(segments)
        if length(segments) == 1
            value = segments[1]
        elseif length(segments) == 3 && isempty(segments[1]) && isempty(segments[3])
            value = segments[2]
        else
            report(number, "E_SYNTAX", "invalid value")
            continue
        end
        if section === nothing
            report(number, "E_NO_SECTION", "no current section")
            continue
        end
        full_key = section * "." * key
        if !append
            if haskey(assigned, full_key)
                report(number, "W_DUPLICATE", "$full_key already set at line $(assigned[full_key])")
            end
            assigned[full_key] = number
        end
        push!(statements, Statement(append ? :append : :assign, number, full_key, value))
    end
    ParsedDocument(statements, diagnostics)
end
