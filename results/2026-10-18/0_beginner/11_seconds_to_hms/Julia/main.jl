using Printf
for seconds in [0, 59, 3725, 45296, 86400, 312047]
    hours = div(seconds, 3600)
    minutes = div(seconds % 3600, 60)
    @printf("%d seconds = %02d:%02d:%02d\n", seconds, hours, minutes, seconds % 60)
end
