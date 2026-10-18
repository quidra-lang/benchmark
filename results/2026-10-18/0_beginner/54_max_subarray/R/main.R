arrays <- list(c(3,-5,8,-2,6,-9,4,1,-7,5,-3,2),c(-4,7,-1,3,-8,10,-2,5,-6,-2,9,-12,4,-1),c(-6,-3,5,-1,-4,3,-9,2,3,-1,4,-5,1,6,-2))
for (numbers in arrays) {
    current <- numbers[1]; best <- current; start <- 1; best_start <- 1; best_end <- 1
    for (i in 2:length(numbers)) {
        if (numbers[i] > current+numbers[i]) { current <- numbers[i]; start <- i
        } else { current <- current+numbers[i] }
        if (current > best) { best <- current; best_start <- start; best_end <- i }
    }
    cat(sprintf("max sum %d at [%d, %d]\n",best,best_start-1,best_end-1))
}
