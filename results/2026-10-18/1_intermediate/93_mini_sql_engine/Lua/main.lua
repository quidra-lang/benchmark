local NULL={}
local function fail(s) error(s,0) end
local function set(s) local a={} for w in s:gmatch('%S+') do a[w]=true end return a end
local reserved=set('SELECT DISTINCT FROM AS JOIN INNER LEFT OUTER ON WHERE GROUP BY HAVING ORDER ASC DESC LIMIT OFFSET INSERT INTO VALUES UPDATE SET DELETE CREATE TABLE DROP PRIMARY KEY NOT NULL INT TEXT AND OR IS IN BETWEEN LIKE COUNT SUM MIN MAX AVG EXIT')
local aggregates=set('COUNT SUM MIN MAX AVG') local comparisons=set('= <> != < <= > >=')
local function slice(a,first,last) local b={} for i=first,last or #a do b[#b+1]=a[i] end return b end
local function concat(a,b) local z={} for _,v in ipairs(a) do z[#z+1]=v end for _,v in ipairs(b) do z[#z+1]=v end return z end
local function node(kind,op,args,value) return {kind=kind,op=op,args=args or {},value=value} end
local function tokenize(s)
 local a,i={},1
 while i<=#s do
  local c=s:sub(i,i) local start=i local kind,value
  if c==' ' or c=='\n' then i=i+1 elseif s:sub(i,i+1)=='--' then i=s:find('\n',i,true) or #s+1
  else
   if c=="'" then i=s:find("'",i+1,true)+1 kind='string' value=s:sub(start+1,i-2)
   elseif c:match('%d') then i=i+1 while i<=#s and s:sub(i,i):match('%d') do i=i+1 end kind='integer' value=tonumber(s:sub(start,i-1))
   elseif c:match('[A-Za-z_]') then i=i+1 while i<=#s and s:sub(i,i):match('[A-Za-z0-9_]') do i=i+1 end value=s:sub(start,i-1) local upper=value:upper() kind=reserved[upper] and 'keyword' or 'name' if kind=='keyword' then value=upper end
   else local two=s:sub(i,i+1) if two=='<>' or two=='!=' or two=='<=' or two=='>=' or two=='||' then value=two i=i+2 elseif ('(),.;*/%+-=<>'):find(c,1,true) then value=c i=i+1 else fail("unexpected character '"..c.."'") end kind='symbol' end
   a[#a+1]={kind=kind,value=value,text=s:sub(start,i-1)}
  end
 end return a
end
local Parser={} Parser.__index=Parser
function Parser:new(tokens) return setmetatable({tokens=tokens,i=1},self) end
function Parser:peek() return self.tokens[self.i] end
function Parser:take() local t=self:peek() self.i=self.i+1 return t end
function Parser:at(w) local t=self:peek() return (t.kind=='keyword' or t.kind=='symbol') and t.value==w end
function Parser:accept(w) if self:at(w) then self.i=self.i+1 return true end return false end
function Parser:syntax() fail("syntax error at '"..self:peek().text.."'") end
function Parser:expect(w) if not self:accept(w) then self:syntax() end end
function Parser:kind(k) if self:peek().kind~=k then self:syntax() end return self:take().value end
function Parser:comma(read) local a={read()} while self:accept(',') do a[#a+1]=read() end return a end
function Parser:parens(read) self:expect('(') local a=self:comma(read) self:expect(')') return a end
function Parser:alias() if self:accept('AS') then return self:kind('name') elseif self:peek().kind=='name' then return self:take().value end end
function Parser:table() local name=self:kind('name') return {name=name,alias=self:alias() or name} end
function Parser:reference() local name=self:kind('name') local e=node('ref') if self:accept('.') then e.table=name e.column=self:kind('name') e.text=name..'.'..e.column else e.column=name e.text=name end return e end
function Parser:expr(level)
 level=level or 0
 if level==2 and self:accept('NOT') then return node('unary','NOT',{self:expr(2)}) end
 if level==6 and self:accept('-') then return node('unary','-',{self:expr(6)}) end
 if level==7 then return self:primary() end
 local left=self:expr(level+1)
 if level==3 then
  if self:peek().kind=='symbol' and comparisons[self:peek().value] then local op=self:take().value return node('binary',op,{left,self:expr(4)}) end
  if self:accept('IS') then local neg=self:accept('NOT') self:expect('NULL') local e=node('isnull','',{left}) e.neg=neg return e end
  local neg=self:accept('NOT') local e
  if self:accept('IN') then e=node('in','',concat({left},self:parens(function()return self:expr()end)))
  elseif self:accept('BETWEEN') then local low=self:expr(4) self:expect('AND') e=node('between','',{left,low,self:expr(4)})
  elseif self:accept('LIKE') then e=node('like','',{left,self:expr(4)}) elseif neg then self:syntax() end
  if e then e.neg=neg return e end return left
 end
 local ops=({[0]=set('OR'),[1]=set('AND'),[2]={},[4]=set('+ - ||'),[5]=set('* / %'),[6]={}})[level]
 while ops[self:peek().value] and (self:peek().kind=='keyword' or self:peek().kind=='symbol') do local op=self:take().value left=node('binary',op,{left,self:expr(level+1)}) end return left
end
function Parser:primary()
 local t=self:peek() if t.kind=='integer' or t.kind=='string' then self:take() return node('literal','',{},t.value) end
 if self:accept('NULL') then return node('literal','',{},NULL) end
 if t.kind=='name' then return self:reference() end
 if aggregates[t.value] and t.kind=='keyword' then local name=self:take().value self:expect('(') local e=node('aggregate',name) if not(name=='COUNT' and self:accept('*')) then e.distinct=self:accept('DISTINCT') e.args={self:expr()} end self:expect(')') return e end
 if self:accept('(') then local e=self:expr() self:expect(')') return node('group','',{e}) end self:syntax()
end
function Parser:clause(w) if self:accept(w) then return self:expr() end end
function Parser:item()
 local start=self.i local e=self:expr() local tokens=slice(self.tokens,start,self.i-1) local alias=self:alias() local heading=alias
 if not heading then if e.kind=='ref' then heading=e.column else heading='' for i,t in ipairs(tokens) do if i>1 and t.kind~='symbol' and tokens[i-1].kind~='symbol' then heading=heading..' ' end heading=heading..t.text end end end return {expr=e,alias=alias,heading=heading}
end
function Parser:order_item()
 local start=self.i local e=self:expr() local single=self.i==start+1 local t=self.tokens[start] local desc=self:accept('DESC') if not desc then self:accept('ASC') end
 return {expr=e,desc=desc,ordinal=single and t.kind=='integer' and t.value or nil,alias=single and t.kind=='name' and t.value or nil}
end
function Parser:query()
 local q={kind='select',distinct=self:accept('DISTINCT'),joins={},group={},order={}}
 if self:accept('*') then q.star=true q.items={} else q.items=self:comma(function()return self:item()end) end self:expect('FROM') q.source=self:table()
 while self:at('JOIN') or self:at('INNER') or self:at('LEFT') do local left=self:accept('LEFT') if left then self:accept('OUTER') else self:accept('INNER') end self:expect('JOIN') local t=self:table() self:expect('ON') q.joins[#q.joins+1]={table=t,left=left,condition=self:expr()} end
 q.where=self:clause('WHERE') if self:accept('GROUP') then q.grouped=true self:expect('BY') q.group=self:comma(function()return self:reference()end) end q.having=self:clause('HAVING')
 if self:accept('ORDER') then self:expect('BY') q.order=self:comma(function()return self:order_item()end) end
 if self:accept('LIMIT') then q.limit=self:kind('integer') if self:accept('OFFSET') then q.offset=self:kind('integer') end end return q
end
function Parser:statement()
 local s
 if self:accept('CREATE') then self:expect('TABLE') local name=self:kind('name') local cols=self:parens(function() local c={name=self:kind('name'),primary=0,notnull=false} if not self:at('INT') and not self:at('TEXT') then self:syntax() end c.type=self:take().value while true do if self:accept('PRIMARY') then self:expect('KEY') c.primary=c.primary+1 c.notnull=true elseif self:accept('NOT') then self:expect('NULL') c.notnull=true else break end end return c end) s={kind='create',name=name,columns=cols}
 elseif self:accept('DROP') then self:expect('TABLE') s={kind='drop',name=self:kind('name')}
 elseif self:accept('INSERT') then self:expect('INTO') local name=self:kind('name') local names if self:at('(') then names=self:parens(function()return self:kind('name')end) end self:expect('VALUES') s={kind='insert',name=name,names=names,tuples=self:comma(function()return self:parens(function()return self:expr()end)end)}
 elseif self:accept('UPDATE') then local name=self:kind('name') self:expect('SET') local assignments=self:comma(function()local n=self:kind('name') self:expect('=') return {n,self:expr()}end) s={kind='update',name=name,assignments=assignments,where=self:clause('WHERE')}
 elseif self:accept('DELETE') then self:expect('FROM') s={kind='delete',name=self:kind('name'),where=self:clause('WHERE')}
 elseif self:accept('SELECT') then s=self:query() elseif self:accept('EXIT') then s={kind='exit'} end self:expect(';') return s
end
local function column(t,name) for i,c in ipairs(t.columns) do if c.name==name then return i end end end
local function resolve(e,scope)
 local found,kind,table_seen
 for _,entry in ipairs(scope) do if not e.table or e.table==entry.name then table_seen=true local i=column(entry.table,e.column) if i then if found then fail('ambiguous column '..e.column) end found=entry.offset+i kind=entry.table.columns[i].type end end end
 if e.table and not table_seen then fail('unknown table '..e.table) end if not found then fail('unknown column '..e.text) end e.index=found return kind
end
local function compatible(a,b) return a==b or a=='NULL' or b=='NULL' end
local function require_type(a,b,op) if not compatible(a,b) then fail('type mismatch for '..op) end end
local check
check=function(e,scope,allow,grouped,inside)
 if e.kind=='literal' then return e.value==NULL and 'NULL' or type(e.value)=='number' and 'INT' or 'TEXT' end
 if e.kind=='ref' then local t=resolve(e,scope) if grouped and not inside and not grouped[e.index] then fail('column '..e.text..' is not grouped') end return t end
 if e.kind=='aggregate' then if not allow or inside then fail('misuse of aggregate '..e.op) end if #e.args==0 then return 'INT' end local t=check(e.args[1],scope,allow,grouped,true) if e.op=='SUM' or e.op=='AVG' then require_type(t,'INT',e.op) end return (e.op=='MIN' or e.op=='MAX') and t or 'INT' end
 local ts={} for _,arg in ipairs(e.args) do ts[#ts+1]=check(arg,scope,allow,grouped,inside) end
 if e.kind=='group' then return ts[1] elseif e.kind=='isnull' then return 'INT' elseif e.kind=='binary' and comparisons[e.op] then require_type(ts[1],ts[2],e.op) return 'INT'
 elseif e.kind=='in' or e.kind=='between' then for i=2,#ts do require_type(ts[i],ts[1],e.kind=='in' and 'IN' or 'BETWEEN') end return 'INT'
 else local op=e.kind=='like' and 'LIKE' or e.op local t=(op=='LIKE' or op=='||') and 'TEXT' or 'INT' for _,actual in ipairs(ts) do require_type(actual,t,op) end return op=='||' and 'TEXT' or 'INT' end
end
local function condition(e,scope,name,allow,grouped) if e then require_type(check(e,scope,allow,grouped),'INT',name) end end
local function has_aggregate(e) if e.kind=='aggregate' then return true end for _,a in ipairs(e.args) do if has_aggregate(a) then return true end end return false end
local function truth(v) return v~=NULL and v~=0 end
local function inverse(v) if v==NULL then return NULL end return v==0 and 1 or 0 end
local function quotient(a,b) local q=math.abs(a)//math.abs(b) if (a<0)~=(b<0) then return -q end return q end
local function operate(op,a,b)
 if op=='AND' then if a==0 or b==0 then return 0 elseif a==NULL or b==NULL then return NULL else return 1 end end
 if op=='OR' then if truth(a) or truth(b) then return 1 elseif a==NULL or b==NULL then return NULL else return 0 end end
 if a==NULL or b==NULL then return NULL end
 if op=='+' then return a+b elseif op=='||' then return a..b elseif op=='-' then return a-b elseif op=='*' then return a*b elseif op=='/' then return b==0 and NULL or quotient(a,b) elseif op=='%' then return b==0 and NULL or a-b*quotient(a,b) end
 local ok=op=='=' and a==b or (op=='<>' or op=='!=') and a~=b or op=='<' and a<b or op=='>' and a>b or op=='<=' and a<=b or op=='>=' and a>=b return ok and 1 or 0
end
local function like(text,pattern)
 local dp={[0]=true} for i=1,#text do dp[i]=false end for i=1,#pattern do local c=pattern:sub(i,i) if c=='%' then for j=1,#text do dp[j]=dp[j] or dp[j-1] end else for j=#text,1,-1 do dp[j]=dp[j-1] and (c=='_' or c==text:sub(j,j)) end dp[0]=false end end return dp[#text] and 1 or 0
end
local evaluate
evaluate=function(e,row,group)
 if e.kind=='literal' then return e.value elseif e.kind=='ref' then return row[e.index] end
 if e.kind=='aggregate' then
  if #e.args==0 then return #group end local a={} for _,r in ipairs(group) do local v=evaluate(e.args[1],r) if v~=NULL then local duplicate=false if e.distinct then for _,old in ipairs(a) do if v==old then duplicate=true break end end end if not duplicate then a[#a+1]=v end end end
  if e.op=='COUNT' then return #a elseif #a==0 then return NULL end local result=a[1]
  if e.op=='MIN' or e.op=='MAX' then for i=2,#a do if e.op=='MIN' and a[i]<result or e.op=='MAX' and a[i]>result then result=a[i] end end return result end result=0 for _,v in ipairs(a) do result=result+v end return e.op=='AVG' and quotient(result,#a) or result
 end
 local a={} for _,arg in ipairs(e.args) do a[#a+1]=evaluate(arg,row,group) end
 if e.kind=='group' then return a[1] elseif e.kind=='unary' then if e.op=='NOT' then return inverse(a[1]) elseif a[1]==NULL then return NULL else return -a[1] end elseif e.kind=='binary' then return operate(e.op,a[1],a[2]) elseif e.kind=='isnull' then return ((a[1]==NULL)~=e.neg) and 1 or 0 end
 local result if e.kind=='in' then result=0 if a[1]==NULL then result=NULL else local unknown=false for i=2,#a do if a[i]==NULL then unknown=true elseif a[i]==a[1] then result=1 break end end if result==0 and unknown then result=NULL end end elseif e.kind=='between' then result=operate('AND',operate('>=',a[1],a[2]),operate('<=',a[1],a[3])) elseif e.kind=='like' then result=(a[1]==NULL or a[2]==NULL) and NULL or like(a[1],a[2]) end return e.neg and inverse(result) or result
end
local function satisfies(e,row,group) return not e or truth(evaluate(e,row,group)) end
local function count(n) return n..(n==1 and ' row' or ' rows') end
local function written(v) return v==NULL and 'NULL' or type(v)=='number' and string.format('%d',v) or v end
local function row_equal(a,b) if #a~=#b then return false end for i=1,#a do if a[i]~=b[i] then return false end end return true end
local function print_table(items,types,rows)
 local widths,cells={},{} for i,item in ipairs(items) do widths[i]=#item.heading end
 for _,row in ipairs(rows) do local r={} for i,v in ipairs(row) do r[i]=written(v) widths[i]=math.max(widths[i],#r[i]) end cells[#cells+1]=r end
 local separator='+' for _,w in ipairs(widths) do separator=separator..string.rep('-',w+2)..'+' end
 local function render(cells,header) local s='|' for i,c in ipairs(cells) do local padding=string.rep(' ',widths[i]-#c) s=s..' '..(not header and types[i]=='INT' and padding..c or c..padding)..' |' end return s end
 print(separator) local heads={} for _,item in ipairs(items) do heads[#heads+1]=item.heading end print(render(heads,true)) print(separator) for _,r in ipairs(cells) do print(render(r,false)) end print(separator) print('('..count(#rows)..')')
end
local Database={} Database.__index=Database
function Database:table(n) if not self.tables[n] then fail('unknown table '..n) end return self.tables[n] end
function Database:targets(t,names) local a={} local seen={} for _,name in ipairs(names) do local i=column(t,name) if not i then fail('unknown column '..name) end if seen[i] then fail('duplicate column '..name) end seen[i]=true a[#a+1]=i end return a end
function Database:constraints(t,rows,checked)
 for _,i in ipairs(checked) do for j,c in ipairs(t.columns) do if c.notnull and rows[i][j]==NULL then fail('NULL value in column '..c.name) end end
  if t.key then for j,r in ipairs(rows) do if i~=j and r[t.key]==rows[i][t.key] then fail('duplicate primary key '..written(r[t.key])) end end end end
end
function Database:select(q)
 local scope={} local width=0 local names={}
 local function add(ref) local t=self:table(ref.name) if names[ref.alias] then fail('duplicate table name '..ref.alias) end names[ref.alias]=true scope[#scope+1]={name=ref.alias,table=t,offset=width} width=width+#t.columns end
 add(q.source) for _,j in ipairs(q.joins) do add(j.table) condition(j.condition,scope,'ON') end condition(q.where,scope,'WHERE')
 local grouping={} for _,ref in ipairs(q.group) do resolve(ref,scope) grouping[#grouping+1]=ref.index end
 if q.star then for _,entry in ipairs(scope) do for _,c in ipairs(entry.table.columns) do local e=node('ref') e.table=entry.name e.column=c.name e.text=c.name q.items[#q.items+1]={expr=e,heading=c.name} end end end
 local aggregate=q.grouped or q.having~=nil for _,i in ipairs(q.items) do aggregate=aggregate or has_aggregate(i.expr) end for _,i in ipairs(q.order) do aggregate=aggregate or has_aggregate(i.expr) end
 local grouped if aggregate then grouped={} for _,i in ipairs(grouping) do grouped[i]=true end end
 local types={} for _,i in ipairs(q.items) do types[#types+1]=check(i.expr,scope,true,grouped) end condition(q.having,scope,'HAVING',true,grouped)
 local keys={} for _,o in ipairs(q.order) do local key
  if o.ordinal then if o.ordinal<1 or o.ordinal>#q.items then fail('ORDER BY position '..o.ordinal..' is out of range') end key=q.items[o.ordinal].expr
  elseif o.alias then for _,i in ipairs(q.items) do if i.alias==o.alias then key=i.expr break end end end
  if not key then check(o.expr,scope,true,grouped) key=o.expr end keys[#keys+1]=key end
 local rows=scope[1].table.rows
 for ji,j in ipairs(q.joins) do local t=scope[ji+1].table local nextrows={} for _,left in ipairs(rows) do local found=false for _,right in ipairs(t.rows) do local combined=concat(left,right) if satisfies(j.condition,combined) then nextrows[#nextrows+1]=combined found=true end end if j.left and not found then local padding={} for _=1,#t.columns do padding[#padding+1]=NULL end nextrows[#nextrows+1]=concat(left,padding) end end rows=nextrows end
 local filtered={} for _,r in ipairs(rows) do if satisfies(q.where,r) then filtered[#filtered+1]=r end end rows=filtered
 local groups={}
 if not aggregate then for _,r in ipairs(rows) do groups[#groups+1]={r} end elseif not q.grouped then groups={rows}
 else local groupkeys={} for _,r in ipairs(rows) do local k={} for _,i in ipairs(grouping) do k[#k+1]=r[i] end local at for i,old in ipairs(groupkeys) do if row_equal(k,old) then at=i break end end if not at then at=#groups+1 groups[at]={} groupkeys[at]=k end groups[at][#groups[at]+1]=r end end
 local results={}
 for _,g in ipairs(groups) do local row=g[1] or {} local context=aggregate and g or nil if satisfies(q.having,row,context) then local values,sortkeys={},{} for _,i in ipairs(q.items) do values[#values+1]=evaluate(i.expr,row,context) end for _,key in ipairs(keys) do sortkeys[#sortkeys+1]=evaluate(key,row,context) end results[#results+1]={values=values,keys=sortkeys,position=#results+1} end end
 table.sort(results,function(a,b) for i,o in ipairs(q.order) do local x,y=a.keys[i],b.keys[i] if x~=y then local smaller=x==NULL or y~=NULL and x<y if o.desc then return not smaller else return smaller end end end return a.position<b.position end)
 local selected={} local unique={} for _,r in ipairs(results) do local duplicate=false if q.distinct then for _,old in ipairs(unique) do if row_equal(old,r.values) then duplicate=true break end end end if not duplicate then unique[#unique+1]=r.values end end
 local start=(q.offset or 0)+1 local last=q.limit and start+q.limit-1 or #unique for i=start,math.min(last,#unique) do selected[#selected+1]=unique[i] end print_table(q.items,types,selected)
end
function Database:execute(s)
 if s.kind=='create' then if self.tables[s.name] then fail('table '..s.name..' already exists') end local seen={} local primary=0 local key for i,c in ipairs(s.columns) do if seen[c.name] then fail('duplicate column '..c.name) end seen[c.name]=true primary=primary+c.primary if primary>=2 then fail('multiple primary keys') end if c.primary>0 then key=i end end self.tables[s.name]={name=s.name,columns=s.columns,key=key,rows={}} print('Table '..s.name..' created.') return elseif s.kind=='select' then return self:select(s) end
 local t=self:table(s.name) if s.kind=='drop' then self.tables[s.name]=nil print('Table '..s.name..' dropped.') return end
 local rows,checked,countrows={},{},0
 if s.kind=='insert' then
  local targets={} if s.names then targets=self:targets(t,s.names) else for i=1,#t.columns do targets[i]=i end end
  for _,tuple in ipairs(s.tuples) do if #tuple~=#targets then fail('expected '..#targets..' values, got '..#tuple) end for i,e in ipairs(tuple) do local c=t.columns[targets[i]] require_type(check(e,{}),c.type,'column '..c.name) end end
  rows=concat(t.rows,{}) for _,tuple in ipairs(s.tuples) do local r={} for i=1,#t.columns do r[i]=NULL end for i,e in ipairs(tuple) do r[targets[i]]=evaluate(e,{}) end rows[#rows+1]=r checked[#checked+1]=#rows end countrows=#s.tuples self:constraints(t,rows,checked)
 elseif s.kind=='update' then
  local names={} for _,a in ipairs(s.assignments) do names[#names+1]=a[1] end local targets=self:targets(t,names) local scope={{name=t.name,table=t,offset=0}}
  for i,a in ipairs(s.assignments) do local c=t.columns[targets[i]] require_type(check(a[2],scope),c.type,'column '..c.name) end condition(s.where,scope,'WHERE')
  for i,r in ipairs(t.rows) do local nextrow=r if satisfies(s.where,r) then nextrow=concat(r,{}) for j,a in ipairs(s.assignments) do nextrow[targets[j]]=evaluate(a[2],r) end countrows=countrows+1 checked[#checked+1]=i end rows[#rows+1]=nextrow end self:constraints(t,rows,checked)
 else condition(s.where,{{name=t.name,table=t,offset=0}},'WHERE') for _,r in ipairs(t.rows) do if satisfies(s.where,r) then countrows=countrows+1 else rows[#rows+1]=r end end end
 t.rows=rows print(count(countrows)..(s.kind=='insert' and ' inserted.' or s.kind=='update' and ' updated.' or ' deleted.'))
end
local source=io.read('*a') local segments={} local start,i=1,1
while i<=#source do local c=source:sub(i,i) if c=="'" then i=source:find("'",i+1,true)+1 elseif source:sub(i,i+1)=='--' then i=source:find('\n',i,true) or #source+1 elseif c==';' then segments[#segments+1]=source:sub(start,i) start=i+1 i=i+1 else i=i+1 end end
local db=setmetatable({tables={}},Database)
for _,s in ipairs(segments) do local ok,command=pcall(function()return Parser:new(tokenize(s)):statement()end) if not ok then print('ERROR: '..command) elseif command then if command.kind=='exit' then break end local success,err=pcall(function()db:execute(command)end) if not success then print('ERROR: '..err) end end end
