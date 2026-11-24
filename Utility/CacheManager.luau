-- Arvyn Hub | Resource Cache System by 4zaa.dev
--
-- Cache.get(url, duration?, validate?) -> content | nil, isCached, seconds
--   A saved copy is returned at once and refreshed in the background (saved when it changed), so an update reaches
--   players one load later. Without a copy it downloads now. A download is saved only when validate(content) passes
--   (default: it compiles), so a failed or broken download never replaces a good copy; nil when nothing is usable.
--   duration is kept in meta.json for older versions of this file and no longer expires a copy.

getgenv = getgenv or getfenv

local HttpService = game:GetService("HttpService")

local CACHE_DIR = "Arvyn Scripts/Cache"

local FileApi = type(readfile) == "function" and type(writefile) == "function" and type(isfile) == "function"
    and type(isfolder) == "function" and type(makefolder) == "function"

local function GenerateKey(str)
    local hash = 5381
    for i = 1, #str do
        hash = ((hash * 33) + string.byte(str, i)) % 2^32
    end
    return string.format("%d", hash)
end

local function GetCachePath(url)
    return CACHE_DIR .. "/" .. GenerateKey(url)
end

local function Compiles(content)
    return loadstring(content) ~= nil
end

local function Download(url, validate)
    local ok, content = pcall(game.HttpGet, game, url)
    if not ok or type(content) ~= "string" or content == "" then return nil end
    local valid, result = pcall(validate, content)
    return (valid and result) and content or nil
end

local function ReadCopy(path)
    if not FileApi then return nil end
    local ok, content = pcall(function()
        if isfile(path .. "/content.txt") then return readfile(path .. "/content.txt") end
    end)
    return ok and type(content) == "string" and content ~= "" and content or nil
end

local function WriteCopy(path, content, duration)
    if not FileApi then return end
    pcall(function()
        for _, folder in ipairs({ "Arvyn Scripts", CACHE_DIR, path }) do
            if not isfolder(folder) then makefolder(folder) end
        end
        writefile(path .. "/content.txt", content)
        writefile(path .. "/meta.json", HttpService:JSONEncode({ saved_at = tick(), duration = duration or 86400 }))
    end)
end

local Cache = {}

function Cache.init()
    if FileApi then
        pcall(function()
            if not isfolder("Arvyn Scripts") then makefolder("Arvyn Scripts") end
            if not isfolder(CACHE_DIR) then makefolder(CACHE_DIR) end
        end)
    end
end

function Cache.get(url, duration, validate)
    local path = GetCachePath(url)
    local startTime = tick()
    validate = validate or Compiles

    local cached = ReadCopy(path)
    if cached then
        local valid, result = pcall(validate, cached)
        if valid and result then
            task.spawn(function()
                local fresh = Download(url, function(content) return content ~= cached and validate(content) end)
                if fresh then WriteCopy(path, fresh, duration) end
            end)
            return cached, true, tick() - startTime
        end
    end

    local fresh = Download(url, validate)
    if fresh then WriteCopy(path, fresh, duration) end
    return fresh, false, tick() - startTime
end

function Cache.clear(url)
    local path = GetCachePath(url)
    if FileApi and type(delfolder) == "function" and isfolder(path) then
        delfolder(path)
        return true
    end
    return false
end

Cache.init()

return Cache
