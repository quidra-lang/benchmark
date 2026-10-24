const MASK = "********"

function string_notation(text)
    escaped = replace(text, '\\' => "\\\\", '"' => "\\\"", '\n' => "\\n", '\t' => "\\t")
    "\"" * escaped * "\""
end

function value_notation(kind, item_kind, value)
    if kind == "list"
        return "[" * join((value_notation(item_kind, nothing, item) for item in value), ", ") * "]"
    elseif kind == "string"
        return string_notation(value)
    elseif kind == "bool"
        return value ? "true" : "false"
    end
    string(value)
end

shown(output) = output.secret ? MASK : output.notation
origin_text(origin) = "$(origin[1]):$(origin[2])"

function normalized_block(profile)
    lines = ["profile " * profile.name]
    previous = nothing
    for key in ordered_keys(keys(profile.outputs))
        section, name = split_key(key)
        if section != previous
            push!(lines, "[$section]")
            previous = section
        end
        push!(lines, name * " = " * shown(profile.outputs[key]))
    end
    lines
end

function diagnostics_block(profile)
    lines = ["profile $(profile.name) errors $(profile.errors) warnings $(profile.warnings)"]
    for (document, line, code, message) in profile.diagnostics
        push!(lines, "$document:$line $code $message")
    end
    lines
end

function diff_block(diff)
    lines = ["diff $(diff.first) -> $(diff.second): $(diff.added) added, $(diff.removed) removed, $(diff.changed) changed"]
    for (sign, key, before, after) in diff.entries
        if sign == "+"
            push!(lines, "+ $key = " * shown(after))
        elseif sign == "-"
            push!(lines, "- $key = " * shown(before))
        else
            push!(lines, "~ $key: " * shown(before) * " -> " * shown(after))
        end
    end
    lines
end

function report_block(profile)
    lines = ["profile " * profile.name, "includes"]
    for (depth, text) in profile.tree
        push!(lines, repeat("  ", depth + 1) * text)
    end
    push!(lines, "overridden")
    for (key, history) in profile.overridden
        push!(lines, "  $key: " * join(origin_text.(history), " -> "))
    end
    isempty(profile.overridden) && push!(lines, "  (none)")
    push!(lines, "keys $(length(profile.outputs)) documents $(profile.document_keys) manifest $(profile.manifest_keys) defaults $(profile.default_keys)")
    push!(lines, "dropped $(profile.dropped)")
    push!(lines, "errors $(profile.errors) warnings $(profile.warnings)")
    lines
end

function write_blocks(path, blocks)
    write(path, join((join(lines, "\n") for lines in blocks), "\n\n") * "\n")
end

function write_outputs(directory, profiles, diffs)
    mkpath(directory)
    write_blocks(joinpath(directory, "normalized.txt"), normalized_block.(profiles))
    write_blocks(joinpath(directory, "diagnostics.txt"), diagnostics_block.(profiles))
    write_blocks(joinpath(directory, "diff.txt"), diff_block.(diffs))
    write_blocks(joinpath(directory, "report.txt"), report_block.(profiles))
end
