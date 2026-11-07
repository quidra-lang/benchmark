local M = {}
function M.rdiv(a,b) return (2*a+b)//(2*b) end
function M.sat(v,counter) local limited=math.max(-32768,math.min(32767,v));if limited~=v and counter then counter.count=counter.count+1 end;return limited end
function M.peak(x) local p=0;for _,v in ipairs(x) do p=math.max(p,math.abs(v)) end;return p end
function M.sum(x) local total=0;for _,v in ipairs(x) do total=total+v end;return total end
function M.read()
 local file=assert(io.open("input/signals.txt"));local text=file:read("a");file:close();local tokens={};for token in text:gmatch("%S+") do tokens[#tokens+1]=token end
 local signals={};local index=1;while index<=#tokens do local s={name=tokens[index+1],rate=tonumber(tokens[index+2]),samples={},origin="input",ingredients={}};local count=tonumber(tokens[index+3]);for j=1,count do s.samples[j]=tonumber(tokens[index+3+j]) end;signals[#signals+1]=s;index=index+4+count end;return signals
end
function M.lines(s)
 local lines={string.format("SIGNAL %s %d %d",s.name,s.rate,#s.samples)}
 for first=1,#s.samples,16 do local values={};for j=first,math.min(first+15,#s.samples) do values[#values+1]=s.samples[j] end;lines[#lines+1]=table.concat(values," ") end;return lines
end
function M.test(command,count,pos,amp,seed)
 local x={};local state=seed;for n=0,count-1 do local value=0;if command=="IMPULSE" then value=n==pos and amp or 0 elseif command=="STEP" then value=n>=pos and amp or 0 else state=(48271*state)%2147483647;value=state%65536-32768 end;x[n+1]=value end;return x
end
return M
