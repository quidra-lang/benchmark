read_grid_agents =: 3 : 0
    lines =. read_lines 'input/map.txt'
    'GridWidth GridHeight' =: parse_integer 0{::lines
    GridRows =: }.lines
    GridCells =: ;GridRows
    NumberCells =: #GridCells
    FreeCells =: I.GridCells='.'
    IsFree =: GridCells='.'
    Destinations =: NumberCells$<i.0
    Degrees =: NumberCells$0
    for_cell. FreeCells do.
        xx =. GridWidth|cell
        yy =. cell intdiv GridWidth
        adjacent =. ,cell
        for_delta. 4 2$_1 0 0 1 1 0 0 _1 do.
            'dy dx' =. delta
            nx =. xx+dx
            ny =. yy+dy
            if. (nx>:0)*.(nx<GridWidth)*.(ny>:0)*.ny<GridHeight do.
                next =. nx+GridWidth*ny
                if. next{IsFree do.
                    adjacent =. adjacent,next
                end.
            end.
        end.
        Destinations =: (<adjacent)cell}Destinations
        Degrees =: ((#adjacent)-1)cell}Degrees
    end.
    Starts =: i.0
    Goals =: i.0
    for_line. }.read_lines 'input/agents.csv' do.
        values =. parse_integer ' 'join <;._1 ',',>line
        'id sx sy gx gy' =. values
        Starts =: Starts,sx+GridWidth*sy
        Goals =: Goals,gx+GridWidth*gy
    end.
    NumberAgents =: #Starts
    AgentNames =: (65+i.NumberAgents){a.
    Distances =: (NumberAgents,NumberCells)$_1
    for_agent. i.NumberAgents do.
        distance =. distance_table agent{Goals
        Distances =: distance agent}Distances
    end.
)
map_neighbors =: 3 : '}.y{::Destinations'
distance_table =: 3 : 0
    distance =. NumberCells$_1
    distance =. 0 y}distance
    queue =. ,y
    front =. 0
    while. front<#queue do.
        cell =. front{queue
        front =. front+1
        for_neighbor. map_neighbors cell do.
            if. _1=neighbor{distance do.
                distance =. (1+cell{distance)neighbor}distance
                queue =. queue,neighbor
            end.
        end.
    end.
    distance
)
