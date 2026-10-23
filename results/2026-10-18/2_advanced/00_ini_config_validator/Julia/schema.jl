function split_key(key)
    dot = findlast(==('.'), key)
    (String(key[1:dot-1]), String(key[dot+1:end]))
end

section_of(key) = split_key(key)[1]
ordered_keys(keys) = sort!(collect(keys); by=split_key)

struct Spec
    line::Int
    pattern::String
    kind::String
    key::String
    section_parts::Vector{String}
    wildcard::Bool
    attributes::Dict{String,String}
end

function Spec(line, words)
    section, key = split_key(words[1])
    parts = String.(split(section, '.'))
    attributes = Dict{String,String}()
    for word in words[3:end]
        pair = split(word, '='; limit=2, keepempty=true)
        attributes[pair[1]] = length(pair) == 2 ? pair[2] : ""
    end
    Spec(line, words[1], words[2], key, parts, "*" in parts, attributes)
end

has_attribute(spec, name) = haskey(spec.attributes, name)
attribute(spec, name, default=nothing) = get(spec.attributes, name, default)
enum_values(spec) = has_attribute(spec, "values") ? String.(split(attribute(spec, "values"), ',')) : String[]

function matches_section(spec, section)
    parts = split(section, '.')
    length(parts) == length(spec.section_parts) &&
        all(pattern == "*" || pattern == part for (pattern, part) in zip(spec.section_parts, parts))
end

struct Schema
    specs::Vector{Spec}
    exact::Dict{String,Spec}
end

function load_schema(path)
    specs = Spec[]
    for (number, line) in enumerate(readlines(path))
        if !isempty(space_trim(line)) && !startswith(line, "#")
            push!(specs, Spec(number, String.(split(line, ' '; keepempty=true))))
        end
    end
    exact = Dict{String,Spec}(spec.pattern => spec for spec in specs if !spec.wildcard)
    Schema(specs, exact)
end

function spec_for(schema, key)
    haskey(schema.exact, key) && return schema.exact[key]
    section, name = split_key(key)
    for spec in schema.specs
        if spec.wildcard && spec.key == name && matches_section(spec, section)
            return spec
        end
    end
    nothing
end

function target_keys(schema, spec, sections)
    !spec.wildcard && return [spec.pattern]
    result = String[]
    for section in sort!(collect(sections))
        key = section * "." * spec.key
        if matches_section(spec, section) && spec_for(schema, key) === spec
            push!(result, key)
        end
    end
    result
end
