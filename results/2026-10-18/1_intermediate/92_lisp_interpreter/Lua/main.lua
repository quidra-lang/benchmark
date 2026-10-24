local NIL, VOID, UNINIT = {tag='nil'}, {tag='void'}, {tag='uninitialized'}
local symbols = {}
local function symbol(s) if not symbols[s] then symbols[s]={tag='symbol',name=s} end return symbols[s] end
local function pair(a,b) return {tag='pair',car=a,cdr=b} end
local function kind(v,t) return type(v)=='table' and v.tag==t end
local function list(a,tail) local v=tail if v==nil then v=NIL end for i=#a,1,-1 do v=pair(a[i],v) end return v end
local function items(v) local a={} while kind(v,'pair') do a[#a+1]=v.car v=v.cdr end if v==NIL then return a end end
local function slice(a,first,last) local b={} for i=first,last or #a do b[#b+1]=a[i] end return b end
local function repr(v,quoted)
  if quoted==nil then quoted=true end
  if v==NIL then return '()' elseif v==VOID then return '#<void>' elseif type(v)=='boolean' then return v and '#t' or '#f'
  elseif type(v)=='number' then return string.format('%d',v) elseif type(v)=='string' then
    if not quoted then return v end
    return '"'..v:gsub('\\','\\\\'):gsub('"','\\"'):gsub('\n','\\n')..'"'
  elseif v.tag=='symbol' then return v.name elseif v.tag=='procedure' then return v.name and '#<procedure '..v.name..'>' or '#<procedure>' end
  local a={} while kind(v,'pair') do a[#a+1]=repr(v.car,quoted) v=v.cdr end
  if v~=NIL then a[#a+1]='.' a[#a+1]=repr(v,quoted) end return '('..table.concat(a,' ')..')'
end
local function equal(a,b,deep) if deep and kind(a,'pair') and kind(b,'pair') then return equal(a.car,b.car,true) and equal(a.cdr,b.cdr,true) end return a==b end
local function fail(s) error(s,0) end
local function env(parent) return {parent=parent,frame={}} end
local function find(e,n) while e do if e.frame[n]~=nil then return e end e=e.parent end fail('unbound variable: '..n) end
local function lookup(e,n) local v=find(e,n).frame[n] if v==UNINIT then fail('uninitialized variable: '..n) end return v end
local evaluate, call
local function body(a,e) local v=VOID for _,x in ipairs(a) do v=evaluate(x,e) end return v end
local function parameters(v)
  local names,seen={},{} while kind(v,'pair') do if not kind(v.car,'symbol') or seen[v.car.name] then return nil end
    names[#names+1]=v.car.name seen[v.car.name]=true v=v.cdr end
  if v==NIL then return {names=names} end
  if not kind(v,'symbol') or seen[v.name] then return nil end return {names=names,rest=v.name}
end
local function closure(p,b,e,name) return {tag='procedure',name=name,min=#p.names,rest=p.rest,params=p.names,body=b,env=e} end
local function shape(ok,x) if not ok then fail('bad syntax: '..repr(x)) end end
local function bindings(v,unique)
  local a=items(v) if not a then return nil end local bs,seen={},{}
  for _,x in ipairs(a) do local b=items(x) if not b or #b~=2 or not kind(b[1],'symbol') or unique and seen[b[1].name] then return nil end
    bs[#bs+1]={b[1].name,b[2]} seen[b[1].name]=true end return bs
end
call=function(p,a)
  if #a<p.min or not p.rest and #a~=p.min then fail((p.name or 'lambda')..': wrong number of arguments (expected '..(p.rest and 'at least ' or '')..p.min..', got '..#a..')') end
  if p.fn then return p.fn(a) end local e=env(p.env)
  for i,n in ipairs(p.params) do e.frame[n]=a[i] end if p.rest then e.frame[p.rest]=list(slice(a,p.min+1)) end return body(p.body,e)
end
evaluate=function(x,e)
  if kind(x,'symbol') then return lookup(e,x.name) end
  if not kind(x,'pair') then shape(x~=NIL,x) return x end
  local a=items(x) shape(a,x) local n,h=#a,kind(a[1],'symbol') and a[1].name or ''
  if h=='quote' then shape(n==2,x) return a[2]
  elseif h=='if' then shape(n==3 or n==4,x) if evaluate(a[2],e)~=false then return evaluate(a[3],e) elseif n==4 then return evaluate(a[4],e) else return VOID end
  elseif h=='begin' then return body(slice(a,2),e)
  elseif h=='lambda' then local p=n>=3 and parameters(a[2]) shape(p,x) return closure(p,slice(a,3),e)
  elseif h=='define' then
    if kind(a[2],'symbol') then shape(n==3,x) local v=evaluate(a[3],e) if kind(v,'procedure') and not v.fn and not v.name then v.name=a[2].name end e.frame[a[2].name]=v
    else local t=a[2] local p=n>=3 and kind(t,'pair') and kind(t.car,'symbol') and parameters(t.cdr) shape(p,x) e.frame[t.car.name]=closure(p,slice(a,3),e,t.car.name) end return VOID
  elseif h=='set!' then shape(n==3 and kind(a[2],'symbol'),x) local v=evaluate(a[3],e) find(e,a[2].name).frame[a[2].name]=v return VOID
  elseif h=='let' or h=='let*' or h=='letrec' then
    local named=h=='let' and kind(a[2],'symbol') local at=named and 3 or 2 local bs=n>=at+1 and bindings(a[at],h~='let*') shape(bs,x) local scope=env(e)
    if h=='let*' then if #bs>0 then scope=e end for _,b in ipairs(bs) do local v=evaluate(b[2],scope) scope=env(scope) scope.frame[b[1]]=v end
    elseif h=='letrec' then for _,b in ipairs(bs) do scope.frame[b[1]]=UNINIT end for _,b in ipairs(bs) do scope.frame[b[1]]=evaluate(b[2],scope) end
    else local vs={} for _,b in ipairs(bs) do vs[#vs+1]=evaluate(b[2],e) end
      if named then local names={} for _,b in ipairs(bs) do names[#names+1]=b[1] end local p=closure({names=names},slice(a,4),scope,a[2].name) scope.frame[a[2].name]=p return call(p,vs) end
      for i,b in ipairs(bs) do scope.frame[b[1]]=vs[i] end end return body(slice(a,at+1),scope)
  elseif h=='cond' then
    local cs={} for i=2,n do local c=items(a[i]) shape(c and #c>0,x) if c[1]==symbol('else') then shape(#c>=2 and i==n,x) end cs[#cs+1]=c end
    for _,c in ipairs(cs) do if c[1]==symbol('else') then return body(slice(c,2),e) end local v=evaluate(c[1],e) if v~=false then if #c==1 then return v else return body(slice(c,2),e) end end end return VOID
  elseif h=='and' then local v=true for i=2,n do v=evaluate(a[i],e) if v==false then break end end return v
  elseif h=='or' then for i=2,n do local v=evaluate(a[i],e) if v~=false then return v end end return false
  elseif h=='when' or h=='unless' then shape(n>=3,x) if (evaluate(a[2],e)~=false)==(h=='when') then return body(slice(a,3),e) end return VOID end
  local f=evaluate(a[1],e) local args={} for i=2,n do args[#args+1]=evaluate(a[i],e) end
  if not kind(f,'procedure') then fail('not a procedure: '..repr(f)) end return call(f,args)
end
local mid=false
local function write(s) io.write(s) if #s>0 then mid=s:sub(-1)~='\n' end end
local function line(s) if mid then write('\n') end write(s..'\n') end
local function global_env()
  local e=env()
  local function add(n,m,r,f) e.frame[n]={tag='procedure',name=n,min=m,rest=r,fn=f} end
  local function expect(n,v,k)
    local ok=k=='integer' and type(v)=='number' or k=='string' and type(v)=='string' or k=='list' and items(v)~=nil or k=='pair' and kind(v,'pair') or k=='procedure' and kind(v,'procedure')
    if not ok then fail(n..': expected '..k..', got '..repr(v)) end return v
  end
  for _,name in ipairs{'+','*','-','quotient','remainder','modulo','abs','min','max','gcd','=','<','>','<=','>='} do
    local fixed=(name=='quotient' or name=='remainder' or name=='modulo') and 2 or name=='abs' and 1 or nil
    add(name,fixed or ((name=='+' or name=='*' or name=='gcd') and 0 or 1),not fixed,function(a)
      for _,v in ipairs(a) do expect(name,v,'integer') end
      if name=='+' or name=='*' then local v=name=='+' and 0 or 1 for _,x in ipairs(a) do if name=='+' then v=v+x else v=v*x end end return v
      elseif name=='-' then local v=a[1] if #a==1 then return -v end for i=2,#a do v=v-a[i] end return v
      elseif name=='abs' then return math.abs(a[1]) elseif name=='min' then return math.min(table.unpack(a)) elseif name=='max' then return math.max(table.unpack(a))
      elseif name=='gcd' then local g=0 for _,v in ipairs(a) do v=math.abs(v) while v~=0 do g,v=v,g%v end end return g
      elseif name=='quotient' or name=='remainder' or name=='modulo' then
        if a[2]==0 then fail(name..': division by zero') end local q=math.floor(math.abs(a[1])/math.abs(a[2])) if (a[1]<0)~=(a[2]<0) then q=-q end
        if name=='quotient' then return q elseif name=='remainder' then return a[1]-a[2]*q else return a[1]%a[2] end
      end
      for i=2,#a do local u,v=a[i-1],a[i] local ok=name=='=' and u==v or name=='<' and u<v or name=='>' and u>v or name=='<=' and u<=v or name=='>=' and u>=v if not ok then return false end end return true
    end)
  end
  add('not',1,false,function(a) return a[1]==false end)
  add('eq?',2,false,function(a) return equal(a[1],a[2]) end) add('equal?',2,false,function(a) return equal(a[1],a[2],true) end)
  for _,name in ipairs{'null?','pair?','list?','number?','symbol?','procedure?'} do add(name,1,false,function(a) local v=a[1]
    return name=='null?' and v==NIL or name=='pair?' and kind(v,'pair') or name=='list?' and items(v)~=nil or name=='number?' and type(v)=='number' or name=='symbol?' and kind(v,'symbol') or name=='procedure?' and kind(v,'procedure') end) end
  add('cons',2,false,function(a) return pair(a[1],a[2]) end) add('list',0,true,list)
  for _,name in ipairs{'car','cdr','cadr'} do add(name,1,false,function(a) local p=expect(name,a[1],'pair') if name=='car' then return p.car elseif name=='cdr' then return p.cdr end return expect(name,p.cdr,'pair').car end) end
  for _,name in ipairs{'length','reverse','list-ref'} do add(name,name=='list-ref' and 2 or 1,false,function(a)
    local ls=items(expect(name,a[1],'list')) if name=='length' then return #ls elseif name=='reverse' then local v=NIL for _,x in ipairs(ls) do v=pair(x,v) end return v end
    local k=expect(name,a[2],'integer') if k<0 or k>=#ls then fail('list-ref: index out of range: '..string.format('%d',k)) end return ls[k+1]
  end) end
  add('append',0,true,function(a) if #a==0 then return NIL end local z={} for i=1,#a-1 do for _,v in ipairs(items(expect('append',a[i],'list'))) do z[#z+1]=v end end return list(z,a[#a]) end)
  for _,name in ipairs{'map','filter','fold-left','apply'} do add(name,name=='fold-left' and 3 or 2,name~='filter',function(a)
    local f=expect(name,a[1],'procedure') if name=='apply' then local z=slice(a,2,#a-1) for _,v in ipairs(items(expect(name,a[#a],'list'))) do z[#z+1]=v end return call(f,z) end
    local ls={} local count=math.huge for i=(name=='fold-left' and 3 or 2),#a do local z=items(expect(name,a[i],'list')) ls[#ls+1]=z count=math.min(count,#z) end
    local result,acc={},a[2] for i=1,count do
      if name=='filter' then if call(f,{ls[1][i]})~=false then result[#result+1]=ls[1][i] end
      else local z={} if name=='fold-left' then z[1]=acc end for _,l in ipairs(ls) do z[#z+1]=l[i] end local v=call(f,z) if name=='map' then result[#result+1]=v else acc=v end end end
    if name=='fold-left' then return acc end return list(result)
  end) end
  add('string-append',0,true,function(a) for _,v in ipairs(a) do expect('string-append',v,'string') end return table.concat(a) end)
  add('number->string',1,false,function(a) return string.format('%d',expect('number->string',a[1],'integer')) end)
  add('display',1,false,function(a) write(repr(a[1],false)) return VOID end) add('newline',0,false,function() write('\n') return VOID end)
  add('error',1,true,function(a) local s=expect('error',a[1],'string') for i=2,#a do s=s..' '..repr(a[i]) end fail(s) end) return e
end
local lines={} for s in io.lines() do if s=='(exit)' then break end lines[#lines+1]=s end
local row,col=1,1
local function skip() row=row+1 col=1 end
local function at_end() while row<=#lines do local s=lines[row] while s:sub(col,col)==' ' do col=col+1 end if col<=#s and s:sub(col,col)~=';' then return false end skip() end return true end
local function token()
  if at_end() then fail('unexpected end of input') end local s=lines[row] local c=s:sub(col,col) col=col+1
  if c=='(' or c==')' or c=="'" then return c end
  if c=='"' then local v='' while col<=#s do c=s:sub(col,col) col=col+1 if c=='"' then return 'v',v end
    if c=='\\' then if col>#s then break end c=s:sub(col,col) col=col+1 if c~='"' and c~='\\' and c~='n' then fail('bad escape') end if c=='n' then c='\n' end end v=v..c end fail('unterminated string') end
  local first=col-1 while col<=#s and not (" ()'\";"):find(s:sub(col,col),1,true) do col=col+1 end local a=s:sub(first,col-1)
  if a=='.' then return '.' elseif a:match('^[+-]?%d+$') then return 'v',tonumber(a) elseif a=='#t' then return 'v',true elseif a=='#f' then return 'v',false elseif a:sub(1,1)=='#' then fail('bad token: '..a) end return 'v',symbol(a)
end
local datum
local function from(t,v)
  if t=='v' then return v elseif t=="'" then return list{symbol('quote'),datum()} elseif t~='(' then fail('unexpected '..t) end
  local a={} while true do local k,v=token() if k==')' then return list(a) end if k=='.' and #a>0 then local tail=datum() if token()~=')' then fail('expected )') end return list(a,tail) end a[#a+1]=from(k,v) end
end
datum=function() return from(token()) end
local global=global_env()
while not at_end() do local ok,x=pcall(datum) if not ok then line('Error: read: '..x) if x=='unexpected end of input' then break end skip()
  else local success,v=pcall(evaluate,x,global) if not success then line('Error: '..v) elseif v~=VOID then line(repr(v)) end end end
if mid then write('\n') end
