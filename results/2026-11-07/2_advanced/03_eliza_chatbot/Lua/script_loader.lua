local M = {}
local globals = {INITIAL=true, FINAL=true, QUIT=true, STOP=true, DEFAULT=true, QUESTION=true, REPEAT=true, MEMSIZE=true, PERSIST=true, PRE=true, POST=true, SYNON=true}
local texts = {INITIAL=true, FINAL=true, DEFAULT=true, QUESTION=true, REPEAT=true}
local rules = {DECOMP=true, MEMORY=true}
local items = {REASM=true, GOTO=true, NEWKEY=true, RESTATE=true}
function M.words(text)
    local result = {}
    for word in text:gmatch("[^ ]+") do result[#result+1] = word end
    return result
end
function M.word(text)
    return text ~= "" and text:sub(1,1) ~= "'" and text:sub(-1) ~= "'" and not text:find("[^a-z0-9']")
end
function M.reference(text) return text:match("^%(%d%)$") ~= nil end
function M.wildcard(text) return text == "*" or text == "#" or text:sub(1,1) == "@" end
local function number(text) return text:match("^%d%d?$") ~= nil end
local function every(arguments, first, predicate)
    for i=first,#arguments do if not predicate(arguments[i]) then return false end end
    return true
end
local function formed(name, args)
    local count = #args
    if texts[name] or name == "REASM" then return count >= 1 end
    if name == "QUIT" or name == "STOP" then return count >= 1 and every(args,1,M.word) end
    if name == "MEMSIZE" then return count == 1 and number(args[1]) and tonumber(args[1]) >= 1 and tonumber(args[1]) <= 20 end
    if name == "PERSIST" then return count == 1 and (args[1] == "cycles" or args[1] == "memory") end
    if name == "PRE" or name == "SYNON" then return count >= 2 and every(args,1,M.word) end
    if name == "POST" then return count >= 2 and M.word(args[1]) end
    if name == "KEY" then return count == 2 and M.word(args[1]) and number(args[2]) end
    if rules[name] then
        return count >= 1 and every(args,1,function(x) return x == "*" or x == "#" or (x:sub(1,1) == "@" and M.word(x:sub(2))) or M.word(x) end)
    end
    if name == "GOTO" then return count == 1 and M.word(args[1]) end
    if name == "NEWKEY" then return count == 0 end
    return count >= 2 and M.word(args[1]) and every(args,2,function(x) return M.word(x) or M.reference(x) end)
end
function M.load(path)
    local s = {lines={}, texts={}, quit={}, stop={}, memsize=3, persist={}, pres={}, posts={}, pre={}, post={}, groups={}, group={}, keywords={}, keyword={}, rules={}, items={}, diagnostics={}}
    for name in pairs(texts) do s.texts[name] = {} end
    local current, rule, ignoring, definitions = nil,nil,false,{}
    for line in io.lines(path) do
        s.lines[#s.lines+1] = line
        local number_line = #s.lines
        if line ~= "" and line:sub(1,1) ~= "#" then
            local name, text = line:match("^([^ ]+) (.*)$")
            if not name then name,text = line,"" end
            local args = M.words(text)
            local skip = false
            if globals[name] or name == "KEY" then current,rule,ignoring = nil,nil,false
            elseif rules[name] or items[name] then
                if ignoring then skip = true elseif rules[name] then rule = nil end
            end
            if not skip then
                local code, message
                local definition = name == "MEMSIZE" and "MEMSIZE" or ((name == "KEY" or name == "PRE" or name == "POST" or name == "SYNON" or name == "PERSIST") and (name.." "..(args[1] or "")) or nil)
                if not (globals[name] or name == "KEY" or rules[name] or items[name]) then code,message = "SYNTAX","unknown directive "..name
                elseif not formed(name,args) then code,message = "SYNTAX","bad arguments for "..name
                elseif rules[name] and not current then code,message = "ORPHAN",name.." without KEY"
                elseif name == "REASM" and not rule then code,message = "ORPHAN","REASM without DECOMP or MEMORY"
                elseif (name == "GOTO" or name == "NEWKEY" or name == "RESTATE") and (not rule or rule.kind == "MEMORY") then code,message = "ORPHAN",name.." without DECOMP"
                elseif definition and definitions[definition] then
                    code,message = "DUPLICATE",definition.." first defined at line "..definitions[definition]
                    if name == "KEY" then ignoring = true end
                end
                if code then s.diagnostics[#s.diagnostics+1] = {line=number_line,code=code,message=message}
                else
                    if definition then definitions[definition] = number_line end
                    if texts[name] then table.insert(s.texts[name],text)
                    elseif name == "QUIT" or name == "STOP" then for _,word in ipairs(args) do s[name == "QUIT" and "quit" or "stop"][word] = true end
                    elseif name == "MEMSIZE" then s.memsize = tonumber(args[1])
                    elseif name == "PERSIST" then s.persist[args[1]] = true
                    elseif name == "PRE" or name == "POST" then
                        local replacement = {}; for i=2,#args do replacement[#replacement+1] = args[i] end
                        local entry = {source=args[1],replacement=replacement,line=number_line}
                        table.insert(s[name == "PRE" and "pres" or "posts"],entry)
                        s[name == "PRE" and "pre" or "post"][args[1]] = replacement
                    elseif name == "SYNON" then
                        local members = {}; for _,word in ipairs(args) do members[word] = true end
                        local group = {name=args[1],members=members,line=number_line}
                        table.insert(s.groups,group); s.group[args[1]] = members
                    elseif name == "KEY" then
                        current = {word=args[1],rank=tonumber(args[2]),line=number_line,index=#s.keywords+1,memories={},decomps={}}
                        table.insert(s.keywords,current); s.keyword[current.word] = current
                    elseif rules[name] then
                        rule = {kind=name,pattern=args,line=number_line,index=#s.rules+1,items={}}
                        table.insert(s.rules,rule); table.insert(current[name == "MEMORY" and "memories" or "decomps"],rule)
                    else
                        local item = {kind=name,text=text,args=args,line=number_line,index=#s.items+1}
                        table.insert(s.items,item); table.insert(rule.items,item)
                    end
                end
            end
        end
    end
    return s
end
return M
