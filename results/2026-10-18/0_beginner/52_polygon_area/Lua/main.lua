local polygons = {{{0,0},{5,0},{6,4},{1,3}},{{2,1},{0,4},{3,7},{7,6},{8,2}},{{0,0},{8,0},{8,6},{5,6},{4,3},{3,6},{0,6}}}
for number,vertices in ipairs(polygons) do
    local twice_area,perimeter = 0,0.0
    for i,point in ipairs(vertices) do
        local following = vertices[i%#vertices+1]
        twice_area = twice_area + point[1]*following[2]-following[1]*point[2]
        local dx,dy = point[1]-following[1],point[2]-following[2]
        perimeter = perimeter + math.sqrt(dx*dx+dy*dy)
    end
    io.write(string.format("polygon %d: area=%.1f perimeter=%.3f\n",number,math.abs(twice_area)/2,perimeter))
end
