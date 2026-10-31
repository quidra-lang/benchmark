local D = {}
local G = {}
G.__index = G
function D.generator(seed) return setmetatable({ state = seed }, G) end
function G:draw() self.state = 48271 * self.state % 2147483647; return self.state end
function G:shuffle(values)
    for i = #values, 2, -1 do local j = self:draw() % i + 1; values[i], values[j] = values[j], values[i] end
end
local function words(line)
    local result = {}
    for word in line:gmatch("%S+") do result[#result + 1] = word end
    return result
end
local function images(path)
    local input, result = assert(io.open(path, "r")), {}
    input:read("*l")
    for line in input:lines() do
        local id, label, pixels = line:match("^([^,]+),(%d+),([01]+)$")
        local vector = {}
        for i = 1, #pixels do vector[i] = pixels:byte(i) == 49 and 1.0 or 0.0 end
        result[#result + 1] = { id = id, label = tonumber(label), pixels = pixels, vector = vector }
    end
    input:close()
    return result
end
function D.read()
    local result, current, width, height = { networks = {}, weights = {}, settings = { runs = {} } }
    for line in io.lines("input/network.txt") do
        local values = words(line)
        if values[1] == "IMAGE" then width, height = tonumber(values[2]), tonumber(values[3])
        elseif values[1] == "NETWORK" then
            current = { name = values[2], width = width, height = height, layers = {} }
            result.networks[#result.networks + 1] = current
        elseif values[1] == "HIDDEN" or values[1] == "OUTPUT" then
            current.layers[#current.layers + 1] = { units = tonumber(values[2]), activation = values[3], kind = values[1] }
            if values[1] == "OUTPUT" then current.classes = tonumber(values[2]) end
        end
    end
    for line in io.lines("input/weights.txt") do
        local values = words(line)
        if values[1] == "NETWORK" then current = {}; result.weights[values[2]] = current
        elseif values[1] == "W" or values[1] == "B" then for i = 2, #values do current[#current + 1] = tonumber(values[i]) end end
    end
    local aliases = { SEED = "seed", BATCH_SIZE = "batch_size", MAX_EPOCHS = "max_epochs", PATIENCE = "patience", GRADIENT_CHECK_STRIDE = "gradient_stride", CALIBRATION_BINS = "calibration_bins" }
    local settings = result.settings
    for line in io.lines("input/params.txt") do
        local values = words(line)
        local key = values[1]
        if key == "RUN" then
            local extra = {}
            for i = 7, #values do extra[#extra + 1] = tonumber(values[i]) end
            settings.runs[#settings.runs + 1] = { name = values[2], network = values[3], optimizer = values[4], rate = tonumber(values[5]), decay = tonumber(values[6]), extra = extra }
        elseif key == "LR_STEP" then settings.lr_step, settings.lr_gamma = tonumber(values[2]), tonumber(values[3])
        elseif key == "PRUNE" or key == "NOISE" then
            local percentages = {}
            for i = 2, #values do percentages[#percentages + 1] = tonumber(values[i]) end
            settings[key:lower()] = percentages
        else settings[aliases[key]] = tonumber(values[2]) end
    end
    result.train, result.test = images("input/train.csv"), images("input/test.csv")
    return result
end
return D
