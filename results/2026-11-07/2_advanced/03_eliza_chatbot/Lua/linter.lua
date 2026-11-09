local matcher = require("matcher")
local loader = require("script_loader")
local M = {}
local codes = {"SYNTAX","ORPHAN","DUPLICATE","KEY_NO_DECOMP","KEY_UNREACHABLE","SYNON_UNUSED","PRE_CHAIN","SYNON_UNKNOWN","RULE_NO_REASM","RULE_SHADOWED","REF_UNBOUND","TARGET_UNDEFINED","TARGET_CYCLE"}
local errors = {SYNTAX=true,ORPHAN=true,DUPLICATE=true,SYNON_UNKNOWN=true,REF_UNBOUND=true,TARGET_UNDEFINED=true,TARGET_CYCLE=true}
function M.lint(s)
    local found,order,graph = {},{},{}
    for i,code in ipairs(codes) do order[code] = i end
    local function add(line,code,message) found[#found+1] = {line=line,code=code,message=message,order=#found+1} end
    for _,d in ipairs(s.diagnostics) do add(d.line,d.code,d.message) end
    local replacements,targets,used = {},{},{}
    for _,pre in ipairs(s.pres) do for _,word in ipairs(pre.replacement) do replacements[word] = true end end
    for _,item in ipairs(s.items) do if item.kind == "GOTO" or item.kind == "RESTATE" then targets[item.args[1]] = true end end
    for _,rule in ipairs(s.rules) do for _,e in ipairs(rule.pattern) do if e:sub(1,1) == "@" then used[e:sub(2)] = true end end end
    for _,key in ipairs(s.keywords) do
        graph[key.word] = {}
        if #key.decomps == 0 then add(key.line,"KEY_NO_DECOMP","keyword "..key.word.." has no DECOMP") end
        if s.pre[key.word] and not replacements[key.word] and not targets[key.word] then add(key.line,"KEY_UNREACHABLE","keyword "..key.word.." is replaced by PRE") end
        for _,rule in ipairs(key.decomps) do for _,item in ipairs(rule.items) do
            if (item.kind == "GOTO" or item.kind == "RESTATE") and s.keyword[item.args[1]] then table.insert(graph[key.word],item.args[1]) end
        end end
    end
    for _,group in ipairs(s.groups) do if not used[group.name] then add(group.line,"SYNON_UNUSED","group "..group.name.." is never used") end end
    for _,pre in ipairs(s.pres) do for _,word in ipairs(pre.replacement) do if s.pre[word] then add(pre.line,"PRE_CHAIN","replacement "..word.." is itself replaced by PRE") end end end
    local function unknown(rule)
        local result = {}
        for _,e in ipairs(rule.pattern) do if e:sub(1,1) == "@" and not s.group[e:sub(2)] then result[#result+1] = e:sub(2) end end
        return result
    end
    local function reaches(start,goal,seen)
        if start == goal then return true end
        if seen[start] then return false end
        seen[start] = true
        for _,target in ipairs(graph[start]) do if reaches(target,goal,seen) then return true end end
        return false
    end
    for _,key in ipairs(s.keywords) do for _,rules in ipairs({key.memories,key.decomps}) do for i,rule in ipairs(rules) do
        local missing = unknown(rule)
        for _,name in ipairs(missing) do add(rule.line,"SYNON_UNKNOWN","unknown group "..name) end
        if #rule.items == 0 then add(rule.line,"RULE_NO_REASM","rule has no reassembly") end
        if #missing == 0 then for j=1,i-1 do
            if #unknown(rules[j]) == 0 and matcher.covers(rules[j].pattern,rule.pattern,s.group) then add(rule.line,"RULE_SHADOWED","pattern is shadowed by line "..rules[j].line); break end
        end end
        local wildcards = 0; for _,e in ipairs(rule.pattern) do if loader.wildcard(e) then wildcards = wildcards+1 end end
        for _,item in ipairs(rule.items) do
            local references = {}
            if item.kind == "REASM" then for n in item.text:gmatch("%((%d)%)") do references[#references+1] = tonumber(n) end
            elseif item.kind == "RESTATE" then for n=2,#item.args do if loader.reference(item.args[n]) then references[#references+1] = tonumber(item.args[n]:sub(2,2)) end end end
            for _,n in ipairs(references) do if n == 0 or n > wildcards then add(item.line,"REF_UNBOUND","reference ("..n..") is not bound") end end
            if item.kind == "GOTO" or item.kind == "RESTATE" then
                local target = item.args[1]
                if not s.keyword[target] then add(item.line,"TARGET_UNDEFINED","target "..target.." is not a keyword")
                elseif reaches(target,key.word,{}) then add(item.line,"TARGET_CYCLE","edge "..key.word.." -> "..target.." is on a cycle") end
            end
        end
    end end end
    table.sort(found,function(a,b) if a.line ~= b.line then return a.line < b.line elseif a.code ~= b.code then return order[a.code] < order[b.code] else return a.order < b.order end end)
    if #found == 0 then return {"OK"} end
    local lines,count = {},0
    for _,d in ipairs(found) do lines[#lines+1] = d.line.." "..d.code.." "..d.message; if errors[d.code] then count=count+1 end end
    lines[#lines+1] = "TOTAL "..#found.." errors="..count.." warnings="..(#found-count)
    return lines
end
return M
