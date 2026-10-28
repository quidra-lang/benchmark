orient(p,q,r) = (q[1]-p[1])*(r[2]-p[2])-(q[2]-p[2])*(r[1]-p[1])
d2(p,q) = (p[1]-q[1])^2+(p[2]-q[2])^2
dot_at(o,p,q) = (p[1]-o[1])*(q[1]-o[1])+(p[2]-o[2])*(q[2]-o[2])
function incircle(a,b,c,d)
    ax,ay = a[1]-d[1],a[2]-d[2]
    bx,by = b[1]-d[1],b[2]-d[2]
    cx,cy = c[1]-d[1],c[2]-d[2]
    aa,bb,cc = ax*ax+ay*ay,bx*bx+by*by,cx*cx+cy*cy
    ax*(by*cc-bb*cy)-ay*(bx*cc-bb*cx)+aa*(bx*cy-by*cx)
end
function circumcenter(a,b,c)
    bx,by = b[1]-a[1],b[2]-a[2]
    cx,cy = c[1]-a[1],c[2]-a[2]
    bb,cc = bx*bx+by*by,cx*cx+cy*cy
    denominator = 2*(bx*cy-by*cx)
    (a[1]*denominator+cy*bb-by*cc,a[2]*denominator+bx*cc-cx*bb,denominator)
end
function fraction(n,d)
    common = gcd(n,d)
    n,d = n÷common,d÷common
    d==1 ? string(n) : "$n/$d"
end
function reduce_direction(dx,dy)
    common = gcd(abs(dx),abs(dy))
    (dx÷common,dy÷common)
end
