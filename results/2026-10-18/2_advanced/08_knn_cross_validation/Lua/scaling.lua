local M = {}
function M.compute(rows,method)
 local s={centers={},scales={}}
 for j=1,#rows[1].values do
  if method=="standard" then local total=0.0;for _,r in ipairs(rows) do total=total+r.values[j] end;local center=total/#rows;s.centers[j]=center;s.scales[j]=0.0;if #rows>1 then local squares=0.0;for _,r in ipairs(rows) do local d=r.values[j]-center;squares=squares+d*d end;s.scales[j]=math.sqrt(squares/(#rows-1)) end
  else local low,high=rows[1].values[j],rows[1].values[j];for _,r in ipairs(rows) do low=math.min(low,r.values[j]);high=math.max(high,r.values[j]) end;s.centers[j]=low;s.scales[j]=high-low end
 end;return s
end
function M.transform(s,row,features)
 local out={};for _,i in ipairs(features) do out[#out+1]=s.scales[i]>0 and (row.values[i]-s.centers[i])/s.scales[i] or 0.0 end;return out
end
return M
