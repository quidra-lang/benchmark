local MASK = "********"
local ESCAPED = { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\t"] = "\\t" }

local function string_notation(text)
    return '"' .. text:gsub('[\\"\n\t]', ESCAPED) .. '"'
end

local function value_notation(kind, item_kind, value)
    if kind == "list" then
        local items = {}
        for _, item in ipairs(value) do
            table.insert(items, value_notation(item_kind, nil, item))
        end
        return "[" .. table.concat(items, ", ") .. "]"
    end
    if kind == "string" then
        return string_notation(value)
    end
    if kind == "bool" then
        return value and "true" or "false"
    end
    return tostring(value)
end

local function shown(output)
    return output.secret and MASK or output.notation
end

local function origin_text(origin)
    return origin.document .. ":" .. origin.line
end

local function sorted_names(map)
    local names = {}
    for name in pairs(map) do
        table.insert(names, name)
    end
    table.sort(names)
    return names
end

local function normalized_block(profile)
    local lines = { "profile " .. profile.name }
    local sections = {}
    for key, output in pairs(profile.outputs) do
        local section, name = key:match("^(.*)%.([^.]*)$")
        sections[section] = sections[section] or {}
        sections[section][name] = output
    end
    for _, section in ipairs(sorted_names(sections)) do
        table.insert(lines, "[" .. section .. "]")
        local keys = sections[section]
        for _, name in ipairs(sorted_names(keys)) do
            table.insert(lines, name .. " = " .. shown(keys[name]))
        end
    end
    return lines
end

local function diagnostics_block(profile)
    local lines = {
        string.format("profile %s errors %d warnings %d", profile.name, profile.errors,
            profile.warnings),
    }
    for _, diagnostic in ipairs(profile.diagnostics) do
        table.insert(lines, string.format("%s:%d %s %s", diagnostic.document, diagnostic.line,
            diagnostic.code, diagnostic.message))
    end
    return lines
end

local function diff_block(diff)
    local lines = {
        string.format("diff %s -> %s: %d added, %d removed, %d changed", diff.first, diff.second,
            diff.added, diff.removed, diff.changed),
    }
    for _, entry in ipairs(diff.entries) do
        if entry.sign == "+" then
            table.insert(lines, string.format("+ %s = %s", entry.key, shown(entry.after)))
        elseif entry.sign == "-" then
            table.insert(lines, string.format("- %s = %s", entry.key, shown(entry.before)))
        else
            table.insert(lines, string.format("~ %s: %s -> %s", entry.key, shown(entry.before),
                shown(entry.after)))
        end
    end
    return lines
end

local function report_block(profile)
    local lines = { "profile " .. profile.name, "includes" }
    for _, node in ipairs(profile.tree) do
        table.insert(lines, "  " .. string.rep("  ", node.depth) .. node.text)
    end
    table.insert(lines, "overridden")
    for _, entry in ipairs(profile.overridden) do
        local origins = {}
        for _, origin in ipairs(entry.history) do
            table.insert(origins, origin_text(origin))
        end
        table.insert(lines, "  " .. entry.key .. ": " .. table.concat(origins, " -> "))
    end
    if #profile.overridden == 0 then
        table.insert(lines, "  (none)")
    end
    table.insert(lines, string.format("keys %d documents %d manifest %d defaults %d",
        profile.output_count, profile.document_keys, profile.manifest_keys, profile.default_keys))
    table.insert(lines, "dropped " .. profile.dropped)
    table.insert(lines, string.format("errors %d warnings %d", profile.errors, profile.warnings))
    return lines
end

local function write_file(path, items, build_block)
    local blocks = {}
    for _, item in ipairs(items) do
        table.insert(blocks, table.concat(build_block(item), "\n"))
    end
    local handle = assert(io.open(path, "w"))
    handle:write(table.concat(blocks, "\n\n"), "\n")
    handle:close()
end

local function write_outputs(directory, profiles, diffs)
    os.execute("mkdir -p " .. directory)
    write_file(directory .. "/normalized.txt", profiles, normalized_block)
    write_file(directory .. "/diagnostics.txt", profiles, diagnostics_block)
    write_file(directory .. "/diff.txt", diffs, diff_block)
    write_file(directory .. "/report.txt", profiles, report_block)
end

return {
    MASK = MASK,
    string_notation = string_notation,
    value_notation = value_notation,
    shown = shown,
    origin_text = origin_text,
    write_outputs = write_outputs,
}
