local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")

local ServerReporter = {}
ServerReporter.__index = ServerReporter

local function Sha256(message)
	local band, bxor, bnot, rrotate, rshift = bit32.band, bit32.bxor, bit32.bnot, bit32.rrotate, bit32.rshift
	local K = {
		0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
		0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
		0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
		0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
		0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
		0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
		0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
		0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
	}
	local H = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
	local length = #message
	message = message .. "\128" .. string.rep("\0", (55 - length) % 64) .. string.pack(">I8", length * 8)
	local w = table.create(64, 0)
	for chunk = 1, #message, 64 do
		for i = 0, 15 do w[i + 1] = string.unpack(">I4", message, chunk + i * 4) end
		for i = 17, 64 do
			local x, y = w[i - 15], w[i - 2]
			local s0 = bxor(rrotate(x, 7), rrotate(x, 18), rshift(x, 3))
			local s1 = bxor(rrotate(y, 17), rrotate(y, 19), rshift(y, 10))
			w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % 4294967296
		end
		local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
		for i = 1, 64 do
			local S1 = bxor(rrotate(e, 6), rrotate(e, 11), rrotate(e, 25))
			local ch = bxor(band(e, f), band(bnot(e), g))
			local t1 = h + S1 + ch + K[i] + w[i]
			local S0 = bxor(rrotate(a, 2), rrotate(a, 13), rrotate(a, 22))
			local maj = bxor(band(a, b), band(a, c), band(b, c))
			h, g, f, e = g, f, e, (d + t1) % 4294967296
			d, c, b, a = c, b, a, (t1 + S0 + maj) % 4294967296
		end
		H[1], H[2], H[3], H[4] = (H[1] + a) % 4294967296, (H[2] + b) % 4294967296, (H[3] + c) % 4294967296, (H[4] + d) % 4294967296
		H[5], H[6], H[7], H[8] = (H[5] + e) % 4294967296, (H[6] + f) % 4294967296, (H[7] + g) % 4294967296, (H[8] + h) % 4294967296
	end
	return string.format(string.rep("%08x", 8), table.unpack(H))
end
ServerReporter.Sha256 = Sha256

local function DefaultRequest()
	return (syn and syn.request) or (http and http.request) or http_request or request
end

local function DefaultHash()
	local c = crypt or (syn and syn.crypt)
	if c and c.hash then
		return function(data) return c.hash(data, "sha256") end
	end
	return Sha256
end

function ServerReporter.new(options)
	assert(type(options) == "table", "ServerReporter.new: options table expected")
	assert(type(options.Url) == "string", "ServerReporter.new: Url is required")
	assert(type(options.Id) == "string", "ServerReporter.new: Id is required")
	assert(type(options.Secret) == "string" or type(options.Sign) == "function",
		"ServerReporter.new: Secret or Sign is required")
	local self = setmetatable({}, ServerReporter)
	self.Url = options.Url:gsub("/+$", "")
	self.Id = options.Id
	self.SignFn = options.Sign
	local secret = options.Secret
	self.Interval = options.Interval or 15
	self.Heartbeat = options.Heartbeat or 90
	self.Jitter = options.Jitter or 30
	self.MaxBackoff = options.MaxBackoff or 300
	self.JoinTimeout = options.JoinTimeout or 8
	self.TeleportFn = options.Teleport
	self.OnNotify = options.OnNotify
	self.RequestFn = options.Request or DefaultRequest()
	if not self.SignFn then
		local hash = options.Hash or DefaultHash()
		self.SignFn = function(timestamp, body) return hash(timestamp .. body .. secret) end
	end
	self.Enabled = true
	self.Events = {}
	self.EventsByKey = {}
	self.State = { Sig = "", At = -math.huge, Wait = 0, Fails = 0 }
	self.Joining = false
	return self
end

function ServerReporter:AddEvent(event)
	assert(type(event) == "table" and type(event.Key) == "string" and type(event.Check) == "function",
		"ServerReporter:AddEvent: { Key = string, Check = function } expected")
	event.Key = event.Key:lower()
	event.Name = event.Name or event.Key
	event.MaxAge = event.MaxAge or 10
	if self.EventsByKey[event.Key] then
		for i, existing in ipairs(self.Events) do
			if existing.Key == event.Key then table.remove(self.Events, i) break end
		end
	end
	table.insert(self.Events, event)
	self.EventsByKey[event.Key] = event
	return event
end

function ServerReporter:AddEvents(list)
	for _, event in ipairs(list) do self:AddEvent(event) end
end

function ServerReporter:RemoveEvent(key)
	key = key:lower()
	self.EventsByKey[key] = nil
	for i, event in ipairs(self.Events) do
		if event.Key == key then table.remove(self.Events, i) break end
	end
end

function ServerReporter:ReadEvent(event)
	local ok, result = pcall(event.Check)
	if not ok or not result then return false, {} end
	if type(result) == "table" then
		local items = {}
		for _, item in ipairs(result) do
			if type(item) == "string" and not table.find(items, item) then table.insert(items, item) end
		end
		return #items > 0, items
	end
	return true, { type(result) == "string" and result or "" }
end

function ServerReporter:Request(method, path, payload)
	if not self.RequestFn then return false, nil, 0 end
	local body = payload ~= nil and HttpService:JSONEncode(payload) or ""
	local timestamp = tostring(os.time())
	local headers = {
		["X-API-ID"] = self.Id,
		["X-Timestamp"] = timestamp,
		["X-Signature"] = self.SignFn(timestamp, body),
	}
	if payload ~= nil then headers["Content-Type"] = "application/json" end
	local ok, response = pcall(self.RequestFn, {
		Url = self.Url .. path,
		Method = method,
		Headers = headers,
		Body = payload ~= nil and body or nil,
	})
	if not ok or type(response) ~= "table" then return false, nil, 0 end
	local status = tonumber(response.StatusCode) or 0
	local data
	if type(response.Body) == "string" and response.Body ~= "" then
		local okDecode, decoded = pcall(HttpService.JSONDecode, HttpService, response.Body)
		if okDecode then data = decoded end
	end
	return status >= 200 and status < 300, data, status
end

function ServerReporter:CheckedKeys(includeWitness)
	local keys = {}
	for _, event in ipairs(self.Events) do
		if includeWitness or not event.Witness then table.insert(keys, event.Key) end
	end
	return keys
end

function ServerReporter:SendBatch(events, checked)
	return self:Request("POST", "/spawns/batch", {
		place_id = game.PlaceId,
		job_id = game.JobId,
		player_count = #Players:GetPlayers(),
		max_players = Players.MaxPlayers,
		events = next(events) and events or nil,
		checked = checked or self:CheckedKeys(),
	})
end

function ServerReporter:Step(force)
	local events, parts = {}, {}
	if self.Enabled then
		for _, event in ipairs(self.Events) do
			local live, items = self:ReadEvent(event)
			if live then
				events[event.Key] = items
				for _, item in ipairs(items) do table.insert(parts, event.Key .. "=" .. item) end
			end
		end
	end
	table.sort(parts)
	local sig = table.concat(parts, "|")
	local state = self.State
	if sig == "" and state.Sig == "" then return false end
	if not force then
		local elapsed = os.clock() - state.At
		if state.Fails > 0 then
			if elapsed < math.min(30 * 2 ^ (state.Fails - 1), self.MaxBackoff) then return false end
		elseif sig == state.Sig and elapsed < state.Wait then
			return false
		end
	end
	state.At = os.clock()
	local ok = self:SendBatch(events, not self.Enabled and self:CheckedKeys(true) or nil)
	if ok then
		state.Sig, state.Fails = sig, 0
		state.Wait = self.Heartbeat + math.random() * self.Jitter
	else
		state.Fails = math.min(state.Fails + 1, 10)
	end
	return ok
end

function ServerReporter:Clear()
	self.State.Sig = ""
	return self:SendBatch({}, self:CheckedKeys(true))
end

function ServerReporter:SetEnabled(enabled)
	self.Enabled = enabled ~= false
end

function ServerReporter:Start()
	if self.Thread then return end
	self.Thread = task.spawn(function()
		task.wait(math.random() * 5)
		while self.Thread do
			pcall(self.Step, self)
			task.wait(self.Interval)
		end
	end)
end

function ServerReporter:Stop()
	local thread = self.Thread
	self.Thread = nil
	if thread and coroutine.status(thread) ~= "dead" and thread ~= coroutine.running() then
		pcall(task.cancel, thread)
	end
end

function ServerReporter:Destroy()
	self:Stop()
	if self.State.Sig ~= "" then task.spawn(self.Clear, self) end
end

function ServerReporter:GetServers(key, opts)
	opts = opts or {}
	local event = self.EventsByKey[key:lower()]
	local query = { "max_age=" .. tostring(opts.MaxAge or (event and event.MaxAge) or 10) }
	if not opts.AnyPlace then table.insert(query, "place_id=" .. tostring(opts.PlaceId or game.PlaceId)) end
	if opts.Item and opts.Item ~= "" then table.insert(query, "item=" .. HttpService:UrlEncode(opts.Item)) end
	local ok, data, status = self:Request("GET", "/spawns/" .. key:lower() .. "?" .. table.concat(query, "&"))
	if not ok or type(data) ~= "table" then return nil, status end
	local servers, seen = {}, {}
	for _, entry in ipairs(data) do
		if type(entry) == "table" and type(entry.job_id) == "string" and entry.job_id ~= "" then
			local maxPlayers = tonumber(entry.max_players) or 0
			local full = maxPlayers > 0 and (tonumber(entry.player_count) or 0) >= maxPlayers
			if entry.job_id ~= game.JobId and not seen[entry.job_id] and not full then
				seen[entry.job_id] = true
				table.insert(servers, entry)
			end
		end
	end
	return servers
end

function ServerReporter:ListServers(opts)
	if type(opts) == "number" then opts = { MaxAge = opts } end
	opts = opts or {}
	local query = { "max_age=" .. tostring(opts.MaxAge or 10) }
	if not opts.AnyPlace then table.insert(query, "place_id=" .. tostring(opts.PlaceId or game.PlaceId)) end
	local ok, data, status = self:Request("GET", "/spawns/all?" .. table.concat(query, "&"))
	if not ok or type(data) ~= "table" then return nil, status end
	local rows, now = {}, os.time()
	for _, entry in ipairs(data) do
		if type(entry) == "table" and type(entry.job_id) == "string" and entry.job_id ~= "" then
			local event = self.EventsByKey[entry.event_type]
			local seenAt = 0
			pcall(function() seenAt = DateTime.fromIsoDate(entry.last_seen).UnixTimestamp end)
			local players, maxPlayers = tonumber(entry.player_count) or 0, tonumber(entry.max_players) or 0
			table.insert(rows, {
				Entry = entry,
				EventKey = entry.event_type,
				Event = event and event.Name or tostring(entry.event_type),
				Item = (entry.item_name ~= nil and entry.item_name ~= "") and entry.item_name or "-",
				Players = maxPlayers > 0 and string.format("%d/%d", players, maxPlayers) or (players > 0 and tostring(players) or "?"),
				PlayerCount = players,
				Age = seenAt > 0 and math.max(now - seenAt, 0) or nil,
				Job = entry.job_id:sub(1, 8),
				Current = entry.job_id == game.JobId,
				Highlight = entry.job_id == game.JobId,
			})
		end
	end
	return rows
end

function ServerReporter:Notify(title, text, kind)
	if self.OnNotify then pcall(self.OnNotify, title, text, kind or "Info") end
end

function ServerReporter:Teleport(entry)
	if self.TeleportFn then return self.TeleportFn(entry) end
	TeleportService:TeleportToPlaceInstance(tonumber(entry.place_id) or game.PlaceId, entry.job_id, Players.LocalPlayer)
end

function ServerReporter:JoinServerList(servers, label)
	label = label or "event"
	if self.Joining then
		return self:Notify("Server Finder", "Already joining a server...", "Warning")
	end
	self.Joining = true
	task.spawn(function()
		local startJob = game.JobId
		for i, entry in ipairs(servers) do
			if game.JobId ~= startJob then break end
			self:Notify("Server Finder", string.format("Joining %s server (%d/%d)...", label, i, #servers))
			pcall(GuiService.ClearError, GuiService)
			local failed, done = false, false
			local thread = coroutine.running()
			local function resume()
				if done then return end
				done = true
				task.spawn(thread)
			end
			local conn = TeleportService.TeleportInitFailed:Connect(function(player)
				if player == Players.LocalPlayer then failed = true resume() end
			end)
			task.spawn(function()
				local ok = pcall(self.Teleport, self, entry)
				if not ok then failed = true resume() end
			end)
			task.delay(self.JoinTimeout, resume)
			coroutine.yield()
			conn:Disconnect()
			pcall(GuiService.ClearError, GuiService)
			if failed then task.wait(1) end
		end
		self.Joining = false
		if game.JobId == startJob then
			self:Notify("Server Finder", "All " .. label .. " servers were full or unavailable.", "Warning")
		end
	end)
end

function ServerReporter:JoinEvent(key, item, label)
	local event = self.EventsByKey[key:lower()]
	label = label or (event and event.Name) or key
	if self.Joining then
		return self:Notify("Server Finder", "Already joining a server...", "Warning")
	end
	if event then
		local live, items = self:ReadEvent(event)
		if live and (not item or table.find(items, item)) then
			return self:Notify("Server Finder", label .. " is already active in this server.", "Success")
		end
	end
	task.spawn(function()
		local servers, status = self:GetServers(key, { Item = item, MaxAge = event and event.MaxAge })
		if not servers then
			self:Notify("Server Finder", "Failed to reach the API (" .. tostring(status) .. ").", "Error")
		elseif #servers == 0 then
			self:Notify("Server Finder", "No recent " .. label .. " server found. Try again later.", "Warning")
		else
			self:JoinServerList(servers, label)
		end
	end)
end

return ServerReporter
