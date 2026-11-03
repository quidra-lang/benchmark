local M = {}
local function split(line, pattern)
    local result = {}
    for value in line:gmatch(pattern) do
        result[#result + 1] = value
    end
    return result
end
local function table_rows(path, multiclass)
    local features, training, testing, first = {}, {}, {}, true
    for line in io.lines(path) do
        local fields = split(line, "[^,]+")
        if first then
            first = false
            for j = 2, #fields - (multiclass and 2 or 1) do
                features[#features + 1] = fields[j]
            end
        else
            local row = {id = fields[1], values = {}, label = tonumber(fields[#fields - (multiclass and 1 or 0)])}
            for j = 2, #features + 1 do
                row.values[#row.values + 1] = tonumber(fields[j]) + 0.0
            end
            local destination = multiclass and fields[#fields] == "test" and testing or training
            destination[#destination + 1] = row
        end
    end
    return features, training, testing
end
function M.read()
    local features, training = table_rows("input/train.csv", false)
    local _, testing = table_rows("input/test.csv", false)
    local multi_features, multi_training, multi_testing = table_rows("input/multiclass.csv", true)
    local settings = {}
    for line in io.lines("input/params.txt") do
        local fields = split(line, "%S+")
        local key = table.remove(fields, 1)
        settings[key] = fields
    end
    local function numbers(fields, integral, first)
        local result = {}
        for i = first or 1, #fields do
            result[#result + 1] = integral and tonumber(fields[i]) or tonumber(fields[i]) + 0.0
        end
        return result
    end
    local params = {
        rounds = tonumber(settings.ROUNDS[1]), variants = settings.VARIANTS, bins = tonumber(settings.BINS[1]),
        smoothing = tonumber(settings.SMOOTHING[1]) + 0.0, convergence = tonumber(settings.CONVERGENCE[1]) + 0.0,
        clip = tonumber(settings.CLIP[1]) + 0.0, folds = tonumber(settings.FOLDS[1]), margins = numbers(settings.MARGINS, false),
        classes = tonumber(settings.CLASSES[1]), samme_rounds = tonumber(settings.SAMME_ROUNDS[1]),
        permutation_repeats = tonumber(settings.PERMUTATION[1]), permutation_seed = tonumber(settings.PERMUTATION[2]),
        noise_seed = tonumber(settings.NOISE[1]), noise = numbers(settings.NOISE, true, 2), sizes = numbers(settings.SIZES, true),
        shrinkage = numbers(settings.SHRINKAGE, false), bootstrap_count = tonumber(settings.BOOTSTRAP[1]),
        bootstrap_seed = tonumber(settings.BOOTSTRAP[2])
    }
    return {features = features, training = training, testing = testing, multi_features = multi_features,
        multi_training = multi_training, multi_testing = multi_testing, params = params}
end
return M
