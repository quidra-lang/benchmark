local Policy = require("policy")
local Report = {}

function Report.path(path)
    return table.concat(path, ",")
end

function Report.attribute(attribute)
    return string.format("path %s origin %s med %d comm %s", Report.path(attribute.path),
        attribute.origin, attribute.med, Policy.communities_text(attribute.communities))
end

function Report.route(route)
    if not route then return "NONE" end
    local communities = Policy.communities_text(route.communities)
    if not route.link then return string.format("LOCAL origin %s comm %s", route.origin, communities) end
    return string.format("next %d path %s link %s lp %d med %d origin %s comm %s", route.path[1],
        Report.path(route.path), route.link.name, route.local_pref, route.med, route.origin, communities)
end

function Report.write(reports)
    assert(os.execute("mkdir -p output"))
    for _, report in ipairs(reports) do
        local file = assert(io.open("output/" .. report[1], "wb"))
        for _, line in ipairs(report[2]) do file:write(line, "\n") end
        file:close()
    end
end

return Report
