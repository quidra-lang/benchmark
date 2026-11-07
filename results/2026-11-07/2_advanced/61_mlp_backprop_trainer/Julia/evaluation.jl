using Printf
function real_text(value,places)
    isnothing(value) && return "-"
    result = Printf.format(Printf.Format("%.$(places)f"),value)
    startswith(result,"-") && parse(Float64,result)==0 ? result[2:end] : result
end
function ratio(numerator,denominator)
    denominator==0 && return "-"
    rounded = (20000numerator+denominator)÷(2denominator)
    "$(rounded÷10000).$(lpad(rounded%10000,4,'0'))"
end
best_two(scores) = sort(collect(eachindex(scores));by=i->(-scores[i],i))[1:2].-1
function confusion(outcomes,classes)
    table = zeros(Int,classes,classes)
    for outcome in outcomes
        table[outcome.label+1,outcome.predicted+1] += 1
    end
    table
end
function class_measures(table,klass)
    support,predicted = sum(table[klass+1,:]),sum(table[:,klass+1])
    true_count = table[klass+1,klass+1]
    (
        support=support,
        predicted=predicted,
        precision=ratio(true_count,predicted),
        recall=ratio(true_count,support),
        f1=ratio(2true_count,support+predicted)
    )
end
level_maps(levels,width,height) = [join(
    (join(level[r*width+1:(r+1)*width]) for level in levels),
    " "
) for r in 0:height-1]
ascii_image(
    pixels,
    width
) = [join(char=='1' ? '#' : '.' for char in pixels[i:i+width-1]) for i in 1:width:length(pixels)]
function binary_frequency(images,label,pixels)
    chosen = [image for image in images if image.label==label]
    isempty(chosen) && return zeros(Int,pixels)
    [min(9,10count(image->image.pixels[i]=='1',chosen)÷length(chosen)) for i in 1:pixels]
end
