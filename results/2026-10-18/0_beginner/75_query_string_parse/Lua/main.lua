local function decode_component(source)
    source = source:gsub("%+", " ")
    return (source:gsub("%%(%x%x)", function(hex)
        return string.char(tonumber(hex, 16))
    end))
end

local queries = {
    "name=Alice+Smith&age=30&city=New%20York",
    "q=c%2B%2B+tutorial&page=2&sort=desc&page=3",
    "msg=50%25+off%21&debug&lang=en&ref=&lang=ja",
    "redirect=https%3a%2f%2fexample.com%2Fhome&token=abc==&item10=pen&item2=fish%26chips",
}
for number, query in ipairs(queries) do
    local parameters = {}
    for item in query:gmatch("[^&]+") do
        local position = item:find("=", 1, true)
        local key = decode_component(position and item:sub(1, position - 1) or item)
        local value = position and decode_component(item:sub(position + 1)) or ""
        parameters[key] = parameters[key] or {}
        parameters[key][#parameters[key] + 1] = value
    end
    local keys = {}
    for key in pairs(parameters) do keys[#keys + 1] = key end
    table.sort(keys)
    io.write(string.format("query %d:\n", number))
    for _, key in ipairs(keys) do
        local quoted = {}
        for _, value in ipairs(parameters[key]) do quoted[#quoted + 1] = '"' .. value .. '"' end
        io.write("  ", key, ": ", table.concat(quoted, ", "), "\n")
    end
end
