local Box = require("boxes")
local Lexer = require("lexer")
local Layout = {}
local types = {ordinary = 1, operator = 2, binary = 3, relation = 4, open = 5, close = 6, punctuation = 7}
local spacing = {{0, 1, "B", "R", 0, 0, 0}, {1, 1, false, "R", 0, 0, 0},
    {"B", "B", false, false, "B", false, false}, {"R", "R", false, 0, "R", 0, 0},
    {0, 0, false, 0, 0, 0, 0}, {0, 1, "B", "R", 0, 0, 0}, {"P", "P", false, "P", "P", "P", "P"}}

function Layout.element_types(node)
    local kind = "ordinary"
    if node.kind == "symbol" then kind = Box.symbol_types[node.value] or kind
    elseif node.kind == "command" then kind = Box.command_types[node.value]
    elseif node.kind == "delim" then return {"open", "close"}
    elseif node.kind == "script" then return Layout.element_types(node.children[1])
    elseif node.kind == "overset" or node.kind == "underset" then return Layout.element_types(node.children[2]) end
    return {kind, kind}
end

function Layout.converted_types(nodes)
    local result = {}
    local before_binary = {binary = true, operator = true, relation = true, open = true, punctuation = true}
    for i, node in ipairs(nodes) do result[i] = Layout.element_types(node) end
    for i, current in ipairs(result) do
        if current[1] == "binary" and (i == 1 or before_binary[result[i - 1][2]]) then current[1], current[2] = "ordinary", "ordinary" end
        if (current[1] == "relation" or current[1] == "close" or current[1] == "punctuation") and i >= 2 and result[i - 1][2] == "binary" then
            result[i - 1] = {"ordinary", "ordinary"}
        end
    end
    if #result > 0 and result[#result][2] == "binary" then result[#result] = {"ordinary", "ordinary"} end
    return result
end

function Layout.word_element(node)
    if node.kind == "script" then return Layout.word_element(node.children[1]) end
    return node.kind == "command" and (Lexer.greek[node.value:sub(2)] == true or node.value == "\\infty")
end

function Layout.alphanumeric(node)
    if node.kind == "identifier" or node.kind == "number" or Layout.word_element(node) then return true end
    if node.kind == "script" then return Layout.alphanumeric(node.children[1]) end
    local names = {overline = true, hat = true, vec = true, dot = true, tilde = true}
    return node.kind == "accent" and names[node.value] == true and Layout.alphanumeric(node.children[1])
end

function Layout.spacing(nodes, style, parameters)
    local converted, gaps = Layout.converted_types(nodes), {}
    local values = {B = style == "normal" and parameters.bin_space or 0,
        R = style == "normal" and parameters.rel_space or 0, P = style == "normal" and parameters.punct_space or 0}
    for i = 1, #nodes - 1 do
        if Layout.alphanumeric(nodes[i]) and Layout.alphanumeric(nodes[i + 1]) and (Layout.word_element(nodes[i]) or Layout.word_element(nodes[i + 1])) then gaps[i] = 1
        else
            local entry = spacing[types[converted[i][2]]][types[converted[i + 1][1]]]
            gaps[i] = type(entry) == "string" and values[entry] or entry
        end
    end
    return converted, gaps
end

function Layout.row(children, gaps, description, roles)
    local ascent, descent, width = 0, 0, 0
    for _, child in ipairs(children) do ascent, descent, width = math.max(ascent, child.baseline), math.max(descent, child:descent()), width + child.width end
    for _, gap in ipairs(gaps) do width = width + gap end
    local result, x = Box.new(width, ascent + descent + 1, ascent, description or "row"), 0
    for i, child in ipairs(children) do
        result:add(child, x, ascent - child.baseline, roles and roles[i] or "")
        x = x + child.width + (gaps[i] or 0)
    end
    return result
end

return Layout
