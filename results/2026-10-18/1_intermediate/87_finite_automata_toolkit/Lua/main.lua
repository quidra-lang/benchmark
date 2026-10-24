local function fail(format,...) error({reason=string.format(format,...)},0) end
local function split(text,separator) local result={}; local start=1; while true do local at=text:find(separator,start,true); if not at then result[#result+1]=text:sub(start); break end; result[#result+1]=text:sub(start,at-1); start=at+#separator end; return result end
local function contains(items,value) for _,item in ipairs(items) do if item==value then return true end end; return false end
local function series(prefix,n) local result={}; for i=1,n do result[i]=prefix..(i-1) end; return result end
local function make_automaton(kind,states,alphabet,start)
    local result={kind=kind,states=states,alphabet=alphabet,start=start,final={},transitions={}}
    for i=1,#states do result.final[i]=false; result.transitions[i]={}; for c=1,#alphabet+1 do result.transitions[i][c]={} end end
    return result
end
local function add(a,p,c,q) local destinations=a.transitions[p][c]; if not contains(destinations,q) then destinations[#destinations+1]=q; table.sort(destinations) end end
local function ordered_set(set,n) local result={}; for i=1,n do if set[i] then result[#result+1]=i end end; return result end
local function closure(a,states)
    local seen,queue={},{}
    for _,state in ipairs(states) do if not seen[state] then seen[state]=true; queue[#queue+1]=state end end
    local i=1
    while i<=#queue do for _,next_state in ipairs(a.transitions[queue[i]][#a.alphabet+1]) do if not seen[next_state] then seen[next_state]=true; queue[#queue+1]=next_state end end; i=i+1 end
    return ordered_set(seen,#a.states)
end
local function destination(a,states,c)
    local next_states={}; for _,state in ipairs(states) do for _,next_state in ipairs(a.transitions[state][c]) do next_states[#next_states+1]=next_state end end
    return closure(a,next_states)
end
local function accepts(a,states) for _,state in ipairs(states) do if a.final[state] then return true end end; return false end
local function state_set(a,states) local names={}; for _,state in ipairs(states) do names[#names+1]=a.states[state] end; return "{"..table.concat(names,",").."}" end
local function state_list(a,states) if #states==0 then return "none" end; local names={}; for _,state in ipairs(states) do names[#names+1]=a.states[state] end; return table.concat(names,",") end
local function summary(a,name)
    local finals,count=0,0
    for _,accepting in ipairs(a.final) do if accepting then finals=finals+1 end end
    for _,row in ipairs(a.transitions) do for _,destinations in ipairs(row) do count=count+#destinations end end
    return string.format("%s %s: alphabet=%s states=%d accepting=%d transitions=%d",a.kind,name,a.alphabet,#a.states,finals,count)
end
local function set_key(states) return table.concat(states,",") end
local function determinize(a)
    local sets={closure(a,{a.start})}; local indices={[set_key(sets[1])]=1}; local rows={}; local i=1
    while i<=#sets do
        local row={}
        for c=1,#a.alphabet do
            local next_states=destination(a,sets[i],c); local key=set_key(next_states); local index=indices[key]
            if not index then index=#sets+1; indices[key]=index; sets[index]=next_states end
            row[c]=index
        end
        rows[i]=row; i=i+1
    end
    local result=make_automaton("DFA",series("D",#sets),a.alphabet,1)
    for index,set in ipairs(sets) do result.final[index]=accepts(a,set); for c,next_state in ipairs(rows[index]) do add(result,index,c,next_state) end end
    return result,sets
end
local function graph_reach(a,starts,reverse)
    local edges={}; for i=1,#a.states do edges[i]={} end
    for p,row in ipairs(a.transitions) do for _,destinations in ipairs(row) do for _,q in ipairs(destinations) do local from,to=p,q; if reverse then from,to=q,p end; edges[from][#edges[from]+1]=to end end end
    local seen,queue={},{}
    for _,state in ipairs(starts) do if not seen[state] then seen[state]=true; queue[#queue+1]=state end end
    local i=1
    while i<=#queue do for _,next_state in ipairs(edges[queue[i]]) do if not seen[next_state] then seen[next_state]=true; queue[#queue+1]=next_state end end; i=i+1 end
    return seen
end
local function partition_text(a,blocks) local parts={}; for _,block in ipairs(blocks) do parts[#parts+1]=state_set(a,block) end; return table.concat(parts," ") end
local function minimize(a)
    local reachable=graph_reach(a,{a.start},false)
    local missing,blocks,by_final={},{},{}
    for state=1,#a.states do
        if not reachable[state] then missing[#missing+1]=state
        else local key=a.final[state] and 1 or 0; local group=by_final[key]; if not group then group=#blocks+1; by_final[key]=group; blocks[group]={} end; blocks[group][#blocks[group]+1]=state end
    end
    local details={"  unreachable: "..state_list(a,missing),"  round 0: "..partition_text(a,blocks)}
    local round=1
    while true do
        local membership={}; for i,block in ipairs(blocks) do for _,state in ipairs(block) do membership[state]=i end end
        local next_blocks,signatures={},{}
        for state=1,#a.states do
            if reachable[state] then
                local signature={membership[state]}; for c=1,#a.alphabet do signature[#signature+1]=membership[a.transitions[state][c][1]] end
                local key=set_key(signature); local group=signatures[key]; if not group then group=#next_blocks+1; signatures[key]=group; next_blocks[group]={} end; next_blocks[group][#next_blocks[group]+1]=state
            end
        end
        if #next_blocks==#blocks then break end
        blocks=next_blocks; details[#details+1]=string.format("  round %d: %s",round,partition_text(a,blocks)); round=round+1
    end
    local membership={}; for i,block in ipairs(blocks) do for _,state in ipairs(block) do membership[state]=i end end
    local order={membership[a.start]}; local indices={[order[1]]=1}; local rows={}; local i=1
    while i<=#order do
        local representative=blocks[order[i]][1]; local row={}
        for c=1,#a.alphabet do local group=membership[a.transitions[representative][c][1]]; local index=indices[group]; if not index then index=#order+1; indices[group]=index; order[index]=group end; row[c]=index end
        rows[i]=row; i=i+1
    end
    local result=make_automaton("DFA",series("M",#order),a.alphabet,1)
    for index,group in ipairs(order) do result.final[index]=a.final[blocks[group][1]]; for c,next_state in ipairs(rows[index]) do add(result,index,c,next_state) end; details[#details+1]=string.format("  M%d = %s",index-1,state_set(a,blocks[group])) end
    return result,details
end
local function product(a,b,command)
    local pairs={{a.start,b.start}}; local indices={[set_key(pairs[1])]=1}; local rows={}; local i=1
    while i<=#pairs do
        local row={}; local pair=pairs[i]
        for c=1,#a.alphabet do local next_pair={a.transitions[pair[1]][c][1],b.transitions[pair[2]][c][1]}; local key=set_key(next_pair); local index=indices[key]; if not index then index=#pairs+1; indices[key]=index; pairs[index]=next_pair end; row[c]=index end
        rows[i]=row; i=i+1
    end
    local result=make_automaton("DFA",series("P",#pairs),a.alphabet,1); local details={}
    for index,pair in ipairs(pairs) do
        local x,y=a.final[pair[1]],b.final[pair[2]]
        result.final[index]=command=="UNION" and (x or y) or command=="INTERSECT" and x and y or command=="DIFF" and x and not y
        for c,next_state in ipairs(rows[index]) do add(result,index,c,next_state) end
        details[#details+1]=string.format("  P%d = (%s,%s)",index-1,a.states[pair[1]],b.states[pair[2]])
    end
    return result,details
end
local function word_text(word) return word=="" and "e" or word end
local function witness(a)
    local queue={{state=a.start,word=""}}; local seen={[a.start]=true}; local i=1
    while i<=#queue do
        local current=queue[i]; if a.final[current.state] then return current.word end
        for c=1,#a.alphabet do local next_state=a.transitions[current.state][c][1]; if not seen[next_state] then seen[next_state]=true; queue[#queue+1]={state=next_state,word=current.word..a.alphabet:sub(c,c)} end end
        i=i+1
    end
end
local function equivalent(a,b)
    local initial={a.start,b.start}; local queue={{pair=initial,word=""}}; local seen={[set_key(initial)]=true}; local i=1
    while i<=#queue do
        local current=queue[i]; local pair=current.pair
        if a.final[pair[1]]~=b.final[pair[2]] then return current.word,a.final[pair[1]] end
        for c=1,#a.alphabet do local next_pair={a.transitions[pair[1]][c][1],b.transitions[pair[2]][c][1]}; local key=set_key(next_pair); if not seen[key] then seen[key]=true; queue[#queue+1]={pair=next_pair,word=current.word..a.alphabet:sub(c,c)} end end
        i=i+1
    end
end
local function language(a)
    local finals={}; for state,accepting in ipairs(a.final) do if accepting then finals[#finals+1]=state end end
    local live=graph_reach(a,finals,true)
    if not live[a.start] then return "empty",live end
    local colors={}
    local function cycle(state)
        colors[state]=1
        for c=1,#a.alphabet do local next_state=a.transitions[state][c][1]; if live[next_state] and (colors[next_state]==1 or not colors[next_state] and cycle(next_state)) then return true end end
        colors[state]=2; return false
    end
    return cycle(a.start) and "infinite" or "finite",live
end
local function finite_count(a,live)
    local memo={}
    local function count(state)
        if not live[state] then return 0 end
        if memo[state]~=nil then return memo[state] end
        local result=a.final[state] and 1 or 0
        for c=1,#a.alphabet do result=result+count(a.transitions[state][c][1]) end
        memo[state]=result; return result
    end
    return count(a.start)
end
local function count_length(a,n)
    local counts={[a.start]=1}
    for _=1,n do local next_counts={}; for state,count in pairs(counts) do for c=1,#a.alphabet do local next_state=a.transitions[state][c][1]; next_counts[next_state]=(next_counts[next_state] or 0)+count end end; counts=next_counts end
    local total=0; for state,count in pairs(counts) do if a.final[state] then total=total+count end end; return total
end
local function synchronize(a)
    local initial={}; for state=1,#a.states do initial[state]=state end
    local queue={{states=initial,word=""}}; local seen={[set_key(initial)]=true}; local i=1
    while i<=#queue do
        local current=queue[i]; if #current.states==1 then return current.word,current.states[1] end
        for c=1,#a.alphabet do
            local present={}; for _,state in ipairs(current.states) do present[a.transitions[state][c][1]]=true end
            local next_states=ordered_set(present,#a.states); local key=set_key(next_states)
            if not seen[key] then seen[key]=true; queue[#queue+1]={states=next_states,word=current.word..a.alphabet:sub(c,c)} end
        end
        i=i+1
    end
end
local RegexParser={}
RegexParser.__index=RegexParser
function RegexParser:peek() return self.text:sub(self.at,self.at) end
function RegexParser:invalid() fail("syntax error at %d",self.at) end
local function regex_symbol(c) return c~="" and (c>="a" and c<="z" or c>="0" and c<="9") end
function RegexParser:atom()
    local c=self:peek()
    if regex_symbol(c) then self.at=self.at+1; return {kind=c,children={}} end
    if c=="(" then self.at=self.at+1; local result=self:alternation(); if self:peek()~=")" then self:invalid() end; self.at=self.at+1; return result end
    self:invalid()
end
function RegexParser:factor()
    local result=self:atom()
    while contains({"*","+","?"},self:peek()) do local c=self:peek(); self.at=self.at+1; result={kind=c,children={result}} end
    return result
end
function RegexParser:concatenation()
    local children={self:factor()}
    while regex_symbol(self:peek()) or self:peek()=="(" do children[#children+1]=self:factor() end
    return #children==1 and children[1] or {kind=".",children=children}
end
function RegexParser:alternation()
    local children={self:concatenation()}
    while self:peek()=="|" do self.at=self.at+1; children[#children+1]=self:concatenation() end
    return #children==1 and children[1] or {kind="|",children=children}
end
local function regex_automaton(tree,alphabet)
    local transitions,count={},0
    local function state() count=count+1; return count end
    local function transition(p,c,q) transitions[#transitions+1]={p,c,q} end
    local epsilon=#alphabet+1
    local function build(tree)
        if #tree.children==0 then local s,f=state(),state(); local c=tree.kind=="e" and epsilon or alphabet:find(tree.kind,1,true); transition(s,c,f); return s,f end
        if tree.kind=="." then local start,previous=build(tree.children[1]); for i=2,#tree.children do local s,f=build(tree.children[i]); transition(previous,epsilon,s); previous=f end; return start,previous end
        local start=state()
        if tree.kind=="|" then
            local parts={}; for _,child in ipairs(tree.children) do local s,f=build(child); parts[#parts+1]={s,f} end
            local ending=state(); for _,part in ipairs(parts) do transition(start,epsilon,part[1]); transition(part[2],epsilon,ending) end; return start,ending
        end
        local s,f=build(tree.children[1]); local ending=state()
        transition(start,epsilon,s); transition(f,epsilon,ending)
        if tree.kind~="?" then transition(f,epsilon,s) end
        if tree.kind~="+" then transition(start,epsilon,ending) end
        return start,ending
    end
    local start,ending=build(tree); local result=make_automaton("NFA",series("N",count),alphabet,start); result.final[ending]=true
    for _,triple in ipairs(transitions) do add(result,triple[1],triple[2],triple[3]) end
    return result
end
local function sorted_alphabet(text) local chars={}; for c in text:gmatch(".") do chars[#chars+1]=c end; table.sort(chars); return table.concat(chars) end
local function state_index(a,name) for i,state in ipairs(a.states) do if state==name then return i end end; fail("unknown state %s",name) end
local Toolkit={}
Toolkit.__index=Toolkit
function Toolkit:find(name) for _,entry in ipairs(self.entries) do if entry.name==name then return entry.automaton end end end
function Toolkit:register(name,a,details)
    self.entries[#self.entries+1]={name=name,automaton=a}
    local out={summary(a,name)}; for _,text in ipairs(details or {}) do out[#out+1]=text end; return out
end
function Toolkit:define(command,args)
    if #args<5 then fail("wrong number of arguments") end
    local name=args[1]; if self:find(name) then fail("%s already exists",name) end
    local states=split(args[2],","); local seen={}
    for _,state in ipairs(states) do if seen[state] then fail("duplicate state %s",state) end; seen[state]=true end
    local a=make_automaton(command,states,sorted_alphabet(args[3]),1); a.start=state_index(a,args[4])
    if args[5]~="-" then for _,state in ipairs(split(args[5],",")) do local index=state_index(a,state); if a.final[index] then fail("duplicate state %s",state) end; a.final[index]=true end end
    local triples,pairs={},{}
    for i=6,#args do
        local word=args[i]; local parts=split(word,":"); local p=state_index(a,parts[1]); local c=a.alphabet:find(parts[2],1,true)
        if parts[2]=="e" then if command=="DFA" then fail("epsilon transition in DFA") end; c=#a.alphabet+1 elseif not c then fail("unknown symbol %s",parts[2]) end
        local q=state_index(a,parts[3])
        if triples[word] then fail("duplicate transition %s",word) end; triples[word]=true
        local key=p..":"..c; if command=="DFA" and pairs[key] then fail("conflicting transition %s",word) end; pairs[key]=true
        add(a,p,c,q)
    end
    if command=="DFA" then for state=1,#states do for c=1,#a.alphabet do if #a.transitions[state][c]==0 then fail("missing transition %s:%s",a.states[state],a.alphabet:sub(c,c)) end end end end
    return self:register(name,a)
end
local counts={ACCEPT=2,CLOSURE=2,TODFA=2,EPSFREE=2,MINIMIZE=2,EQUIV=2,UNION=3,INTERSECT=3,DIFF=3,COMPLEMENT=2,REVERSE=2,CONCAT=3,STAR=2,ENUM=2,COUNT=2,EMPTY=1,FINITE=1,INFO=1,TABLE=1,SHOW=1,SYNC=1,LIST=0,DELETE=1}
function Toolkit:command(words)
    local command=table.remove(words,1); local args=words
    if command=="DFA" or command=="NFA" then return self:define(command,args) end
    if command=="REGEX" then
        if #args~=3 then fail("wrong number of arguments") end; if self:find(args[1]) then fail("%s already exists",args[1]) end
        local alphabet=sorted_alphabet(args[2])
        for c in args[3]:gmatch(".") do if regex_symbol(c) and c~="e" and not alphabet:find(c,1,true) then fail("unknown symbol %s",c) end end
        local parser=setmetatable({text=args[3],at=1},RegexParser); local tree=parser:alternation(); if parser.at<=#parser.text then parser:invalid() end
        return self:register(args[1],regex_automaton(tree,alphabet))
    end
    if counts[command]==nil then fail("unknown command %s",command) end
    if #args~=counts[command] then fail("wrong number of arguments") end
    if command=="LIST" then local out={}; for _,entry in ipairs(self.entries) do out[#out+1]=summary(entry.automaton,entry.name) end; return #out==0 and {"(none)"} or out end
    local reference_count=contains({"EQUIV","UNION","INTERSECT","DIFF","CONCAT"},command) and 2 or 1
    local autos={}
    for i=1,reference_count do autos[i]=self:find(args[i]); if not autos[i] then fail("unknown automaton %s",args[i]) end end
    local creates=contains({"TODFA","EPSFREE","MINIMIZE","UNION","INTERSECT","DIFF","COMPLEMENT","REVERSE","CONCAT","STAR"},command)
    if creates and self:find(args[#args]) then fail("%s already exists",args[#args]) end
    if contains({"MINIMIZE","UNION","INTERSECT","DIFF","COMPLEMENT","SYNC"},command) then for i,a in ipairs(autos) do if a.kind~="DFA" then fail("%s is not a DFA",args[i]) end end end
    if reference_count==2 and autos[1].alphabet~=autos[2].alphabet then fail("alphabets differ") end
    local a=autos[1]
    if command=="DELETE" then for i,entry in ipairs(self.entries) do if entry.name==args[1] then table.remove(self.entries,i); break end end; return {"deleted "..args[1]}
    elseif command=="ACCEPT" then
        local word=args[2]=="e" and "" or args[2]
        for c in word:gmatch(".") do if not a.alphabet:find(c,1,true) then fail("unknown symbol %s",c) end end
        local states=closure(a,{a.start})
        local function display(states) return a.kind=="DFA" and a.states[states[1]] or state_set(a,states) end
        local path=display(states)
        for c in word:gmatch(".") do states=destination(a,states,a.alphabet:find(c,1,true)); path=path.." -"..c.."-> "..display(states) end
        return {(accepts(a,states) and "ACCEPT" or "REJECT").." "..path}
    elseif command=="CLOSURE" then local states={}; for _,state in ipairs(split(args[2],",")) do states[#states+1]=state_index(a,state) end; return {state_set(a,closure(a,states))}
    elseif command=="TODFA" then local result,sets=determinize(a); local details={}; for i,set in ipairs(sets) do details[#details+1]=string.format("  D%d = %s",i-1,state_set(a,set)) end; return self:register(args[2],result,details)
    elseif command=="EPSFREE" then
        local result=make_automaton("NFA",a.states,a.alphabet,a.start)
        for state=1,#a.states do local closed=closure(a,{state}); result.final[state]=accepts(a,closed); for c=1,#a.alphabet do for _,next_state in ipairs(destination(a,closed,c)) do add(result,state,c,next_state) end end end
        return self:register(args[2],result)
    elseif command=="MINIMIZE" then local result,details=minimize(a); return self:register(args[2],result,details)
    elseif command=="UNION" or command=="INTERSECT" or command=="DIFF" then local result,details=product(a,autos[2],command); return self:register(args[3],result,details)
    elseif command=="EQUIV" then
        local x,z=determinize(a),determinize(autos[2]); local word,left=equivalent(x,z)
        if word==nil then return {"EQUIVALENT"} end
        return {string.format("NOT EQUIVALENT: %s is accepted only by %s",word_text(word),left and args[1] or args[2])}
    elseif command=="COMPLEMENT" then
        local result=make_automaton("DFA",a.states,a.alphabet,a.start)
        for state=1,#a.states do result.final[state]=not a.final[state]; for c=1,#a.alphabet do add(result,state,c,a.transitions[state][c][1]) end end
        return self:register(args[2],result)
    elseif command=="REVERSE" or command=="CONCAT" or command=="STAR" then
        local total,start=#a.states+1,1
        if command=="CONCAT" then total,start=#a.states+#autos[2].states,a.start end
        local result=make_automaton("NFA",series("N",total),a.alphabet,start); local epsilon=#a.alphabet+1
        if command=="REVERSE" then
            for p,row in ipairs(a.transitions) do for c,destinations in ipairs(row) do for _,q in ipairs(destinations) do add(result,q+1,c,p+1) end end end
            for state,accepting in ipairs(a.final) do if accepting then add(result,1,epsilon,state+1) end end; result.final[a.start+1]=true
        elseif command=="STAR" then
            for p,row in ipairs(a.transitions) do for c,destinations in ipairs(row) do for _,q in ipairs(destinations) do add(result,p+1,c,q+1) end end end
            result.final[1]=true; add(result,1,epsilon,a.start+1)
            for state,accepting in ipairs(a.final) do if accepting then result.final[state+1]=true; add(result,state+1,epsilon,a.start+1) end end
        else
            for p,row in ipairs(a.transitions) do for c,destinations in ipairs(row) do for _,q in ipairs(destinations) do add(result,p,c,q) end end end
            local b,offset=autos[2],#a.states
            for p,row in ipairs(b.transitions) do for c,destinations in ipairs(row) do for _,q in ipairs(destinations) do add(result,p+offset,c,q+offset) end end end
            for state,accepting in ipairs(a.final) do if accepting then add(result,state,epsilon,b.start+offset) end end
            for state,accepting in ipairs(b.final) do result.final[state+offset]=accepting end
        end
        return self:register(args[#args],result)
    elseif command=="SYNC" then local word,state=synchronize(a); return word and {string.format("SYNCHRONIZING %s -> %s",word_text(word),a.states[state])} or {"NOT SYNCHRONIZING"}
    elseif command=="COUNT" then return {tostring(count_length(determinize(a),tonumber(args[2])))}
    elseif command=="ENUM" then
        local k,d=tonumber(args[2]),determinize(a)
        local queue={{state=d.start,word=""}}; local total,accepted,i=0,{},1
        while i<=#queue do
            local current=queue[i]
            if d.final[current.state] then total=total+1; if #accepted<50 then accepted[#accepted+1]=word_text(current.word) end end
            if #current.word<k then for c=1,#d.alphabet do queue[#queue+1]={state=d.transitions[current.state][c][1],word=current.word..d.alphabet:sub(c,c)} end end
            i=i+1
        end
        local text=tostring(total); if #accepted>0 then text=text.." "..table.concat(accepted," ") end; if total>50 then text=text.." ..." end; return {text}
    elseif command=="EMPTY" then local word=witness(determinize(a)); return word and {"NOT EMPTY "..word_text(word)} or {"EMPTY"}
    elseif command=="FINITE" then local d=determinize(a); local classification,live=language(d); return classification=="infinite" and {"INFINITE"} or {"FINITE "..finite_count(d,live)}
    elseif command=="INFO" then
        local epsilon,deterministic,complete=0,true,true; local finals={}
        for state,accepting in ipairs(a.final) do
            if accepting then finals[#finals+1]=state end
            epsilon=epsilon+#a.transitions[state][#a.alphabet+1]
            for c=1,#a.alphabet do if #a.transitions[state][c]>1 then deterministic=false end; if #a.transitions[state][c]==0 then complete=false end end
        end
        if epsilon>0 then deterministic=false end
        local d=determinize(a); local classification=language(d); local minimal=minimize(d)
        local function yes(value) return value and "yes" or "no" end
        return {summary(a,args[1]),"  epsilon transitions: "..epsilon,"  reachable: "..state_list(a,ordered_set(graph_reach(a,{a.start},false),#a.states)),"  live: "..state_list(a,ordered_set(graph_reach(a,finals,true),#a.states)),"  deterministic: "..yes(deterministic),"  complete: "..yes(complete),"  language: "..classification,"  minimal DFA states: "..#minimal.states}
    elseif command=="SHOW" then
        local finals={}; for state,accepting in ipairs(a.final) do if accepting then finals[#finals+1]=a.states[state] end end
        local parts={a.kind,args[1],table.concat(a.states,","),a.alphabet,a.states[a.start],#finals==0 and "-" or table.concat(finals,",")}
        for p,row in ipairs(a.transitions) do for c,destinations in ipairs(row) do local symbol=c<=#a.alphabet and a.alphabet:sub(c,c) or "e"; for _,q in ipairs(destinations) do parts[#parts+1]=a.states[p]..":"..symbol..":"..a.states[q] end end end
        return {table.concat(parts," ")}
    elseif command=="TABLE" then
        local columns=#a.alphabet+1; local epsilon=false
        if a.kind=="NFA" then for state=1,#a.states do if #a.transitions[state][#a.alphabet+1]>0 then epsilon=true; break end end end
        if epsilon then columns=columns+1 end
        local header={""}; for c=1,columns-1 do header[c+1]=c<=#a.alphabet and a.alphabet:sub(c,c) or "e" end
        local rows={header}
        for state,name in ipairs(a.states) do
            local row={(state==a.start and "->" or "  ")..(a.final[state] and "*" or " ")..name}
            for c=1,columns-1 do local destinations=a.transitions[state][c]; row[c+1]=a.kind=="DFA" and a.states[destinations[1]] or #destinations==0 and "-" or state_set(a,destinations) end
            rows[#rows+1]=row
        end
        local widths={}; for c=1,columns do widths[c]=0; for _,row in ipairs(rows) do widths[c]=math.max(widths[c],#row[c]) end end
        local lines={}; for _,row in ipairs(rows) do local cells={}; for c,text in ipairs(row) do cells[c]=text..string.rep(" ",widths[c]-#text) end; lines[#lines+1]=(table.concat(cells,"  "):gsub(" +$","")) end
        return lines
    end
end
local toolkit=setmetatable({entries={}},Toolkit)
local count=tonumber(io.read("*l"))
for _=1,count do
    local line=io.read("*l")
    if line:sub(1,1)~="#" then
        local ok,result=pcall(function() return toolkit:command(split(line," ")) end)
        if not ok then if type(result)~="table" or not result.reason then error(result,0) end; io.write("error: ",result.reason,"\n")
        else for _,text in ipairs(result) do io.write(text,"\n") end end
    end
end
