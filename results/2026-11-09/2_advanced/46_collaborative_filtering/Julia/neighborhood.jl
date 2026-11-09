function largest_neighbors(candidates,n)
    sorted = sort(candidates;by=c->(-c[2],c[1]))
    sorted[1:min(n,length(sorted))]
end
function build_neighborhood(data,shrinkage)
    nu,ni = length(data.users),length(data.items)
    user,item = fill(NaN,nu,nu),fill(NaN,ni,ni)
    user_common = zeros(Int,nu,nu)
    counts,differences = zeros(Int,ni,ni),zeros(Int,ni,ni)
    for u in 1:nu-1,v in u+1:nu
        common = [i for i in data.by_user[u] if data.ratings[v,i]>0]
        n = length(common)
        n<2 && continue
        sx = sy = sxx = syy = sxy = 0
        for i in common
            x,y = data.ratings[u,i],data.ratings[v,i]
            sx += x
            sy += y
            sxx += x*x
            syy += y*y
            sxy += x*y
        end
        num,dx,dy = n*sxy-sx*sy,n*sxx-sx*sx,n*syy-sy*sy
        (dx==0 || dy==0) && continue
        a = (num*n)*(num*n)
        b = dx*dy*(n+shrinkage)*(n+shrinkage)
        user[u,v] = user[v,u] = sign(num)*sqrt(a/b)
        user_common[u,v] = user_common[v,u] = n
    end
    for i in 1:ni-1,j in i+1:ni
        common = [u for u in data.by_item[i] if data.ratings[u,j]>0]
        n = length(common)
        n==0 && continue
        counts[i,j] = counts[j,i] = n
        difference = sum(data.ratings[u,i]-data.ratings[u,j] for u in common)
        differences[i,j],differences[j,i] = difference,-difference
        n<2 && continue
        numerator = left = right = 0.0
        for u in common
            x,y = data.ratings[u,i]-data.user_means[u],data.ratings[u,j]-data.user_means[u]
            numerator += x*y
            left += x*x
            right += y*y
        end
        (left==0 || right==0) && continue
        item[i,j] = item[j,i] = numerator/sqrt(left*right)*n/(n+shrinkage)
    end
    (user=user,item=item,user_common=user_common,counts=counts,differences=differences,shrinkage=shrinkage)
end
deviation(
    neighborhood,
    target,
    source
) = neighborhood.differences[target,source]/(neighborhood.counts[target,source]+neighborhood.shrinkage)
