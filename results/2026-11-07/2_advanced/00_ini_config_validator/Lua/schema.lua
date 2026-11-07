local WILDCARD = "*"
local FLAGS = { required = true, secret = true, unique = true, fixed = true }
local TEXT_ATTRIBUTES = { default = true, item = true, when = true, le = true }

local function comma_list(text)
    local items = {}
    for item in text:gmatch("[^,]+") do
        table.insert(items, item)
    end
    return items
end

local Spec = {}
Spec.__index = Spec

function Spec.new(line, words)
    local section, key = words[1]:match("^(.*)%.([^.]*)$")
    local spec = setmetatable({
        line = line,
        pattern = words[1],
        key = key,
        section_parts = {},
        wildcard = false,
        kind = words[2],
        required = false,
        secret = false,
        unique = false,
        fixed = false,
        values = {},
        item = "string",
        aliases = {},
    }, Spec)
    for part in section:gmatch("[^.]+") do
        table.insert(spec.section_parts, part)
        spec.wildcard = spec.wildcard or part == WILDCARD
    end
    for index = 3, #words do
        spec:add_attribute(words[index])
    end
    return spec
end

function Spec:add_attribute(attribute)
    local name, argument = attribute:match("^([^=]*)=?(.*)$")
    if FLAGS[name] then
        self[name] = true
    elseif TEXT_ATTRIBUTES[name] then
        self[name] = argument
    elseif name == "range" then
        local lower, upper = argument:match("^(.-)%.%.(.*)$")
        self.range = { lower = lower, upper = upper }
    elseif name == "values" then
        self.values = comma_list(argument)
    elseif name == "alias" then
        self.aliases = comma_list(argument)
    end
end

function Spec:matches(section)
    local count = 0
    for part in (section .. "."):gmatch("(.-)%.") do
        count = count + 1
        local pattern = self.section_parts[count]
        if pattern ~= WILDCARD and pattern ~= part then
            return false
        end
    end
    return count == #self.section_parts
end

local Schema = {}
Schema.__index = Schema

function Schema.new(specs)
    local exact = {}
    for _, spec in ipairs(specs) do
        if not spec.wildcard then
            exact[spec.pattern] = spec
        end
    end
    return setmetatable({ specs = specs, exact = exact }, Schema)
end

function Schema:spec_for(full_key)
    if self.exact[full_key] then
        return self.exact[full_key]
    end
    local section, key = full_key:match("^(.*)%.([^.]*)$")
    for _, spec in ipairs(self.specs) do
        if spec.wildcard and spec.key == key and spec:matches(section) then
            return spec
        end
    end
    return nil
end

function Schema:target_keys(spec, sections)
    if not spec.wildcard then
        return { spec.pattern }
    end
    local names = {}
    for section in pairs(sections) do
        table.insert(names, section)
    end
    table.sort(names)
    local keys = {}
    for _, section in ipairs(names) do
        local key = section .. "." .. spec.key
        if spec:matches(section) and self:spec_for(key) == spec then
            table.insert(keys, key)
        end
    end
    return keys
end

local function load_schema(path)
    local specs = {}
    local number = 0
    for line in io.lines(path) do
        number = number + 1
        if line:find("[^ ]") and line:sub(1, 1) ~= "#" then
            local words = {}
            for word in line:gmatch("[^ ]+") do
                table.insert(words, word)
            end
            table.insert(specs, Spec.new(number, words))
        end
    end
    return Schema.new(specs)
end

return { load_schema = load_schema }
