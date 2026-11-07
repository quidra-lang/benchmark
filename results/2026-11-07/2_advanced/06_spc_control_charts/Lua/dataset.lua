local M = {}
M.charts = {"XBAR_R","R","XBAR_S","S","I","MR","CUSUM","EWMA","MA"}
M.families = {"XBAR_R","XBAR_S","I_MR"}
M.attributes = {"p","np","c","u"}
M.constants = {
 {a2=1.880,a3=2.659,b3=0,b4=3.267,d3=0,d4=3.267,d2=1.128,c4=0.7979},
 {a2=1.023,a3=1.954,b3=0,b4=2.568,d3=0,d4=2.574,d2=1.693,c4=0.8862},
 {a2=0.729,a3=1.628,b3=0,b4=2.266,d3=0,d4=2.282,d2=2.059,c4=0.9213},
 {a2=0.577,a3=1.427,b3=0,b4=2.089,d3=0,d4=2.114,d2=2.326,c4=0.9400},
 {a2=0.483,a3=1.287,b3=0.030,b4=1.970,d3=0,d4=2.004,d2=2.534,c4=0.9515},
 {a2=0.419,a3=1.182,b3=0.118,b4=1.882,d3=0.076,d4=1.924,d2=2.704,c4=0.9594},
 {a2=0.373,a3=1.099,b3=0.185,b4=1.815,d3=0.136,d4=1.864,d2=2.847,c4=0.9650},
 {a2=0.337,a3=1.032,b3=0.239,b4=1.761,d3=0.184,d4=1.816,d2=2.970,c4=0.9693},
 {a2=0.308,a3=0.975,b3=0.284,b4=1.716,d3=0.223,d4=1.777,d2=3.078,c4=0.9727}
}
local function csv(name)
 local file=assert(io.open("input/"..name)); local rows={}; file:read("l")
 for line in file:lines() do local row={}; for token in line:gmatch("[^,]+") do row[#row+1]=assert(tonumber(token)) end; rows[#rows+1]=row end
 file:close(); return rows
end
function M.read()
 local settings={rules={}}
 local file=assert(io.open("input/spec.txt"))
 for line in file:lines() do
  local fields={}; for token in line:gmatch("%S+") do fields[#fields+1]=token end
  if fields[1]=="rules" then local rules={}; for j=3,#fields do rules[#rules+1]=tonumber(fields[j]) end; settings.rules[fields[2]]=rules
  else settings[fields[1]]=tonumber(fields[2]) or fields[2] end
 end
 file:close(); local values,lots={},{}
 for _,row in ipairs(csv("measurements.csv")) do values[#values+1]=row[3] end
 for _,row in ipairs(csv("attributes.csv")) do lots[#lots+1]={number=row[1],inspected=row[2],defectives=row[3],defects=row[4]} end
 return settings,values,lots
end
return M
