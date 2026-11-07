function ordered_sum(values)
    total = 0.0
    for value in values
        total += value
    end
    total
end
determinant(cov) = cov[1]*cov[3]-cov[2]*cov[2]
function mahalanobis(point,mean,cov)
    dx,dy = point[1]-mean[1],point[2]-mean[2]
    a,b,c = cov
    (c*dx*dx-2b*dx*dy+a*dy*dy)/determinant(cov)
end
weighted_log_density(
    point,
    weight,
    mean,
    cov
) = log(weight)-log(2pi)-log(determinant(cov))/2-mahalanobis(point,mean,cov)/2
function eigen_data(cov)
    a,b,c = cov
    h = (a+c)/2
    g = sqrt(((a-c)/2)*((a-c)/2)+b*b)
    leading,trailing = h+g,h-g
    if b==0
        direction = a>=c ? (1.0,0.0) : (0.0,1.0)
    else
        vx,vy = a>=c ? (leading-c,b) : (b,leading-a)
        length = sqrt(vx*vx+vy*vy)
        direction = vx<0 ? (-vx/length,-vy/length) : (vx/length,vy/length)
    end
    (leading=leading,trailing=trailing,direction=direction,angle=atan(direction[2],direction[1])*180/pi,
        axes=(sqrt(leading),sqrt(trailing)),area=pi*sqrt(leading*trailing),correlation=b/sqrt(a*c))
end
function bhattacharyya(mean_a,cov_a,mean_b,cov_b)
    average = ntuple(i->(cov_a[i]+cov_b[i])/2,3)
    distance = mahalanobis(
        mean_b,
        mean_a,
        average
    )/8+log(determinant(average)/sqrt(determinant(cov_a)*determinant(cov_b)))/2
    distance,exp(-distance)
end
