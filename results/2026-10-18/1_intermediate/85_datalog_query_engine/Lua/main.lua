local reserved = {}
for word in ("not mod count sum min max retract dump why forget listing strata stats check predicates undo halt"):gmatch("%S+") do reserved[word] = true end
local function fail(format, ...) error({reason=string.format(format, ...)}, 0) end
local function contains(items, value) for _, item in ipairs(items) do if item == value then return true end end; return false end
local function keys(set) local result = {}; for key in pairs(set) do result[#result + 1] = key end; table.sort(result); return result end
local function copy(map) local result = {}; for key, value in pairs(map) do result[key] = value end; return result end
local function lower(c) return c ~= "" and c >= "a" and c <= "z" end
local function upper(c) return c ~= "" and c >= "A" and c <= "Z" end
local function digit(c) return c ~= "" and c >= "0" and c <= "9" end
local function word_character(c) return lower(c) or upper(c) or digit(c) or c == "_" end
local function lexical(line)
    local result, i = {}, 1
    while i <= #line do
        local c, start = line:sub(i,i), i
        if c == " " then i = i + 1
        elseif c == "%" then break
        elseif c == '"' then
            local closing = line:find('"', i + 1, true)
            if not closing then fail("unterminated string") end
            result[#result+1] = {kind="string", text=line:sub(i,closing)}
            i = closing + 1
        elseif contains({":-","?-","!=","<=",">="}, line:sub(i,i+1)) then
            local text = line:sub(i,i+1); result[#result+1] = {kind=text,text=text}; i=i+2
        elseif ("(),.:=<>+-*/"):find(c,1,true) then
            result[#result+1]={kind=c,text=c}; i=i+1
        else
            if not word_character(c) then fail("bad character '%s'",c) end
            repeat i=i+1 until not word_character(line:sub(i,i))
            local text=line:sub(start,i-1)
            local item={text=text}
            if lower(c) then item.kind=reserved[text] and text or "name"
            elseif upper(c) then item.kind="variable"
            elseif text=="_" then item.kind="anonymous"
            else
                if not text:match("^%d+$") then fail("bad token '%s'",text) end
                item.kind,item.number="integer",tonumber(text)
                if item.number>1000000000 then fail("integer out of range '%s'",text) end
            end
            result[#result+1]=item
        end
    end
    return result
end
local Parser={}
Parser.__index=Parser
function Parser:peek() return self.tokens[self.position] and self.tokens[self.position].kind or "end" end
function Parser:invalid()
    if self:peek()=="end" then fail("syntax error at end of line") end
    fail("syntax error at '%s'",self.tokens[self.position].text)
end
function Parser:take(kind)
    if self:peek()~=kind then self:invalid() end
    local item=self.tokens[self.position]; self.position=self.position+1; return item
end
function Parser:term()
    local kind=self:peek()
    if kind=="name" then return {kind="constant",value=self:take(kind).text}
    elseif kind=="string" then return {kind="constant",value=self:take(kind).text:sub(2,-2)}
    elseif kind=="integer" then return {kind="constant",value=self:take(kind).number}
    elseif kind=="-" then self:take("-"); return {kind="constant",value=-self:take("integer").number}
    elseif kind=="variable" then return {kind=kind,name=self:take(kind).text}
    elseif kind=="anonymous" then self:take(kind); return {kind=kind} end
    self:invalid()
end
function Parser:atom()
    local result={name=self:take("name").text,terms={}}
    if self:peek()=="(" then
        self:take("("); result.terms[1]=self:term()
        while self:peek()=="," do self:take(","); result.terms[#result.terms+1]=self:term() end
        self:take(")")
    end
    return result
end
function Parser:factor()
    if self:peek()=="(" then self:take("("); local inside=self:expression(); self:take(")"); return {kind="group",left=inside} end
    return {kind="term",term=self:term()}
end
function Parser:product()
    local result=self:factor()
    while contains({"*","/","mod"},self:peek()) do local operator=self:take(self:peek()).kind; result={kind="operation",operator=operator,left=result,right=self:factor()} end
    return result
end
function Parser:expression()
    local result=self:product()
    while self:peek()=="+" or self:peek()=="-" do local operator=self:take(self:peek()).kind; result={kind="operation",operator=operator,left=result,right=self:product()} end
    return result
end
function Parser:literal()
    if self:peek()=="not" then self:take("not"); return {kind="negative",atom=self:atom()} end
    if self:peek()=="name" then
        local next_kind=self.tokens[self.position+1] and self.tokens[self.position+1].kind or "end"
        if not contains({"=","!=","<","<=",">",">=","+","-","*","/","mod"},next_kind) then return {kind="positive",atom=self:atom()} end
    end
    local left=self:expression()
    if not contains({"=","!=","<","<=",">",">="},self:peek()) then self:invalid() end
    local operator=self:take(self:peek()).kind
    return {kind="comparison",operator=operator,left=left,right=self:expression()}
end
function Parser:body()
    local result={self:literal()}
    while self:peek()=="," do self:take(","); result[#result+1]=self:literal() end
    return result
end
function Parser:statement()
    local kind=self:peek()
    local result={body={}}
    if kind=="name" then
        result.head,result.kind=self:atom(),"fact"
        if self:peek()==":-" then self:take(":-"); result.kind,result.body="rule",self:body() end
    elseif kind==":-" then self:take(kind); result.kind,result.body="constraint",self:body()
    elseif kind=="?-" then
        self:take(kind); result.kind="query"
        if contains({"count","sum","min","max"},self:peek()) then
            result.aggregate=self:take(self:peek()).kind
            if result.aggregate~="count" then result.variable=self:take("variable").text; self:take(":") end
        end
        result.body=self:body()
    elseif kind=="retract" or kind=="why" then self:take(kind); result.kind,result.head=kind,self:atom()
    elseif kind=="dump" then self:take(kind); result.kind,result.name=kind,self:take("name").text
    elseif kind=="forget" then self:take(kind); result.kind,result.number=kind,self:take("integer").number
    elseif kind=="listing" then self:take(kind); result.kind=kind; if self:peek()=="name" then result.name=self:take("name").text end
    elseif contains({"strata","stats","check","predicates","undo","halt"},kind) then self:take(kind); result.kind=kind
    else self:invalid() end
    self:take(".")
    if self:peek()~="end" then self:invalid() end
    return result
end
local function compare_value(a,b)
    if type(a)~=type(b) then return type(a)=="number" and -1 or 1 end
    return a<b and -1 or a>b and 1 or 0
end
local function compare_tuple(a,b) for i=1,#a do local order=compare_value(a[i],b[i]); if order~=0 then return order end end; return 0 end
local function notation(value)
    if type(value)=="number" then return tostring(value) end
    if value:match("^[a-z][a-zA-Z0-9_]*$") and not reserved[value] then return value end
    return '"'..value..'"'
end
local function term_text(term,assignment)
    if term.kind=="constant" then return notation(term.value) end
    if term.kind=="anonymous" then return "_" end
    return assignment and notation(assignment[term.name]) or term.name
end
local function atom_text(atom,assignment)
    if #atom.terms==0 then return atom.name end
    local parts={}; for _,term in ipairs(atom.terms) do parts[#parts+1]=term_text(term,assignment) end
    return atom.name.."("..table.concat(parts,", ")..")"
end
local function expression_text(expression,assignment)
    if expression.kind=="term" then return term_text(expression.term,assignment) end
    if expression.kind=="group" then return "("..expression_text(expression.left,assignment)..")" end
    return expression_text(expression.left,assignment).." "..expression.operator.." "..expression_text(expression.right,assignment)
end
local function literal_text(literal,assignment)
    if literal.kind=="comparison" then return expression_text(literal.left,assignment).." "..literal.operator.." "..expression_text(literal.right,assignment) end
    return (literal.kind=="negative" and "not " or "")..atom_text(literal.atom,assignment)
end
local function rule_text(statement)
    local parts={}; for _,literal in ipairs(statement.body) do parts[#parts+1]=literal_text(literal) end
    return (statement.head and atom_text(statement.head).." :- " or ":- ")..table.concat(parts,", ").."."
end
local function expression_terms(expression,result)
    if expression.kind=="term" then result[#result+1]=expression.term
    else expression_terms(expression.left,result); if expression.kind=="operation" then expression_terms(expression.right,result) end end
end
local function literal_terms(literal)
    if literal.kind~="comparison" then return literal.atom.terms end
    local result={}; expression_terms(literal.left,result); expression_terms(literal.right,result); return result
end
local function all_terms(statement)
    local result={}
    if statement.head then for _,term in ipairs(statement.head.terms) do result[#result+1]=term end end
    for _,literal in ipairs(statement.body) do for _,term in ipairs(literal_terms(literal)) do result[#result+1]=term end end
    return result
end
local function variables(terms)
    local result,seen={},{}
    for _,term in ipairs(terms) do if term.kind=="variable" and not seen[term.name] then seen[term.name]=true; result[#result+1]=term.name end end
    return result
end
local function tuple_key(tuple)
    local result={}
    for _,value in ipairs(tuple) do result[#result+1]=type(value)=="number" and "i"..value..";" or "s"..#value..":"..value end
    return table.concat(result)
end
local function ordered_tuples(set)
    local result={}; for _,tuple in pairs(set) do result[#result+1]=tuple end
    table.sort(result,function(a,b) return compare_tuple(a.values,b.values)<0 end); return result
end
local function atoms(statement)
    local result={}
    if statement.head then result[1]=statement.head end
    for _,literal in ipairs(statement.body) do if literal.kind~="comparison" then result[#result+1]=literal.atom end end
    return result
end
local Database={}
Database.__index=Database
function Database.new() return setmetatable({predicates={},rules={},history={},next_number=1},Database) end
function Database:save(line)
    local predicates,rules={},{}
    for name,predicate in pairs(self.predicates) do predicates[name]={arity=predicate.arity,facts=copy(predicate.facts)} end
    for i,rule in ipairs(self.rules) do rules[i]=rule end
    self.history[#self.history+1]={predicates=predicates,rules=rules,line=line}
end
function Database:check_predicates(statement,clause)
    local arities={}; for name,predicate in pairs(self.predicates) do arities[name]=predicate.arity end
    for _,atom in ipairs(atoms(statement)) do
        local expected=arities[atom.name]
        if expected==nil and not clause then fail("unknown predicate %s",atom.name) end
        if expected~=nil and expected~=#atom.terms then fail("arity mismatch for %s: expected %d, got %d",atom.name,expected,#atom.terms) end
        arities[atom.name]=#atom.terms
    end
    return arities
end
local function safety(statement)
    if statement.head then for _,term in ipairs(statement.head.terms) do if term.kind=="anonymous" then fail("anonymous variable in head") end end end
    local bound={}
    for _,literal in ipairs(statement.body) do
        if literal.kind=="comparison" then for _,term in ipairs(literal_terms(literal)) do if term.kind=="anonymous" then fail("anonymous variable in comparison") end end end
        if literal.kind=="positive" then for _,name in ipairs(variables(literal.atom.terms)) do bound[name]=true end end
    end
    local checked={}
    if statement.head then for _,term in ipairs(statement.head.terms) do checked[#checked+1]=term end end
    if statement.aggregate and statement.aggregate~="count" then checked[#checked+1]={kind="variable",name=statement.variable} end
    for _,literal in ipairs(statement.body) do if literal.kind~="positive" then for _,term in ipairs(literal_terms(literal)) do checked[#checked+1]=term end end end
    for _,term in ipairs(checked) do if term.kind=="variable" and not bound[term.name] then fail("unsafe variable %s",term.name) end end
end
local function strata(arities,rules)
    local names=keys(arities)
    local reach,levels,recursive={},{},{}
    for _,name in ipairs(names) do reach[name]={}; levels[name]=0 end
    for _,rule in ipairs(rules) do
        if rule.statement.head then for _,literal in ipairs(rule.statement.body) do if literal.kind~="comparison" then reach[rule.statement.head.name][literal.atom.name]=true end end end
    end
    for _,middle in ipairs(names) do for _,a in ipairs(names) do for _,b in ipairs(names) do if reach[a][middle] and reach[middle][b] then reach[a][b]=true end end end end
    for _,name in ipairs(names) do recursive[name]=reach[name][name] or false end
    for _,rule in ipairs(rules) do
        if rule.statement.head then for _,literal in ipairs(rule.statement.body) do if literal.kind=="negative" and (literal.atom.name==rule.statement.head.name or reach[literal.atom.name][rule.statement.head.name]) then return nil end end end
    end
    local changed=true
    while changed do
        changed=false
        for _,rule in ipairs(rules) do
            if rule.statement.head then
                for _,literal in ipairs(rule.statement.body) do
                    if literal.kind~="comparison" then
                        local required=levels[literal.atom.name]+(literal.kind=="negative" and 1 or 0)
                        if levels[rule.statement.head.name]<required then levels[rule.statement.head.name]=required; changed=true end
                    end
                end
            end
        end
    end
    return levels,recursive
end
function Database:levels()
    local arities={}; for name,predicate in pairs(self.predicates) do arities[name]=predicate.arity end
    return strata(arities,self.rules)
end
local function match(atom,values,assignment)
    local result=copy(assignment or {})
    for i,term in ipairs(atom.terms) do
        if term.kind=="constant" and term.value~=values[i] then return nil end
        if term.kind=="variable" then
            if result[term.name]~=nil and result[term.name]~=values[i] then return nil end
            result[term.name]=values[i]
        end
    end
    return result
end
local function evaluate(expression,assignment)
    if expression.kind=="term" then return expression.term.kind=="constant" and expression.term.value or assignment[expression.term.name] end
    if expression.kind=="group" then return evaluate(expression.left,assignment) end
    local a,b=evaluate(expression.left,assignment),evaluate(expression.right,assignment)
    if type(a)~="number" or type(b)~="number" then return nil end
    local operator=expression.operator
    if operator=="+" then return a+b elseif operator=="-" then return a-b elseif operator=="*" then return a*b end
    if b==0 then return nil end
    local quotient=a//b
    return operator=="mod" and a-b*quotient or quotient
end
local function comparison(literal,assignment)
    local a,b=evaluate(literal.left,assignment),evaluate(literal.right,assignment)
    if a==nil or b==nil then return false end
    local operator=literal.operator
    if operator=="=" then return a==b elseif operator=="!=" then return a~=b end
    if type(a)~="number" or type(b)~="number" then return false end
    if operator=="<" then return a<b elseif operator=="<=" then return a<=b elseif operator==">" then return a>b else return a>=b end
end
local function solutions(body,model,before)
    local positives={}
    for _,literal in ipairs(body) do if literal.kind=="positive" then positives[#positives+1]=literal end end
    local function accepts_binding(binding)
        for _,literal in ipairs(body) do
            if literal.kind~="positive" then
                local ready=true
                for _,term in ipairs(literal_terms(literal)) do if term.kind=="variable" and binding[term.name]==nil then ready=false; break end end
                if ready then
                    if literal.kind=="comparison" and not comparison(literal,binding) then return false end
                    if literal.kind=="negative" then for _,tuple in pairs(model[literal.atom.name]) do if match(literal.atom,tuple.values,binding) then return false end end end
                end
            end
        end
        return true
    end
    local result,finished={},{}
    local function binding_key(binding)
        local values={}
        for _,name in ipairs(keys(binding)) do values[#values+1]=binding[name] end
        return tuple_key(values)
    end
    local function visit(binding,remaining)
        if not accepts_binding(binding) then return end
        if #remaining==0 then
            local key=binding_key(binding)
            if not finished[key] then finished[key]=true; result[#result+1]=binding end
            return
        end
        local selected,candidates
        for i,literal in ipairs(remaining) do
            local matches,seen={},{}
            for _,tuple in pairs(model[literal.atom.name]) do
                if not before or tuple.round<before then
                    local matched=match(literal.atom,tuple.values,binding)
                    if matched and accepts_binding(matched) then
                        local key=binding_key(matched)
                        if not seen[key] then seen[key]=true; matches[#matches+1]=matched end
                    end
                end
            end
            if #matches==0 then return end
            if not candidates or #matches<#candidates then selected,candidates=i,matches end
        end
        local next_remaining={}
        for i,literal in ipairs(remaining) do if i~=selected then next_remaining[#next_remaining+1]=literal end end
        for _,matched in ipairs(candidates) do visit(matched,next_remaining) end
    end
    visit({},positives)
    return result
end
local function atom_values(atom,assignment)
    local result={}
    for _,term in ipairs(atom.terms) do result[#result+1]=term.kind=="constant" and term.value or assignment[term.name] end
    return result
end
function Database:model()
    local levels=self:levels()
    local result={tuples={},levels=levels,rounds={},added={}}
    local maximum=-1
    for name,predicate in pairs(self.predicates) do
        result.tuples[name]={}
        for key,values in pairs(predicate.facts) do result.tuples[name][key]={values=values,round=0,rule=0} end
        maximum=math.max(maximum,levels[name])
    end
    local serial=0
    for level=0,maximum do
        result.rounds[level],result.added[level]=0,0
        while true do
            local pending,count={},0
            for _,rule in ipairs(self.rules) do
                local head=rule.statement.head
                if head and levels[head.name]==level then
                    pending[head.name]=pending[head.name] or {}
                    for _,assignment in ipairs(solutions(rule.statement.body,result.tuples)) do
                        local values=atom_values(head,assignment); local key=tuple_key(values)
                        if not result.tuples[head.name][key] and not pending[head.name][key] then pending[head.name][key]={values=values,rule=rule.number}; count=count+1 end
                    end
                end
            end
            if count==0 then break end
            serial=serial+1; result.rounds[level]=result.rounds[level]+1; result.added[level]=result.added[level]+count
            for name,set in pairs(pending) do for key,tuple in pairs(set) do tuple.round=serial; result.tuples[name][key]=tuple end end
        end
    end
    result.maximum=maximum
    return result
end
local function answer_rows(statement,model)
    local names=variables(all_terms({body=statement.body}))
    local rows={}
    for _,assignment in ipairs(solutions(statement.body,model.tuples)) do
        local row={}; for _,name in ipairs(names) do row[#row+1]=assignment[name] end; rows[#rows+1]=row
    end
    table.sort(rows,function(a,b) return compare_tuple(a,b)<0 end)
    return names,rows
end
local function answer_text(names,row)
    local parts={}; for i,name in ipairs(names) do parts[#parts+1]=name.." = "..notation(row[i]) end; return table.concat(parts,", ")
end
local function tuple_atom(name,values)
    local atom={name=name,terms={}}
    for _,value in ipairs(values) do atom.terms[#atom.terms+1]={kind="constant",value=value} end
    return atom
end
function Database:proof(name,target,depth,model)
    local prefix=string.rep(" ",depth*2)..atom_text(tuple_atom(name,target.values))
    if target.round==0 then return {prefix.." [fact]"} end
    for _,rule in ipairs(self.rules) do
        local statement=rule.statement
        if statement.head and statement.head.name==name then
            local candidates={}
            for _,binding in ipairs(solutions(statement.body,model.tuples,target.round)) do if compare_tuple(atom_values(statement.head,binding),target.values)==0 then candidates[#candidates+1]=binding end end
            if #candidates>0 then
                local names=variables(all_terms(statement))
                table.sort(candidates,function(a,b) for _,variable in ipairs(names) do local order=compare_value(a[variable],b[variable]); if order~=0 then return order<0 end end; return false end)
                local binding=candidates[1]
                local lines={string.format("%s [rule %d]",prefix,rule.number)}
                for _,literal in ipairs(statement.body) do
                    if literal.kind=="positive" then
                        for _,tuple in ipairs(ordered_tuples(model.tuples[literal.atom.name])) do
                            if tuple.round<target.round and match(literal.atom,tuple.values,binding) then for _,text in ipairs(self:proof(literal.atom.name,tuple,depth+1,model)) do lines[#lines+1]=text end; break end
                        end
                    else lines[#lines+1]=string.rep(" ",(depth+1)*2)..literal_text(literal,binding) end
                end
                return lines
            end
        end
    end
end
local function plural(count,singular) return count==1 and singular or singular.."s" end
function Database:execute(statement,line)
    local out={}
    local function emit(format,...) out[#out+1]=string.format(format,...) end
    local kind=statement.kind
    if kind=="fact" or kind=="rule" or kind=="constraint" then
        local arities=self:check_predicates(statement,true)
        safety(statement)
        if kind=="fact" then
            local head=statement.head; local values=atom_values(head); local key=tuple_key(values)
            if self.predicates[head.name] and self.predicates[head.name].facts[key] then return out end
            self:save(line)
            self.predicates[head.name]=self.predicates[head.name] or {arity=#values,facts={}}
            self.predicates[head.name].facts[key]=values
            return out
        end
        local text=rule_text(statement)
        for _,rule in ipairs(self.rules) do if rule_text(rule.statement)==text then fail("duplicate of rule %d",rule.number) end end
        local candidate={}; for i,rule in ipairs(self.rules) do candidate[i]=rule end
        candidate[#candidate+1]={number=self.next_number,statement=statement}
        if kind=="rule" and not strata(arities,candidate) then fail("negative cycle through %s",statement.head.name) end
        self:save(line)
        for name,arity in pairs(arities) do self.predicates[name]=self.predicates[name] or {arity=arity,facts={}} end
        self.rules=candidate; self.next_number=self.next_number+1
        local terms=all_terms(statement)
        for _,name in ipairs(variables(terms)) do
            local count=0; for _,term in ipairs(terms) do if term.kind=="variable" and term.name==name then count=count+1 end end
            if count==1 then emit("WARNING line %d: singleton variable %s",line,name) end
        end
        return out
    end
    if kind=="undo" then
        if #self.history==0 then fail("nothing to undo") end
        local previous=table.remove(self.history)
        self.predicates,self.rules=previous.predicates,previous.rules
        emit("undid line %d",previous.line); return out
    elseif kind=="forget" then
        local index; for i,rule in ipairs(self.rules) do if rule.number==statement.number then index=i; break end end
        if not index then fail("no rule %d",statement.number) end
        self:save(line); table.remove(self.rules,index); return out
    elseif kind=="listing" then
        if statement.name and not self.predicates[statement.name] then fail("unknown predicate %s",statement.name) end
        for _,rule in ipairs(self.rules) do if not statement.name or rule.statement.head and rule.statement.head.name==statement.name then emit("%d: %s",rule.number,rule_text(rule.statement)) end end
        if #out==0 then emit("no rules") end; return out
    elseif kind=="strata" then
        local levels,recursive=self:levels(); local maximum=-1
        for _,level in pairs(levels) do maximum=math.max(maximum,level) end
        if maximum<0 then emit("no predicates") end
        for level=0,maximum do
            local names={}; for _,name in ipairs(keys(self.predicates)) do if levels[name]==level then names[#names+1]=name..(recursive[name] and "*" or "") end end
            emit("stratum %d: %s",level,table.concat(names,", "))
        end
        return out
    end
    if kind=="query" or kind=="retract" or kind=="why" then self:check_predicates(statement,false); if kind=="query" then safety(statement) end end
    if kind=="retract" then
        local predicate=self.predicates[statement.head.name]; local removed={}
        for key,values in pairs(predicate.facts) do if match(statement.head,values) then removed[#removed+1]=key end end
        if #removed==0 then fail("no matching facts") end
        self:save(line); for _,key in ipairs(removed) do predicate.facts[key]=nil end
        emit("%d %s retracted",#removed,plural(#removed,"fact")); return out
    end
    if kind=="why" then for _,term in ipairs(statement.head.terms) do if term.kind~="constant" then fail("why needs a ground atom") end end end
    if kind=="dump" and not self.predicates[statement.name] then fail("unknown predicate %s",statement.name) end
    local model=self:model()
    if kind=="query" then
        local names,answers=answer_rows(statement,model)
        if statement.aggregate=="count" then emit("%d",#answers)
        elseif statement.aggregate=="sum" then
            local column; for i,name in ipairs(names) do if name==statement.variable then column=i end end
            local total=0
            for _,row in ipairs(answers) do if type(row[column])~="number" then fail("non-integer value in sum") end; total=total+row[column] end
            emit("%d",total)
        elseif statement.aggregate=="min" or statement.aggregate=="max" then
            if #answers==0 then emit("no answers")
            else
                local column; for i,name in ipairs(names) do if name==statement.variable then column=i end end
                local selected=answers[1][column]
                for _,row in ipairs(answers) do local order=compare_value(row[column],selected); if statement.aggregate=="min" and order<0 or statement.aggregate=="max" and order>0 then selected=row[column] end end
                emit("%s",notation(selected))
            end
        elseif #names==0 then emit(#answers>0 and "true." or "false.")
        else for _,row in ipairs(answers) do emit("%s",answer_text(names,row)) end; emit("%d %s",#answers,plural(#answers,"answer")) end
    elseif kind=="dump" then
        local rows=ordered_tuples(model.tuples[statement.name])
        for _,tuple in ipairs(rows) do emit("%s.",atom_text(tuple_atom(statement.name,tuple.values))) end
        emit("%d %s",#rows,plural(#rows,"tuple"))
    elseif kind=="why" then
        local tuple=model.tuples[statement.head.name][tuple_key(atom_values(statement.head))]
        if not tuple then emit("false.") else out=self:proof(statement.head.name,tuple,0,model) end
    elseif kind=="check" then
        local count=0
        for _,rule in ipairs(self.rules) do
            if not rule.statement.head then
                count=count+1; local names,answers=answer_rows(rule.statement,model)
                if #answers==0 then emit("constraint %d: ok",rule.number)
                else emit("constraint %d: %d %s",rule.number,#answers,plural(#answers,"violation")); if #names>0 then for _,row in ipairs(answers) do emit("  %s",answer_text(names,row)) end end end
            end
        end
        if count==0 then emit("no constraints") end
    elseif kind=="predicates" then
        if next(self.predicates)==nil then emit("no predicates") end
        for _,name in ipairs(keys(self.predicates)) do
            local count=0; for _,rule in ipairs(self.rules) do if rule.statement.head and rule.statement.head.name==name then count=count+1 end end
            local predicate=self.predicates[name]; local facts,tuples=0,0; for _ in pairs(predicate.facts) do facts=facts+1 end; for _ in pairs(model.tuples[name]) do tuples=tuples+1 end
            emit("%s/%d: facts %d, rules %d, tuples %d",name,predicate.arity,facts,count,tuples)
        end
    elseif kind=="stats" then
        local facts,rules,constraints,tuples=0,0,0,0
        for name,predicate in pairs(self.predicates) do for _ in pairs(predicate.facts) do facts=facts+1 end; for _ in pairs(model.tuples[name]) do tuples=tuples+1 end end
        for _,rule in ipairs(self.rules) do if rule.statement.head then rules=rules+1 else constraints=constraints+1 end end
        emit("facts %d, rules %d, constraints %d, tuples %d",facts,rules,constraints,tuples)
        for level=0,model.maximum do emit("stratum %d: rounds %d, new %d",level,model.rounds[level],model.added[level]) end
        for _,rule in ipairs(self.rules) do
            if rule.statement.head then
                local count=0; for _,set in pairs(model.tuples) do for _,tuple in pairs(set) do if tuple.round>0 and tuple.rule==rule.number then count=count+1 end end end
                emit("rule %d: new %d",rule.number,count)
            end
        end
    end
    return out
end
local database=Database.new()
local line_number=0
for line in io.lines() do
    line_number=line_number+1
    local halt=false
    local ok,result=pcall(function()
        local tokens=lexical(line)
        if #tokens==0 then return {} end
        local statement=setmetatable({tokens=tokens,position=1},Parser):statement()
        if statement.kind=="halt" then halt=true; return {} end
        return database:execute(statement,line_number)
    end)
    if not ok then if type(result)~="table" or not result.reason then error(result,0) end; io.write(string.format("ERROR line %d: %s\n",line_number,result.reason))
    else for _,text in ipairs(result) do io.write(text,"\n") end end
    if halt then break end
end
