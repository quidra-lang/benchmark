using Printf
function main()
    for (a,b,c) in [(1,-3,-10),(-2,5,4),(3,1,-2),(4,-12,9),(1,2,5),(-2,3,-4)]
        discriminant = b*b - 4*a*c
        @printf("%d %d %d: ",a,b,c)
        if discriminant > 0
            first = (-b + sqrt(Float64(discriminant))) / (2*a)
            second = (-b - sqrt(Float64(discriminant))) / (2*a)
            @printf("x1 = %.4f, x2 = %.4f\n",max(first,second),min(first,second))
        elseif discriminant == 0
            @printf("x = %.4f\n",-b/(2*a))
        else
            real = -b/(2*a)
            imaginary = sqrt(Float64(-discriminant))/(2*abs(a))
            @printf("x = %.4f + %.4fi, %.4f - %.4fi\n",real,imaginary,real,imaginary)
        end
    end
end
main()
