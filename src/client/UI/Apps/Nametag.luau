-- Nametag collection: preview a style first, then explicitly equip or purchase it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local UI = script:FindFirstAncestor("UI")
local Deps = require(UI.Deps)
local Button = require(UI.Kit.Button)
local Widgets = require(UI.Components.Widgets)
local CommerceActions = require(UI.Components.CommerceActions)
local Commerce = require(ReplicatedStorage.Shared.Catalog.CommerceCatalog)
local Styles = require(ReplicatedStorage.Shared.Config.NametagStyles)

local Fusion, Theme, Data = Deps.Fusion, Deps.Theme, Deps.Data
local Children, peek = Fusion.Children, Fusion.peek
local Space = Theme.Space
local Player = Players.LocalPlayer

local PREVIEW_FONT = Font.new("rbxasset://fonts/families/FredokaOne.json")
local HELP = {
	Level = "Earned through levels. Choose any unlocked milestone.",
	Name = "Preview a color, then buy or equip it.",
}

local App = { Label = "Nametag", Hidden = true, Width = 520, MinWidth = 360, HeightScale = 1.2 }

-- Helpers ---------------------------------------------------------------------

-- Mirrors a Data accessor into a Fusion Value; nil falls back to `default`.
local function observe(scope, accessor, default)
	local value = scope:Value(default)
	table.insert(scope, (accessor.Observe(function(new)
		value:set(if new == nil then default else new)
	end)))
	return value
end

-- TextLabel with the shared defaults; anything in `props` overrides them.
local function label(scope, props)
	local merged = {
		BackgroundTransparency = 1,
		TextSize = 14,
		TextColor3 = Theme.Color.BaseContent,
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for key, value in props do
		merged[key] = value
	end
	merged.FontFace = merged.FontFace or Widgets.font(scope, "Body")
	merged.Size = merged.Size or UDim2.new(1, 0, 0, merged.TextSize + Space.XS)
	return scope:New("TextLabel")(merged)
end

-- Transparent frame that lays its items out in a padded, width-filling list.
local function stack(scope, direction, props, items)
	props.BackgroundTransparency = 1
	props[Children] = {
		scope:New "UIListLayout" {
			FillDirection = direction,
			HorizontalFlex = Enum.UIFlexAlignment.Fill,
			Padding = UDim.new(0, Space.S),
			SortOrder = Enum.SortOrder.LayoutOrder,
		},
		items,
	}
	return scope:New("Frame")(props)
end

-- Text colour that switches to PrimaryContent while `active` is true.
local function tint(scope, active, idle)
	return scope:Computed(function(use)
		return use(if use(active) then Theme.Color.PrimaryContent else idle)
	end)
end

-- Page ------------------------------------------------------------------------

local function page(scope)
	local renderer = Deps.controller("TagController")
	local alive = true

	-- State

	local busy = scope:Value(false)
	local feedback = scope:Value("")
	local slot = scope:Value("Level")
	local perks = scope:Value({})
	local level = observe(scope, Data.Stats.Level, 0)
	local owned = observe(scope, Data.Nametag.Owned, {})
	local equipped = {
		Name = observe(scope, Data.Nametag.Name, "Default"),
		Level = observe(scope, Data.Nametag.Level, "Auto"),
	}
	local selected = {
		Name = scope:Value(peek(equipped.Name)),
		Level = scope:Value(peek(equipped.Level)),
	}

	for _, item in Commerce.List do
		if item.Kind ~= "Nametags" then
			continue
		end
		table.insert(scope, (Data.ObserveOwned(item.Key, function(isOwned)
			if not alive then
				return
			end
			local updated = table.clone(peek(perks))
			updated[item.Id] = isOwned == true
			perks:set(updated)
		end)))
	end

	local function isAvailable(use, id)
		local def = Styles.Items[id]
		if def.Free then
			return true
		elseif def.RequiredLevel then
			return use(level) >= def.RequiredLevel
		end
		local ownedIds = use(owned)
		return ownedIds[id] == true or table.find(ownedIds, id) ~= nil or use(perks)[id] == true
	end

	local current = scope:Computed(function(use)
		return use(selected[use(slot)])
	end)
	local canUse = scope:Computed(function(use)
		return isAvailable(use, use(current))
	end)
	local isEquipped = scope:Computed(function(use)
		return use(equipped[use(slot)]) == use(current)
	end)

	-- Slot cards: pick the slot being edited and show its style live

	local function slotCard(targetSlot, order)
		local active = scope:Computed(function(use)
			return use(slot) == targetSlot
		end)

		local card = Button(scope, {
			name = targetSlot .. "Slot",
			text = "",
			fill = true,
			height = 72,
			layoutOrder = order,
			primary = active,
			onActivate = function()
				slot:set(targetSlot)
				feedback:set("")
			end,
		})

		label(scope, {
			Name = "Heading",
			Parent = card,
			Text = `{string.upper(targetSlot)}  ·  EDIT`,
			TextSize = 12,
			TextColor3 = tint(scope, active, Theme.Color.BaseContent),
			Position = UDim2.fromOffset(0, Space.S),
		})

		local sample = label(scope, {
			Name = "Preview",
			Parent = card,
			FontFace = PREVIEW_FONT,
			TextSize = 22,
			TextColor3 = Color3.new(1, 1, 1),
			TextStrokeColor3 = Color3.new(0, 0, 0),
			TextStrokeTransparency = 0.45,
			Position = UDim2.fromOffset(Space.S, 32),
			Size = UDim2.new(1, -Space.S * 2, 0, 30),
		})

		-- TagController styles the label directly, so undo the previous style before applying the next.
		local unstyle
		local function restyle()
			if unstyle then
				unstyle()
				unstyle = nil
			end
			sample.FontFace = PREVIEW_FONT
			sample.Text = if targetSlot == "Level" then `Lv. {peek(level)}` else Player.DisplayName
			unstyle = renderer.StyleNametag(sample, targetSlot, peek(selected[targetSlot]), peek(level), Player)
		end

		scope:Observer(selected[targetSlot]):onChange(restyle)
		scope:Observer(level):onChange(restyle)
		restyle()
		table.insert(scope, function()
			if unstyle then
				unstyle()
			end
		end)

		return card
	end

	-- Style tiles: name, colour swatch and availability of every style in the slot

	local function styleTile(inner, index, id)
		local def = Styles.Items[id]
		local sales = (Commerce.Get("Nametags", id) or {}).Sales
		local active = inner:Computed(function(use)
			return use(current) == id
		end)

		local tile = Button(inner, {
			name = "Style_" .. id,
			text = "",
			width = 0,
			height = 76,
			layoutOrder = index,
			primary = active,
			onActivate = function()
				selected[peek(slot)]:set(id)
				feedback:set("")
			end,
		})

		label(inner, {
			Name = "Name",
			Parent = tile,
			Text = def.Name,
			TextColor3 = tint(inner, active, Theme.Color.BaseContent),
			Position = UDim2.fromOffset(Space.S, Space.S),
			Size = UDim2.new(1, -Space.S * 2, 0, 22),
		})

		inner:New "Frame" {
			Name = "Swatch",
			Parent = tile,
			BackgroundColor3 = def.Color or Color3.new(1, 1, 1),
			Position = UDim2.fromOffset(Space.M, 40),
			Size = UDim2.fromOffset(16, 16),
			[Children] = {
				inner:New "UICorner" { CornerRadius = UDim.new(1, 0) },
				inner:New "UIStroke" { Color = Theme.Color.NeutralStroke },
			},
		}

		label(inner, {
			Name = "State",
			Parent = tile,
			TextSize = 12,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = tint(inner, active, Theme.Color.NeutralContentDark),
			Position = UDim2.fromOffset(Space.M + 24, 38),
			Size = UDim2.new(1, -Space.M * 2 - 24, 0, 22),
			Text = inner:Computed(function(use)
				if use(equipped[use(slot)]) == id then
					return "Equipped"
				elseif isAvailable(use, id) then
					return "Available"
				elseif def.RequiredLevel then
					return `Level {def.RequiredLevel}`
				elseif sales and sales.Status then
					return `{sales.Status.Amount} {sales.Status.Label}`
				elseif sales and (sales.ProductId or sales.PassId) then
					return "Robux"
				end
				return "Locked"
			end),
		})

		return tile
	end

	local slotIds = scope:Computed(function(use)
		return Styles.SlotIds[use(slot)]
	end)

	local collection = scope:New "ScrollingFrame" {
		Name = "Collection",
		LayoutOrder = 2,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 150),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = Theme.Color.NeutralContent,
		ScrollBarImageTransparency = 0.3,

		[Children] = {
			scope:New "UIFlexItem" { FlexMode = Enum.UIFlexMode.Fill },
			scope:New "UIPadding" {
				PaddingTop = UDim.new(0, Space.S),
				PaddingBottom = UDim.new(0, Space.S),
				PaddingLeft = UDim.new(0, Space.XS),
				PaddingRight = UDim.new(0, Space.S),
			},
			scope:New "UIGridLayout" {
				CellSize = UDim2.new(0.5, -Space.S / 2, 0, 76),
				CellPadding = UDim2.fromOffset(Space.S, Space.S),
				SortOrder = Enum.SortOrder.LayoutOrder,
			},
			scope:ForPairs(slotIds, function(_, inner, index, id)
				return index, styleTile(inner, index, id)
			end),
		},
	}

	scope:Observer(slot):onChange(function()
		collection.CanvasPosition = Vector2.zero
	end)

	-- Details: what is selected, plus equip / purchase actions

	local selectionText = scope:Computed(function(use)
		if use(feedback) ~= "" then
			return use(feedback)
		end
		local id = use(current)
		local def = Styles.Items[id]
		if def.RequiredLevel and not isAvailable(use, id) then
			return `{def.RequiredLevel - use(level)} more levels to unlock · Preview only`
		end
		return `{def.Name} · {if use(isEquipped) then "Equipped" else "Preview"}`
	end)

	local function equipSelected()
		if peek(busy) then
			return
		end
		local targetSlot, id = peek(slot), peek(current)
		busy:set(true)
		feedback:set("")

		task.spawn(function()
			local ok, done, reason = pcall(Data.Request, "EquipNametag", targetSlot, id)
			if not alive then
				return
			end
			busy:set(false)
			if not ok then
				feedback:set("Try again in a moment")
			elseif not done then
				feedback:set(tostring(reason or "Try again"))
			end
		end)
	end

	local equip = Button(scope, {
		name = "Equip",
		primary = true,
		width = 0,
		layoutOrder = 1,
		loading = busy,
		text = scope:Computed(function(use)
			if use(isEquipped) then
				return "Equipped"
			elseif not use(canUse) then
				return "Locked"
			end
			return `Equip {use(slot)} style`
		end),
		interactable = scope:Computed(function(use)
			return use(canUse) and not use(isEquipped) and not use(busy)
		end),
		visible = scope:Computed(function(use)
			return use(canUse) or use(slot) == "Level"
		end),
		onActivate = equipSelected,
	})
	equip.Size = UDim2.new(1, 0, 0, Theme.Size.Control)

	-- Layout

	table.insert(scope, function()
		alive = false
	end)

	local Row, Column = Enum.FillDirection.Horizontal, Enum.FillDirection.Vertical

	return stack(scope, Column, { Name = "NametagPage", Size = UDim2.fromScale(1, 1) }, {
		stack(scope, Row, { Name = "Preview", Size = UDim2.new(1, 0, 0, 72) }, {
			slotCard("Level", 0),
			slotCard("Name", 1),
		}),

		label(scope, {
			Name = "Help",
			LayoutOrder = 1,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = scope:Computed(function(use)
				return HELP[use(slot)]
			end),
		}),

		collection,

		stack(scope, Column, {
			Name = "Details",
			LayoutOrder = 3,
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
		}, {
			label(scope, {
				Name = "Selection",
				TextXAlignment = Enum.TextXAlignment.Left,
				Text = selectionText,
			}),
			equip,
			CommerceActions(scope, {
				entry = scope:Computed(function(use)
					return Commerce.Get("Nametags", use(current))
				end),
				owned = canUse,
				layoutOrder = 2,
				purchaseHint = "Equip it here in Nametag > Name after buying.",
				onBought = function()
					if alive then
						feedback:set("Unlocked! Select Equip to apply.")
					end
				end,
			}),
		}),
	})
end

function App.Build()
	return { title = "Nametag", tabs = { { label = "Customize", build = page } } }
end

return App
