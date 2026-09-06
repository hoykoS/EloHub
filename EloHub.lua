local SCRIPT_SLUG = "elohub"
local SCRIPT_TITLE = "EloHub"
local VALIDATE_URL = "https://elohub-tg.onrender.com/validate"
local KEY_FILE = "elohub_" .. SCRIPT_SLUG .. "_key.txt"

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Prefer CoreGui: some games actively scan/clear PlayerGui and would tear
-- this window down (or block it from ever rendering) before it's usable.
-- Most executors grant write access to CoreGui even though a normal
-- LocalScript can't; fall back to PlayerGui if that access isn't there.
local function resolveGuiParent()
	local ok, coreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok and coreGui then
		return coreGui
	end
	return playerGui
end

-- --------------------------------------------------------------------------
-- Storage (best-effort: not every executor exposes file IO)
-- --------------------------------------------------------------------------
local function loadSavedKey()
	local ok, data = pcall(function()
		if readfile and isfile and isfile(KEY_FILE) then
			return readfile(KEY_FILE)
		end
		return nil
	end)
	if ok and data and #data > 0 then
		return data
	end
	return nil
end

local function saveKey(key)
	pcall(function()
		if writefile then
			writefile(KEY_FILE, key)
		end
	end)
end

local function clearSavedKey()
	pcall(function()
		if delfile and isfile and isfile(KEY_FILE) then
			delfile(KEY_FILE)
		end
	end)
end

-- --------------------------------------------------------------------------
-- Backend call
-- --------------------------------------------------------------------------
-- Roblox's own HttpService:PostAsync only reaches domains on Roblox's
-- allowlist and most executors don't bother patching it (unlike
-- game:HttpGet, which is patched almost everywhere) — so a POST to our own
-- server via PostAsync fails even when the server is perfectly healthy.
-- Every serious executor instead exposes a raw HTTP client under one of
-- these names (the "UNC" request function) that talks to any domain;
-- PostAsync is only the last-resort fallback for Studio/rare executors
-- that do patch it.
local function nativeRequest()
	return (syn and syn.request) or http_request or request or (fluxus and fluxus.request)
end

local function httpPostJson(url, jsonBody)
	local requestFn = nativeRequest()
	if requestFn then
		local ok, res = pcall(function()
			return requestFn({
				Url = url,
				Method = "POST",
				Headers = { ["Content-Type"] = "application/json" },
				Body = jsonBody,
			})
		end)
		if ok and type(res) == "table" then
			local status = res.StatusCode
			local success = res.Success == true or (status and status >= 200 and status < 300)
			if success and res.Body then
				return true, res.Body
			end
			return false, nil
		end
		return false, nil
	end

	-- Fallback: the real HttpService (works in Studio, or on the rare
	-- executor that does patch PostAsync).
	local ok, response = pcall(function()
		return HttpService:PostAsync(url, jsonBody, Enum.HttpContentType.ApplicationJson)
	end)
	if ok then
		return true, response
	end
	return false, nil
end

local function requestValidate(key)
	local payload = HttpService:JSONEncode({
		key = key,
		robloxUserId = player.UserId,
		script = SCRIPT_SLUG,
	})

	local ok, response = httpPostJson(VALIDATE_URL, payload)
	if not ok then
		return false, "network_error"
	end

	local decodeOk, decoded = pcall(function()
		return HttpService:JSONDecode(response)
	end)
	if not decodeOk or type(decoded) ~= "table" then
		return false, "bad_response"
	end

	if decoded.ok == true then
		return true, decoded.source
	end
	return false, decoded.reason or "unknown_error"
end

local ERROR_TEXT = {
	not_found = "Ключ не найден. Проверьте и попробуйте снова.",
	wrong_script = "Этот ключ не подходит для данного скрипта.",
	revoked = "Этот ключ заблокирован администратором.",
	already_bound = "Ключ уже привязан к другому аккаунту Roblox.",
	bad_request = "Некорректный запрос. Попробуйте снова.",
	script_unavailable = "Скрипт временно недоступен на сервере.",
	network_error = "Нет соединения с сервером. Проверьте интернет и попробуйте снова.",
	bad_response = "Сервер вернул некорректный ответ. Попробуйте снова.",
}

-- --------------------------------------------------------------------------
-- UI — wrapped in pcall so a single unsupported property/API on some
-- executor prints a warning (F9 console) instead of the window silently
-- never appearing with no trace of why.
-- --------------------------------------------------------------------------
local function buildUI()
local gui = Instance.new("ScreenGui")
gui.Name = "EloHubKeyGate"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999
gui.Parent = resolveGuiParent()

local overlay = Instance.new("Frame")
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.4
overlay.BorderSizePixel = 0
overlay.Parent = gui

local card = Instance.new("Frame")
card.AnchorPoint = Vector2.new(0.5, 0.5)
card.Position = UDim2.fromScale(0.5, 0.5)
card.Size = UDim2.new(0, 300, 0, 210)
card.BackgroundColor3 = Color3.fromRGB(24, 24, 28)
card.BorderSizePixel = 0
card.Parent = overlay

local cardCorner = Instance.new("UICorner")
cardCorner.CornerRadius = UDim.new(0, 14)
cardCorner.Parent = card

local accent = Instance.new("Frame")
accent.Size = UDim2.new(1, 0, 0, 4)
accent.BackgroundColor3 = Color3.fromRGB(90, 120, 255)
accent.BorderSizePixel = 0
accent.Parent = card
local accentCorner = Instance.new("UICorner")
accentCorner.CornerRadius = UDim.new(0, 14)
accentCorner.Parent = accent

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.Position = UDim2.new(0, 16, 0, 16)
title.Size = UDim2.new(1, -32, 0, 26)
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextColor3 = Color3.fromRGB(235, 235, 240)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = SCRIPT_TITLE
title.Parent = card

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.Position = UDim2.new(0, 16, 0, 44)
subtitle.Size = UDim2.new(1, -32, 0, 20)
subtitle.Font = Enum.Font.Gotham
subtitle.TextSize = 13
subtitle.TextColor3 = Color3.fromRGB(150, 150, 160)
subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Text = "Введите ключ активации"
subtitle.Parent = card

local inputHolder = Instance.new("Frame")
inputHolder.Position = UDim2.new(0, 16, 0, 74)
inputHolder.Size = UDim2.new(1, -32, 0, 40)
inputHolder.BackgroundColor3 = Color3.fromRGB(36, 36, 42)
inputHolder.BorderSizePixel = 0
inputHolder.Parent = card
local inputCorner = Instance.new("UICorner")
inputCorner.CornerRadius = UDim.new(0, 10)
inputCorner.Parent = inputHolder

local input = Instance.new("TextBox")
input.BackgroundTransparency = 1
input.Position = UDim2.new(0, 12, 0, 0)
input.Size = UDim2.new(1, -24, 1, 0)
input.Font = Enum.Font.GothamMedium
input.TextSize = 15
input.TextColor3 = Color3.fromRGB(235, 235, 240)
input.PlaceholderText = "EH-XXX-XXX"
input.PlaceholderColor3 = Color3.fromRGB(110, 110, 120)
input.Text = ""
input.ClearTextOnFocus = false
input.TextXAlignment = Enum.TextXAlignment.Left
input.Parent = inputHolder

local status = Instance.new("TextLabel")
status.BackgroundTransparency = 1
status.Position = UDim2.new(0, 16, 0, 118)
status.Size = UDim2.new(1, -32, 0, 34)
status.Font = Enum.Font.Gotham
status.TextSize = 12
status.TextColor3 = Color3.fromRGB(255, 110, 110)
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextYAlignment = Enum.TextYAlignment.Top
status.Text = ""
status.Parent = card

local button = Instance.new("TextButton")
button.Position = UDim2.new(0, 16, 1, -56)
button.Size = UDim2.new(1, -32, 0, 40)
button.BackgroundColor3 = Color3.fromRGB(90, 120, 255)
button.BorderSizePixel = 0
button.Font = Enum.Font.GothamBold
button.TextSize = 15
button.TextColor3 = Color3.fromRGB(255, 255, 255)
button.Text = "Активировать"
button.AutoButtonColor = true
button.Parent = card
local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 10)
buttonCorner.Parent = button

local function setBusy(busy)
	button.Active = not busy
	input.TextEditable = not busy
	button.Text = busy and "Проверка..." or "Активировать"
end

local function runSource(source)
	gui:Destroy()
	local chunk, compileErr = loadstring(source)
	if not chunk then
		warn("[" .. SCRIPT_TITLE .. "] Ошибка компиляции: " .. tostring(compileErr))
		return
	end
	local ranOk, runErr = pcall(chunk)
	if not ranOk then
		warn("[" .. SCRIPT_TITLE .. "] Ошибка выполнения: " .. tostring(runErr))
	end
end

local attempting = false

local function attempt(key)
	if attempting or #key == 0 then
		return
	end
	attempting = true
	setBusy(true)
	status.Text = ""

	local ok, result = requestValidate(key)
	attempting = false
	setBusy(false)

	if ok then
		saveKey(key)
		runSource(result)
		return
	end

	clearSavedKey()
	status.Text = ERROR_TEXT[result] or "Неизвестная ошибка. Попробуйте снова."
end

button.MouseButton1Click:Connect(function()
	attempt(input.Text:gsub("^%s+", ""):gsub("%s+$", ""))
end)

input.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		attempt(input.Text:gsub("^%s+", ""):gsub("%s+$", ""))
	end
end)

-- Auto-try a previously saved key silently; fall back to the prompt on failure.
local saved = loadSavedKey()
if saved then
	input.Text = saved
	attempt(saved)
end
end

local uiOk, uiErr = pcall(buildUI)
if not uiOk then
	warn("[EloHubKeyGate] Не удалось построить окно ключа: " .. tostring(uiErr))
end
