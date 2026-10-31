function read_dataset()
    read_csv(path) = [parse.(Int,split(line,',')) for line in readlines(path)[2:end]]
    points,rectangles = read_csv("input/points.csv"),read_csv("input/rects.csv")
    rows = [split(line,' ') for line in readlines("input/params.txt")]
    parameters = (
        world=parse(Int,rows[1][2]),
        bucket=parse(Int,rows[2][2]),
        maximum=parse(Int,rows[3][2]),
        minimum=parse(Int,rows[3][3]),
        cell_size=parse(Int,rows[4][2])
    )
    commands = [(
        name=String(words[1]),
        values=parse.(Int,words[2:end])
    ) for words in (split(line,' ') for line in readlines("input/queries.txt"))]
    points,rectangles,parameters,commands
end
