local Services = loadstring(game:HttpGet("https://raw.githubusercontent.com/Code4Zaaa/arvyn/refs/heads/main/Utility/Services.lua"))();
local HttpService = Services:Get('HttpService');
local HttpRequest = http_request or request or (http and http.request) or (syn and syn.request)

local Webhook = {};
Webhook.__index = Webhook;

function Webhook.new(url)
    local self = setmetatable({}, Webhook);

    self._url = url;

    return self;
end;

function Webhook:Send(data, yields)
    if (typeof(data) == 'string') then
        data = {content = data};
    end;

    local function send()
        HttpRequest({
            Url = self._url,
            Method = 'POST',
            Headers = {['Content-Type'] = 'application/json'},
            Body = HttpService:JSONEncode(data)
        });
    end;

    if (yields) then
        pcall(send);
    else
        task.spawn(send);
    end;
end;

return Webhook;