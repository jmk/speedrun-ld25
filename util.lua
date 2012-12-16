
function clamp(x, min, max)
    return math.max(min, math.min(max, x))
end

function lerp(a, b, x)
    return a * (1-x) + (b*x)
end

function randf(a, b)
    return lerp(a, b, math.random())
end

function randsgn()
    if (math.random() >= 0.5) then
        return -1
    else
        return 1
    end
end
