local script_dir = arg[0]:match("^(.*)/") or "."
package.path = script_dir .. "/?.lua;" .. package.path

local emitter = require("emitter")
local parse_document = require("ini_parser").parse_document
local Expander = require("interpolate").Expander
local load_schema = require("schema").load_schema

local MASK = emitter.MASK
local shown = emitter.shown
local string_notation = emitter.string_notation
local value_notation = emitter.value_notation

local INPUT_DIR = "input"
local OUTPUT_DIR = "output"
local NUMERIC_TYPES = { int = true, size = true, duration = true }
local TRUE_WORDS = { ["true"] = true, yes = true, on = true, ["1"] = true }
local FALSE_WORDS = { ["false"] = true, no = true, off = true, ["0"] = true }
local SIZE_FACTORS = { [""] = 1, b = 1, kb = 1024, mb = 1048576, gb = 1073741824 }
local DEFAULT_PORTS = { http = 80, https = 443 }
local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
local DURATION_UNITS = { h = 3600, m = 60, s = 1 }
local DURATION_ORDER = "hms"

local function read_lines(path)
    local lines = {}
    for line in io.lines(path) do
        table.insert(lines, line)
    end
    return lines
end

local function split(text, separator)
    local parts = {}
    local start = 1
    while true do
        local found = text:find(separator, start, true)
        if not found then
            table.insert(parts, text:sub(start))
            return parts
        end
        table.insert(parts, text:sub(start, found - 1))
        start = found + #separator
    end
end

local function strip(text)
    return text:match("^ *(.-) *$")
end

local function copy(list)
    return table.move(list, 1, #list, 1, {})
end

local function index_of(list, value)
    for index, item in ipairs(list) do
        if item == value then
            return index
        end
    end
    return nil
end

local function split_key(key)
    return key:match("^(.*)%.([^.]*)$")
end

local function section_of(key)
    return (split_key(key))
end

local function key_less(left, right)
    local left_section, left_name = split_key(left)
    local right_section, right_name = split_key(right)
    if left_section ~= right_section then
        return left_section < right_section
    end
    return left_name < right_name
end

local function sorted_keys(map)
    local keys = {}
    for key in pairs(map) do
        table.insert(keys, key)
    end
    table.sort(keys, key_less)
    return keys
end

local function parse_int(text)
    local sign, body = text:match("^([+-]?)(.*)$")
    local number
    local hex_digits = body:match("^0[xX](%x+)$")
    if hex_digits then
        if #hex_digits > 10 then
            return nil
        end
        number = tonumber(hex_digits, 16)
    else
        if not body:find("^%d[%d_]*$") or body:find("__", 1, true) or body:sub(-1) == "_" then
            return nil
        end
        local digits = body:gsub("_", "")
        if #digits > 12 then
            return nil
        end
        number = tonumber(digits)
    end
    return sign == "-" and -number or number
end

local function parse_bool(text)
    local lowered = text:lower()
    if TRUE_WORDS[lowered] then
        return true
    end
    if FALSE_WORDS[lowered] then
        return false
    end
    return nil
end

local function parse_enum(text, values)
    local lowered = text:lower()
    for _, value in ipairs(values) do
        if value == lowered then
            return value
        end
    end
    return nil
end

local function parse_size(text)
    local whole, fraction, unit = text:match("^(%d+)%.(%d+)(%a*)$")
    if not whole then
        whole, unit = text:match("^(%d+)(%a*)$")
    end
    if not whole or #whole > 6 or (fraction and #fraction > 3) then
        return nil
    end
    local factor = SIZE_FACTORS[unit:lower()]
    if not factor then
        return nil
    end
    if not fraction then
        return tonumber(whole) * factor
    end
    local scaled = tonumber(fraction) * factor
    local divisor = math.tointeger(10 ^ #fraction)
    if scaled % divisor ~= 0 then
        return nil
    end
    return tonumber(whole) * factor + scaled // divisor
end

local function parse_duration(text)
    if text:find("^%d+$") then
        return #text <= 6 and tonumber(text) or nil
    end
    local total = 0
    local position = 1
    local previous = 0
    while position <= #text do
        local digits, unit = text:match("^(%d+)([hms])", position)
        if not digits or #digits > 6 then
            return nil
        end
        local order = DURATION_ORDER:find(unit, 1, true)
        if order <= previous then
            return nil
        end
        previous = order
        total = total + tonumber(digits) * DURATION_UNITS[unit]
        position = position + #digits + 1
    end
    return position > 1 and total or nil
end

local function is_ipv4(text)
    local parts = split(text, ".")
    if #parts ~= 4 then
        return false
    end
    for _, part in ipairs(parts) do
        if #part < 1 or #part > 3 then
            return false
        end
        if part ~= "0" and part:sub(1, 1) == "0" then
            return false
        end
        if tonumber(part) > 255 then
            return false
        end
    end
    return true
end

local function is_label(label)
    return #label >= 1 and #label <= 63 and not label:find("[^%w-]")
        and label:sub(1, 1) ~= "-" and label:sub(-1) ~= "-"
end

local function parse_host(text)
    if not text:find("[^%d.]") then
        return is_ipv4(text) and text or nil
    end
    if #text > 253 then
        return nil
    end
    for _, label in ipairs(split(text, ".")) do
        if not is_label(label) then
            return nil
        end
    end
    return text:lower()
end

local function parse_path(text)
    if text == "" or text:find("[ \n\t]") then
        return nil
    end
    local absolute = text:sub(1, 1) == "/"
    local parts = {}
    for _, part in ipairs(split(text, "/")) do
        if part == ".." then
            if #parts > 0 and parts[#parts] ~= ".." then
                table.remove(parts)
            elseif absolute then
                return nil
            else
                table.insert(parts, part)
            end
        elseif part ~= "" and part ~= "." then
            table.insert(parts, part)
        end
    end
    if absolute then
        return "/" .. table.concat(parts, "/")
    end
    return #parts > 0 and table.concat(parts, "/") or "."
end

local function parse_url(text)
    local separator = text:find("://", 1, true)
    if not separator then
        return nil
    end
    local scheme = text:sub(1, separator - 1)
    local rest = text:sub(separator + 3)
    if not scheme:find("^%a[%w+.-]*$") or rest:find("[?#]") then
        return nil
    end
    local authority, path = rest:match("^([^/]*)/?(.*)$")
    local host, port = authority:match("^([^:]*):(.*)$")
    if not host then
        host = authority
    end
    local host_value = parse_host(host)
    local path_value = parse_path("/" .. path)
    if not host_value or not path_value then
        return nil
    end
    scheme = scheme:lower()
    local result = scheme .. "://" .. host_value
    if port then
        if not port:find("^[1-9]%d*$") or #port > 5 or tonumber(port) > 65535 then
            return nil
        end
        if DEFAULT_PORTS[scheme] ~= tonumber(port) then
            result = result .. ":" .. port
        end
    end
    return result .. path_value
end

local function is_leap_year(year)
    return (year % 4 == 0 and year % 100 ~= 0) or year % 400 == 0
end

local function parse_date(text)
    if not text:find("^%d%d%d%d%-%d%d%-%d%d$") then
        return nil
    end
    local year = tonumber(text:sub(1, 4))
    local month = tonumber(text:sub(6, 7))
    local day = tonumber(text:sub(9))
    if year < 1 or month < 1 or month > 12 then
        return nil
    end
    local days = DAYS_IN_MONTH[month]
    if month == 2 and is_leap_year(year) then
        days = 29
    end
    return (day >= 1 and day <= days) and text or nil
end

local SCALAR_PARSERS = {
    int = parse_int,
    bool = parse_bool,
    size = parse_size,
    duration = parse_duration,
    host = parse_host,
    path = parse_path,
    url = parse_url,
    date = parse_date,
}

local function parse_scalar(kind, text, values)
    if kind == "string" then
        return text
    end
    if kind == "enum" then
        return parse_enum(text, values)
    end
    return SCALAR_PARSERS[kind](text)
end

local function checked_text(text, secret)
    return secret and MASK or string_notation(text)
end

local function check_error(code, message)
    return { code = code, message = message }
end

local function invalid_value(key, kind, values, display)
    if kind == "enum" then
        local message = string.format("%s: %s is not one of %s", key, display,
            table.concat(values, ","))
        return check_error("E_ENUM", message)
    end
    return check_error("E_TYPE", string.format("%s: %s is not a valid %s", key, display, kind))
end

local function bound_value(kind, text)
    if text == "" then
        return nil
    end
    if kind == "string" or kind == "list" then
        return tonumber(text)
    end
    return parse_scalar(kind, text, {})
end

local function bound_text(bound)
    return bound == nil and "" or tostring(bound)
end

local function check_range(key, spec, value)
    local lower = bound_value(spec.kind, spec.range.lower)
    local upper = bound_value(spec.kind, spec.range.upper)
    local measure, display
    if spec.kind == "string" then
        measure = #value
        display = "length " .. measure
    elseif spec.kind == "list" then
        measure = #value
        display = "count " .. measure
    else
        measure = value
        display = spec.secret and MASK or tostring(value)
    end
    if (lower ~= nil and measure < lower) or (upper ~= nil and measure > upper) then
        local bounds = bound_text(lower) .. ".." .. bound_text(upper)
        return check_error("E_RANGE",
            string.format("%s: %s is out of range %s", key, display, bounds))
    end
    return nil
end

local function same_origin(left, right)
    return left.document == right.document and left.line == right.line
end

local function diagnostic_less(left, right)
    if left.document ~= right.document then
        return left.document < right.document
    end
    if left.line ~= right.line then
        return left.line < right.line
    end
    if left.code ~= right.code then
        return left.code < right.code
    end
    return left.message < right.message
end

local function output_key(definition, spec, value)
    local output = { definition = definition, spec = spec, value = value }
    if spec == nil then
        output.kind = "string"
        output.secret = false
        output.notation = string_notation(value)
    else
        output.kind = spec.kind
        output.secret = spec.secret
        output.notation = value_notation(spec.kind, spec.item, value)
    end
    return output
end

local Library = {}
Library.__index = Library

function Library.new(directory)
    return setmetatable({ directory = directory, documents = {} }, Library)
end

function Library:find(name)
    if self.documents[name] == nil then
        local path = self.directory .. "/" .. name .. ".ini"
        local handle = io.open(path)
        if handle then
            handle:close()
            self.documents[name] = parse_document(name, read_lines(path))
        else
            self.documents[name] = false
        end
    end
    return self.documents[name]
end

local Profile = {}
Profile.__index = Profile

function Profile.new(number, line)
    local words = split(line, " ")
    return setmetatable({
        name = words[1],
        root = words[2],
        number = number,
        overrides = { table.unpack(words, 3) },
        configuration = {},
        definition_count = 0,
        parents = {},
        tree = {},
        reported = {},
        outputs = {},
        output_count = 0,
        diagnostics = {},
        errors = 0,
        warnings = 0,
        overridden = {},
        document_keys = 0,
        manifest_keys = 0,
        default_keys = 0,
        dropped = 0,
    }, Profile)
end

function Profile:collect(diagnostic)
    local identity = table.concat({
        diagnostic.document,
        diagnostic.line,
        diagnostic.code,
        diagnostic.message,
    }, "\0")
    self.reported[identity] = diagnostic
end

function Profile:report(origin, code, message)
    self:collect({ document = origin.document, line = origin.line, code = code, message = message })
end

function Profile:define(key, value, origin)
    self.definition_count = self.definition_count + 1
    local history = {}
    local current = self.configuration[key]
    if current then
        history = copy(current.history)
    end
    if #history == 0 or not same_origin(history[#history], origin) then
        table.insert(history, origin)
    end
    self.configuration[key] = {
        value = value,
        origin = origin,
        number = self.definition_count,
        history = history,
    }
end

function Profile:process(schema, library, earlier)
    self:apply(library, self.root, { self.root })
    self:apply_overrides()
    self:inherit_sections()
    self:resolve_aliases(schema)
    local sections = self:fill_defaults(schema)
    local configured = {}
    local configured_count = 0
    for key in pairs(self.configuration) do
        configured[key] = true
        configured_count = configured_count + 1
    end
    self:check_types(schema, self:expand_values())
    self:check_order()
    self:check_required(schema, sections, configured)
    self:check_fixed(earlier)
    self:summarize(configured_count)
end

function Profile:apply(library, name, chain)
    local document = library:find(name)
    table.insert(self.tree, { depth = #chain - 1, text = name })
    for _, diagnostic in ipairs(document.diagnostics) do
        self:collect(diagnostic)
    end
    for _, statement in ipairs(document.statements) do
        local origin = { document = name, line = statement.line }
        if statement.kind == "assign" then
            self:define(statement.target, statement.value, origin)
        elseif statement.kind == "append" then
            self:append(statement.target, statement.value, origin)
        elseif statement.kind == "unset" then
            self:unset(statement.target, origin)
        elseif statement.kind == "inherit" then
            self.parents[statement.target] = { parent = statement.value, origin = origin }
        else
            self:include(library, statement.target, chain, origin)
        end
    end
end

function Profile:append(key, value, origin)
    local current = self.configuration[key]
    if current and current.value ~= "" then
        value = current.value .. "," .. value
    end
    self:define(key, value, origin)
end

function Profile:unset(key, origin)
    if self.configuration[key] then
        self.configuration[key] = nil
    else
        self:report(origin, "W_UNSET", key .. " is not set")
    end
end

function Profile:include(library, name, chain, origin)
    local depth = #chain
    local position = index_of(chain, name)
    if position then
        local path = { table.unpack(chain, position) }
        table.insert(path, name)
        self:report(origin, "E_INCLUDE_CYCLE", "include cycle " .. table.concat(path, " -> "))
        table.insert(self.tree, { depth = depth, text = name .. " (cycle)" })
    elseif not library:find(name) then
        self:report(origin, "E_INCLUDE_MISSING", "missing document " .. name)
        table.insert(self.tree, { depth = depth, text = name .. " (missing)" })
    else
        local extended = copy(chain)
        table.insert(extended, name)
        self:apply(library, name, extended)
    end
end

function Profile:apply_overrides()
    for _, override in ipairs(self.overrides) do
        local key, value = override:match("^([^=]*)=(.*)$")
        self:define(key, value, { document = "manifest", line = self.number })
    end
end

function Profile:inherit_sections()
    local own_keys = {}
    for key, definition in pairs(self.configuration) do
        local section, name = split_key(key)
        own_keys[section] = own_keys[section] or {}
        own_keys[section][name] = definition
    end
    for section, declaration in pairs(self.parents) do
        local chain = { section }
        local last = section
        while self.parents[last] and not index_of(chain, self.parents[last].parent) do
            last = self.parents[last].parent
            table.insert(chain, last)
        end
        if self.parents[last] then
            local path = copy(chain)
            table.insert(path, self.parents[last].parent)
            self:report(declaration.origin, "E_INHERIT_CYCLE",
                "inheritance cycle " .. table.concat(path, " -> "))
        else
            local parent = declaration.parent
            if not self.parents[parent] and not own_keys[parent] then
                self:report(declaration.origin, "W_PARENT_EMPTY",
                    string.format("section %s inherits from empty section %s", section, parent))
            end
            for index = 2, #chain do
                for name, definition in pairs(own_keys[chain[index]] or {}) do
                    local key = section .. "." .. name
                    if self.configuration[key] == nil then
                        self.configuration[key] = definition
                    end
                end
            end
        end
    end
end

function Profile:resolve_aliases(schema)
    for _, spec in ipairs(schema.specs) do
        local candidates = {}
        if self.configuration[spec.pattern] then
            table.insert(candidates, spec.pattern)
        end
        local alias_found = false
        for _, alias in ipairs(spec.aliases) do
            if self.configuration[alias] then
                table.insert(candidates, alias)
                alias_found = true
            end
        end
        if alias_found then
            local winner = candidates[1]
            for index = 2, #candidates do
                local candidate = candidates[index]
                if self.configuration[candidate].number > self.configuration[winner].number then
                    winner = candidate
                end
            end
            local chosen = self.configuration[winner]
            for _, candidate in ipairs(candidates) do
                local origin = self.configuration[candidate].origin
                if candidate ~= spec.pattern then
                    self:report(origin, "W_DEPRECATED",
                        string.format("%s is deprecated, use %s", candidate, spec.pattern))
                end
                if candidate ~= winner then
                    self:report(origin, "W_SHADOWED", string.format("%s is superseded by %s at %s",
                        candidate, winner, emitter.origin_text(chosen.origin)))
                end
            end
            self.configuration[spec.pattern] = chosen
            for _, alias in ipairs(spec.aliases) do
                self.configuration[alias] = nil
            end
        end
    end
end

function Profile:fill_defaults(schema)
    local sections = {}
    for key in pairs(self.configuration) do
        sections[section_of(key)] = true
    end
    for _, spec in ipairs(schema.specs) do
        if spec.default then
            for _, key in ipairs(schema:target_keys(spec, sections)) do
                if self.configuration[key] == nil then
                    self:define(key, spec.default, { document = "schema", line = spec.line })
                end
            end
        end
    end
    return sections
end

function Profile:expand_values()
    local values = {}
    local origins = {}
    for key, definition in pairs(self.configuration) do
        values[key] = definition.value
        origins[key] = definition.origin
    end
    local expander = Expander.new(values, origins)
    for _, key in ipairs(sorted_keys(self.configuration)) do
        expander:expand(key)
    end
    for _, diagnostic in ipairs(expander.diagnostics) do
        self:collect(diagnostic)
    end
    return expander.results
end

function Profile:check_types(schema, results)
    for _, key in ipairs(sorted_keys(results)) do
        local text = results[key]
        if text then
            local definition = self.configuration[key]
            local spec = schema:spec_for(key)
            if spec == nil then
                self:report(definition.origin, "W_UNKNOWN", key .. " is not in the schema")
                self.outputs[key] = output_key(definition, nil, text)
            else
                local value, failure = self:normalize(key, spec, text, definition.origin)
                if failure then
                    self:report(definition.origin, failure.code, failure.message)
                else
                    self.outputs[key] = output_key(definition, spec, value)
                end
            end
        end
    end
end

function Profile:normalize(key, spec, text, origin)
    local value, failure
    if spec.kind == "list" then
        value, failure = self:normalize_list(key, spec, text, origin)
    else
        value = parse_scalar(spec.kind, text, spec.values)
        if value == nil then
            failure = invalid_value(key, spec.kind, spec.values, checked_text(text, spec.secret))
        end
    end
    if failure == nil and spec.range then
        failure = check_range(key, spec, value)
    end
    return value, failure
end

function Profile:normalize_list(key, spec, text, origin)
    if not text:find("[^ ]") then
        return {}
    end
    local items = {}
    local has_empty = false
    for _, item in ipairs(split(text, ",")) do
        local stripped = strip(item)
        if stripped == "" then
            has_empty = true
        else
            table.insert(items, stripped)
        end
    end
    if has_empty then
        self:report(origin, "W_EMPTY_ITEM", key .. ": empty list item ignored")
    end
    local values = {}
    for _, item in ipairs(items) do
        local value = parse_scalar(spec.item, item, spec.values)
        if value == nil then
            local display = "item " .. checked_text(item, spec.secret)
            return nil, invalid_value(key, spec.item, spec.values, display)
        end
        table.insert(values, value)
    end
    if not spec.unique then
        return values
    end
    local unique_values = {}
    local notations = {}
    for _, value in ipairs(values) do
        local notation = value_notation(spec.item, nil, value)
        if not notations[notation] then
            notations[notation] = true
            table.insert(unique_values, value)
        end
    end
    if #unique_values < #values then
        self:report(origin, "W_DUPLICATE_ITEM", key .. ": duplicate items removed")
    end
    return unique_values
end

function Profile:check_order()
    local reported = {}
    for _, key in ipairs(sorted_keys(self.outputs)) do
        local output = self.outputs[key]
        if output.spec and output.spec.le then
            local limit_key = section_of(key) .. "." .. output.spec.le
            local limit = self.outputs[limit_key]
            if limit and NUMERIC_TYPES[limit.kind] and output.value > limit.value then
                self:report(output.definition.origin, "E_ORDER",
                    string.format("%s: %s is greater than %s (%s)", key, shown(output), limit_key,
                        shown(limit)))
                table.insert(reported, key)
            end
        end
    end
    for _, key in ipairs(reported) do
        self.outputs[key] = nil
    end
end

function Profile:check_required(schema, sections, configured)
    local origin = { document = self.root, line = 0 }
    for _, spec in ipairs(schema.specs) do
        if spec.required then
            for _, key in ipairs(schema:target_keys(spec, sections)) do
                if not configured[key] then
                    if spec.when == nil then
                        self:report(origin, "E_REQUIRED", key .. " is required")
                    else
                        local condition_key = section_of(key) .. "." .. spec.when
                        local condition = self.outputs[condition_key]
                        if condition and condition.kind == "bool" and condition.value then
                            self:report(origin, "E_REQUIRED", string.format(
                                "%s is required when %s is true", key, condition_key))
                        end
                    end
                end
            end
        end
    end
end

function Profile:check_fixed(earlier)
    for _, key in ipairs(sorted_keys(self.outputs)) do
        local output = self.outputs[key]
        if output.spec and output.spec.fixed then
            local reference
            for _, profile in ipairs(earlier) do
                if profile.outputs[key] then
                    reference = profile
                    break
                end
            end
            if reference and reference.outputs[key].notation ~= output.notation then
                self:report(output.definition.origin, "E_FIXED",
                    string.format("%s: value differs from profile %s", key, reference.name))
                self.outputs[key] = nil
            end
        end
    end
end

function Profile:summarize(configured_count)
    for _, diagnostic in pairs(self.reported) do
        table.insert(self.diagnostics, diagnostic)
    end
    table.sort(self.diagnostics, diagnostic_less)
    for _, diagnostic in ipairs(self.diagnostics) do
        if diagnostic.code:sub(1, 2) == "E_" then
            self.errors = self.errors + 1
        end
    end
    self.warnings = #self.diagnostics - self.errors
    for _, key in ipairs(sorted_keys(self.outputs)) do
        local definition = self.outputs[key].definition
        self.output_count = self.output_count + 1
        if #definition.history >= 2 then
            table.insert(self.overridden, { key = key, history = definition.history })
        end
        local document = definition.origin.document
        if document == "manifest" then
            self.manifest_keys = self.manifest_keys + 1
        elseif document == "schema" then
            self.default_keys = self.default_keys + 1
        else
            self.document_keys = self.document_keys + 1
        end
    end
    self.dropped = configured_count - self.output_count
end

local function profile_diff(first, second)
    local diff = {
        first = first.name,
        second = second.name,
        entries = {},
        added = 0,
        removed = 0,
        changed = 0,
    }
    local keys = {}
    for key in pairs(first.outputs) do
        keys[key] = true
    end
    for key in pairs(second.outputs) do
        keys[key] = true
    end
    for _, key in ipairs(sorted_keys(keys)) do
        local before = first.outputs[key]
        local after = second.outputs[key]
        if before == nil then
            diff.added = diff.added + 1
            table.insert(diff.entries, { sign = "+", key = key, after = after })
        elseif after == nil then
            diff.removed = diff.removed + 1
            table.insert(diff.entries, { sign = "-", key = key, before = before })
        elseif before.notation ~= after.notation then
            diff.changed = diff.changed + 1
            table.insert(diff.entries, { sign = "~", key = key, before = before, after = after })
        end
    end
    return diff
end

local function main()
    local schema = load_schema(INPUT_DIR .. "/schema.txt")
    local library = Library.new(INPUT_DIR .. "/conf")
    local profiles = {}
    for number, line in ipairs(read_lines(INPUT_DIR .. "/manifest.txt")) do
        local profile = Profile.new(number, line)
        profile:process(schema, library, profiles)
        table.insert(profiles, profile)
    end
    local diffs = {}
    for index = 2, #profiles do
        table.insert(diffs, profile_diff(profiles[index - 1], profiles[index]))
    end
    emitter.write_outputs(OUTPUT_DIR, profiles, diffs)
end

main()
