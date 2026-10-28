function loss_interval(relative,velocity,t1,t2,dh,dv)
    px,py,pz = relative
    wx,wy,wz = velocity
    qa,qb,qc = wx*wx+wy*wy,2*(px*wx+py*wy),(px*px+py*py)-dh*dh
    lo,hi = Float64(t1),Float64(t2)
    if qa<1e-12
        qc>=0 && return nothing
    else
        discriminant = qb*qb-4*qa*qc
        discriminant<=0 && return nothing
        root = sqrt(discriminant)
        lo,hi = max(lo,t1+(-qb-root)/(2*qa)),min(hi,t1+(-qb+root)/(2*qa))
    end
    if wz==0
        abs(pz)>=dv && return nothing
    else
        r1,r2 = (-dv-pz)/wz,(dv-pz)/wz
        lo,hi = max(lo,t1+min(r1,r2)),min(hi,t1+max(r1,r2))
    end
    hi-lo<=1e-6 && return nothing
    tc = qa>=1e-12 ? t1+(-qb/(2*qa)) : Float64(t1)
    tc = min(max(tc,lo),hi)
    tau = tc-t1
    ex,ey = px+wx*tau,py+wy*tau
    (lo=lo,hi=hi,tc=tc,distance=sqrt(ex*ex+ey*ey),vertical=abs(pz+wz*tau))
end
function pair_conflicts(a,ta,b,tb,dh,dv)
    pieces = NamedTuple[]
    for sa in ta.segments,sb in tb.segments
        t1,t2 = max(sa.ts,sb.ts),min(sa.te,sb.te)
        t1>=t2 && continue
        pa,pb = segment_position(sa,t1),segment_position(sb,t1)
        relative,velocity = ntuple(i->pa[i]-pb[i],3),ntuple(i->sa.velocity[i]-sb.velocity[i],3)
        interval = loss_interval(relative,velocity,t1,t2,dh,dv)
        !isnothing(interval) && push!(pieces,(;interval...,a_segment=sa,b_segment=sb))
    end
    sort!(pieces;by=p->p.lo,alg=MergeSort)
    conflicts = NamedTuple[]
    for piece in pieces
        if isempty(conflicts) || piece.lo-conflicts[end].finish>1e-6
            push!(conflicts,(pair=(a,b),start=piece.lo,finish=piece.hi,pieces=[piece],closest=piece))
        else
            previous = conflicts[end]
            closest = piece.distance<previous.closest.distance-1e-9 ? piece : previous.closest
            conflicts[end] = (;previous...,finish=piece.hi,pieces=[previous.pieces;[piece]],closest=closest)
        end
    end
    conflicts
end
function all_conflicts(trajectories,dh,dv)
    conflicts = NamedTuple[]
    for a in eachindex(trajectories),b in a+1:length(trajectories)
        append!(conflicts,pair_conflicts(a,trajectories[a],b,trajectories[b],dh,dv))
    end
    sort!(conflicts;by=c->(c.start,c.pair...))
end
