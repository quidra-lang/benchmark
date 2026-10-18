coefficients <- list(c(1L,-3L,-10L),c(-2L,5L,4L),c(3L,1L,-2L),c(4L,-12L,9L),c(1L,2L,5L),c(-2L,3L,-4L))
for (coefficient in coefficients) {
    a <- coefficient[1]
    b <- coefficient[2]
    c_value <- coefficient[3]
    discriminant <- b*b-4L*a*c_value
    cat(sprintf("%d %d %d: ",a,b,c_value))
    if (discriminant > 0) {
        first <- (-b+sqrt(discriminant))/(2*a)
        second <- (-b-sqrt(discriminant))/(2*a)
        cat(sprintf("x1 = %.4f, x2 = %.4f\n",max(first,second),min(first,second)))
    } else if (discriminant == 0) {
        cat(sprintf("x = %.4f\n",-b/(2*a)))
    } else {
        real <- -b/(2*a)
        imaginary <- sqrt(-discriminant)/(2*abs(a))
        cat(sprintf("x = %.4f + %.4fi, %.4f - %.4fi\n",real,imaginary,real,imaginary))
    }
}
