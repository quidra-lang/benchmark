const REGION_ORDER = ("nonocc","all","disc")
function truth_regions(truth,width,height)
    known = findall(!=(0),truth)
    occluded = Int[]
    for p in known
        y,x = divrem(p-1,width)
        g = truth[p]
        target = x-g
        if target<0 || any(truth[y*width+x2+1]>g && x2-truth[y*width+x2+1]==target for x2 in 0:width-1)
            push!(occluded,p)
        end
    end
    visible = setdiff(known,occluded)
    disc = Int[]
    for p in visible
        y,x = divrem(p-1,width)
        if any(truth[yy*width+xx+1]!=0 && abs(truth[yy*width+xx+1]-truth[p])>=2 for yy in max(0,y-1):min(
            height-1,
            y+1
        ) for xx in max(0,x-1):min(width-1,x+1))
            push!(disc,p)
        end
    end
    Dict("all"=>known,"nonocc"=>visible,"disc"=>disc,"occluded"=>occluded)
end
function evaluate(image,truth,region)
    errors = [abs(image[p]-truth[p]) for p in region if image[p]!=0]
    valid = length(errors)
    missing = length(region)-valid
    total = sum(errors)
    (
        pixels=length(region),
        valid=valid,
        bad1=missing+count(>(1),errors),
        bad2=missing+count(>(2),errors),
        error_sum=total,
        mae=valid==0 ? "-" : two_decimals(total,valid),
        exact=count(==(0),errors)
    )
end
function ratio(a,b)
    b==0 && return "0/1 0.00"
    divisor = gcd(a,b)
    "$(a÷divisor)/$(b÷divisor) "*two_decimals(100a,b)
end
