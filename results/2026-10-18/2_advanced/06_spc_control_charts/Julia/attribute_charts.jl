module AttributeCharts
export centerline, lotpoint
function centerline(chart,lots)
    d = sum(l.defectives for l in lots)
    c = sum(l.defects for l in lots)
    s = sum(l.inspected for l in lots)
    center = chart == 1 ? d/s : chart == 2 ? d/length(lots) : chart == 3 ? c/length(lots) : c/s
    (value=center,fraction=d/s)
end
function lotpoint(chart,lot,center)
    cl = center.value
    if chart == 1
        value = lot.defectives/lot.inspected
        sigma = sqrt(cl*(1-cl)/lot.inspected)
    elseif chart == 2
        value = Float64(lot.defectives)
        sigma = sqrt(cl*(1-center.fraction))
    elseif chart == 3
        value = Float64(lot.defects)
        sigma = sqrt(cl)
    else
        value = lot.defects/lot.inspected
        sigma = sqrt(cl/lot.inspected)
    end
    lcl = max(0.0,cl-3*sigma)
    ucl = cl+3*sigma
    (value=value,lcl=lcl,ucl=ucl,z=(value-cl)/sigma,status=value > ucl ? "high" : value < lcl ? "low" : "ok")
end
end
