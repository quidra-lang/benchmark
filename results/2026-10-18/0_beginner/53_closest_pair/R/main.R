points <- matrix(as.integer(c(12,-7,-33,25,41,18,-8,-44,27,39,-46,-12,5,14,36,-29,-19,47,-2,3)),ncol=2,byrow=TRUE)
nearest <- c(0,0,Inf)
farthest <- c(0,0,-1)
for (i in 1:(nrow(points)-1)) {
    for (j in (i+1):nrow(points)) {
        dx <- points[i,1]-points[j,1]
        dy <- points[i,2]-points[j,2]
        squared <- dx*dx+dy*dy
        if (squared < nearest[3]) nearest <- c(i-1,j-1,squared)
        if (squared > farthest[3]) farthest <- c(i-1,j-1,squared)
    }
}
for (label in c("closest","farthest")) {
    pair <- if (label == "closest") nearest else farthest
    distance <- sqrt(pair[3])
    cat(sprintf("%s: P%d P%d %.4f\n",label,pair[1],pair[2],distance))
}
