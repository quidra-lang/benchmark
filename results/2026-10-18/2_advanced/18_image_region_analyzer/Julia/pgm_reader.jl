struct Image
    name::String
    width::Int
    height::Int
    maxval::Int
    pixels::Matrix{Int}
end

function read_images(path)
    words = String[]
    for line in readlines(path)
        append!(words, String.(split(first(split(line, '#'; limit=2, keepempty=true)))))
    end
    images = Image[]
    position = 1
    while position <= length(words)
        name = words[position + 1]
        width, height, maxval = parse.(Int, words[position + 3:position + 5])
        position += 6
        values = parse.(Int, words[position:position + width * height - 1])
        pixels = permutedims(reshape(values, width, height))
        position += width * height
        push!(images, Image(name, width, height, maxval, pixels))
    end
    images
end
