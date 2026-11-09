function walk_boxes(box,x,y,level=0,role="")
    result = Any[(box=box,x=x,y=y,level=level,role=role)]
    for (child,dx,dy,child_role) in box.children
        append!(result,walk_boxes(child,x+dx,y+dy,level+1,child_role))
    end
    result
end
function draw_boxes(roots,width,height)
    grid = fill(' ',height,width)
    for (root,root_x,root_y) in roots
        for entry in walk_boxes(root,root_x,root_y)
            for (text,dx,dy) in entry.box.strings
                for (i,c) in enumerate(text)
                    c != ' ' && (grid[entry.y+dy+1,entry.x+dx+i] = c)
                end
            end
        end
    end
    [rstrip(c -> c == ' ',String(grid[row,:])) for row in 1:height]
end
function box_lines(roots)
    result = Any[]
    for (root,x,y) in roots, entry in walk_boxes(root,x,y)
        box = entry.box
        text = repeat("  ",entry.level) * entry.role * box.description *
            " x=$(entry.x) y=$(entry.y) w=$(box.width) h=$(box.height) b=$(box.baseline)"
        push!(result,(text=text,level=entry.level,kind=String(split(box.description,' ')[1])))
    end
    result
end
