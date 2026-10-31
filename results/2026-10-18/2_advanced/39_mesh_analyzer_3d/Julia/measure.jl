using Printf
const WINDING_PI = 3.141592653589793
subtract(a,b) = (a[1]-b[1],a[2]-b[2],a[3]-b[3])
cross(a,b) = (a[2]*b[3]-a[3]*b[2],a[3]*b[1]-a[1]*b[3],a[1]*b[2]-a[2]*b[1])
dot(a,b) = a[1]*b[1]+a[2]*b[2]+a[3]*b[3]
function normal(face,points)
    a,b,c = (points[i] for i in face.vertices)
    cross(subtract(b,a),subtract(c,a))
end
function determinant(face,points)
    a,b,c = (points[i] for i in face.vertices)
    dot(a,cross(b,c))
end
function area(faces,points)
    total = 0.0
    for face in faces
        n = normal(face,points)
        total += sqrt(Float64(dot(n,n)))
    end
    total/2
end
function triangle_angle(face,points)
    a,b,c = (points[i] for i in face.vertices)
    smallest = min(
        dot(subtract(b,a),subtract(c,a)),
        dot(subtract(c,b),subtract(a,b)),
        dot(subtract(a,c),subtract(b,c))
    )
    smallest < 0 ? "obtuse" : smallest == 0 ? "right" : "acute"
end
edge_length_squared(edge,points) = (difference=subtract(
    points[edge[1]],
    points[edge[2]]
);dot(difference,difference))
function winding_number(face_indices,faces,points,sample)
    total = 0.0
    for index in face_indices
        a,b,c = (subtract(points[v],sample) for v in faces[index].vertices)
        la,lb,lc = sqrt(Float64(dot(a,a))),sqrt(Float64(dot(b,b))),sqrt(Float64(dot(c,c)))
        numerator = dot(a,cross(b,c))
        denominator = la*lb*lc+dot(a,b)*lc+dot(b,c)*la+dot(c,a)*lb
        total += 2*atan(numerator,denominator)
    end
    round(Int,total/(4*WINDING_PI))
end
volume6(face_indices,faces,points) = sum(determinant(faces[i],points) for i in face_indices;init=0)
function centroid(face_indices,faces,points,six_volume)
    ntuple(3) do axis
        numerator = 0
        for index in face_indices
            face = faces[index]
            signed = determinant(face,points)
            numerator += signed*sum(points[v][axis] for v in face.vertices)
        end
        numerator//(4*six_volume)
    end
end
function format_fraction(value)
    denominator(value) == 1 ? string(numerator(value)) : "$(numerator(value))/$(denominator(value))"
end
format_fraction(n,d) = format_fraction(n//d)
format_real(value) = @sprintf("%.3f",value == 0 ? 0.0 : value)
bbox(vertices,points) = Tuple(vcat(
    [minimum(points[v][axis] for v in vertices) for axis in 1:3],
    [maximum(points[v][axis] for v in vertices) for axis in 1:3]
))
