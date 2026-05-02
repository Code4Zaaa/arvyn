-- Arvyn Hub | Resource Cache System by 4zaa.dev

getgenv = getgenv or getfenv

local HttpService = game:GetService("HttpService")

local CACHE_DIR = "Arvyn Scripts/Cache"

local function GenerateKey(str)
    local n = #str
    string.gsub(str, ".", function(c)
        n += c:byte() + #str
    end)
    return tostring(math.round(n + 15))
end

local function Request(url)
    local ok, res = pcall(game.HttpGet, game, url)
    if ok then return res end

    task.wait(1)

    local seed = tostring(math.random()) .. tostring(math.random()) .. tostring(math.random())
    return '-- Resource unavailable\nlocal _id = "' .. GenerateKey(seed) .. '";'
end

local function GetCachePath(url)
    return CACHE_DIR .. "/" .. GenerateKey(url)
end

local Cache = {}

function Cache.init()
    if not isfolder(CACHE_DIR) then
        makefolder(CACHE_DIR)
    end
end

function Cache.get(url, duration)
    local path      = GetCachePath(url)
    local startTime = tick()

    local function reload()
        local content = Request(url)

        if not isfolder(path) then
            makefolder(path)
        end

        local meta = { saved_at = tick(), duration = duration }
        writefile(path .. "/meta.json",   HttpService:JSONEncode(meta))
        writefile(path .. "/content.txt", content)

        return content
    end

    local hasCache = isfolder(path)
        and isfile(path .. "/meta.json")
        and isfile(path .. "/content.txt")
        and readfile(path .. "/meta.json")
        and readfile(path .. "/content.txt")

    if hasCache then
        local meta
        xpcall(
            function()
                meta = HttpService:JSONDecode(readfile(path .. "/meta.json"))
            end,
            function()
                meta = { saved_at = -5, duration = 1 }
                pcall(Cache.clear, url)
            end
        )

        local age = tick() - meta.saved_at
        if age > meta.duration then
            return reload(), false, (tick() - startTime)
        end

        return readfile(path .. "/content.txt"), true, (tick() - startTime)
    end

    return reload(), false, (tick() - startTime)
end

function Cache.clear(url)
    local path = GetCachePath(url)

    if isfolder(path) then
        delfolder(path)
        return true
    end

    return false
end

Cache.init()

return Cache