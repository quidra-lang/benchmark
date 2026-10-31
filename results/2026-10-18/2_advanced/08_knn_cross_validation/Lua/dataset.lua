local M = {}
local function lines(name) local file=assert(io.open("input/"..name));local out={};for line in file:lines() do out[#out+1]=line end;file:close();return out end
local function csv(line) local fields={};for field in (line..","):gmatch("(.-),") do fields[#fields+1]=field end;return fields end
local function rows(name,offset)
 local data=lines(name);local header=csv(data[1]);local features={};for j=2,#header-2 do features[#features+1]=header[j] end;local out={}
 for j=2,#data do local f=csv(data[j]);local r={id=f[1],label=f[#f-1],values={},target=0,has_target=f[#f]~="",index=offset+#out+1};for k=2,#f-2 do r.values[#r.values+1]=assert(tonumber(f[k])) end;if r.has_target then r.target=assert(tonumber(f[#f])) end;out[#out+1]=r end;return features,out
end
function M.read()
 local features,train=rows("train.csv",0);local _,test=rows("test.csv",#train);local s={}
 for _,line in ipairs(lines("params.txt")) do local fields={};for word in line:gmatch("%S+") do fields[#fields+1]=word end;local key=table.remove(fields,1);if key=="FOLDS" or key=="EDIT_K" or key=="TOP" then s[key]=tonumber(fields[1]) elseif key=="K_VALUES" or key=="CURVE" or key=="BINS" then s[key]={};for _,word in ipairs(fields) do s[key][#s[key]+1]=tonumber(word) end else s[key]=fields end end
 local found,labels={},{};for _,r in ipairs(train) do found[r.label]=true end;for label in pairs(found) do labels[#labels+1]=label end;table.sort(labels)
 return {features=features,labels=labels,train=train,test=test,settings=s}
end
return M
