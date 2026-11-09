local directory = arg[0]:match("^(.*)/") or "."
package.path = directory.."/?.lua;"..package.path
local loader = require("script_loader")
local linter = require("linter")
local matcher = require("matcher")
local responder = require("responder")
local memory = require("memory")
local sources = {"keyword","memory","question","default","repeat"}
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}; for key,item in pairs(value) do result[key] = copy(item) end
    return result
end
local function append(target,values) for _,value in ipairs(values) do target[#target+1] = value end end
local function normalize(text)
    local clauses,words,word = {},{},""
    local function finish_word()
        word = word:gsub("^'+",""):gsub("'+$","")
        if word ~= "" then words[#words+1] = word end
        word = ""
    end
    for character in (text:lower().."."):gmatch(".") do
        if character:match("[a-z0-9']") then word=word..character
        else
            finish_word()
            if character:find("[,%.%?!;]") and #words > 0 then clauses[#clauses+1]=words; words={} end
        end
    end
    return clauses
end
local function flatten(clauses) local words={}; for _,clause in ipairs(clauses) do append(words,clause) end; return words end
local function clause_key(clauses)
    local result={}; for _,clause in ipairs(clauses) do result[#result+1]=table.concat(clause,"\0") end
    return table.concat(result,"\1")
end
local function entries(keyword)
    local result={}
    for _,kind in ipairs({"memories","decomps"}) do for n,rule in ipairs(keyword[kind]) do result[#result+1]={kind == "memories" and "memory" or "decomp",n,rule} end end
    return result
end
local function grouped(values,size)
    local result={}; for i=1,#values,size do local group={}; for j=i,math.min(i+size-1,#values) do group[#group+1]=values[j] end; result[#result+1]=table.concat(group," ") end
    return result
end
local function ranked_counts(counts)
    local words={}; for word in pairs(counts) do words[#words+1]=word end
    table.sort(words,function(a,b) return counts[a] == counts[b] and a < b or counts[a] > counts[b] end)
    local result={}; for i=1,math.min(5,#words) do result[#result+1]=words[i].." "..counts[words[i]] end
    return #result == 0 and "none" or table.concat(result,", ")
end
local function source_line(session)
    local result={"turns="..session.turns}
    for _,name in ipairs(sources) do result[#result+1]=name.."="..session.sources[name] end
    return table.concat(result," ")
end
local Bot={}; Bot.__index=Bot
function Bot.new(script)
    local state={positions={},hits={},item_uses={},uses={},replies={},list_positions={DEFAULT=1,QUESTION=1,REPEAT=1},memory=memory.new(script.memsize)}
    for _,rule in ipairs(script.rules) do state.positions[rule.index]=1; state.hits[rule.index]=0 end
    for _,item in ipairs(script.items) do state.item_uses[item.index]=0 end
    for _,key in ipairs(script.keywords) do state.uses[key.index]=0; state.replies[key.index]=0 end
    return setmetatable({script=script,state=state,transcript={},total={turns=0,sources={keyword=0,memory=0,question=0,default=0,["repeat"]=0}}},Bot)
end
function Bot:prefix() return self.state.session.name.." "..self.state.session.turns end
function Bot:reset()
    for _,rule in ipairs(self.script.rules) do self.state.positions[rule.index]=1 end
    for name in pairs(self.state.list_positions) do self.state.list_positions[name]=1 end
end
function Bot:take_text(name)
    local position=self.state.list_positions[name]
    self.state.list_positions[name]=position % #self.script.texts[name]+1
    return self.script.texts[name][position]
end
function Bot:take_item(rule)
    local position=self.state.positions[rule.index]
    local item=rule.items[position]
    self.state.positions[rule.index]=position % #rule.items+1
    self.state.item_uses[item.index]=self.state.item_uses[item.index]+1
    return item,position
end
function Bot:prepared(text)
    local clauses=normalize(text)
    for i,clause in ipairs(clauses) do
        local words={}; for _,word in ipairs(clause) do append(words,self.script.pre[word] or {word}) end
        clauses[i]=words
    end
    return clauses
end
function Bot:is_quit(text)
    local words=flatten(normalize(text)); return #words == 1 and self.script.quit[words[1]] == true
end
function Bot:keyword_list(words)
    local result,seen={},{ }
    for _,word in ipairs(words) do if self.script.keyword[word] and not seen[word] then result[#result+1]=self.script.keyword[word]; seen[word]=#result end end
    table.sort(result,function(a,b) return a.rank == b.rank and seen[a.word] < seen[b.word] or a.rank > b.rank end)
    return result
end
function Bot:selected(clauses)
    for i,clause in ipairs(clauses) do for _,word in ipairs(clause) do if self.script.keyword[word] then return i,clause end end end
end
function Bot:find_rule(rules,words)
    for number,rule in ipairs(rules) do local bindings=matcher.match(rule.pattern,words,self.script.group); if bindings then return rule,number,bindings end end
end
function Bot:keyword_reply(clauses,trace)
    local number,words=self:selected(clauses)
    if not number then trace[#trace+1]="CLAUSE none"; return nil end
    trace[#trace+1]="CLAUSE "..number.." "..table.concat(words," ")
    local keys=self:keyword_list(words); local names={}; for _,key in ipairs(keys) do names[#names+1]=key.word end
    trace[#trace+1]="KEYS "..table.concat(names," ")
    local rule,n,bindings=self:find_rule(keys[1].memories,words)
    if rule then
        trace[#trace+1]="MEMORY "..keys[1].word.." "..n
        self.state.hits[rule.index]=self.state.hits[rule.index]+1
        if #rule.items > 0 then
            local item=self:take_item(rule)
            local text=responder.reply(item.text,bindings,self.script.post)
            if memory.store(self.state.memory,self:prefix(),keys[1].word,text) then self.state.session.stored=self.state.session.stored+1 end
        end
    end
    local entered={}
    for _,initial in ipairs(keys) do if not entered[initial.word] then
        trace[#trace+1]="ENTER "..initial.word
        local key,current=initial,words
        while key do
            entered[key.word]=true
            self.state.uses[key.index]=self.state.uses[key.index]+1
            rule,n,bindings=self:find_rule(key.decomps,current)
            if not rule then trace[#trace+1]="NOMATCH "..key.word; break end
            self.state.hits[rule.index]=self.state.hits[rule.index]+1
            if #rule.items == 0 then trace[#trace+1]="DECOMP "..key.word.." "..n.." 0"; break end
            local item,position=self:take_item(rule)
            trace[#trace+1]="DECOMP "..key.word.." "..n.." "..position
            if item.kind == "REASM" then
                self.state.replies[key.index]=self.state.replies[key.index]+1
                self.state.session.topics[key.word]=(self.state.session.topics[key.word] or 0)+1
                return responder.reply(item.text,bindings,self.script.post)
            end
            if item.kind == "NEWKEY" then break end
            local target=item.args[1]
            if not self.script.keyword[target] or entered[target] then trace[#trace+1]="BLOCKED "..target; break end
            if item.kind == "RESTATE" then
                current=responder.restate(item.args,bindings)
                trace[#trace+1]="RESTATE "..target..(#current > 0 and " "..table.concat(current," ") or "")
            else trace[#trace+1]="GOTO "..target end
            key=self.script.keyword[target]
        end
    end end
end
function Bot:decide(text)
    local session=self.state.session
    local clauses=normalize(text); local trace,reply,source={}
    if #self.script.texts.REPEAT > 0 and #clauses > 0 and clause_key(clauses) == session.previous then
        trace[#trace+1]="REPEAT"; reply=self:take_text("REPEAT"); source="repeat"
    else
        reply=self:keyword_reply(self:prepared(text),trace); source="keyword"
        if not reply then
            if #self.state.memory.texts > 0 then reply=memory.recall(self.state.memory,self:prefix()); source="memory"; session.recalled=session.recalled+1
            elseif text:sub(-1) == "?" and #self.script.texts.QUESTION > 0 then reply=self:take_text("QUESTION"); source="question"
            else reply=self:take_text("DEFAULT"); source="default" end
        end
    end
    trace[#trace+1]="REPLY "..source
    session.previous=clause_key(clauses); session.sources[source]=session.sources[source]+1
    if source == "question" or source == "default" then session.unrecognized[#session.unrecognized+1]=session.turns end
    return reply,trace
end
function Bot:command(line)
    local name,text=line:match("^([^ ]+) (.*)$"); if not name then name,text=line,"" end
    local args=loader.words(text)
    local none={ [":keys"]=true,[":why"]=true,[":history"]=true,[":memory"]=true,[":forget"]=true,[":reset"]=true,[":unused"]=true,[":stats"]=true,[":undo"]=true }
    local one={ [":groups"]=true,[":find"]=true,[":script"]=true,[":cycles"]=true,[":coverage"]=true }
    local free={ [":prepare"]=true,[":reflect"]=true,[":say"]=true,[":explain"]=true }
    if not (none[name] or one[name] or free[name] or name == ":trace" or name == ":test") then return {"unknown command "..name} end
    if (none[name] and #args > 0) or (one[name] and #args ~= 1) or (free[name] and text == "") or (name == ":test" and #args < 2) or (name == ":trace" and (#args ~= 1 or (args[1] ~= "on" and args[1] ~= "off"))) then return {"bad arguments"} end
    if (name == ":script" or name == ":cycles" or name == ":coverage" or name == ":test") and not self.script.keyword[args[1]] then return {"unknown keyword "..args[1]} end
    local result,session={},self.state.session
    if name == ":prepare" then
        local clauses=self:prepared(text)
        for i,clause in ipairs(clauses) do result[#result+1]="clause "..i..": "..table.concat(clause," ") end
        if #clauses == 0 then result[#result+1]="no words" end
        local i,words=self:selected(clauses)
        if not i then result[#result+1]="selected none"
        else
            result[#result+1]="selected "..i
            local keys={}; for _,key in ipairs(self:keyword_list(words)) do keys[#keys+1]=key.word.."/"..key.rank end
            result[#result+1]="keys "..table.concat(keys," ")
        end
    elseif name == ":test" then
        local words=flatten(self:prepared(text:match("^[^ ]+ (.*)$")))
        for _,entry in ipairs(entries(self.script.keyword[args[1]])) do
            local bindings=matcher.match(entry[3].pattern,words,self.script.group)
            local value="no match"
            if bindings then
                local parts={}; for _,binding in ipairs(bindings) do parts[#parts+1]="["..table.concat(binding," ").."]" end
                value=#parts == 0 and "match" or table.concat(parts," ")
            end
            result[#result+1]=entry[1].." "..entry[2]..": "..value
        end
        if #result == 0 then result={"no rules"} end
    elseif name == ":reflect" then
        for _,clause in ipairs(self:prepared(text)) do result[#result+1]=table.concat(responder.reflect(clause,self.script.post)," ") end
        if #result == 0 then result={"no words"} end
    elseif name == ":keys" then
        local keys={}; for _,key in ipairs(self.script.keywords) do keys[#keys+1]=key end
        table.sort(keys,function(a,b) return a.rank == b.rank and a.word < b.word or a.rank > b.rank end)
        local labels={}; for _,key in ipairs(keys) do labels[#labels+1]=key.word.."/"..key.rank end
        result=grouped(labels,8)
    elseif name == ":groups" then
        for _,group in ipairs(self.script.groups) do if group.members[args[1]] then result[#result+1]=group.name end end
        table.sort(result); result={#result == 0 and "none" or table.concat(result," ")}
    elseif name == ":find" then
        local word=args[1]; local key=self.script.keyword[word]
        if key then result[#result+1]="keyword rank "..key.rank end
        for _,kind in ipairs({"pre","post"}) do for _,sub in ipairs(self.script[kind == "pre" and "pres" or "posts"]) do
            local found=sub.source == word; for _,value in ipairs(sub.replacement) do if value == word then found=true end end
            if found then result[#result+1]=kind.." "..sub.line..": "..sub.source.." -> "..table.concat(sub.replacement," ") end
        end end
        for _,group in ipairs(self.script.groups) do if group.members[word] then result[#result+1]="group "..group.name.." line "..group.line end end
        for _,keyword in ipairs(self.script.keywords) do for _,entry in ipairs(entries(keyword)) do
            for _,element in ipairs(entry[3].pattern) do if element == word then result[#result+1]="pattern "..keyword.word.." "..entry[1].." "..entry[2]; break end end
        end end
        if self.script.stop[word] then result[#result+1]="stop word" end
        if self.script.quit[word] then result[#result+1]="quit word" end
        if #result == 0 then result={"not found"} end
    elseif name == ":script" then
        local key=self.script.keyword[args[1]]; local numbers={key.line}
        for _,entry in ipairs(entries(key)) do numbers[#numbers+1]=entry[3].line; for _,item in ipairs(entry[3].items) do numbers[#numbers+1]=item.line end end
        table.sort(numbers); for _,n in ipairs(numbers) do result[#result+1]=n.." "..self.script.lines[n] end
    elseif name == ":why" then result=session.last_trace or {"no reply yet"}
    elseif name == ":trace" then session.trace_on=args[1] == "on"; result={"trace "..args[1]}
    elseif name == ":history" then
        for i=math.max(1,#session.history-4),#session.history do result[#result+1]=session.history[i] end
        if #result == 0 then result={"no turns yet"} end
    elseif name == ":memory" then
        result={"memory "..#self.state.memory.texts.."/"..self.state.memory.capacity}
        for i,value in ipairs(self.state.memory.texts) do result[#result+1]=i..": "..value end
    elseif name == ":forget" then local count=#self.state.memory.texts; memory.clear(self.state.memory,self:prefix()); result={"forgot "..count}
    elseif name == ":cycles" or name == ":coverage" then
        for _,entry in ipairs(entries(self.script.keyword[args[1]])) do
            local rule=entry[3]; local prefix=entry[1].." "..entry[2]..": "
            if name == ":cycles" then result[#result+1]=prefix..(#rule.items == 0 and "empty" or "next "..self.state.positions[rule.index].."/"..#rule.items)
            else
                local uses={}; for _,item in ipairs(rule.items) do uses[#uses+1]=tostring(self.state.item_uses[item.index]) end
                result[#result+1]=prefix.."hits "..self.state.hits[rule.index].." entries "..(#uses == 0 and "-" or table.concat(uses," "))
            end
        end
        if #result == 0 then result={"no rules"} end
    elseif name == ":reset" then self:reset(); result={"cycles reset"}
    elseif name == ":unused" then
        local numbers={}; for _,item in ipairs(self.script.items) do if self.state.item_uses[item.index] == 0 then numbers[#numbers+1]=item.line end end
        table.sort(numbers); result={"unused "..#numbers}; local values={}; for _,n in ipairs(numbers) do values[#values+1]=tostring(n) end; append(result,grouped(values,12))
    elseif name == ":stats" then result={source_line(session)}
    elseif name == ":say" or name == ":explain" then
        if self:is_quit(text) then result={"would quit"}
        else
            local saved=copy(self.state); local reply,trace=self:decide(text); self.state=saved
            result=name == ":say" and {reply} or trace
        end
    elseif name == ":undo" then
        if not session.undo then result={"nothing to undo"}
        else self.state=session.undo; result={"undone turn "..(self.state.session.turns+1)} end
    end
    return result
end
function Bot:indented(lines) for _,line in ipairs(lines) do self.transcript[#self.transcript+1]="  "..line end end
function Bot:notes()
    local session=self.state.session
    self.transcript[#self.transcript+1]="NOTES "..session.name
    local unrecognized={}; for _,n in ipairs(session.unrecognized) do unrecognized[#unrecognized+1]=tostring(n) end
    self:indented({source_line(session),"topics: "..ranked_counts(session.topics),"words: "..ranked_counts(session.words),"memory: stored="..session.stored.." recalled="..session.recalled.." pending="..#self.state.memory.texts,"unrecognized: "..(#unrecognized == 0 and "none" or table.concat(unrecognized," "))})
    self.total.turns=self.total.turns+session.turns
    for _,name in ipairs(sources) do self.total.sources[name]=self.total.sources[name]+session.sources[name] end
end
function Bot:run(path)
    local sessions=0
    for line in io.lines(path) do
        if line:sub(1,8) == "SESSION " then
            sessions=sessions+1; local name=line:sub(9)
            if sessions > 1 then
                self.transcript[#self.transcript+1]=""
                if not self.script.persist.cycles then self:reset() end
                if not self.script.persist.memory then memory.clear(self.state.memory,name.." 0") end
            end
            self.state.session={name=name,turns=0,sources={keyword=0,memory=0,question=0,default=0,["repeat"]=0},history={},trace_on=false,topics={},words={},stored=0,recalled=0,unrecognized={}}
            self.transcript[#self.transcript+1]=line
            append(self.transcript,responder.wrap(self.script.texts.INITIAL[(sessions-1)%#self.script.texts.INITIAL+1]))
        elseif line:sub(1,1) == ":" then self.transcript[#self.transcript+1]=line; self:indented(self:command(line))
        else
            self.transcript[#self.transcript+1]="YOU: "..line
            if self:is_quit(line) then append(self.transcript,responder.wrap(self.script.texts.FINAL[(sessions-1)%#self.script.texts.FINAL+1])); self:notes()
            else
                local snapshot=copy(self.state); snapshot.session.undo=nil
                local session=self.state.session; session.undo=snapshot; session.turns=session.turns+1
                for _,word in ipairs(flatten(normalize(line))) do if not self.script.stop[word] then session.words[word]=(session.words[word] or 0)+1 end end
                session.history[#session.history+1]=session.turns..": "..line
                local reply,trace=self:decide(line); append(self.transcript,responder.wrap(reply)); session.last_trace=trace
                if session.trace_on then self:indented(trace) end
            end
        end
    end
    self.transcript[#self.transcript+1]=""; self.transcript[#self.transcript+1]="SUMMARY sessions="..sessions.." "..source_line(self.total)
end
function Bot:statistics()
    local keys={}; for _,key in ipairs(self.script.keywords) do keys[#keys+1]=key end
    table.sort(keys,function(a,b) return self.state.uses[a.index] == self.state.uses[b.index] and a.word < b.word or self.state.uses[a.index] > self.state.uses[b.index] end)
    local lines={"keyword,rank,uses,replies,decomposition_hits"}
    for _,key in ipairs(keys) do
        local hits={}; for _,rule in ipairs(key.decomps) do hits[#hits+1]=tostring(self.state.hits[rule.index]) end
        lines[#lines+1]=key.word..","..key.rank..","..self.state.uses[key.index]..","..self.state.replies[key.index]..","..(#hits == 0 and "-" or table.concat(hits,"/"))
    end
    return lines
end
local function write(path,lines)
    local file=assert(io.open(path,"w")); for _,line in ipairs(lines) do file:write(line,"\n") end; file:close()
end
local script=loader.load("input/script.txt")
os.execute("mkdir -p output")
write("output/lint.txt",linter.lint(script))
local bot=Bot.new(script); bot:run("input/dialogue.txt")
write("output/transcript.txt",bot.transcript)
write("output/keyword_stats.csv",bot:statistics())
write("output/memory_log.txt",bot.state.memory.log)
