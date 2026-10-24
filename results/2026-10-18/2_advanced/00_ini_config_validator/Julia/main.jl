module IniValidator

include("lexer.jl")
include("ini_parser.jl")
include("schema.jl")
include("interpolate.jl")
include("emitter.jl")

const SIZE_FACTORS = Dict("" => 1, "b" => 1, "kb" => 1024, "mb" => 1048576, "gb" => 1073741824)
const DEFAULT_PORTS = Dict("http" => 80, "https" => 443)

function parse_int(text)
    matched = match(r"\A([+-]?)(?:0[xX]([0-9a-fA-F]{1,10})|([0-9](?:_?[0-9])*))\z", text)
    matched === nothing && return nothing
    sign, hex, decimal = matched.captures
    if hex !== nothing
        value = parse(Int, hex; base=16)
    else
        digits = replace(decimal, "_" => "")
        length(digits) > 12 && return nothing
        value = parse(Int, digits; base=10)
    end
    sign == "-" ? -value : value
end

function parse_size(text)
    matched = match(r"\A([0-9]{1,6})(?:\.([0-9]{1,3}))?([A-Za-z]*)\z", text)
    matched === nothing && return nothing
    whole, fraction, unit = matched.captures
    factor = get(SIZE_FACTORS, lowercase(unit), nothing)
    factor === nothing && return nothing
    value = parse(Int, whole) * factor
    fraction === nothing && return value
    scaled = parse(Int, fraction) * factor
    divisor = 10 ^ length(fraction)
    scaled % divisor == 0 ? value + scaled ÷ divisor : nothing
end

function parse_duration(text)
    occursin(r"\A[0-9]{1,6}\z", text) && return parse(Int, text)
    isempty(text) && return nothing
    matched = match(r"\A(?:([0-9]{1,6})h)?(?:([0-9]{1,6})m)?(?:([0-9]{1,6})s)?\z", text)
    matched === nothing && return nothing
    sum((part === nothing ? 0 : parse(Int, part)) * factor
        for (part, factor) in zip(matched.captures, (3600, 60, 1)))
end

function parse_host(text)
    if occursin(r"\A[0-9.]*\z", text)
        parts = split(text, '.'; keepempty=true)
        length(parts) != 4 && return nothing
        for part in parts
            if !occursin(r"\A[0-9]{1,3}\z", part) ||
               (length(part) > 1 && startswith(part, "0")) || parse(Int, part) > 255
                return nothing
            end
        end
        return String(text)
    end
    length(text) > 253 && return nothing
    for label in split(text, '.'; keepempty=true)
        if !occursin(r"\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\z", label)
            return nothing
        end
    end
    lowercase(text)
end

function parse_path(text)
    (isempty(text) || any(char -> char in (' ', '\n', '\t'), text)) && return nothing
    absolute = startswith(text, "/")
    parts = String[]
    for part in split(text, '/'; keepempty=true)
        part in ("", ".") && continue
        if part != ".."
            push!(parts, part)
        elseif !isempty(parts) && parts[end] != ".."
            pop!(parts)
        elseif absolute
            return nothing
        else
            push!(parts, part)
        end
    end
    absolute ? "/" * join(parts, "/") : (isempty(parts) ? "." : join(parts, "/"))
end

function parse_url(text)
    pair = split(text, "://"; limit=2, keepempty=true)
    if length(pair) != 2 || !occursin(r"\A[A-Za-z][A-Za-z0-9+.-]*\z", pair[1])
        return nothing
    end
    scheme, rest = pair
    (occursin('?', rest) || occursin('#', rest)) && return nothing
    parts = split(rest, '/'; limit=2, keepempty=true)
    authority = split(parts[1], ':'; limit=2, keepempty=true)
    host = parse_host(authority[1])
    path = parse_path("/" * (length(parts) == 2 ? parts[2] : ""))
    (host === nothing || path === nothing) && return nothing
    scheme = lowercase(scheme)
    result = scheme * "://" * host
    if length(authority) == 2
        port = authority[2]
        if !occursin(r"\A[1-9][0-9]{0,4}\z", port) || parse(Int, port) > 65535
            return nothing
        end
        if get(DEFAULT_PORTS, scheme, nothing) != parse(Int, port)
            result *= ":" * port
        end
    end
    result * path
end

function parse_date(text)
    !occursin(r"\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z", text) && return nothing
    year, month, day = parse.(Int, split(text, '-'))
    (year < 1 || !(1 <= month <= 12)) && return nothing
    days = (31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31)[month]
    if month == 2 && ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0)
        days = 29
    end
    1 <= day <= days ? String(text) : nothing
end

function parse_scalar(kind, text, values=String[])
    if kind == "string"
        return String(text)
    elseif kind == "int"
        return parse_int(text)
    elseif kind == "bool"
        lowered = lowercase(text)
        lowered in ("true", "yes", "on", "1") && return true
        lowered in ("false", "no", "off", "0") && return false
        return nothing
    elseif kind == "enum"
        lowered = lowercase(text)
        return lowered in values ? String(lowered) : nothing
    elseif kind == "size"
        return parse_size(text)
    elseif kind == "duration"
        return parse_duration(text)
    elseif kind == "host"
        return parse_host(text)
    elseif kind == "path"
        return parse_path(text)
    elseif kind == "url"
        return parse_url(text)
    elseif kind == "date"
        return parse_date(text)
    end
    nothing
end

struct CheckFailure <: Exception
    code::String
    message::String
end

function invalid_value(key, kind, values, display)
    if kind == "enum"
        return CheckFailure("E_ENUM", "$key: $display is not one of " * join(values, ","))
    end
    CheckFailure("E_TYPE", "$key: $display is not a valid $kind")
end

function check_range(key, spec, value)
    bound(text) = isempty(text) ? nothing : (spec.kind in ("string", "list") ? parse(Int, text) : parse_scalar(spec.kind, text))
    lower, upper = bound.(split(attribute(spec, "range"), ".."; limit=2, keepempty=true))
    measure = spec.kind in ("string", "list") ? length(value) : value
    if (lower === nothing || measure >= lower) && (upper === nothing || measure <= upper)
        return
    end
    display = if spec.kind == "string"
        "length $measure"
    elseif spec.kind == "list"
        "count $measure"
    else
        has_attribute(spec, "secret") ? MASK : string(value)
    end
    bounds = (lower === nothing ? "" : string(lower)) * ".." * (upper === nothing ? "" : string(upper))
    throw(CheckFailure("E_RANGE", "$key: $display is out of range $bounds"))
end

struct Definition
    value::String
    origin::Origin
    number::Int
    history::Vector{Origin}
end

struct OutputKey
    definition::Definition
    spec::Union{Nothing,Spec}
    value::Any
    kind::String
    secret::Bool
    notation::String
end

function OutputKey(definition, spec, value)
    kind = spec === nothing ? "string" : spec.kind
    secret = spec !== nothing && has_attribute(spec, "secret")
    item = spec === nothing ? nothing : attribute(spec, "item", "string")
    OutputKey(definition, spec, value, kind, secret, value_notation(kind, item, value))
end

struct DocumentLibrary
    directory::String
    documents::Dict{String,Union{Nothing,ParsedDocument}}
end

DocumentLibrary(directory) = DocumentLibrary(directory, Dict{String,Union{Nothing,ParsedDocument}}())

function find_document(library, name)
    if !haskey(library.documents, name)
        path = joinpath(library.directory, name * ".ini")
        library.documents[name] = ispath(path) ? parse_document(name, readlines(path)) : nothing
    end
    library.documents[name]
end

mutable struct Profile
    name::String
    root::String
    number::Int
    overrides::Vector{String}
    configuration::Dict{String,Definition}
    definition_count::Int
    parents::Dict{String,Tuple{String,Origin}}
    tree::Vector{Tuple{Int,String}}
    reported::Set{Diagnostic}
    outputs::Dict{String,OutputKey}
    diagnostics::Vector{Diagnostic}
    errors::Int
    warnings::Int
    overridden::Vector{Tuple{String,Vector{Origin}}}
    document_keys::Int
    manifest_keys::Int
    default_keys::Int
    dropped::Int
end

function Profile(number, line)
    words = String.(split(line, ' '; keepempty=true))
    Profile(words[1], words[2], number, words[3:end], Dict{String,Definition}(), 0,
            Dict{String,Tuple{String,Origin}}(), Tuple{Int,String}[], Set{Diagnostic}(),
            Dict{String,OutputKey}(), Diagnostic[], 0, 0, Tuple{String,Vector{Origin}}[], 0, 0, 0, 0)
end

function report!(profile::Profile, origin, code, message)
    push!(profile.reported, (origin[1], origin[2], code, message))
end

function define_key!(profile, key, value, origin)
    history = haskey(profile.configuration, key) ? copy(profile.configuration[key].history) : Origin[]
    if isempty(history) || history[end] != origin
        push!(history, origin)
    end
    profile.definition_count += 1
    profile.configuration[key] = Definition(value, origin, profile.definition_count, history)
end

function apply_document!(profile, library, name, chain)
    document = find_document(library, name)
    push!(profile.tree, (length(chain) - 1, name))
    union!(profile.reported, document.diagnostics)
    for statement in document.statements
        origin = (name, statement.line)
        key = statement.target
        if statement.kind in (:assign, :append)
            value = statement.value
            if statement.kind == :append && haskey(profile.configuration, key) && !isempty(profile.configuration[key].value)
                value = profile.configuration[key].value * "," * value
            end
            define_key!(profile, key, value, origin)
        elseif statement.kind == :unset
            if haskey(profile.configuration, key)
                delete!(profile.configuration, key)
            else
                report!(profile, origin, "W_UNSET", "$key is not set")
            end
        elseif statement.kind == :inherit
            profile.parents[key] = (statement.value, origin)
        else
            cycle_start = findfirst(==(key), chain)
            if cycle_start !== nothing
                path = [chain[cycle_start:end]; key]
                report!(profile, origin, "E_INCLUDE_CYCLE", "include cycle " * join(path, " -> "))
                push!(profile.tree, (length(chain), key * " (cycle)"))
            elseif find_document(library, key) === nothing
                report!(profile, origin, "E_INCLUDE_MISSING", "missing document " * key)
                push!(profile.tree, (length(chain), key * " (missing)"))
            else
                apply_document!(profile, library, key, [chain; key])
            end
        end
    end
end

function inherit_sections!(profile)
    own = Dict{String,Vector{Tuple{String,Definition}}}()
    for (key, definition) in profile.configuration
        section, name = split_key(key)
        push!(get!(() -> Tuple{String,Definition}[], own, section), (name, definition))
    end
    for (section, (parent, origin)) in profile.parents
        chain = [section]
        while haskey(profile.parents, chain[end]) && !(profile.parents[chain[end]][1] in chain)
            push!(chain, profile.parents[chain[end]][1])
        end
        last = chain[end]
        if haskey(profile.parents, last)
            push!(chain, profile.parents[last][1])
            report!(profile, origin, "E_INHERIT_CYCLE", "inheritance cycle " * join(chain, " -> "))
            continue
        end
        if !haskey(profile.parents, parent) && !haskey(own, parent)
            report!(profile, origin, "W_PARENT_EMPTY", "section $section inherits from empty section $parent")
        end
        for ancestor in chain[2:end]
            for (name, definition) in get(own, ancestor, Tuple{String,Definition}[])
                key = section * "." * name
                if !haskey(profile.configuration, key)
                    profile.configuration[key] = definition
                end
            end
        end
    end
end

function resolve_aliases!(profile, schema)
    for spec in schema.specs
        has_attribute(spec, "alias") || continue
        aliases = filter(key -> haskey(profile.configuration, key), String.(split(attribute(spec, "alias"), ',')))
        isempty(aliases) && continue
        candidates = haskey(profile.configuration, spec.pattern) ? [spec.pattern; aliases] : aliases
        winner = candidates[1]
        for candidate in candidates
            if profile.configuration[candidate].number > profile.configuration[winner].number
                winner = candidate
            end
        end
        chosen = profile.configuration[winner]
        for candidate in candidates
            origin = profile.configuration[candidate].origin
            if candidate != spec.pattern
                report!(profile, origin, "W_DEPRECATED", "$candidate is deprecated, use $(spec.pattern)")
            end
            if candidate != winner
                report!(profile, origin, "W_SHADOWED", "$candidate is superseded by $winner at " * origin_text(chosen.origin))
            end
        end
        profile.configuration[spec.pattern] = chosen
        for alias in aliases
            delete!(profile.configuration, alias)
        end
    end
end

function fill_defaults!(profile, schema)
    sections = Set(section_of(key) for key in keys(profile.configuration))
    for spec in schema.specs
        has_attribute(spec, "default") || continue
        for key in target_keys(schema, spec, sections)
            if !haskey(profile.configuration, key)
                define_key!(profile, key, attribute(spec, "default"), ("schema", spec.line))
            end
        end
    end
    sections
end

function normalize!(profile, key, spec, text, origin)
    values = enum_values(spec)
    if spec.kind != "list"
        value = parse_scalar(spec.kind, text, values)
        if value === nothing
            display = has_attribute(spec, "secret") ? MASK : string_notation(text)
            throw(invalid_value(key, spec.kind, values, display))
        end
    else
        value = Any[]
        items = isempty(space_trim(text)) ? String[] : space_trim.(split(text, ','; keepempty=true))
        if "" in items
            report!(profile, origin, "W_EMPTY_ITEM", "$key: empty list item ignored")
        end
        item_kind = attribute(spec, "item", "string")
        for item in items
            isempty(item) && continue
            parsed = parse_scalar(item_kind, item, values)
            if parsed === nothing
                display = "item " * (has_attribute(spec, "secret") ? MASK : string_notation(item))
                throw(invalid_value(key, item_kind, values, display))
            end
            push!(value, parsed)
        end
        if has_attribute(spec, "unique")
            seen = Set{String}()
            unique_values = Any[]
            for item in value
                notation = value_notation(item_kind, nothing, item)
                if !(notation in seen)
                    push!(seen, notation)
                    push!(unique_values, item)
                end
            end
            if length(unique_values) < length(value)
                report!(profile, origin, "W_DUPLICATE_ITEM", "$key: duplicate items removed")
            end
            value = unique_values
        end
    end
    has_attribute(spec, "range") && check_range(key, spec, value)
    value
end

function check_types!(profile, schema)
    values = Dict{String,String}(key => definition.value for (key, definition) in profile.configuration)
    origins = Dict{String,Origin}(key => definition.origin for (key, definition) in profile.configuration)
    expander = Expander(values, origins)
    for key in ordered_keys(keys(profile.configuration))
        expand!(expander, key)
    end
    union!(profile.reported, expander.diagnostics)
    for key in ordered_keys(keys(expander.results))
        text = expander.results[key]
        text === nothing && continue
        definition = profile.configuration[key]
        spec = spec_for(schema, key)
        if spec === nothing
            report!(profile, definition.origin, "W_UNKNOWN", "$key is not in the schema")
            value = text
        else
            try
                value = normalize!(profile, key, spec, text, definition.origin)
            catch error
                error isa CheckFailure || rethrow()
                report!(profile, definition.origin, error.code, error.message)
                continue
            end
        end
        profile.outputs[key] = OutputKey(definition, spec, value)
    end
end

function check_order!(profile)
    remove = String[]
    for key in ordered_keys(keys(profile.outputs))
        output = profile.outputs[key]
        (output.spec === nothing || !has_attribute(output.spec, "le")) && continue
        limit_key = section_of(key) * "." * attribute(output.spec, "le")
        limit = get(profile.outputs, limit_key, nothing)
        if limit !== nothing && limit.kind in ("int", "size", "duration") && output.value > limit.value
            report!(profile, output.definition.origin, "E_ORDER",
                    "$key: " * shown(output) * " is greater than $limit_key (" * shown(limit) * ")")
            push!(remove, key)
        end
    end
    for key in remove
        delete!(profile.outputs, key)
    end
end

function check_required!(profile, schema, sections, configured)
    for spec in schema.specs
        has_attribute(spec, "required") || continue
        for key in target_keys(schema, spec, sections)
            key in configured && continue
            if !has_attribute(spec, "when")
                report!(profile, (profile.root, 0), "E_REQUIRED", "$key is required")
            else
                condition_key = section_of(key) * "." * attribute(spec, "when")
                condition = get(profile.outputs, condition_key, nothing)
                if condition !== nothing && condition.value === true
                    report!(profile, (profile.root, 0), "E_REQUIRED", "$key is required when $condition_key is true")
                end
            end
        end
    end
end

function check_fixed!(profile, earlier)
    for key in ordered_keys(keys(profile.outputs))
        output = profile.outputs[key]
        (output.spec === nothing || !has_attribute(output.spec, "fixed")) && continue
        for reference in earlier
            if haskey(reference.outputs, key)
                if reference.outputs[key].notation != output.notation
                    report!(profile, output.definition.origin, "E_FIXED", "$key: value differs from profile $(reference.name)")
                    delete!(profile.outputs, key)
                end
                break
            end
        end
    end
end

function summarize!(profile, configured_count)
    profile.diagnostics = sort!(collect(profile.reported))
    profile.errors = count(diagnostic -> startswith(diagnostic[3], "E_"), profile.diagnostics)
    profile.warnings = length(profile.diagnostics) - profile.errors
    for key in ordered_keys(keys(profile.outputs))
        definition = profile.outputs[key].definition
        if length(definition.history) >= 2
            push!(profile.overridden, (key, definition.history))
        end
        document = definition.origin[1]
        if document == "manifest"
            profile.manifest_keys += 1
        elseif document == "schema"
            profile.default_keys += 1
        else
            profile.document_keys += 1
        end
    end
    profile.dropped = configured_count - length(profile.outputs)
end

function process!(profile, schema, library, earlier)
    apply_document!(profile, library, profile.root, [profile.root])
    for override in profile.overrides
        key, value = String.(split(override, '='; limit=2, keepempty=true))
        define_key!(profile, key, value, ("manifest", profile.number))
    end
    inherit_sections!(profile)
    resolve_aliases!(profile, schema)
    sections = fill_defaults!(profile, schema)
    configured = Set(keys(profile.configuration))
    check_types!(profile, schema)
    check_order!(profile)
    check_required!(profile, schema, sections, configured)
    check_fixed!(profile, earlier)
    summarize!(profile, length(configured))
end

struct ProfileDiff
    first::String
    second::String
    entries::Vector{Tuple{String,String,Union{Nothing,OutputKey},Union{Nothing,OutputKey}}}
    added::Int
    removed::Int
    changed::Int
end

function ProfileDiff(first, second)
    entries = Tuple{String,String,Union{Nothing,OutputKey},Union{Nothing,OutputKey}}[]
    added = removed = changed = 0
    for key in ordered_keys(union(keys(first.outputs), keys(second.outputs)))
        before = get(first.outputs, key, nothing)
        after = get(second.outputs, key, nothing)
        if before === nothing
            added += 1
            push!(entries, ("+", key, before, after))
        elseif after === nothing
            removed += 1
            push!(entries, ("-", key, before, after))
        elseif before.notation != after.notation
            changed += 1
            push!(entries, ("~", key, before, after))
        end
    end
    ProfileDiff(first.name, second.name, entries, added, removed, changed)
end

function main()
    schema = load_schema("input/schema.txt")
    library = DocumentLibrary(joinpath("input", "conf"))
    profiles = Profile[]
    diffs = ProfileDiff[]
    for (number, line) in enumerate(readlines("input/manifest.txt"))
        profile = Profile(number, line)
        process!(profile, schema, library, profiles)
        !isempty(profiles) && push!(diffs, ProfileDiff(profiles[end], profile))
        push!(profiles, profile)
    end
    write_outputs("output", profiles, diffs)
end

main()

end
