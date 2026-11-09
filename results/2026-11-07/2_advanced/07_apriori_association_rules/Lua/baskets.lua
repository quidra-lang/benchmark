local M = {}
function M.lines(name)
 local file=assert(io.open("input/"..name));local lines={};for line in file:lines() do lines[#lines+1]=line end;file:close();return lines
end
function M.records(name)
 local lines=M.lines(name);local rows={}
 for j=2,#lines do local row={};for field in lines[j]:gmatch("[^,]+") do row[#row+1]=field end;rows[#rows+1]=row end
 return rows
end
function M.items(b,taxonomy,extended)
 local found={};for i in pairs(b.counts) do found[i]=true;if extended then found[taxonomy[i]]=true end end
 local ids={};for i in pairs(found) do ids[#ids+1]=i end;table.sort(ids);return ids
end
function M.contains(items,set) for _,i in ipairs(set) do if not items[i] then return false end end;return true end
function M.sets(baskets,taxonomy,extended)
 local sets={};for _,b in ipairs(baskets) do local set={};for _,i in ipairs(M.items(b,taxonomy,extended)) do set[i]=true end;sets[#sets+1]=set end;return sets
end
function M.key(set) return table.concat(set,",") end
function M.compare(a,b)
 for j=1,math.min(#a,#b) do if a[j]~=b[j] then return a[j]<b[j] and -1 or 1 end end
 return #a==#b and 0 or #a<#b and -1 or 1
end
function M.subset(a,b)
 local j=1;for _,i in ipairs(b) do if a[j]==i then j=j+1 end end;return j>#a
end
function M.union(a,b)
 local found={};for _,i in ipairs(a) do found[i]=true end;for _,i in ipairs(b) do found[i]=true end
 local out={};for i in pairs(found) do out[#out+1]=i end;table.sort(out);return out
end
function M.selected(set,mask)
 local out={};for j,i in ipairs(set) do if (mask & (1 << (j-1)))~=0 then out[#out+1]=i end end;return out
end
local Support={};Support.__index=Support
function M.support(sets) return setmetatable({sets=sets,cache={[""]=#sets}},Support) end
function Support:count(set)
 local key=M.key(set);local count=self.cache[key];if count~=nil then return count end
 count=0;for _,b in ipairs(self.sets) do if M.contains(b,set) then count=count+1 end end;self.cache[key]=count;return count
end
return M
