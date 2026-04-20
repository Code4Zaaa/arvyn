local String = {}

--[=[
    Formats a number with commas (e.g., 1000 -> 1,000)
]=]
function String.CommaFormat(n: number | string): string
    local s = tostring(n)
    return s:reverse():gsub("%d%d%d", "%1,"):reverse():gsub("^,", "")
end

--[=[
    Abbreviates a number (e.g., 1,500,000 -> 1.5M)
]=]
function String.Abbreviate(n: number): string
    local abbrev = {
        {1e12, "T"}, 
        {1e9, "B"}, 
        {1e6, "M"}, 
        {1e3, "K"}
    }
    
    for _, v in ipairs(abbrev) do
        if n >= v[1] then 
            return string.format("%.1f%s", n / v[1], v[2]) 
        end
    end
    
    return tostring(n)
end

--[=[
    Formats seconds into a human-readable string (e.g., 3660 -> 1H 1M)
]=]
function String.FormatTime(s: number): string
    if not s or s == math.huge or s == -1 then 
        return "Lifetime" 
    end
    
    local days = math.floor(s / 86400)
    local hours = math.floor((s % 86400) / 3600)
    local minutes = math.floor((s % 3600) / 60)
    
    if days > 0 then
        return string.format("%dD %dH", days, hours)
    elseif hours > 0 then
        return string.format("%dH %dM", hours, minutes)
    else
        return string.format("%dM", minutes)
    end
end

return String
