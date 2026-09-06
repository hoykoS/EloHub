local SCRIPT_SLUG = "elohub"
local SCRIPT_TITLE = "EloHub"
local KEY_FILE = "elohub_" .. SCRIPT_SLUG .. "_key.txt"

-- Same repo/branch this loader itself was fetched from — reachable by every
-- executor (including mobile ones like Delta with no working POST/custom
-- HTTP client) because it's the exact same game:HttpGet call and domain
-- already used to load this file.
local MANIFEST_URL = "https://raw.githubusercontent.com/hoykoS/EloHub/main/data/manifest.json"
local PAYLOAD_URL = "https://raw.githubusercontent.com/hoykoS/EloHub/main/data/payload.enc"

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

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
-- Crypto — pure arithmetic (mod/div only, never bit32/bit ops, which behave
-- inconsistently across Luau versions). Mirrored byte-for-byte in the bot's
-- bot/services/roblox_crypto.py; do not change one without the other.
-- --------------------------------------------------------------------------
local CRYPTO_M = 16777216
local CRYPTO_LCG_A = 1103
local CRYPTO_LCG_C = 12345
local CRYPTO_HASH_MULT = 131

local function seedFromBytes(bytes)
	local seed = 0
	for i = 1, #bytes do
		seed = (seed * CRYPTO_HASH_MULT + bytes[i]) % CRYPTO_M
	end
	return seed
end

local function seedFromText(text)
	local seed = 0
	for i = 1, #text do
		seed = (seed * CRYPTO_HASH_MULT + string.byte(text, i)) % CRYPTO_M
	end
	return seed
end

local function keystream(seed, length)
	local state = seed
	local out = table.create and table.create(length) or {}
	for i = 1, length do
		state = (state * CRYPTO_LCG_A + CRYPTO_LCG_C) % CRYPTO_M
		out[i] = state % 256
	end
	return out
end

local function byteXor(a, b)
	local result = 0
	local bitval = 1
	while a > 0 or b > 0 do
		local abit = a % 2
		local bbit = b % 2
		if abit ~= bbit then
			result = result + bitval
		end
		a = (a - abit) / 2
		b = (b - bbit) / 2
		bitval = bitval * 2
	end
	return result
end

local function xorBytes(bytes, ks)
	local out = {}
	for i = 1, #bytes do
		out[i] = byteXor(bytes[i], ks[i])
	end
	return out
end

local function stringToBytes(s)
	local bytes = {}
	for i = 1, #s do
		bytes[i] = string.byte(s, i)
	end
	return bytes
end

local function bytesToString(bytes)
	local chars = {}
	for i = 1, #bytes do
		chars[i] = string.char(bytes[i])
	end
	return table.concat(chars)
end

local function hexToBytes(hex)
	local bytes = {}
	for i = 1, #hex, 2 do
		bytes[#bytes + 1] = tonumber(hex:sub(i, i + 1), 16)
	end
	return bytes
end

local function lookupHash(key)
	return string.format("%06x", seedFromText(key))
end

local function watermarkTag(key)
	return string.format("%06x", seedFromText(key .. ":wm"))
end

local function unwrapSecret(wrappedHex, key)
	local wrappedBytes = hexToBytes(wrappedHex)
	local ks = keystream(seedFromText(key), #wrappedBytes)
	return xorBytes(wrappedBytes, ks)
end

local function decryptPayload(payloadHex, secretBytes)
	local cipherBytes = hexToBytes(payloadHex)
	local ks = keystream(seedFromBytes(secretBytes), #cipherBytes)
	return bytesToString(xorBytes(cipherBytes, ks))
end

-- --------------------------------------------------------------------------
-- Local activation check — no live backend call at all: the manifest and
-- encrypted payload are static files fetched with the same game:HttpGet
-- that already loaded this script. A key that isn't in the manifest (never
-- issued, or blocked and removed on the next export) simply can't unwrap
-- anything meaningful.
-- --------------------------------------------------------------------------
local function fetchText(url)
	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if not ok or not body or #body == 0 then
		return nil
	end
	return body
end

local function activate(key)
	local manifestText = fetchText(MANIFEST_URL)
	if not manifestText then
		return false, "network_error"
	end
	local decodeOk, manifest = pcall(function()
		return HttpService:JSONDecode(manifestText)
	end)
	if not decodeOk or type(manifest) ~= "table" then
		return false, "network_error"
	end

	local wrapped = manifest[lookupHash(key)]
	if not wrapped then
		return false, "not_found"
	end

	local payloadHex = fetchText(PAYLOAD_URL)
	if not payloadHex then
		return false, "network_error"
	end

	local ok, source = pcall(function()
		local secretBytes = unwrapSecret(wrapped, key)
		return decryptPayload(payloadHex, secretBytes)
	end)
	if not ok or not source or #source == 0 then
		return false, "bad_response"
	end

	local watermark = string.format('local _EH_TAG = "%s"\n', watermarkTag(key))
	return true, watermark .. source
end

local ERROR_TEXT = {
	not_found = "Ключ не найден. Проверьте и попробуйте снова.",
	network_error = "Нет соединения с сервером. Проверьте интернет и попробуйте снова.",
	bad_response = "Не удалось прочитать данные. Попробуйте снова.",
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
input.TextSize = 14
input.TextColor3 = Color3.fromRGB(235, 235, 240)
input.PlaceholderText = "EH-XXXXXXXXXXXXXXXX"
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

local function setBusy(busy, progressText)
	button.Active = not busy
	input.TextEditable = not busy
	button.Text = busy and (progressText or "Проверка...") or "Активировать"
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

-- GitHub's raw CDN occasionally hiccups; retry a couple of times before
-- showing an error instead of failing on the very first blip.
local RETRY_ATTEMPTS = 3
local RETRY_DELAY_SECONDS = 3

local function attempt(key)
	if attempting or #key == 0 then
		return
	end
	attempting = true
	status.Text = ""

	local ok, result
	for i = 1, RETRY_ATTEMPTS do
		setBusy(true, i > 1 and string.format("Проверка... (%d/%d)", i, RETRY_ATTEMPTS) or nil)
		ok, result = activate(key)
		if ok or result ~= "network_error" then
			break
		end
		if i < RETRY_ATTEMPTS then
			task.wait(RETRY_DELAY_SECONDS)
		end
	end

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
