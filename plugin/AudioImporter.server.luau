local ServerStorage = game:GetService("ServerStorage")

local VALIDATE_TIMEOUT = 15
local MAX_CONCURRENT = 8

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
local Input = Main.Input2

-- A entrada por ID foi removida; esconde a caixa antiga se ela ainda existir na UI.
local LegacyInput = Main:FindFirstChild("Input")
if LegacyInput then
	LegacyInput.Visible = false
end

local AddedCount = 0
local InvalidCount = 0

local Processing = {}
local Running = 0

local function UpdateStatus()
	Status.Total.Text = ("Total: %d"):format(#Storage:GetChildren())
	Status.Added.Text = ("Added: %d"):format(AddedCount)
	Status.Invalid.Text = ("Invalid: %d"):format(InvalidCount)
end

local function Trim(text)
	return text:match("^%s*(.-)%s*$")
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
local function ParseLine(line)
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
	local assetType = fields[idIndex + 1]

	if not assetId or not IsAudioType(assetType) then
		return
	end

	return {
		Id = assetId,
		Name = table.concat(fields, ",", 1, idIndex - 1),
		Modified = fields[idIndex + 2],
		Creator = table.concat(fields, ",", idIndex + 3),
	}
end

local function ParseAssetManagerText(text)
	local entries = {}
	local seen = {}

	for line in text:gmatch("[^\r\n]+") do
		local entry = ParseLine(line)

		if entry and not seen[entry.Id] then
			seen[entry.Id] = true
			table.insert(entries, entry)
		end
	end

	return entries
end

local function ValidateAudio(id)
	local sound = Instance.new("Sound")
	sound.SoundId = ("rbxassetid://%d"):format(id)
	sound.Volume = 0
	sound.Parent = TempStorage

	pcall(function()
		sound:Play()
	end)

	local deadline = os.clock() + VALIDATE_TIMEOUT

	while sound.TimeLength <= 0 and os.clock() < deadline do
		task.wait()
	end

	local valid = sound.TimeLength > 0

	sound:Destroy()

	return valid
end

local function CreateAudioFolder(entry)
	local folder = Instance.new("Folder")
	folder.Name = tostring(entry.Id)

	folder:SetAttribute("Name", entry.Name)
	folder:SetAttribute("Created", entry.Modified)
	folder:SetAttribute("Creator", entry.Creator)

	folder.Parent = Storage

	return folder
end

local function ProcessEntry(entry)
	local id = entry.Id

	if Processing[id] or Storage:FindFirstChild(tostring(id)) then
		return
	end

	Processing[id] = true

	while Running >= MAX_CONCURRENT do
		task.wait()
	end

	Running += 1

	local success, err = pcall(function()
		if not ValidateAudio(id) then
			InvalidCount += 1
			UpdateStatus()
			warn("[Inválido]", id, entry.Name)
			return
		end

		CreateAudioFolder(entry)
		print("[Importado]", id, entry.Name)
	end)

	if not success then
		warn("[Erro]", id, err)
	end

	Running -= 1
	Processing[id] = nil
end

local function OnInputFocusLost(enterPressed)
	if not enterPressed then
		return
	end

	local entries = ParseAssetManagerText(Input.Text)

	if #entries == 0 then
		warn("Nenhum áudio encontrado no texto informado.")
		return
	end

	for _, entry in entries do
		task.spawn(ProcessEntry, entry)
	end

	Input.Text = ""
end

local function RefreshCounters()
	AddedCount = 0
	InvalidCount = 0
	UpdateStatus()
end

local function ToggleWidget()
	Widget.Enabled = not Widget.Enabled
end

Storage.ChildAdded:Connect(function()
	AddedCount += 1
	UpdateStatus()
end)

Storage.ChildRemoved:Connect(UpdateStatus)

Widget:GetPropertyChangedSignal("Enabled"):Connect(function()
	OpenButton:SetActive(Widget.Enabled)
end)

Actions.Refresh.MouseButton1Click:Connect(RefreshCounters)
OpenButton.Click:Connect(ToggleWidget)
Input.FocusLost:Connect(OnInputFocusLost)

UpdateStatus()
