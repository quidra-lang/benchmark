struct Histogram
    maxval::Int
    pixels::Int
    counts::Vector{Int}
    below_counts::Vector{Int}
    below_sums::Vector{Int}
    total::Int
    minimum::Int
    maximum::Int
    levels::Int
    median::Int
    mode::Int
    bin_width::Int
    bins::Vector{Int}
end

function Histogram(image::Image)
    frequencies = zeros(Int, image.maxval + 1)
    for value in image.pixels
        frequencies[value + 1] += 1
    end
    below_counts = cumsum(frequencies)
    below_sums = cumsum([value * frequencies[value + 1] for value in 0:image.maxval])
    present = [value for value in 0:image.maxval if frequencies[value + 1] > 0]
    pixels = image.width * image.height
    median = findfirst(value -> 2 * value >= pixels, below_counts) - 1
    mode = findmax(frequencies)[2] - 1
    bin_width = div(image.maxval + 8, 8)
    bins = [sum(frequencies[start + 1:min(start + bin_width, length(frequencies))]) for start in 0:bin_width:image.maxval]
    Histogram(image.maxval, pixels, frequencies, below_counts, below_sums, below_sums[end],
        first(present), last(present), length(present), median, mode, bin_width, bins)
end

function split_histogram(histogram, cutoff)
    below, sum_below = histogram.below_counts[cutoff + 1], histogram.below_sums[cutoff + 1]
    below, sum_below, histogram.pixels - below, histogram.total - sum_below
end

struct Candidate
    cutoff::Int
    below::Int
    sum_below::Int
    above::Int
    sum_above::Int
    numerator::Int
    denominator::Int
end

function compare_scores(first, second)
    q1, r1 = divrem(first.numerator, first.denominator)
    q2, r2 = divrem(second.numerator, second.denominator)
    q1 != q2 && return cmp(q1, q2)
    cmp(r1 * second.denominator, r2 * first.denominator)
end

struct OtsuResult
    cutoff::Int
    upper::Int
    candidates::Vector{Candidate}
end

function otsu(histogram)
    candidates = Candidate[]
    for cutoff in 0:histogram.maxval-1
        below, sum_below, above, sum_above = split_histogram(histogram, cutoff)
        if histogram.counts[cutoff + 1] > 0 && above > 0
            push!(candidates, Candidate(cutoff, below, sum_below, above, sum_above,
                sum_below * sum_below * above + sum_above * sum_above * below, below * above))
        end
    end
    sort!(candidates; lt=(a, b) -> begin
        order = compare_scores(a, b)
        order > 0 || (order == 0 && a.cutoff < b.cutoff)
    end)
    isempty(candidates) && return OtsuResult(histogram.minimum, histogram.minimum, candidates)
    cutoff = candidates[1].cutoff
    following = first(value for value in cutoff+1:histogram.maxval if histogram.counts[value + 1] > 0)
    OtsuResult(cutoff, following - 1, candidates)
end

function isodata(histogram)
    cutoff = div(histogram.total, histogram.pixels)
    iterations = 0
    while true
        below, sum_below, above, sum_above = split_histogram(histogram, cutoff)
        (below == 0 || above == 0) && break
        following = div(sum_below * above + sum_above * below, 2 * below * above)
        iterations += 1
        following == cutoff && break
        cutoff = following
        iterations == 100 && break
    end
    cutoff, iterations
end
