local M={}
function M.image(image,width,height)
    local file=assert(io.open('output/image.ppm','w')); file:write('P3\n',width,' ',height,'\n255\n')
    for y=0,height-1 do local parts={}; for x=0,width-1 do local p=image[y*width+x+1]; parts[#parts+1]=table.concat(p,' ') end; file:write(table.concat(parts,' '),'\n') end
    file:close()
end
function M.preview(image,width,height)
    local file=assert(io.open('output/preview.txt','w')); local ramp='@%#*+=-:,.'
    for y=0,height-1,4 do local parts={}; for x=0,width-1,2 do local total=0; for j=0,3 do for i=0,1 do local p=image[(y+j)*width+x+i+1]; total=total+299*p[1]+587*p[2]+114*p[3] end end; local index=(total//8000)*10//256; parts[#parts+1]=ramp:sub(index+1,index+1) end; file:write(table.concat(parts),'\n') end
    file:close()
end
return M
