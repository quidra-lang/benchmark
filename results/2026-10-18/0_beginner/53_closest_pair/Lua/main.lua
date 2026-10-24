local points = {{12,-7},{-33,25},{41,18},{-8,-44},{27,39},{-46,-12},{5,14},{36,-29},{-19,47},{-2,3}}
local nearest,farthest = {0,0,math.huge},{0,0,-1}
for i = 1,#points-1 do
    for j = i+1,#points do
        local dx,dy = points[i][1]-points[j][1],points[i][2]-points[j][2]
        local squared = dx*dx+dy*dy
        if squared < nearest[3] then nearest = {i-1,j-1,squared} end
        if squared > farthest[3] then farthest = {i-1,j-1,squared} end
    end
end
for index,pair in ipairs({nearest,farthest}) do
    local distance = math.sqrt(pair[3])
    io.write(string.format("%s: P%d P%d %.4f\n",index == 1 and "closest" or "farthest",pair[1],pair[2],distance))
end
