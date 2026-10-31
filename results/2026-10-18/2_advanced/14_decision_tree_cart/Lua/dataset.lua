local M = {}

function M.read_lines(path)
    local lines = {}
    for line in io.lines(path) do lines[#lines + 1] = line end
    return lines
end

local function fields(line, separator)
    local result = {}
    for value in (line .. separator):gmatch("(.-)" .. separator) do result[#result + 1] = value end
    return result
end

function M.load(directory)
    local attributes, classes, target = {}, {}
    for _, line in ipairs(M.read_lines(directory .. "/schema.txt")) do
        local parts = fields(line, " ")
        if parts[1] == "ATTRIBUTE" then
            local attribute = {index = #attributes + 1, name = parts[2], integer = parts[3] == "INT", values = {}, positions = {}}
            for index = 4, #parts do
                attribute.values[#attribute.values + 1] = parts[index]
                attribute.positions[parts[index]] = #attribute.values
            end
            attributes[#attributes + 1] = attribute
        else
            target = parts[2]
            for index = 3, #parts do classes[#classes + 1] = parts[index] end
        end
    end
    local class_positions = {}
    for index, name in ipairs(classes) do class_positions[name] = index end
    local function read_rows(name)
        local result = {}
        for index, line in ipairs(M.read_lines(directory .. "/" .. name .. ".csv")) do
            if index > 1 then
                local parts, values = fields(line, ","), {}
                for _, attribute in ipairs(attributes) do
                    local text = parts[attribute.index + 1]
                    local value = false
                    if text ~= "?" then
                        value = attribute.integer and tonumber(text) or attribute.positions[text]
                    end
                    values[attribute.index] = value
                end
                result[#result + 1] = {id = parts[1], values = values, label = class_positions[parts[#parts]]}
            end
        end
        return result
    end
    local settings = {}
    for _, line in ipairs(M.read_lines(directory .. "/params.txt")) do
        local parts = fields(line, " ")
        local key = parts[1]:lower()
        local values = {}
        for index = 2, #parts do values[#values + 1] = tonumber(parts[index]) end
        settings[key] = key == "curve" and values or values[1]
    end
    return {attributes = attributes, target = target, classes = classes, settings = settings,
        train = read_rows("train"), validation = read_rows("validation"), test = read_rows("test")}
end

return M
