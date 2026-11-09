new_grid(rows,columns) = fill(" ",rows,columns)
function framed(grid)
    border = "+"*repeat("-",size(grid,2))*"+"
    vcat([border],["|"*join(grid[i,:])*"|" for i in axes(grid,1)],[border])
end
grid_index(fraction,n) = min(floor(Int,fraction*n),n-1)
rounded_position(fraction,n) = floor(Int,fraction*n+0.5)
biplot_cell(x,y,x_limit,y_limit,width,height) = (
    grid_index((y_limit-y)/(2y_limit),height),
    grid_index((x+x_limit)/(2x_limit),width)
)
circle_cell(a,b,radius) = (radius÷2+1-rounded_position(b,radius/2),radius+1+rounded_position(a,radius))
diagnostic_cell(t2,spe,x,y,width,height) = (height-1-grid_index(spe/y,height),grid_index(t2/x,width))
function shaft_cells(origin,tip)
    dr,dc = tip[1]-origin[1],tip[2]-origin[2]
    steps = max(abs(dc),abs(dr))
    [(origin[1]+sign(dr)*fld(2s*abs(dr)+steps,2steps),
      origin[2]+sign(dc)*fld(2s*abs(dc)+steps,2steps)) for s in 1:steps-1]
end
function shaft_character(origin,tip)
    dr,dc = tip[1]-origin[1],tip[2]-origin[2]
    2abs(dr)<=abs(dc) ? "-" : 2abs(dc)<=abs(dr) ? "|" : dc*dr<0 ? "/" : "\\"
end
scree_line(
    n,
    kaiser,
    broken,
    width
) = "|"*join(p==broken ? "o" : p==kaiser ? ":" : p<=n ? "#" : " " for p in 1:width)*"|"
