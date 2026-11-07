local directory=arg[0]:match("^(.*)/") or "."
package.path=directory.."/?.lua;"..package.path
local item_module=require("items")
local bom_module=require("bom")
local lot=require("lot_sizing")
local capacity=require("capacity")
local costing=require("costing")
local report=require("report")
local function append(target,values) for _,value in ipairs(values) do target[#target+1]=value end end
local function zeros(count) local result={}; for i=1,count do result[i]=0 end; return result end
local function sum(values) local total=0; for _,value in ipairs(values) do total=total+value end; return total end
local function depth_label(depth) return string.rep(".",depth)..depth end
local data={errors={}}
for line in io.lines("input/params.txt") do
    local words={}; for word in line:gmatch("[^ ]+") do words[#words+1]=word end
    if words[1] == "horizon" then data.horizon=tonumber(words[2])
    elseif words[1] == "tree_quantity" then data.tree_quantity=tonumber(words[2])
    else data.peg={}; for i=2,#words do data.peg[#data.peg+1]=words[i] end end
end
data.items=item_module.read(data.errors); data.bom=bom_module.read(data.items,data.errors)
data.centers=capacity.read_centers(data.errors); data.routings=capacity.read_routings(data.items,data.centers,data.bom,data.errors)
data.codes,data.cumulative,data.order=bom_module.structure(data.items,data.bom)
data.item_order=item_module.keys(data.items); data.center_order=item_module.keys(data.centers); data.weeks={}; for w=1,data.horizon do data.weeks[w]=w end
local function schedule_error(id,week,quantity)
    if not data.items[id] then return "unknown item "..id end
    if week<1 or week>data.horizon then return "week "..week.." outside horizon" end
    if quantity<1 then return "bad quantity "..quantity end
end
local function read_schedule(name,unique)
    local result,seen={},{}
    for _,row in ipairs(item_module.rows(name)) do
        local f=row.fields; local week,quantity=tonumber(f[2]),tonumber(f[3]); local message=schedule_error(f[1],week,quantity)
        local key=f[1].." "..week
        if not message and unique and seen[key] then message="duplicate "..f[1].." week "..week end
        if message then item_module.error(data.errors,name,row.line,message)
        else result[#result+1]={item=f[1],week=week,quantity=quantity,line=row.line}; seen[key]=true end
    end
    return result
end
data.mps=read_schedule("mps.csv",true); local receipts=read_schedule("receipts.csv",false); data.inquiries={}; local inquiry_ids={}
for _,row in ipairs(item_module.rows("orders.csv")) do
    local f=row.fields; local quantity,week=tonumber(f[3]),tonumber(f[4]); local message
    if inquiry_ids[f[1]] then message="duplicate order "..f[1] else message=schedule_error(f[2],week,quantity) end
    if message then item_module.error(data.errors,"orders.csv",row.line,message)
    else data.inquiries[#data.inquiries+1]={id=f[1],item=f[2],quantity=quantity,week=week,line=row.line}; inquiry_ids[f[1]]=true end
end
data.receipts,data.scheduled={},{}
for id in pairs(data.items) do data.receipts[id]={}; data.scheduled[id]=zeros(data.horizon) end
table.sort(receipts,function(a,b) return a.week == b.week and a.line<b.line or a.week<b.week end)
for _,receipt in ipairs(receipts) do table.insert(data.receipts[receipt.item],receipt); data.scheduled[receipt.item][receipt.week]=data.scheduled[receipt.item][receipt.week]+receipt.quantity end
local function run_mrp(promised,extra)
    local plan={items={},loads={},overloads={}}
    for _,id in ipairs(data.order) do plan.items[id]={demands={},gross=zeros(data.horizon),on_hand=zeros(data.horizon),net=zeros(data.horizon),pr=zeros(data.horizon),pl=zeros(data.horizon),orders={},past_due=0} end
    for _,row in ipairs(data.mps) do table.insert(plan.items[row.item].demands,{item=row.item,kind="MPS",week=row.week,quantity=row.quantity,line=row.line}) end
    for _,demand in ipairs(promised) do table.insert(plan.items[demand.item].demands,demand) end
    if extra then table.insert(plan.items[extra.item].demands,extra) end
    for _,id in ipairs(data.order) do
        local p,item=plan.items[id],data.items[id]
        for _,demand in ipairs(p.demands) do p.gross[demand.week]=p.gross[demand.week]+demand.quantity end
        local projected=item.on_hand
        for week=1,data.horizon do
            local available=projected+data.scheduled[id][week]-p.gross[week]; projected=available
            if available<item.safety then
                local quantity=lot.size(item,week,available,data.scheduled[id],p.gross,data.horizon)
                local original=week-item.lead; local order={item=id,number=#p.orders+1,receipt=week,quantity=quantity,original=original,release=math.max(1,original)}
                p.orders[#p.orders+1]=order; p.net[week]=item.safety-available; p.pr[week]=quantity; p.pl[order.release]=p.pl[order.release]+quantity; projected=available+quantity
                if original<1 then p.past_due=p.past_due+quantity end
            end
            p.on_hand[week]=projected
        end
        for _,order in ipairs(p.orders) do for _,row in ipairs(data.bom.children[id]) do
            table.insert(plan.items[row.child].demands,{item=row.child,kind="DEPENDENT",week=order.release,quantity=bom_module.need(row,order.quantity),parent=id,parent_number=order.number})
        end end
    end
    for _,center in ipairs(data.center_order) do plan.loads[center]=zeros(data.horizon); plan.overloads[center]=zeros(data.horizon) end
    for _,id in ipairs(data.order) do
        local operations=data.routings[id] or {}
        for _,order in ipairs(plan.items[id].orders) do for index,operation in ipairs(operations) do
            local week=capacity.week(order.receipt,data.items[id].lead,index-1,#operations)
            plan.loads[operation.center][week]=plan.loads[operation.center][week]+operation.setup+order.quantity*operation.run
        end end
    end
    for _,id in ipairs(data.center_order) do for w=1,data.horizon do plan.overloads[id][w]=math.max(0,plan.loads[id][w]-data.centers[id].available) end end
    return plan
end
local base=run_mrp({}); local current=base; local promised,promises={},{}
for _,inquiry in ipairs(data.inquiries) do
    local promise={inquiry=inquiry,week=0,material=0,reason=""}
    for week=inquiry.week,data.horizon do
        local demand={item=inquiry.item,kind="ORDER",week=week,quantity=inquiry.quantity,order_id=inquiry.id,line=inquiry.line}
        local trial=run_mrp(promised,demand); local reason
        for _,id in ipairs(data.order) do if trial.items[id].past_due>current.items[id].past_due then reason=id; break end end
        if not reason then
            if promise.material == 0 then promise.material=week end
            for _,id in ipairs(data.center_order) do
                for w=1,data.horizon do if trial.overloads[id][w]>current.overloads[id][w] then reason=id.." week "..w; break end end
                if reason then break end
            end
        end
        if not reason then promise.week=week; promised[#promised+1]=demand; current=trial; break end
        if week == inquiry.week then promise.reason=reason end
    end
    promises[#promises+1]=promise
end
local final=current
local demand_ranks={MPS=1,ORDER=2,DEPENDENT=3}; local root_ranks={MPS=1,ORDER=2,SAFETY=3}; local supply_ranks={STOCK=1,RECEIPT=2,ORDER=3}
local function demand_less(a,b)
    if a.week ~= b.week then return a.week<b.week end
    if a.kind ~= b.kind then return demand_ranks[a.kind]<demand_ranks[b.kind] end
    if a.kind == "ORDER" then return a.line<b.line end
    if a.kind == "DEPENDENT" then return a.parent == b.parent and a.parent_number<b.parent_number or a.parent<b.parent end
    return false
end
local function root_less(a,b)
    if a.item ~= b.item then return a.item<b.item end
    if a.kind ~= b.kind then return root_ranks[a.kind]<root_ranks[b.kind] end
    if a.week ~= b.week then return a.week<b.week end
    return (a.order_id or "")<(b.order_id or "")
end
local function root_key(root) return root.item.."|"..root.kind.."|"..root.week.."|"..(root.order_id or "") end
local function parent_supply(demand) return final.items[demand.parent].order_supplies[demand.parent_number] end
for _,id in ipairs(data.order) do
    local p,item=final.items[id],data.items[id]; p.supplies={}; p.order_supplies={}
    local function supply(kind,week,quantity,line,order) return {kind=kind,week=week,quantity=quantity,line=line or 0,order=order,remaining=quantity,allocations={},roots={}} end
    if item.on_hand>0 then table.insert(p.supplies,supply("STOCK",0,item.on_hand)) end
    for _,receipt in ipairs(data.receipts[id]) do table.insert(p.supplies,supply("RECEIPT",receipt.week,receipt.quantity,receipt.line)) end
    for _,order in ipairs(p.orders) do local s=supply("ORDER",order.receipt,order.quantity,0,order); table.insert(p.supplies,s); p.order_supplies[order.number]=s end
    table.sort(p.supplies,function(a,b) if a.week ~= b.week then return a.week<b.week elseif a.kind ~= b.kind then return supply_ranks[a.kind]<supply_ranks[b.kind] else return a.line<b.line end end)
    local demands={}; append(demands,p.demands); table.sort(demands,demand_less)
    if item.safety>0 then table.insert(demands,1,{item=id,kind="SAFETY",week=0,quantity=item.safety}) end
    local index=1
    for _,demand in ipairs(demands) do
        local remaining=demand.quantity
        while remaining>0 do
            while p.supplies[index].remaining == 0 do index=index+1 end
            local s=p.supplies[index]; local share=math.min(remaining,s.remaining)
            s.allocations[#s.allocations+1]={demand=demand,share=share}; s.remaining=s.remaining-share; remaining=remaining-share
        end
    end
    for _,s in ipairs(p.order_supplies) do
        local roots={}
        for _,allocation in ipairs(s.allocations) do
            local d=allocation.demand
            if d.kind == "DEPENDENT" then for _,root in ipairs(parent_supply(d).roots) do roots[root_key(root)]=root end else roots[root_key(d)]=d end
        end
        for _,root in pairs(roots) do s.roots[#s.roots+1]=root end; table.sort(s.roots,root_less)
    end
end
local function demand_text(demand)
    if demand.kind == "SAFETY" then return "SAFETY "..demand.item end
    if demand.kind == "MPS" then return "MPS "..demand.item.." week "..demand.week end
    if demand.kind == "ORDER" then return "ORDER "..demand.order_id.." "..demand.item.." week "..demand.week end
    return demand.parent.." order "..demand.parent_number.." week "..demand.week
end
local grid={}
for _,id in ipairs(data.order) do
    local p,item=final.items[id],data.items[id]
    grid[#grid+1]="ITEM "..id.." LLC "..data.codes[id].." LT "..item.lead.." LOT "..item_module.lot_label(item).." SS "..item.safety.." OH "..item.on_hand.." "..item.description
    for _,entry in ipairs({{"WEEK",data.weeks},{"GROSS",p.gross},{"RECEIPTS",data.scheduled[id]},{"ON_HAND",p.on_hand},{"NET",p.net},{"PLAN_RCPT",p.pr},{"PLAN_REL",p.pl}}) do grid[#grid+1]=report.row(entry[1],entry[2],6) end
    grid[#grid+1]="TOTAL gross "..sum(p.gross).." receipts "..sum(data.scheduled[id]).." planned "..sum(p.pr).." orders "..#p.orders.." ending "..p.on_hand[data.horizon]
end
local pegging={}
local function where_used(id,depth,extension)
    for _,row in ipairs(data.bom.parents[id]) do
        local ext=extension*row.quantity; pegging[#pegging+1]=depth_label(depth).." "..row.parent.." qty "..row.quantity.." ext "..ext; where_used(row.parent,depth+1,ext)
    end
end
local function allocations(s,depth)
    for _,allocation in ipairs(s.allocations) do
        local demand=allocation.demand; pegging[#pegging+1]=string.rep(" ",2*depth).."ALLOC "..allocation.share.." "..demand_text(demand)
        if s.kind == "ORDER" and demand.kind == "DEPENDENT" then allocations(parent_supply(demand),depth+1) end
    end
end
for _,id in ipairs(data.peg) do
    local p=final.items[id]; pegging[#pegging+1]="PEG "..id.." orders "..#p.orders; where_used(id,1,1)
    for _,kind in ipairs({"STOCK","RECEIPT","ORDER"}) do for _,s in ipairs(p.supplies) do if s.kind == kind then
        if kind == "STOCK" then pegging[#pegging+1]="STOCK quantity "..s.quantity
        elseif kind == "RECEIPT" then pegging[#pegging+1]="RECEIPT line "..s.line.." week "..s.week.." quantity "..s.quantity
        else local o=s.order; pegging[#pegging+1]="ORDER "..o.number.." receipt "..o.receipt.." release "..o.release.." quantity "..o.quantity end
        allocations(s,1); if s.remaining>0 then pegging[#pegging+1]="  EXCESS "..s.remaining end
        for _,root in ipairs(s.roots) do pegging[#pegging+1]="  ROOT "..demand_text(root) end
    end end end
end
local tree={}
local function explode(id,gross,extension,depth,totals)
    for _,row in ipairs(data.bom.children[id]) do
        local child=data.items[row.child]; local ext=extension*row.quantity; local quantity=bom_module.need(row,gross); totals[row.child]=(totals[row.child] or 0)+quantity
        tree[#tree+1]=depth_label(depth).." "..row.child.." qty "..row.quantity.." scrap "..row.scrap.." ext "..ext.." gross "..quantity.." lt "..child.lead.." cum "..data.cumulative[row.child].." "..child.description
        explode(row.child,quantity,ext,depth+1,totals)
    end
end
for _,id in ipairs(data.item_order) do if #data.bom.children[id]>0 and #data.bom.parents[id] == 0 then
    local item=data.items[id]; tree[#tree+1]="TREE "..id.." quantity "..data.tree_quantity
    tree[#tree+1]="0 "..id.." ext 1 gross "..data.tree_quantity.." lt "..item.lead.." cum "..data.cumulative[id].." "..item.description
    local totals={}; explode(id,data.tree_quantity,1,1,totals); for _,child in ipairs(item_module.keys(totals)) do tree[#tree+1]="SUM "..child.." "..totals[child] end
    local path,current={id},id
    while #data.bom.children[current]>0 do
        local chosen=data.bom.children[current][1].child
        for _,row in ipairs(data.bom.children[current]) do if data.cumulative[row.child]>data.cumulative[chosen] then chosen=row.child end end
        path[#path+1]=chosen; current=chosen
    end
    tree[#tree+1]="CRITICAL "..table.concat(path," -> ").." cum "..data.cumulative[id]
end end
local costs=costing.rollup(data.items,data.bom,data.order); local usages,values={},{}
for id in pairs(data.items) do usages[id]=sum(final.items[id].gross); values[id]=usages[id]*costs[id].total end
local classes=costing.abc(values); local cost_lines={"item,material,labor,total,usage,value,class"}
for _,id in ipairs(data.item_order) do local c=costs[id]; cost_lines[#cost_lines+1]=table.concat({id,report.money(c.material),report.money(c.labor),report.money(c.total),usages[id],report.money(values[id]),classes[id]},",") end
local exceptions={}; for _,message in ipairs(data.errors) do exceptions[#exceptions+1]="ERROR "..message end
local message_kinds={"BELOW_SAFETY","PAST_DUE","RELEASE","EXPEDITE","DEFER","CANCEL","NO_ROUTING","NO_DEMAND","OVERLOAD"}; local message_counts={}
for _,kind in ipairs(message_kinds) do message_counts[kind]=0 end
local function message(text) exceptions[#exceptions+1]=text; local kind=text:match("^[^ ]+"); message_counts[kind]=message_counts[kind]+1 end
for _,id in ipairs(data.order) do
    local p,item=final.items[id],data.items[id]
    if item.on_hand<item.safety then message("BELOW_SAFETY "..id.." on hand "..item.on_hand.." safety "..item.safety) end
    for _,o in ipairs(p.orders) do
        if o.original<1 then message("PAST_DUE "..id.." order "..o.number.." receipt "..o.receipt.." release "..o.original.." late "..(1-o.original).." quantity "..o.quantity)
        elseif o.original == 1 then message("RELEASE "..id.." order "..o.number.." receipt "..o.receipt.." quantity "..o.quantity) end
    end
    local balances,balance={},item.on_hand; for w=1,data.horizon do balance=balance-p.gross[w]; balances[w]=balance end
    local covered=0
    for _,receipt in ipairs(data.receipts[id]) do
        local need_week=0; for w=1,data.horizon do if balances[w]+covered<item.safety then need_week=w; break end end
        local text=id.." receipt line "..receipt.line.." week "..receipt.week.." quantity "..receipt.quantity
        if need_week == 0 then message("CANCEL "..text) elseif need_week<receipt.week then message("EXPEDITE "..text.." to "..need_week) elseif need_week>receipt.week then message("DEFER "..text.." to "..need_week) end
        covered=covered+receipt.quantity
    end
    if #data.bom.children[id]>0 and not data.routings[id] then message("NO_ROUTING "..id) end
    if sum(p.gross) == 0 and item.on_hand>0 then message("NO_DEMAND "..id.." on hand "..item.on_hand) end
end
for _,id in ipairs(data.center_order) do for w=1,data.horizon do if final.overloads[id][w]>0 then message("OVERLOAD "..id.." week "..w.." load "..final.loads[id][w].." available "..data.centers[id].available) end end end
local summary="SUMMARY errors "..#data.errors; for _,kind in ipairs(message_kinds) do summary=summary.." "..kind:lower().." "..message_counts[kind] end; exceptions[#exceptions+1]=summary
local capacity_lines,totals={},{}
for _,id in ipairs(data.center_order) do
    local center=data.centers[id]; local loads,overloads=final.loads[id],final.overloads[id]; local leveled=capacity.level(loads,center.available,data.horizon); local total=sum(loads); totals[id]=total
    local utilization,overloaded,peak={},0,0
    for w=1,data.horizon do utilization[w]=report.percent(loads[w],center.available); if overloads[w]>0 then overloaded=overloaded+1 end; if total>0 and (peak == 0 or loads[w]>loads[peak]) then peak=w end end
    capacity_lines[#capacity_lines+1]="CENTER "..id.." minutes "..center.minutes.." efficiency "..center.efficiency.." available "..center.available.." "..center.description
    for _,entry in ipairs({{"WEEK",data.weeks},{"LOAD",loads},{"UTIL",utilization},{"OVER",overloads},{"LEVELED",leveled}}) do capacity_lines[#capacity_lines+1]=report.row(entry[1],entry[2],7) end
    capacity_lines[#capacity_lines+1]="TOTAL load "..total.." available "..(center.available*data.horizon).." utilization "..report.percent(total,center.available*data.horizon).." overloaded "..overloaded.." peak "..peak.." backlog "..math.max(0,leveled[1]-center.available)
end
local ranked={}; append(ranked,data.center_order)
table.sort(ranked,function(a,b) local left,right=totals[a]*data.centers[b].available,totals[b]*data.centers[a].available; return left == right and a<b or left>right end)
for rank,id in ipairs(ranked) do capacity_lines[#capacity_lines+1]="RANK "..rank.." "..id.." load "..totals[id].." utilization "..report.percent(totals[id],data.centers[id].available*data.horizon) end
local promise_lines={}; local promise_counts={on_time=0,late=0,rejected=0}
for _,promise in ipairs(promises) do
    local q=promise.inquiry; local head="ORDER "..q.id.." "..q.item.." quantity "..q.quantity.." requested "..q.week
    local status=promise.week == 0 and "rejected" or promise.week == q.week and "on_time" or "late"; promise_counts[status]=promise_counts[status]+1
    local material=promise.material>0 and tostring(promise.material) or "none"
    if status == "rejected" then promise_lines[#promise_lines+1]=head.." rejected material "..material.." reason "..promise.reason
    else
        head=head.." promised "..promise.week
        if status == "late" then head=head.." late "..(promise.week-q.week).." material "..material.." reason "..promise.reason end
        promise_lines[#promise_lines+1]=head
        for _,id in ipairs(data.order) do for _,s in ipairs(final.items[id].order_supplies) do
            local serves=false; for _,root in ipairs(s.roots) do if root.kind == "ORDER" and root.order_id == q.id then serves=true; break end end
            if serves then local o=s.order; promise_lines[#promise_lines+1]="  SUPPLY "..id.." order "..o.number.." receipt "..o.receipt.." release "..o.release.." quantity "..o.quantity end
        end end
    end
end
for _,id in ipairs(data.order) do
    local before,after=base.items[id],final.items[id]
    for w=1,data.horizon do if before.pr[w] ~= after.pr[w] then promise_lines[#promise_lines+1]="CHANGE "..id.." from "..w.." planned "..sum(before.pr).." -> "..sum(after.pr).." orders "..#before.orders.." -> "..#after.orders; break end end
end
promise_lines[#promise_lines+1]="SUMMARY orders "..#promises.." on_time "..promise_counts.on_time.." late "..promise_counts.late.." rejected "..promise_counts.rejected
local releases,release_orders,available={},{},{}
for _,id in ipairs(data.order) do available[id]=data.items[id].on_hand+data.scheduled[id][1]; for _,order in ipairs(final.items[id].orders) do if order.release == 1 then release_orders[#release_orders+1]=order end end end
table.sort(release_orders,function(a,b) if a.original ~= b.original then return a.original<b.original elseif a.item ~= b.item then return a.item<b.item else return a.number<b.number end end)
local made,ready_count,bought,purchase_total=0,0,0,0
for _,o in ipairs(release_orders) do
    local item=data.items[o.item]; local lateness=o.original<1 and " late "..(1-o.original) or ""
    local head=o.item.." order "..o.number.." receipt "..o.receipt.." quantity "..o.quantity..lateness
    if #data.bom.children[o.item] == 0 then
        local value=o.quantity*item.material; bought=bought+1; purchase_total=purchase_total+value; releases[#releases+1]="BUY "..head.." value "..report.money(value)
    else
        local ready=true; local needs={}; local detail={}
        for i,row in ipairs(data.bom.children[o.item]) do local need=bom_module.need(row,o.quantity); needs[i]=need; if need>available[row.child] then ready=false end; detail[#detail+1]="  PICK "..row.child.." need "..need.." available "..available[row.child].." short "..math.max(0,need-available[row.child]) end
        if ready then ready_count=ready_count+1; for i,row in ipairs(data.bom.children[o.item]) do available[row.child]=available[row.child]-needs[i] end end
        local operations=data.routings[o.item] or {}
        for index,operation in ipairs(operations) do detail[#detail+1]="  OPERATION "..operation.number.." "..operation.center.." week "..capacity.week(o.receipt,item.lead,index-1,#operations).." minutes "..(operation.setup+o.quantity*operation.run) end
        made=made+1; releases[#releases+1]="MAKE "..head.." "..(ready and "READY" or "SHORT"); append(releases,detail)
    end
end
releases[#releases+1]="SUMMARY make "..made.." ready "..ready_count.." short "..(made-ready_count).." buy "..bought.." value "..report.money(purchase_total)
local values_output={"week,inventory,purchases,labor"}
for w=1,data.horizon do
    local inventory,purchases,labor=0,0,0
    for _,id in ipairs(data.order) do local p,item=final.items[id],data.items[id]; inventory=inventory+p.on_hand[w]*costs[id].total; if #data.bom.children[id]>0 then labor=labor+p.pl[w]*item.labor else purchases=purchases+p.pl[w]*item.material end end
    values_output[#values_output+1]=w..","..report.money(inventory)..","..report.money(purchases)..","..report.money(labor)
end
os.execute("mkdir -p output")
report.write("mrp_grid.txt",grid); report.write("pegging.txt",pegging); report.write("bom_tree.txt",tree); report.write("cost_rollup.csv",cost_lines); report.write("exceptions.txt",exceptions); report.write("capacity.txt",capacity_lines); report.write("promises.txt",promise_lines); report.write("releases.txt",releases); report.write("value_plan.csv",values_output)
