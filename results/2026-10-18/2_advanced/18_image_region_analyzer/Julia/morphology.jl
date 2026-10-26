const Pixel = Tuple{Int,Int}
const NEIGHBORHOOD = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]

occupied(mask, x, y) = 0 <= y < size(mask, 1) && 0 <= x < size(mask, 2) && mask[y + 1, x + 1]

function erode(mask, offsets)
    height, width = size(mask)
    [all(occupied(mask, x + dx, y + dy) for (dx, dy) in offsets) for y in 0:height-1, x in 0:width-1]
end

function dilate(mask, offsets)
    height, width = size(mask)
    [any(occupied(mask, x - dx, y - dy) for (dx, dy) in offsets) for y in 0:height-1, x in 0:width-1]
end

opening(mask, offsets) = dilate(erode(mask, offsets), offsets)
closing(mask, offsets) = erode(dilate(mask, offsets), offsets)
neighbor_bits(pixels, x, y) = [(x + dx, y + dy) in pixels for (dx, dy) in NEIGHBORHOOD]
transitions(bits) = count(index -> !bits[index] && bits[mod1(index + 1, 8)], 1:8)
crossing_number(pixels, point) = transitions(neighbor_bits(pixels, point...))

function removable(bits, first_step)
    2 <= count(bits) <= 6 && transitions(bits) == 1 || return false
    p2, p4, p6, p8 = bits[1], bits[3], bits[5], bits[7]
    first_step ? !(p2 && p4 && p6) && !(p4 && p6 && p8) : !(p2 && p4 && p8) && !(p2 && p6 && p8)
end

function thinning_step!(skeleton, first_step)
    removed = [point for point in skeleton if removable(neighbor_bits(skeleton, point...), first_step)]
    setdiff!(skeleton, removed)
    !isempty(removed)
end

function thin(pixels)
    skeleton = Set(pixels)
    while true
        first_removed = thinning_step!(skeleton, true)
        second_removed = thinning_step!(skeleton, false)
        !first_removed && !second_removed && return skeleton
    end
end
