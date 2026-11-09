module FeatureScaling
export Scaling, computescaling, transform
struct Scaling
    centers::Vector{Float64}
    scales::Vector{Float64}
end
function computescaling(rows,method)
    centers,scales = Float64[],Float64[]
    for j in eachindex(rows[1].values)
        if method == :standard
            total = 0.0
            for row in rows
                total += row.values[j]
            end
            center = total/length(rows)
            squares = 0.0
            for row in rows
                delta = row.values[j]-center
                squares += delta*delta
            end
            scale = length(rows) == 1 ? 0.0 : sqrt(squares/(length(rows)-1))
        else
            center = rows[1].values[j]
            high = center
            for row in rows
                center = min(center,row.values[j])
                high = max(high,row.values[j])
            end
            scale = high-center
        end
        push!(centers,center)
        push!(scales,scale)
    end
    Scaling(centers,scales)
end
transform(s::Scaling,values,features) = [s.scales[j] > 0 ? (values[j]-s.centers[j])/s.scales[j] : 0.0 for j in features]
end
