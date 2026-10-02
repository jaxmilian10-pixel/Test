local ServerStorage = game:GetService("ServerStorage")
local ContentProvider = game:GetService("ContentProvider")
local MarketplaceService = game:GetService("MarketplaceService")

local VALIDATE_TIMEOUT = 15
local MAX_CONCURRENT = 8
local AUDIO_ASSET_TYPE = Enum.AssetType.Audio.Value

local function GetOrCreateFolder(parent, name)
	local folder = parent:FindFirstChild(name)

	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end

	return folder
end

local Storage = GetOrCreateFolder(GetOrCreateFolder(ServerStorage, "Assets"), "AudioStorage")
local TempStorage = GetOrCreateFolder(ServerStorage, "TempStorage")

local Toolbar = plugin:CreateToolbar("Meu Plugin")
local OpenButton = Toolbar:CreateButton("Abrir", "Abre o plugin", "")

local WidgetInfo = DockWidgetPluginGuiInfo.new(
	Enum.InitialDockState.Float,
	false,
	false,
	300,
	400,
	200,
	300
)

local Widget = plugin:CreateDockWidgetPluginGui("MeuPluginWidget", WidgetInfo)
Widget.Title = "Meu Plugin"

local Main = script:WaitForChild("Main")
Main.Parent = Widget

local Status = Main.Status
local Actions = Main.Actions

-- Input: lista de IDs no formato "id,id,id" (também aceita espaços, ";", quebras de linha e rbxassetid://).
-- Input2: texto copiado do Gerenciador de Ativos (Nome, ID, Tipo, Modificado, Criador).
local IdInput = Main:FindFirstChild("Input")
local InfoInput = Main:FindFirstChild("Input2")

local AddedCount = 0
local InvalidCount = 0
local SkippedCount = 0

local Queue = {}
local Queued = {}
local ActiveWorkers = 0

local function SetLabel(name, text)
	local label = Status:FindFirstChild(name)

	if label then
		label.Text = text
	end
end

local function UpdateStatus()
	SetLabel("Total", ("Total: %d"):format(#Storage:GetChildren()))
	SetLabel("Added", ("Added: %d"):format(AddedCount))
	SetLabel("Invalid", ("Invalid: %d"):format(InvalidCount))
	SetLabel("Skipped", ("Skipped: %d"):format(SkippedCount))
	SetLabel("Pending", ("Pending: %d"):format(#Queue + ActiveWorkers))
end

local function Trim(text)
	return text:match("^%s*(.-)%s*$")
end

--------------------------------------------------------------------------------
-- Parsing
--------------------------------------------------------------------------------

-- Aceita "123,456, 789", um por linha, separados por ";" ou espaço,
-- e também "rbxassetid://123" ou links da Creator Store.
local function ParseIdList(text)
	local entries = {}
	local seen = {}
	local rejected = {}

	for token in text:gmatch("[^,;%s]+") do
		local id = tonumber(token:match("%d+"))

		if not id or id <= 0 then
			table.insert(rejected, token)
		elseif not seen[id] then
			seen[id] = true
			table.insert(entries, { Id = id })
		end
	end

	return entries, rejected
end

-- Divide uma linha CSV respeitando campos entre aspas ("Nome, com vírgula").
local function SplitCsvLine(line)
	local fields = {}
	local current = {}
	local inQuotes = false
	local i = 1

	while i <= #line do
		local char = line:sub(i, i)

		if inQuotes then
			if char == '"' then
				if line:sub(i + 1, i + 1) == '"' then
					table.insert(current, '"')
					i += 1
				else
					inQuotes = false
				end
			else
				table.insert(current, char)
			end
		elseif char == '"' then
			inQuotes = true
		elseif char == "," then
			table.insert(fields, Trim(table.concat(current)))
			current = {}
		else
			table.insert(current, char)
		end

		i += 1
	end

	table.insert(fields, Trim(table.concat(current)))

	return fields
end

local function IsAudioType(assetType)
	local lower = assetType:lower()
	return lower == "audio" or lower == "áudio"
end

-- Formato esperado: Nome, ID do ativo, Tipo, Modificado, Criador.
-- Se o nome ou o criador tiverem vírgulas sem aspas, localiza a coluna do ID
-- procurando um número seguido do tipo "Audio".
local function ParseInfoLine(line)
	local fields = SplitCsvLine(line)

	if #fields < 5 then
		return
	end

	local idIndex = 2

	if #fields > 5 then
		idIndex = nil

		for i = 2, #fields - 3 do
			if tonumber(fields[i]) and IsAudioType(fields[i + 1]) then
				idIndex = i
				break
			end
		end

		if not idIndex then
			return
		end
	end

	local assetId = tonumber(fields[idIndex])

	if not assetId or not IsAudioType(fields[idIndex + 1]) then
		return
	end

	return {
		Id = assetId,
		Name = table.concat(fields, ",", 1, idIndex - 1),
		Modified = fields[idIndex + 2],
		Creator = table.concat(fields, ",", idIndex + 3),
	}
end

local function ParseInfoText(text)
	local entries = {}
	local seen = {}
	local rejected = {}

	for line in text:gmatch("[^\r\n]+") do
		if Trim(line) ~= "" then
			local entry = ParseInfoLine(line)

			if not entry then
				table.insert(rejected, line)
			elseif not seen[entry.Id] then
				seen[entry.Id] = true
				table.insert(entries, entry)
			end
		end
	end

	return entries, rejected
end

--------------------------------------------------------------------------------
-- Validação
--------------------------------------------------------------------------------

-- Preenche Nome/Criador/Modificado pela API quando a entrada só tem o ID.
-- Retorna false se o ativo existe mas não é um áudio.
local function FillInfo(entry)
	local ok, info = pcall(MarketplaceService.GetProductInfo, MarketplaceService, entry.Id, Enum.InfoType.Asset)

	if not ok or type(info) ~= "table" then
		return true
	end

	if info.AssetTypeId and info.AssetTypeId ~= AUDIO_ASSET_TYPE then
		return false
	end

	entry.Name = entry.Name or info.Name
	entry.Modified = entry.Modified or info.Updated or info.Created
	entry.Creator = entry.Creator or (info.Creator and info.Creator.Name)

	return true
end

local function ValidateAudio(id)
	local sound = Instance.new("Sound")
	sound.SoundId = ("rbxassetid://%d"):format(id)
	sound.Volume = 0
	sound.Parent = TempStorage

	local failed = false

	task.spawn(function()
		pcall(ContentProvider.PreloadAsync, ContentProvider, { sound }, function(_, fetchStatus)
			if fetchStatus == Enum.AssetFetchStatus.Failure then
				failed = true
			end
		end)
	end)

	pcall(sound.Play, sound)

	local deadline = os.clock() + VALIDATE_TIMEOUT

	while sound.TimeLength <= 0 and not failed and os.clock() < deadline do
		task.wait()
	end

	local valid = sound.TimeLength > 0

	sound:Destroy()

	return valid
end

--------------------------------------------------------------------------------
-- Importação
--------------------------------------------------------------------------------

local function CreateAudioFolder(entry)
	local folder = Instance.new("Folder")
	folder.Name = tostring(entry.Id)

	folder:SetAttribute("Name", entry.Name or "")
	folder:SetAttribute("Created", entry.Modified or "")
	folder:SetAttribute("Creator", entry.Creator or "")

	folder.Parent = Storage

	return folder
end

local function MarkInvalid(entry, reason)
	InvalidCount += 1
	warn(("[Inválido] %d %s (%s)"):format(entry.Id, entry.Name or "", reason))
end

local function ProcessEntry(entry)
	if Storage:FindFirstChild(tostring(entry.Id)) then
		SkippedCount += 1
		return
	end

	if not entry.Name and not FillInfo(entry) then
		MarkInvalid(entry, "não é um áudio")
		return
	end

	if not ValidateAudio(entry.Id) then
		MarkInvalid(entry, "não carregou")
		return
	end

	-- Outro processo pode ter criado a pasta enquanto validávamos.
	if Storage:FindFirstChild(tostring(entry.Id)) then
		SkippedCount += 1
		return
	end

	CreateAudioFolder(entry)
	AddedCount += 1
	print("[Importado]", entry.Id, entry.Name)
end

local function Worker()
	ActiveWorkers += 1

	while #Queue > 0 do
		local entry = table.remove(Queue, 1)
		local ok, err = pcall(ProcessEntry, entry)

		if not ok then
			InvalidCount += 1
			warn("[Erro]", entry.Id, err)
		end

		Queued[entry.Id] = nil
		UpdateStatus()
	end

	ActiveWorkers -= 1
	UpdateStatus()
end

local function Enqueue(entries)
	local count = 0

	for _, entry in entries do
		if Queued[entry.Id] or Storage:FindFirstChild(tostring(entry.Id)) then
			SkippedCount += 1
		else
			Queued[entry.Id] = true
			table.insert(Queue, entry)
			count += 1
		end
	end

	while ActiveWorkers < MAX_CONCURRENT and #Queue > 0 do
		task.spawn(Worker)
	end

	UpdateStatus()

	return count
end

local function Submit(textBox, parser, label)
	local text = textBox.Text

	if Trim(text) == "" then
		return
	end

	local entries, rejected = parser(text)

	for _, value in rejected do
		warn(("[%s] Ignorado: %s"):format(label, value))
	end

	if #entries == 0 then
		warn(("[%s] Nenhum áudio encontrado no texto informado."):format(label))
		return
	end

	local count = Enqueue(entries)
	print(("[%s] %d na fila, %d já existentes/duplicados."):format(label, count, #entries - count))

	textBox.Text = ""
end

local function ResetCounters()
	AddedCount = 0
	InvalidCount = 0
	SkippedCount = 0
	UpdateStatus()
end

--------------------------------------------------------------------------------
-- Conexões
--------------------------------------------------------------------------------

if IdInput then
	IdInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			Submit(IdInput, ParseIdList, "IDs")
		end
	end)
end

if InfoInput then
	InfoInput.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			Submit(InfoInput, ParseInfoText, "Info")
		end
	end)
end

Storage.ChildAdded:Connect(UpdateStatus)
Storage.ChildRemoved:Connect(UpdateStatus)

Widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	OpenButton:SetActive(Widget.Enabled)
end)

Actions.Refresh.MouseButton1Click:Connect(ResetCounters)

OpenButton.Click:Connect(function()
	Widget.Enabled = not Widget.Enabled
end)

plugin.Unloading:Connect(function()
	table.clear(Queue)
	TempStorage:ClearAllChildren()
end)

UpdateStatus()
