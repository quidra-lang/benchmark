local daycount=require("daycount")
local schedule=require("schedule")
local pricing=require("pricing")
local M={}
function M.zero(curve,day)
    if day<=curve.days[1] then return curve.rates[1] end
    if day>=curve.days[#curve.days] then return curve.rates[#curve.rates] end
    local i=2; while curve.days[i]<day do i=i+1 end
    if curve.days[i] == day then return curve.rates[i] end
    return curve.rates[i-1]+(curve.rates[i]-curve.rates[i-1])*((day-curve.days[i-1])/(curve.days[i]-curve.days[i-1]))
end
function M.discount(curve,day,spread)
    local rate=M.zero(curve,day)+spread; local growth=1.0
    for _=1,day//365 do growth=growth*(1+rate) end
    return 1/(growth*(1+rate*(day%365)/365))
end
function M.pv(curve,flows,spread)
    local total=0.0; for _,flow in ipairs(flows) do total=total+flow[2]*M.discount(curve,flow[1],spread) end
    return total
end
function M.forward(curve,start,finish) return (M.discount(curve,start,0.0)/M.discount(curve,finish,0.0)-1)*365/(finish-start) end
function M.shift(curve,deltas)
    local shifted={days=curve.days,rates={}}; for i,rate in ipairs(curve.rates) do shifted.rates[i]=rate+deltas[i] end; return shifted
end
function M.bootstrap(settlement,pillars)
    local curve={days={},rates={}}
    for _,pillar in ipairs(pillars) do
        local boundaries=schedule.build(settlement,pillar.maturity,pillar.frequency,false,false); local flows={}
        for i=2,#boundaries do
            local n,m=daycount.fraction("30/360",boundaries[i-1],boundaries[i])
            local flow=pillar.coupon*n/(10000*m); if i == #boundaries then flow=flow+1 end
            flows[#flows+1]={boundaries[i]-settlement,flow}
        end
        curve.days[#curve.days+1]=pillar.maturity-settlement; curve.rates[#curve.rates+1]=0.0
        local index=#curve.rates
        curve.rates[index]=pricing.bisect(function(rate) curve.rates[index]=rate; return M.pv(curve,flows,0.0) end,0.0,1.0,1.0)
    end
    return curve
end
function M.spread(curve,flows,target) return pricing.bisect(function(spread) return M.pv(curve,flows,spread) end,-0.5,0.5,target) end
return M
