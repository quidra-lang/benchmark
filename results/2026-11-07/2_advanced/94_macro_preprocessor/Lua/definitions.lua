local L = require("lexer")
local D = {}
D.builtins = { __LINE__ = true, __FILE__ = true, __COUNTER__ = true }
local variadic_error = '"__VA_ARGS__" can only appear in the expansion of a variadic macro'
local function fail(message) error({ category = "definition", message = message }, 0) end
function D.check_name(tokens, directive)
    if #tokens == 0 then return "no macro name given in #" .. directive .. " directive" end
    if tokens[1].kind ~= "identifier" then return "macro names must be identifiers" end
    local name = tokens[1].spelling
    if name == "defined" then return '"defined" cannot be used as a macro name' end
    if D.builtins[name] then return "cannot " .. (directive == "define" and "redefine" or "undefine") .. ' builtin macro "' .. name .. '"' end
end
function D.signature(macro)
    if not macro.parameters then return macro.name end
    local parameters = { table.unpack(macro.parameters) }
    if macro.variadic then parameters[#parameters] = "..." end
    return macro.name .. "(" .. table.concat(parameters, ", ") .. ")"
end
function D.identical(a, b)
    if (not a.parameters) ~= (not b.parameters) or a.variadic ~= b.variadic then return false end
    if a.parameters then
        if #a.parameters ~= #b.parameters then return false end
        for i, name in ipairs(a.parameters) do if name ~= b.parameters[i] then return false end end
    end
    if #a.replacement ~= #b.replacement then return false end
    for i, token in ipairs(a.replacement) do
        if token.spelling ~= b.replacement[i].spelling or token.space ~= b.replacement[i].space then return false end
    end
    return true
end
function D.parse(tokens, position, main_file)
    local err = D.check_name(tokens, "define")
    if err then fail(err) end
    local name, parameters, variadic, index, parameter_set = tokens[1].spelling, false, false, 2, {}
    if name == "__VA_ARGS__" then fail(variadic_error) end
    if tokens[2] and tokens[2].spelling == "(" and not tokens[2].space then
        parameters, index = {}, 3
        if not tokens[index] then fail("missing ')' in macro parameter list") end
        if tokens[index].spelling == ")" then index = index + 1
        else
            while true do
                local token = tokens[index]
                if not token then fail("missing ')' in macro parameter list") end
                if token.spelling == "..." then parameters[#parameters + 1], variadic = "__VA_ARGS__", true
                elseif token.kind == "identifier" then
                    if token.spelling == "__VA_ARGS__" then fail(variadic_error) end
                    if parameter_set[token.spelling] then fail('duplicate macro parameter "' .. token.spelling .. '"') end
                    parameters[#parameters + 1] = token.spelling
                else fail('expected parameter name, found "' .. token.spelling .. '"') end
                parameter_set[parameters[#parameters]] = true
                index = index + 1
                if not tokens[index] then fail("missing ')' in macro parameter list") end
                local following = tokens[index].spelling
                index = index + 1
                if following == ")" then break end
                if variadic then fail('expected \')\' after "...", found "' .. following .. '"') end
                if following ~= "," then fail('expected \',\' or \')\', found "' .. following .. '"') end
            end
        end
    end
    local replacement = {}
    for i = index, #tokens do replacement[#replacement + 1] = L.clone(tokens[i]) end
    if #replacement > 0 then
        replacement[1].space = false
        if replacement[1].spelling == "##" or replacement[#replacement].spelling == "##" then fail("'##' cannot appear at either end of a macro expansion") end
    end
    for i, token in ipairs(replacement) do
        if token.kind == "identifier" and token.spelling == "__VA_ARGS__" and not variadic then fail(variadic_error) end
        local following = replacement[i + 1]
        if token.spelling == "#" and parameters and (not following or following.kind ~= "identifier" or not parameter_set[following.spelling]) then
            fail("'#' is not followed by a macro parameter")
        end
    end
    return { name = name, parameters = parameters, variadic = variadic, replacement = replacement,
        position = position, main_file = main_file, expanded = 0, tested = 0 }
end
return D
