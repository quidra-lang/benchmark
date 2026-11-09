local directory=arg[0]:match("^(.*)/") or "."
package.path=directory.."/?.lua;"..package.path
local dates=require("dates_calendar")
local daycount=require("daycount")
local schedule=require("schedule")
local pricing=require("pricing")
local curve_math=require("curve")
local types={"FIXED","ZERO","AMORT","FRN"}
local buckets={"0-1Y","1-3Y","3-5Y","5-10Y","10Y+"}
local valid_frequency={[1]=true,[2]=true,[4]=true,[12]=true}
local valid_type={FIXED=true,ZERO=true,AMORT=true,FRN=true}
local valid_daycount={["30/360"]=true,["30E/360"]=true,["ACT/360"]=true,["ACT/365F"]=true,["ACT/ACT"]=true}
local valid_bdc={FOLLOWING=true,MODIFIED_FOLLOWING=true,PRECEDING=true,UNADJUSTED=true}
local option_keys={FIXED={EOM=true,LONG=true,CALL=true},ZERO={EOM=true,LONG=true},AMORT={EOM=true,LONG=true,SINK=true},FRN={EOM=true,LONG=true,LAG=true,CAP=true,FLOOR=true}}
local function split(text,separator)
    local result={}; for value in (text..separator):gmatch("(.-)"..separator) do result[#result+1]=value end; return result
end
local function words(text) local result={}; for word in text:gmatch("[^ ]+") do result[#result+1]=word end; return result end
local function lines(name) local result={}; for line in io.lines("input/"..name) do result[#result+1]=line end; return result end
local function rows(name) local result={}; for n,line in ipairs(lines(name)) do if n>1 then result[#result+1]={line=n,fields=split(line,",")} end end; return result end
local function write(name,output) local file=assert(io.open("output/"..name,"w")); for _,line in ipairs(output) do file:write(line,"\n") end; file:close() end
local function sorted_keys(map) local keys={}; for key in pairs(map) do keys[#keys+1]=key end; table.sort(keys); return keys end
local function half_up(a,b) return (2*a+b)//(2*b) end
local function hundredths(value)
    local negative=value<0; if negative then value=-value end
    return (negative and "-" or "")..string.format("%d.%02d",value//100,value%100)
end
local function decimals(value,digits)
    local scale=1; for _=1,digits do scale=scale*10 end
    local negative=value<0; if negative then value=-value end
    local rounded=math.floor(value*scale+0.5)
    return (negative and rounded>0 and "-" or "")..string.format("%d.%0"..digits.."d",rounded//scale,rounded%scale)
end
local function percent(value) return decimals(value*100,4) end
local function amount(value) return decimals(value/100,2) end
local function thousandths(value) local whole,fraction=value:match("^(%d+)%.(%d+)$"); return tonumber(whole)*1000+tonumber(fraction) end
local errors={}
local function add_error(file,line,key,message) errors[#errors+1]=file..":"..line..": "..key..": "..message end
local function reject(message) error(message,0) end
local params={scenarios={},limits={}}
for n,line in ipairs(lines("params.txt")) do
    local args=words(line)
    if args[1] == "valuation_date" then params.valuation=dates.parse(args[2])
    elseif args[1] == "settlement_days" then params.settlement_days=tonumber(args[2])
    elseif args[1] == "scenario" then local shifts={}; for i=3,#args do shifts[#shifts+1]=tonumber(args[i]) end; params.scenarios[#params.scenarios+1]={line=n,name=args[2],shifts=shifts}
    else local limit={}; for i=2,#args do limit[#limit+1]=args[i] end; params.limits[#params.limits+1]=limit end
end
local holidays={}; for _,line in ipairs(lines("calendar.txt")) do holidays[dates.parse(line)]=true end
local fixings={}; for _,row in ipairs(rows("fixings.csv")) do fixings[#fixings+1]={dates.parse(row.fields[1]),tonumber(row.fields[2])} end
local settlement=dates.move(params.valuation,params.settlement_days,1,holidays)
local pillars,seen={},{}
for _,row in ipairs(rows("curve_quotes.csv")) do
    local f=row.fields; local reason
    if seen[f[1]] then reason="duplicate pillar"
    elseif not dates.valid(f[1]) then reason="invalid date"
    elseif dates.parse(f[1])<=settlement then reason="pillar not after settlement"
    elseif not valid_frequency[tonumber(f[3])] then reason="invalid frequency" end
    if reason then add_error("curve_quotes.csv",row.line,f[1],reason)
    else pillars[#pillars+1]={maturity=dates.parse(f[1]),coupon=tonumber(f[2]),frequency=tonumber(f[3])} end
    seen[f[1]]=true
end
table.sort(pillars,function(a,b) return a.maturity<b.maturity end)
local scenarios={}; seen={}
for _,scenario in ipairs(params.scenarios) do
    if seen[scenario.name] then add_error("params.txt",scenario.line,scenario.name,"duplicate scenario")
    elseif #scenario.shifts ~= #pillars then add_error("params.txt",scenario.line,scenario.name,"wrong number of shifts")
    else local deltas={}; for i,shift in ipairs(scenario.shifts) do deltas[i]=shift*0.0001 end; scenarios[#scenarios+1]={name=scenario.name,deltas=deltas} end
    seen[scenario.name]=true
end
local function parse_options(kind,text)
    local options={sinks={},calls={}}; local used={}
    if text ~= "-" then for _,item in ipairs(split(text,";")) do
        local key,value=item:match("^([^=]+)=(.*)$"); if not key then key,value=item,"" end
        if not option_keys[kind][key] or (used[key] and key ~= "SINK" and key ~= "CALL") then reject("invalid option") end
        used[key]=true
        if key == "EOM" or key == "LONG" then options[key]=true
        elseif key == "SINK" or key == "CALL" then
            local date,number=value:match("^([^:]+):(.*)$")
            table.insert(options[key == "SINK" and "sinks" or "calls"],{date,key == "SINK" and tonumber(number) or thousandths(number)})
        else options[key]=tonumber(value) end
    end end
    if kind == "FRN" and (not options.LAG or options.LAG<1 or options.LAG>5 or (options.CAP or 1200)>1200 or (options.FLOOR and options.FLOOR>(options.CAP or 1200))) then reject("invalid option") end
    return options
end
local function schedule_items(items,boundaries,message)
    local inner={}; for i=2,#boundaries-1 do inner[boundaries[i]]=true end
    local result,last={},nil
    for _,item in ipairs(items) do
        if not dates.valid(item[1]) then reject(message) end
        local day=dates.parse(item[1])
        if not inner[day] or (last and day<=last) then reject(message) end
        result[#result+1]={day,item[2]}; last=day
    end
    return result
end
local function period_rate(bond,start)
    if bond.kind == "ZERO" then return 0 end
    if bond.kind ~= "FRN" then return bond.coupon end
    local reset=dates.move(dates.adjust(start,bond.bdc,holidays),bond.options.LAG,-1,holidays)
    local rate
    for _,fixing in ipairs(fixings) do if fixing[1]>reset then break end; rate=fixing[2] end
    if rate == nil then reject("missing fixing") end
    rate=rate+bond.coupon
    if bond.options.FLOOR then rate=math.max(rate,bond.options.FLOOR) end
    if bond.options.CAP then rate=math.min(rate,bond.options.CAP) end
    return rate
end
local function parse_bond(f)
    if seen[f[1]] then reject("duplicate id") end
    if not valid_type[f[2]] then reject("unknown type") end
    if not dates.valid(f[3]) or not dates.valid(f[4]) then reject("invalid date") end
    local issue,maturity=dates.parse(f[3]),dates.parse(f[4])
    if maturity<=issue then reject("maturity not after issue") end
    local coupon,frequency,face=tonumber(f[5]),tonumber(f[6]),tonumber(f[9])
    if not valid_frequency[frequency] then reject("invalid frequency") end
    if not valid_daycount[f[7]] then reject("unknown day count") end
    if not valid_bdc[f[8]] then reject("unknown business day rule") end
    if face%100000 ~= 0 or face>10000000 then reject("invalid face") end
    if coupon>1200 or (f[2] == "ZERO" and coupon ~= 0) then reject("invalid coupon") end
    local bond={code=f[1],kind=f[2],issue=issue,maturity=maturity,coupon=coupon,frequency=frequency,daycount=f[7],bdc=f[8],face=face}
    bond.options=parse_options(bond.kind,f[10]); bond.boundaries=schedule.build(issue,maturity,frequency,bond.options.EOM,bond.options.LONG)
    local sinks=schedule_items(bond.options.sinks,bond.boundaries,"invalid sinking fund"); bond.sinks={}; local total=0
    for _,sink in ipairs(sinks) do if sink[2] == 0 then reject("invalid sinking fund") end; total=total+sink[2]; bond.sinks[sink[1]]=sink[2] end
    if bond.kind == "AMORT" and (total == 0 or total>=face) then reject("invalid sinking fund") end
    bond.calls=schedule_items(bond.options.calls,bond.boundaries,"invalid call schedule")
    for _,call in ipairs(bond.calls) do if call[2]<100000 or call[2]>110000 then reject("invalid call schedule") end end
    bond.periods={}; local opening=face
    for i=2,#bond.boundaries do
        local start,finish=bond.boundaries[i-1],bond.boundaries[i]
        local n,m=daycount.fraction(bond.daycount,start,finish); local rate=period_rate(bond,start)
        local principal=i == #bond.boundaries and opening or (bond.sinks[finish] or 0)
        local coupon_amount=half_up(opening*rate*n,10000*m)
        bond.periods[#bond.periods+1]={number=i-1,start=start,finish=finish,payment=dates.adjust(finish,bond.bdc,holidays),n=n,m=m,rate=rate,opening=opening,coupon=coupon_amount,principal=principal,cash=coupon_amount+principal}
        opening=opening-principal
    end
    return bond
end
local bonds={}; seen={}
for _,row in ipairs(rows("bonds.csv")) do
    local ok,bond=pcall(parse_bond,row.fields)
    if ok then bonds[bond.code]=bond else add_error("bonds.csv",row.line,row.fields[1],bond) end
    seen[row.fields[1]]=true
end
local function valuation(bond,clean)
    local index=1; while bond.periods[index].finish<=settlement do index=index+1 end
    local current=bond.periods[index]; local n,m=daycount.fraction(bond.daycount,current.start,settlement)
    local v={bond=bond,clean=clean,remaining={},cash_flows={},flows={},yield_flows={},outstanding=current.opening,accrued=current.rate*n/(100*m)}
    v.accrued_amount=half_up(v.outstanding*current.rate*n,10000*m); v.clean_amount=half_up(v.outstanding*clean,100000); v.unit_value=v.clean_amount+v.accrued_amount; v.target=clean/1000+v.accrued
    n,m=daycount.fraction(bond.daycount,settlement,current.finish); v.w=bond.frequency*n/m
    for i=index,#bond.periods do
        local period=bond.periods[i]; v.remaining[#v.remaining+1]=period; v.yield_flows[#v.yield_flows+1]=period.cash
        if period.cash>=1 then v.cash_flows[#v.cash_flows+1]=period; v.flows[#v.flows+1]={period.payment-settlement,period.cash} end
    end
    v.next_payment=v.cash_flows[1].payment; return v
end
local valuations={}; seen={}
for _,row in ipairs(rows("prices.csv")) do
    local code=row.fields[1]; local bond=bonds[code]; local reason,v
    if not bond then reason="unknown bond"
    elseif seen[code] then reason="duplicate price"
    elseif not (bond.issue<=settlement and settlement<bond.maturity) then reason="not outstanding"
    else
        v=valuation(bond,thousandths(row.fields[2]))
        if not (pricing.dirty(v.yield_flows,v.w,bond.frequency,v.outstanding,0.0)>v.target and v.target>pricing.dirty(v.yield_flows,v.w,bond.frequency,v.outstanding,1.0)) then reason="yield out of range" end
    end
    if reason then add_error("prices.csv",row.line,code,reason) else valuations[code]=v end
    seen[code]=true
end
local portfolio_map={}
for _,row in ipairs(rows("holdings.csv")) do
    local f=row.fields; local code=f[2]; local face=tonumber(f[3]); local reason
    if not bonds[code] then reason="unknown bond"
    elseif not valuations[code] then reason="no price"
    elseif face%bonds[code].face ~= 0 then reason="invalid face" end
    if reason then add_error("holdings.csv",row.line,code,reason)
    else
        portfolio_map[f[1]]=portfolio_map[f[1]] or {}
        local position=portfolio_map[f[1]][code] or {v=valuations[code],bond=bonds[code],units=0,book=0}
        local units=face//bonds[code].face; position.units=position.units+units; position.book=position.book+half_up(units*position.v.outstanding*thousandths(f[4]),100000)
        portfolio_map[f[1]][code]=position
    end
end
local curve=curve_math.bootstrap(settlement,pillars)
for _,code in ipairs(sorted_keys(valuations)) do
    local v=valuations[code]; local bond=v.bond
    v.ytm=pricing.solve(v.yield_flows,v.w,bond.frequency,v.outstanding,v.target); v.risk=pricing.risk(v.yield_flows,v.w,bond.frequency,v.outstanding,v.ytm)
    v.ytw,v.workout=v.ytm,bond.maturity
    for _,call in ipairs(bond.calls) do if call[1]>settlement then
        local flows={}; for _,period in ipairs(v.remaining) do flows[#flows+1]=period.coupon; if period.finish == call[1] then flows[#flows]=flows[#flows]+half_up(period.opening*call[2],100000); break end end
        local rate=pricing.solve(flows,v.w,bond.frequency,v.outstanding,v.target); if rate<v.ytw then v.ytw,v.workout=rate,call[1] end
    end end
    local principal_days=0; for i,period in ipairs(v.cash_flows) do principal_days=principal_days+period.principal*v.flows[i][1] end
    v.wal=principal_days/(365*v.outstanding); v.curve_clean=curve_math.pv(curve,v.flows,0.0)*100/v.outstanding-v.accrued; v.zspread=curve_math.spread(curve,v.flows,v.unit_value)
end
local cashflows={"bond,period,start,end,payment,fraction,rate_bp,outstanding,coupon,principal"}
for _,code in ipairs(sorted_keys(bonds)) do for _,period in ipairs(bonds[code].periods) do if period.cash>=1 then
    cashflows[#cashflows+1]=table.concat({code,period.number,dates.format(period.start),dates.format(period.finish),dates.format(period.payment),decimals(period.n/period.m,6),period.rate,period.opening,period.coupon,period.principal},",")
end end end
local analytics={"bond,clean,accrued,dirty,ytm,ytw,workout,next_payment,wal,macaulay,modified,convexity,dv01,curve_clean,zspread"}
for _,code in ipairs(sorted_keys(valuations)) do local v=valuations[code]; analytics[#analytics+1]=table.concat({code,decimals(v.clean/1000,6),decimals(v.accrued,6),decimals(v.target,6),percent(v.ytm),percent(v.ytw),dates.format(v.workout),dates.format(v.next_payment),decimals(v.wal,4),decimals(v.risk.macaulay,4),decimals(v.risk.modified,4),decimals(v.risk.convexity,4),decimals(v.risk.dv01,6),decimals(v.curve_clean,6),percent(v.zspread)},",") end
local curve_lines={"valuation "..dates.format(params.valuation).." settlement "..dates.format(settlement)}
local previous=0
for i,pillar in ipairs(pillars) do
    local day=curve.days[i]
    curve_lines[#curve_lines+1]="pillar "..dates.format(pillar.maturity).." days "..day.." frequency "..pillar.frequency.." par "..hundredths(pillar.coupon).." zero "..percent(curve.rates[i]).." df "..decimals(curve_math.discount(curve,day,0.0),6).." forward "..percent(curve_math.forward(curve,previous,day))
    previous=day
end
for year=1,curve.days[#curve.days]//365 do
    local day=365*year
    curve_lines[#curve_lines+1]="grid "..year.."Y days "..day.." zero "..percent(curve_math.zero(curve,day)).." df "..decimals(curve_math.discount(curve,day,0.0),6).." forward "..percent(curve_math.forward(curve,day-365,day))
end
local function position_pv(position,on_curve) return position.units*curve_math.pv(on_curve,position.v.flows,position.v.zspread) end
local function position_value(position) return position.units*position.v.unit_value end
local function position_dv01(position) return position.v.risk.dv01*position.units*position.v.outstanding/10000 end
local function shifted_vector(pillar,shift) local deltas={}; for j=1,#curve.rates do deltas[j]=(pillar == nil or pillar == j) and shift or 0.0 end; return deltas end
local report,scenario_lines,compliance={},{"portfolio,scenario,bond,value,pnl"},{}
for _,name in ipairs(sorted_keys(portfolio_map)) do
    local positions={}; for _,code in ipairs(sorted_keys(portfolio_map[name])) do positions[#positions+1]=portfolio_map[name][code] end
    local p={value=0,face=0,outstanding=0,book=0,gain=0,income=0,ytm=0.0,modified=0.0,convexity=0.0,zspread=0.0,dv01=0.0,types={},buckets={},ladder={},base_values={},base=0.0}
    for _,kind in ipairs(types) do p.types[kind]={count=0,value=0,duration=0.0,dv01=0.0} end
    for _,bucket in ipairs(buckets) do p.buckets[bucket]={count=0,value=0,duration=0.0,dv01=0.0} end
    local cash_flow_list={}
    local function add_group(group,position,value)
        group.count=group.count+1; group.value=group.value+value; group.duration=group.duration+value*position.v.risk.modified; group.dv01=group.dv01+position_dv01(position)
    end
    for i,position in ipairs(positions) do
        local v=position.v; local value=position_value(position)
        p.value=p.value+value; p.face=p.face+position.units*position.bond.face; p.outstanding=p.outstanding+position.units*v.outstanding; p.book=p.book+position.book; p.gain=p.gain+position.units*v.clean_amount-position.book
        p.ytm=p.ytm+value*v.ytm; p.modified=p.modified+value*v.risk.modified; p.convexity=p.convexity+value*v.risk.convexity; p.zspread=p.zspread+value*v.zspread; p.dv01=p.dv01+position_dv01(position)
        p.base_values[i]=position_pv(position,curve); p.base=p.base+p.base_values[i]
        add_group(p.types[position.bond.kind],position,value)
        local days=position.bond.maturity-settlement; local bucket=days<365 and 1 or days<1095 and 2 or days<1825 and 3 or days<3650 and 4 or 5
        add_group(p.buckets[buckets[bucket]],position,value)
        for j,period in ipairs(v.cash_flows) do
            if v.flows[j][1]<=365 then p.income=p.income+position.units*period.coupon end
            cash_flow_list[#cash_flow_list+1]={v.flows[j][1],position.units*period.cash}
            local year=dates.civil(period.payment); local totals=p.ladder[year] or {0,0}; totals[1]=totals[1]+position.units*period.coupon; totals[2]=totals[2]+position.units*period.principal; p.ladder[year]=totals
        end
    end
    p.ytm=p.ytm/p.value; p.modified=p.modified/p.value; p.convexity=p.convexity/p.value; p.zspread=p.zspread/p.value
    local cash_yield=pricing.bisect(function(rate) return curve_math.pv({days={0},rates={rate}},cash_flow_list,0.0) end,0.0,1.0,p.value)
    local function portfolio_pv(on_curve) local total=0.0; for _,position in ipairs(positions) do total=total+position_pv(position,on_curve) end; return total end
    local function duration(pillar)
        local down=portfolio_pv(curve_math.shift(curve,shifted_vector(pillar,-0.0001))); local up=portfolio_pv(curve_math.shift(curve,shifted_vector(pillar,0.0001)))
        return (down-up)/(2*0.0001*p.base)
    end
    report[#report+1]="portfolio "..name
    for _,position in ipairs(positions) do
        local v=position.v; local value=position_value(position)
        report[#report+1]="position "..position.bond.code.." face "..hundredths(position.units*position.bond.face).." outstanding "..hundredths(position.units*v.outstanding).." clean "..decimals(v.clean/1000,6).." value "..hundredths(value).." weight "..decimals(value*100/p.value,4).." book "..hundredths(position.book).." gain "..hundredths(position.units*v.clean_amount-position.book).." ytm "..percent(v.ytm).." modified "..decimals(v.risk.modified,4).." dv01 "..decimals(position_dv01(position),2)
    end
    report[#report+1]="total positions "..#positions.." face "..hundredths(p.face).." outstanding "..hundredths(p.outstanding).." value "..hundredths(p.value).." book "..hundredths(p.book).." gain "..hundredths(p.gain).." income "..hundredths(p.income)
    report[#report+1]="risk ytm "..percent(p.ytm).." yield "..percent(cash_yield).." modified "..decimals(p.modified,4).." convexity "..decimals(p.convexity,4).." zspread "..percent(p.zspread).." dv01 "..decimals(p.dv01,2)
    local key_rates={}; for j=1,#curve.rates do key_rates[j]=decimals(duration(j),4) end
    report[#report+1]="curve effective "..decimals(duration(nil),4).." krd "..table.concat(key_rates," ")
    for _,kind in ipairs(types) do local group=p.types[kind]; report[#report+1]="type "..kind.." positions "..group.count.." value "..hundredths(group.value).." weight "..decimals(group.value*100/p.value,4).." duration "..decimals(group.duration/p.value,4).." dv01 "..decimals(group.dv01,2) end
    for _,bucket in ipairs(buckets) do local group=p.buckets[bucket]; report[#report+1]="bucket "..bucket.." positions "..group.count.." value "..hundredths(group.value).." weight "..decimals(group.value*100/p.value,4).." duration "..decimals(group.duration/p.value,4).." dv01 "..decimals(group.dv01,2) end
    local total_coupon,total_principal=0,0
    for _,year in ipairs(sorted_keys(p.ladder)) do local totals=p.ladder[year]; total_coupon=total_coupon+totals[1]; total_principal=total_principal+totals[2]; report[#report+1]="ladder "..year.." coupon "..hundredths(totals[1]).." principal "..hundredths(totals[2]).." total "..hundredths(totals[1]+totals[2]) end
    report[#report+1]="ladder total coupon "..hundredths(total_coupon).." principal "..hundredths(total_principal).." total "..hundredths(total_coupon+total_principal)
    local all_scenarios={{name="BASE",deltas=shifted_vector(nil,0.0)}}; for _,scenario in ipairs(scenarios) do all_scenarios[#all_scenarios+1]=scenario end
    local worst
    for scenario_index,scenario in ipairs(all_scenarios) do
        local shifted=curve_math.shift(curve,scenario.deltas); local result={name=scenario.name,pnls={},total=0.0}
        for i,position in ipairs(positions) do
            local value=position_pv(position,shifted); local pnl=value-p.base_values[i]; result.pnls[i]=pnl; result.total=result.total+value
            scenario_lines[#scenario_lines+1]=table.concat({name,scenario.name,position.bond.code,amount(value),amount(pnl)},",")
        end
        result.pnl=result.total-p.base
        scenario_lines[#scenario_lines+1]=table.concat({name,scenario.name,"*",amount(result.total),amount(result.pnl)},",")
        if scenario_index>1 and (not worst or result.pnl<worst.pnl) then worst=result end
    end
    if worst then
        local order={}; for i=1,#positions do order[i]=i end
        table.sort(order,function(a,b) return worst.pnls[a] == worst.pnls[b] and positions[a].bond.code<positions[b].bond.code or worst.pnls[a]<worst.pnls[b] end)
        local stress="stress worst "..worst.name.." pnl "..amount(worst.pnl).." losers"
        for i=1,math.min(3,#order) do local j=order[i]; stress=stress.." "..positions[j].bond.code.." "..amount(worst.pnls[j]) end
        report[#report+1]=stress
    end
    local breaches=0
    for _,limit in ipairs(params.limits) do
        local kind=limit[1]; local details,breach
        if kind == "position_weight" then
            local largest=positions[1]; for _,position in ipairs(positions) do if position_value(position)>position_value(largest) then largest=position end end
            local value=position_value(largest); local b=tonumber(limit[2]); details=largest.bond.code.." "..decimals(value*100/p.value,4).." limit "..hundredths(b); breach=value*10000>b*p.value
        elseif kind == "type_weight" then
            local value=p.types[limit[2]].value; local b=tonumber(limit[3]); details=limit[2].." "..decimals(value*100/p.value,4).." limit "..hundredths(b); breach=value*10000>b*p.value
        elseif kind == "max_maturity" then
            local years=tonumber(limit[2]); local count=0; for _,position in ipairs(positions) do if position.bond.maturity-settlement>365*years then count=count+1 end end
            details=years.."Y positions "..count; breach=count>=1
        elseif kind == "min_yield" then local b=tonumber(limit[2]); details=percent(p.ytm).." limit "..hundredths(b); breach=p.ytm*10000<b
        elseif kind == "duration" then local a,b=tonumber(limit[2]),tonumber(limit[3]); details=decimals(p.modified,4).." range "..hundredths(a).." "..hundredths(b); breach=p.modified<a/100 or p.modified>b/100
        else local c=tonumber(limit[2]); details=decimals(p.dv01,2).." limit "..hundredths(c); breach=p.dv01*100>c end
        if breach then breaches=breaches+1 end
        compliance[#compliance+1]=name.." "..kind.." "..details.." "..(breach and "BREACH" or "PASS")
    end
    compliance[#compliance+1]=name.." breaches "..breaches
end
os.execute("mkdir -p output")
write("errors.txt",errors); write("cashflows.csv",cashflows); write("analytics.csv",analytics); write("curve.txt",curve_lines); write("portfolio.txt",report); write("scenarios.csv",scenario_lines); write("compliance.txt",compliance)
