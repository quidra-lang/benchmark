local function emit(s) io.write(s, "\n") end
local function power2(n) return n > 0 and (n & (n - 1)) == 0 end
local function class(n)
    local k = 0
    while n >= 2 do n = n // 2; k = k + 1 end
    return k
end
local Heap = {}
Heap.__index = Heap
function Heap:new(size, mode)
    local h = setmetatable({size=size, mode=mode, blocks={}, ids={}, histories={},
        roots={}, links={}, age=0, rover=0, peak=0, ops={0,0,0,0,0,0}}, self)
    h.blocks[1] = h:freeblock(0, size)
    return h
end
function Heap:freeblock(a, size)
    self.age = self.age + 1
    return {a=a, size=size, age=self.age}
end
function Heap:sort() table.sort(self.blocks, function(a,b) return a.a < b.a end) end
function Heap:index(block)
    for i,b in ipairs(self.blocks) do if b == block then return i end end
end
function Heap:required(n)
    local s = ((n + 7) // 8) * 8 + 8
    if self.mode == "BUDDY" then
        local p = 32
        while p < s do p = p * 2 end
        return p
    end
    return s
end
function Heap:allocate(s, al)
    local choices = {}
    local start = 1
    for i,b in ipairs(self.blocks) do
        if b.a <= self.rover and self.rover < b.a+b.size then start = i end
        if not b.used then
            local p = ((b.a + 8 + al - 1) // al) * al - 8
            if p-b.a > 0 and p-b.a < 16 then p = p + al end
            if p+s <= b.a+b.size then choices[#choices+1] = {b=b, p=p, i=i} end
        end
    end
    if #choices == 0 then return nil end
    local mode = self.mode
    table.sort(choices, function(x,y)
        local a,b = x.b,y.b
        if mode == "NEXT" then
            return (x.i-start+#self.blocks)%#self.blocks < (y.i-start+#self.blocks)%#self.blocks
        elseif mode == "BEST" or mode == "BUDDY" then
            if a.size ~= b.size then return a.size < b.size end
        elseif mode == "WORST" then
            if a.size ~= b.size then return a.size > b.size end
        elseif mode == "SEGFIT" then
            if class(a.size) ~= class(b.size) then return class(a.size) < class(b.size) end
            return a.age > b.age
        end
        return a.a < b.a
    end)
    local c = choices[1]
    local b, p = c.b, c.p
    table.remove(self.blocks, c.i)
    local used
    if mode == "BUDDY" then
        local z = b.size
        while z > s do
            z = z // 2
            self.blocks[#self.blocks+1] = self:freeblock(b.a+z,z)
        end
        used = {a=b.a,size=s,used=true}
    else
        if p > b.a then self.blocks[#self.blocks+1] = self:freeblock(b.a,p-b.a) end
        local z = b.a+b.size-p
        used = {a=p,size=(z-s >= 16 and s or z),used=true}
        if z-s >= 16 then self.blocks[#self.blocks+1] = self:freeblock(p+s,z-s) end
    end
    self.blocks[#self.blocks+1] = used
    self:sort()
    if mode == "NEXT" then self.rover = (used.a+used.size)%self.size end
    return used
end
function Heap:release(b)
    b.used, b.id, b.req, b.data = nil,nil,nil,nil
    local merges = 0
    if self.mode == "BUDDY" then
        while b.size < self.size do
            local buddy = b.a ~ b.size
            local found
            for i,c in ipairs(self.blocks) do
                if c ~= b and not c.used and c.a == buddy and c.size == b.size then found=i; break end
            end
            if not found then break end
            table.remove(self.blocks,found)
            b.a, b.size = math.min(b.a,buddy), b.size*2
            merges = merges+1
        end
        self:sort()
    else
        local i = self:index(b)
        local nextb = self.blocks[i+1]
        if nextb and not nextb.used then
            b.size = b.size+nextb.size
            table.remove(self.blocks,i+1)
            merges = merges+1
        end
        local prev = self.blocks[i-1]
        if prev and not prev.used then
            b.a,b.size = prev.a,b.size+prev.size
            table.remove(self.blocks,i-1)
            merges = merges+1
        end
    end
    self.age = self.age+1
    b.age = self.age
    return b,merges
end
function Heap:record(id,line)
    self.histories[id] = self.histories[id] or {}
    table.insert(self.histories[id],line)
    emit(line)
end
function Heap:state(id)
    local b = self.ids[id]
    if type(b) == "table" then return b end
    emit("ERROR "..(b == false and "USE AFTER FREE " or "UNKNOWN ID ")..id)
end
function Heap:forget(id)
    self.ids[id],self.roots[id],self.links[id] = false,nil,nil
    for _,edges in pairs(self.links) do edges[id] = nil end
end
function Heap:freeid(id,kind)
    local b = self.ids[id]
    if type(b) ~= "table" then
        emit("ERROR "..(b == false and "DOUBLE FREE " or "UNKNOWN ID ")..id)
        return
    end
    local size = b.size
    local f,m = self:release(b)
    self:forget(id)
    if kind == "FREE" then self.ops[2] = self.ops[2]+1 else self.ops[6] = self.ops[6]+1 end
    self:record(id,kind.." "..id.." block="..size.." merges="..m.." free="..f.a.."+"..f.size)
end
function Heap:malloc(id,n,al,kind)
    if n == 0 then emit("ERROR BAD SIZE"); return end
    if type(self.ids[id]) == "table" then emit("ERROR DUPLICATE ID "..id); return end
    local b = self:allocate(self:required(n),al)
    if not b then self.ops[5]=self.ops[5]+1; emit("ERROR OUT OF MEMORY "..id); return end
    b.id,b.req,b.data = id,n,{}
    if kind == "CALLOC" then for i=1,n do b.data[i]=0 end end
    self.ids[id] = b
    self.ops[1]=self.ops[1]+1
    self:record(id,kind.." "..id.." addr="..(b.a+8).." block="..b.size)
end
function Heap:realloc(id,n)
    if n == 0 then self:freeid(id,"FREE"); return end
    if self.ids[id] == nil then self:malloc(id,n,8,"MALLOC"); return end
    local b = self:state(id)
    if not b then return end
    local a,oldsize,oldreq,data = b.a,b.size,b.req,b.data
    local s,kind = self:required(n),nil
    if s <= b.size then
        kind = "kept"
        if self.mode == "BUDDY" then
            if s < b.size then kind="shrunk" end
            while b.size > s do
                b.size=b.size//2
                self.blocks[#self.blocks+1] = self:freeblock(a+b.size,b.size)
            end
            self:sort()
        elseif b.size-s >= 16 then
            local i = self:index(b)
            local z = b.size-s
            b.size = s
            local c = self.blocks[i+1]
            if c and not c.used then z=z+c.size; table.remove(self.blocks,i+1) end
            table.insert(self.blocks,i+1,self:freeblock(a+s,z))
            kind="shrunk"
        end
    elseif self.mode ~= "BUDDY" then
        local i = self:index(b)
        local c = self.blocks[i+1]
        if c and not c.used and b.size+c.size >= s then
            local z = b.size+c.size
            table.remove(self.blocks,i+1)
            b.size = z-s >= 16 and s or z
            if z-s >= 16 then table.insert(self.blocks,i+1,self:freeblock(a+s,z-s)) end
            kind="grown"
        end
    else
        local absorbed = {}
        local t = b.size
        while t < s and a%(2*t)==0 do
            local found
            for _,c in ipairs(self.blocks) do
                if not c.used and c.a==a+t and c.size==t then found=c; break end
            end
            if not found then break end
            absorbed[#absorbed+1]=found
            t=t*2
        end
        if t==s then
            for _,c in ipairs(absorbed) do table.remove(self.blocks,self:index(c)) end
            b.size=s
            kind="grown"
        end
    end
    if not kind then
        local dest=self:allocate(s,8)
        if not dest then self.ops[5]=self.ops[5]+1; emit("ERROR OUT OF MEMORY "..id); return end
        self:release(b)
        b=dest
        b.id=id
        self.ids[id]=b
        kind="moved"
        self.ops[4]=self.ops[4]+1
    end
    b.req,b.data=n,data
    for i=n+1,oldreq do data[i]=nil end
    self.ops[3]=self.ops[3]+1
    local line="REALLOC "..id.." addr="..(b.a+8).." block="..b.size.." "..kind
    if kind=="moved" then line=line.." from="..(a+8) end
    self:record(id,line)
end
function Heap:reachable()
    local seen,stack={},{}
    for id in pairs(self.roots) do stack[#stack+1]=id end
    while #stack>0 do
        local id=table.remove(stack)
        if not seen[id] then
            seen[id]=true
            for dst in pairs(self.links[id] or {}) do stack[#stack+1]=dst end
        end
    end
    return seen
end
function Heap:totals()
    local u,f,l,ub,fb,r=0,0,0,0,0,0
    for _,b in ipairs(self.blocks) do
        if b.used then u=u+b.size; ub=ub+1; r=r+(b.req or 0)
        else f=f+b.size; l=math.max(l,b.size); fb=fb+1 end
    end
    return u,f,l,ub,fb,r,(f>0 and (f-l)*100//f or 0)
end
local function bench(size,seed,ops,maxreq)
    if size<32 or size>65536 or not power2(size) then emit("ERROR BAD HEAP SIZE"); return end
    emit("BENCH heap="..size.." seed="..seed.." ops="..ops.." maxreq="..maxreq)
    for _,mode in ipairs({"FIRST","NEXT","BEST","WORST","SEGFIT","BUDDY"}) do
        local h,x,live,ok,fail,peak=Heap:new(size,mode),seed,{},0,0,0
        for _=1,ops do
            x=48271*x%2147483647
            local alloc=#live==0 or x%3~=0
            x=48271*x%2147483647
            if alloc then
                local b=h:allocate(h:required(1+x%maxreq),8)
                if b then live[#live+1]=b; ok=ok+1 else fail=fail+1 end
            else h:release(table.remove(live,1+x%#live)) end
            local used=h:totals()
            peak=math.max(peak,used)
        end
        local u,_,_,_,_,_,frag=h:totals()
        emit("BENCH "..mode.." ok="..ok.." fail="..fail.." peak="..peak.." used="..u.." frag="..frag.." blocks="..#h.blocks)
    end
end
local heap
local function command(t)
    local cmd,id=t[1],t[2]
    local function num(i) return tonumber(t[i]) end
    if cmd=="BENCH" then bench(num(2),num(3),num(4),num(5)); return end
    if cmd=="HEAP" then
        local s,mode=num(2),t[3]
        if s<32 or s>65536 or s%8~=0 or (mode=="BUDDY" and not power2(s)) then
            emit("ERROR BAD HEAP SIZE")
        else heap=Heap:new(s,mode); emit("HEAP size="..s.." mode="..mode) end
        return
    end
    local h=heap
    if not h then emit("ERROR NO HEAP"); return end
    if cmd=="MALLOC" or cmd=="CALLOC" or cmd=="MEMALIGN" then
        local al,n=8,num(3)
        if cmd=="CALLOC" then n=num(3)*num(4) end
        if cmd=="MEMALIGN" then
            if h.mode=="BUDDY" then emit("ERROR UNSUPPORTED IN BUDDY MODE"); return end
            al,n=num(3),num(4)
            if al<8 or al>4096 or not power2(al) then emit("ERROR BAD ALIGNMENT"); return end
        end
        h:malloc(id,n,al,cmd)
    elseif cmd=="FREE" then h:freeid(id,"FREE")
    elseif cmd=="REALLOC" then h:realloc(id,num(3))
    elseif cmd=="FILL" or cmd=="READ" or cmd=="COPY" then
        local b=h:state(id)
        if not b then return end
        local off,len=num(3),num(cmd=="COPY" and 6 or 4)
        if off+len>b.req then emit("ERROR OUT OF BOUNDS "..id); return end
        if cmd=="FILL" then
            for i=off+1,off+len do b.data[i]=num(5) end
            emit("FILL "..id.." "..off.."+"..len.." = "..num(5))
        elseif cmd=="READ" then
            local values={}
            for i=off+1,off+len do values[#values+1]=b.data[i]~=nil and tostring(b.data[i]) or "?" end
            emit("READ "..id.." "..off.."+"..len.." = "..table.concat(values," "))
        else
            local src,soff=t[4],num(5)
            local c=h:state(src)
            if not c then return end
            if soff+len>c.req then emit("ERROR OUT OF BOUNDS "..src); return end
            local values={}
            for i=1,len do values[i]=c.data[soff+i] or false end
            for i=1,len do b.data[off+i]=values[i]~=false and values[i] or nil end
            emit("COPY "..id.." "..off.."+"..len.." from "..src.." "..soff)
        end
    elseif cmd=="ROOT" or cmd=="UNROOT" then
        if not h:state(id) then return end
        if cmd=="UNROOT" and not h.roots[id] then emit("ERROR NOT ROOT "..id); return end
        h.roots[id]=cmd=="ROOT" or nil
        emit(cmd.." "..id)
    elseif cmd=="LINK" or cmd=="UNLINK" then
        if not h:state(id) or not h:state(t[3]) then return end
        h.links[id]=h.links[id] or {}
        if cmd=="UNLINK" and not h.links[id][t[3]] then emit("ERROR NO LINK "..id.." "..t[3]); return end
        h.links[id][t[3]]=cmd=="LINK" or nil
        emit(cmd.." "..id.." "..t[3])
    elseif cmd=="GC" then
        local reachable,list,bytes=h:reachable(),{},0
        for _,b in ipairs(h.blocks) do
            if b.used and not reachable[b.id] then list[#list+1]=b.id; bytes=bytes+b.size end
        end
        emit("GC collected="..#list.." bytes="..bytes)
        for _,v in ipairs(list) do h:freeid(v,"COLLECT") end
    elseif cmd=="SBRK" then
        local k=num(2)
        if h.size+k>65536 or (h.mode=="BUDDY" and k~=h.size) or (h.mode~="BUDDY" and (k<16 or k%8~=0)) then
            emit("ERROR BAD SBRK SIZE"); return
        end
        local b={a=h.size,size=k}
        h.blocks[#h.blocks+1]=b
        h.size=h.size+k
        h:release(b)
        emit("SBRK heap="..h.size.." free="..b.a.."+"..b.size)
    elseif cmd=="TRIM" then
        local old=h.size
        if h.mode=="BUDDY" then
            while #h.blocks>1 and not h.blocks[#h.blocks].used and h.blocks[#h.blocks].size==h.size//2 do
                h.size=h.size//2; table.remove(h.blocks)
            end
        elseif #h.blocks>1 and not h.blocks[#h.blocks].used then h.size=h.blocks[#h.blocks].a; table.remove(h.blocks) end
        if h.rover>=h.size then h.rover=0 end
        emit("TRIM heap="..h.size.." released="..(old-h.size))
    elseif cmd=="COMPACT" then
        if h.mode=="BUDDY" then emit("ERROR UNSUPPORTED IN BUDDY MODE"); return end
        local blocks,moves,pos={},{},0
        for _,b in ipairs(h.blocks) do
            if b.used then
                if b.a~=pos then moves[#moves+1]={id=b.id,line="MOVE "..b.id.." "..(b.a+8).." -> "..(pos+8)} end
                b.a=pos; pos=pos+b.size; blocks[#blocks+1]=b
            end
        end
        if pos<h.size then blocks[#blocks+1]=h:freeblock(pos,h.size-pos) end
        h.blocks,h.rover=blocks,0
        h.ops[4]=h.ops[4]+#moves
        emit("COMPACT moved="..#moves.." free="..(pos<h.size and pos.."+"..(h.size-pos) or "none"))
        for _,m in ipairs(moves) do h:record(m.id,m.line) end
    elseif cmd=="WHO" then
        local p=num(2)
        if p>=h.size then emit("WHO "..p.." outside"); return end
        for _,b in ipairs(h.blocks) do
            if b.a<=p and p<b.a+b.size then
                local result
                if not b.used then result="free "..b.a.."+"..b.size
                elseif p<b.a+8 then result="header "..b.id
                else local d=p-b.a-8; result=(d<b.req and "data " or "slack ")..b.id.."+"..d end
                emit("WHO "..p.." "..result); break
            end
        end
    elseif cmd=="DUMP" then
        emit("DUMP mode="..h.mode.." heap="..h.size.." blocks="..#h.blocks..(h.mode=="NEXT" and " rover="..h.rover or ""))
        for _,b in ipairs(h.blocks) do emit(b.a.." "..b.size..(b.used and " USED "..b.id.." req="..b.req or " FREE")) end
    elseif cmd=="MAP" then
        emit("MAP heap="..h.size)
        local units={}
        for _,b in ipairs(h.blocks) do
            units[#units+1]=b.used and "H" or "F"
            for k=0,b.size//8-2 do units[#units+1]=b.used and (8*k<b.req and "#" or "-") or "." end
        end
        for i=1,#units,64 do emit(string.format("%05d %s",(i-1)*8,table.concat(units,"",i,math.min(i+63,#units)))) end
    elseif cmd=="FREELIST" then
        local groups,count={},0
        for _,b in ipairs(h.blocks) do
            if not b.used then local k=class(b.size); groups[k]=groups[k] or {}; table.insert(groups[k],b); count=count+1 end
        end
        emit("FREELIST count="..count)
        for k=0,16 do
            if groups[k] then
                if h.mode=="SEGFIT" then table.sort(groups[k],function(a,b) return a.age>b.age end) end
                local items={}
                for _,b in ipairs(groups[k]) do items[#items+1]=b.a.."+"..b.size end
                emit((1<<k).."-"..((1<<(k+1))-1)..": "..table.concat(items," "))
            end
        end
    elseif cmd=="TREE" then
        if h.mode~="BUDDY" then emit("ERROR REQUIRES BUDDY MODE"); return end
        emit("TREE heap="..h.size)
        local function tree(a,s,depth)
            local prefix=string.rep(" ",2*depth)..a.."+"..s
            for _,b in ipairs(h.blocks) do
                if b.a==a and b.size==s then emit(prefix..(b.used and " USED "..b.id or " FREE")); return end
            end
            emit(prefix.." split"); tree(a,s//2,depth+1); tree(a+s//2,s//2,depth+1)
        end
        tree(0,h.size,0)
    elseif cmd=="STATS" then
        local u,f,l,ub,fb,r,frag=h:totals()
        emit("STATS used="..u.." used_blocks="..ub.." free="..f.." free_blocks="..fb.." largest="..l.." frag="..frag.." requested="..r.." peak="..h.peak)
        local o=h.ops
        emit("OPS allocs="..o[1].." frees="..o[2].." reallocs="..o[3].." moves="..o[4].." failures="..o[5].." collected="..o[6])
    elseif cmd=="LEAKS" then
        local reach,list,req,lost=h:reachable(),{},0,0
        for id,b in pairs(h.ids) do
            if type(b)=="table" then list[#list+1]=id; req=req+b.req; if not reach[id] then lost=lost+1 end end
        end
        table.sort(list)
        emit("LEAKS count="..#list.." requested="..req.." lost="..lost)
        for _,id in ipairs(list) do local b=h.ids[id]; emit("LEAK "..id.." addr="..(b.a+8).." block="..b.size.." req="..b.req.." "..(reach[id] and "reachable" or "lost")) end
    elseif cmd=="HISTORY" then
        local history=h.histories[id] or {}
        emit("HISTORY "..id.." events="..#history)
        for _,line in ipairs(history) do emit(line) end
    end
end
local n=tonumber(io.read())
for _=1,n do
    local t={}
    for word in io.read():gmatch("%S+") do t[#t+1]=word end
    command(t)
    if heap then
        local used=heap:totals()
        heap.peak=math.max(heap.peak,used)
    end
end
