local L = require("lexer")
local M = {}
M.__index = M
M.starts = { ["if"] = true, ifdef = true, ifndef = true }
M.branches = { ["else"] = true, elif = true, elifdef = true, elifndef = true }
function M.directive_name(tokens)
    if #tokens >= 2 and tokens[1].spelling == "#" and tokens[2].kind == "identifier" then return tokens[2].spelling end
    return false
end
local function guard(lines)
    local nonempty = {}
    for _, line in ipairs(lines) do if #line.tokens > 0 then nonempty[#nonempty + 1] = line.tokens end end
    if #nonempty == 0 then return false end
    local first, last = nonempty[1], nonempty[#nonempty]
    if #first ~= 3 or M.directive_name(first) ~= "ifndef" or first[3].kind ~= "identifier" then return false end
    if #last ~= 2 or M.directive_name(last) ~= "endif" then return false end
    local depth = 0
    for i, tokens in ipairs(nonempty) do
        local name = M.directive_name(tokens)
        if M.branches[name] and depth == 1 then return false end
        if M.starts[name] then depth = depth + 1 elseif name == "endif" then depth = depth - 1 end
        if depth == 0 and i ~= #nonempty then return false end
    end
    return depth == 0 and first[3].spelling or false
end
function M.new() return setmetatable({ files = {}, order = {} }, M) end
function M:search(name, quoted)
    local paths = quoted and { name, "include/" .. name } or { "include/" .. name }
    for _, path in ipairs(paths) do
        local file = io.open("input/" .. path, "r")
        if file then file:close(); return path end
    end
    return false
end
function M:load(path)
    if not self.files[path] then
        local file = assert(io.open("input/" .. path, "r"))
        local contents = file:read("*a")
        file:close()
        local lines = L.source(contents)
        local _, count = contents:gsub("\n", "")
        self.files[path] = { path = path, physical_lines = count, lines = lines, guard = guard(lines),
            once = false, entered = 0, skipped = 0, output_lines = 0, skipped_lines = 0 }
        self.order[#self.order + 1] = path
    end
    return self.files[path]
end
return M
