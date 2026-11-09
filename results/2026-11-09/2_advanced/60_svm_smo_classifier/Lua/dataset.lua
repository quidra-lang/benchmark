local K = require("kernels")
local D = {}
local function csv(path, multiple)
    local input, training, testing = assert(io.open(path, "r")), {}, {}
    input:read("*l")
    for line in input:lines() do
        local words = {}
        for word in line:gmatch("[^,]+") do words[#words + 1] = word end
        local example = { id = words[1], point = { tonumber(words[2]), tonumber(words[3]) }, label = tonumber(words[4]), role = words[5] }
        local target = multiple and example.role == "test" and testing or training
        target[#target + 1] = example
    end
    input:close()
    return training, testing
end
local function settings(path)
    local result = { kernels = {} }
    for line in io.lines(path) do
        local words = {}
        for word in line:gmatch("%S+") do words[#words + 1] = word end
        local key = words[1]
        if key == "KERNEL" then result.kernels[#result.kernels + 1] = K.new(words)
        else
            local values = {}
            for i = 2, #words do values[#values + 1] = tonumber(words[i]) or words[i] end
            if key == "C_GRID" then result.c_grid = values elseif key == "LEARNING_CURVE" then result.learning_curve = values
            elseif key == "MULTICLASS" then result.multiclass = values elseif key == "PEGASOS" then result.pegasos = values
            elseif key == "PLOT_X" then result.plot_x = values elseif key == "PLOT_Y" then result.plot_y = values elseif key == "PLOT_SIZE" then result.plot_size = values
            elseif key == "TOLERANCE" then result.tolerance = values[1] elseif key == "EPS" then result.eps = values[1]
            elseif key == "MAX_PASSES" then result.max_passes = values[1] elseif key == "FOLDS" then result.folds = values[1]
            elseif key == "NEWTON_ITERATIONS" then result.newton_iterations = values[1] end
        end
    end
    return result
end
function D.read()
    local training = csv("input/train.csv", false)
    local testing = csv("input/test.csv", false)
    local multi_training, multi_testing = csv("input/multiclass.csv", true)
    return training, testing, multi_training, multi_testing, settings("input/params.txt")
end
return D
