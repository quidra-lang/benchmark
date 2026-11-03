cell_center =: 3 : '100*y'
grid_inside =: 3 : '(0<:0{y)*.(Width>0{y)*.(0<:1{y)*.Height>1{y'
grid_index =: 3 : '(0{y)+Width*1{y'
cell_of_index =: 3 : '(Width|y),y div Width'
grid_terrain =: 3 : '(grid_index y){,Grid'
grid_rock =: 3 : '''#''=grid_terrain y'
grid_water =: 3 : '''~''=grid_terrain y'
grid_buildable =: 3 : '''.''=grid_terrain y'
read_map =: 3 : 0
    lines =. read_lines 'map.txt'
    'Width Height' =: num&>' 'split 0{::lines
    Grid =: >(1+i.Height){lines
    Exit =: cell_of_index (,'E'=Grid)i.1
    Spawns =: 0 2$0
    for_number. '123456789' do.
        found =. I.number=,Grid
        if. #found do. Spawns =: Spawns,cell_of_index {.found end.
    end.
    i.0
)
