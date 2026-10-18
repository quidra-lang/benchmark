using Printf
function main()
    polygons = [[(0,0),(5,0),(6,4),(1,3)],[(2,1),(0,4),(3,7),(7,6),(8,2)],[(0,0),(8,0),(8,6),(5,6),(4,3),(3,6),(0,6)]]
    for (number,vertices) in enumerate(polygons)
        twice_area, perimeter = 0, 0.0
        for i in eachindex(vertices)
            x,y = vertices[i]
            next_x,next_y = vertices[mod1(i+1,length(vertices))]
            twice_area += x*next_y-next_x*y
            dx,dy = x-next_x,y-next_y
            perimeter += sqrt(Float64(dx*dx+dy*dy))
        end
        @printf("polygon %d: area=%.1f perimeter=%.3f\n",number,abs(twice_area)/2,perimeter)
    end
end
main()
