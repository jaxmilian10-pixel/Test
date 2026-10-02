-- Nametag collection: preview a style first, then explicitly equip or purchase it.
local RS=game:GetService("ReplicatedStorage")
local Player=game:GetService("Players").LocalPlayer
local UI=script:FindFirstAncestor("UI")
local Deps=require(UI.Deps)
local Button=require(UI.Kit.Button)
local Widgets=require(UI.Components.Widgets)
local CommerceActions=require(UI.Components.CommerceActions)
local Commerce=require(RS.Shared.Catalog.CommerceCatalog)
local Styles=require(RS.Shared.Config.NametagStyles)
local Fusion,Theme,Data=Deps.Fusion,Deps.Theme,Deps.Data
local Children,peek=Fusion.Children,Fusion.peek
local App={Label="Nametag",Hidden=true,Width=520,MinWidth=360,HeightScale=1.2}
local PREVIEW_FONT=Font.new("rbxasset://fonts/families/FredokaOne.json")
local HELP={Level="Earned through levels. Choose any unlocked milestone.",Name="Preview a color, then buy or equip it."}

local function observe(scope,accessor,default)
 local value=scope:Value(default)
 table.insert(scope,(accessor.Observe(function(v) value:set(if v==nil then default else v) end)))
 return value
end

-- TextLabel with the shared defaults; anything in props overrides them.
local function label(scope,props)
 local p={BackgroundTransparency=1,TextSize=14,TextColor3=Theme.Color.BaseContent,TextTruncate=Enum.TextTruncate.AtEnd}
 for k,v in props do p[k]=v end
 p.FontFace=p.FontFace or Widgets.font(scope,"Body")
 p.Size=p.Size or UDim2.new(1,0,0,p.TextSize+Theme.Space.XS)
 return scope:New("TextLabel")(p)
end

-- Transparent frame that lays its items out in a padded, width-filling list.
local function stack(scope,props,items,direction)
 props.BackgroundTransparency=1
 props[Children]={scope:New "UIListLayout" {FillDirection=direction or Enum.FillDirection.Vertical,HorizontalFlex=Enum.UIFlexAlignment.Fill,Padding=UDim.new(0,Theme.Space.S),SortOrder=Enum.SortOrder.LayoutOrder},items}
 return scope:New("Frame")(props)
end

-- PrimaryContent while `active` is true, `idle` otherwise.
local function tint(scope,active,idle)
 return scope:Computed(function(use) return use(if use(active) then Theme.Color.PrimaryContent else idle) end)
end

local function page(scope)
 local renderer=Deps.controller("TagController")
 local alive=true
 local busy,feedback,slot,perks=scope:Value(false),scope:Value(""),scope:Value("Level"),scope:Value({})
 local level=observe(scope,Data.Stats.Level,0)
 local owned=observe(scope,Data.Nametag.Owned,{})
 local equipped={Name=observe(scope,Data.Nametag.Name,"Default"),Level=observe(scope,Data.Nametag.Level,"Auto")}
 local selected={Name=scope:Value(peek(equipped.Name)),Level=scope:Value(peek(equipped.Level))}
 for _,e in Commerce.List do
  if e.Kind~="Nametags" then continue end
  table.insert(scope,(Data.ObserveOwned(e.Key,function(on)
   if not alive then return end
   local set=table.clone(peek(perks))
   set[e.Id]=on==true
   perks:set(set)
  end)))
 end

 local function available(use,id)
  local def=Styles.Items[id]
  if def.Free then return true end
  if def.RequiredLevel then return use(level)>=def.RequiredLevel end
  local set=use(owned)
  return set[id]==true or table.find(set,id)~=nil or use(perks)[id]==true
 end
 local current=scope:Computed(function(use) return use(selected[use(slot)]) end)
 local canUse=scope:Computed(function(use) return available(use,use(current)) end)
 local isEquipped=scope:Computed(function(use) return use(equipped[use(slot)])==use(current) end)

 -- Slot card: switches the edited slot and shows the selected style live, rendered by TagController.
 local function slotCard(targetSlot,order)
  local active=scope:Computed(function(use) return use(slot)==targetSlot end)
  local card=Button(scope,{name=targetSlot.."Slot",text="",fill=true,height=72,layoutOrder=order,primary=active,onActivate=function() slot:set(targetSlot); feedback:set("") end})
  label(scope,{Name="Heading",Parent=card,Text=string.upper(targetSlot).."  ·  EDIT",TextSize=12,Position=UDim2.fromOffset(0,Theme.Space.S),TextColor3=tint(scope,active,Theme.Color.BaseContent)})
  local sample=label(scope,{Name="Preview",Parent=card,TextSize=22,FontFace=PREVIEW_FONT,TextColor3=Color3.new(1,1,1),TextStrokeTransparency=0.45,TextStrokeColor3=Color3.new(),
   Position=UDim2.fromOffset(Theme.Space.S,32),Size=UDim2.new(1,-Theme.Space.S*2,0,30)})
  local stop
  local function restyle()
   if stop then stop(); stop=nil end
   sample.FontFace=PREVIEW_FONT
   sample.Text=if targetSlot=="Level" then `Lv. {peek(level)}` else Player.DisplayName
   stop=renderer.StyleNametag(sample,targetSlot,peek(selected[targetSlot]),peek(level),Player)
  end
  scope:Observer(selected[targetSlot]):onChange(restyle)
  scope:Observer(level):onChange(restyle)
  restyle()
  table.insert(scope,function() if stop then stop() end end)
  return card
 end

 local tiles=scope:ForPairs(scope:Computed(function(use) return Styles.SlotIds[use(slot)] end),function(_,inner,index,id)
  local def,sales=Styles.Items[id],(Commerce.Get("Nametags",id) or {}).Sales
  local active=inner:Computed(function(use) return use(current)==id end)
  local tile=Button(inner,{name="Style_"..id,text="",width=0,height=76,layoutOrder=index,primary=active,onActivate=function() selected[peek(slot)]:set(id); feedback:set("") end})
  label(inner,{Name="Name",Parent=tile,Text=def.Name,Position=UDim2.fromOffset(Theme.Space.S,Theme.Space.S),Size=UDim2.new(1,-Theme.Space.S*2,0,22),TextColor3=tint(inner,active,Theme.Color.BaseContent)})
  inner:New "Frame" {Name="Swatch",Parent=tile,Position=UDim2.fromOffset(Theme.Space.M,40),Size=UDim2.fromOffset(16,16),BackgroundColor3=def.Color or Color3.new(1,1,1),
   [Children]={inner:New "UICorner" {CornerRadius=UDim.new(1,0)},inner:New "UIStroke" {Color=Theme.Color.NeutralStroke}}}
  label(inner,{Name="State",Parent=tile,TextSize=12,TextXAlignment=Enum.TextXAlignment.Left,Position=UDim2.fromOffset(Theme.Space.M+24,38),Size=UDim2.new(1,-Theme.Space.M*2-24,0,22),
   TextColor3=tint(inner,active,Theme.Color.NeutralContentDark),Text=inner:Computed(function(use)
    if use(equipped[use(slot)])==id then return "Equipped" end
    if available(use,id) then return "Available" end
    if def.RequiredLevel then return `Level {def.RequiredLevel}` end
    if sales and sales.Status then return `{sales.Status.Amount} {sales.Status.Label}` end
    return if sales and (sales.ProductId or sales.PassId) then "Robux" else "Locked"
   end)})
  return index,tile
 end)
 local S=Theme.Space.S
 local collection=scope:New "ScrollingFrame" {
  Name="Collection",LayoutOrder=2,BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.new(1,0,0,150),
  AutomaticCanvasSize=Enum.AutomaticSize.Y,CanvasSize=UDim2.new(),ScrollingDirection=Enum.ScrollingDirection.Y,
  ScrollBarThickness=3,ScrollBarImageColor3=Theme.Color.NeutralContent,ScrollBarImageTransparency=0.3,
  [Children]={
   scope:New "UIFlexItem" {FlexMode=Enum.UIFlexMode.Fill},
   scope:New "UIPadding" {PaddingTop=UDim.new(0,S),PaddingBottom=UDim.new(0,S),PaddingLeft=UDim.new(0,Theme.Space.XS),PaddingRight=UDim.new(0,S)},
   scope:New "UIGridLayout" {CellSize=UDim2.new(0.5,-S/2,0,76),CellPadding=UDim2.fromOffset(S,S),SortOrder=Enum.SortOrder.LayoutOrder},
   tiles,
  },
 }
 scope:Observer(slot):onChange(function() collection.CanvasPosition=Vector2.zero end)

 local equip=Button(scope,{
  name="Equip",primary=true,width=0,layoutOrder=1,loading=busy,
  text=scope:Computed(function(use) return if use(isEquipped) then "Equipped" elseif not use(canUse) then "Locked" else `Equip {use(slot)} style` end),
  interactable=scope:Computed(function(use) return use(canUse) and not use(isEquipped) and not use(busy) end),
  visible=scope:Computed(function(use) return use(canUse) or use(slot)=="Level" end),
  onActivate=function()
   if peek(busy) then return end
   local targetSlot,id=peek(slot),peek(current)
   busy:set(true); feedback:set("")
   task.spawn(function()
    local ok,done,why=pcall(Data.Request,"EquipNametag",targetSlot,id)
    if not alive then return end
    busy:set(false)
    if not (ok and done) then feedback:set(if ok then tostring(why or "Try again") else "Try again in a moment") end
   end)
  end,
 })
 equip.Size=UDim2.new(1,0,0,Theme.Size.Control)

 table.insert(scope,function() alive=false end)
 return stack(scope,{Name="NametagPage",Size=UDim2.fromScale(1,1)},{
  stack(scope,{Name="Preview",Size=UDim2.new(1,0,0,72)},{slotCard("Level",0),slotCard("Name",1)},Enum.FillDirection.Horizontal),
  label(scope,{Name="Help",LayoutOrder=1,TextXAlignment=Enum.TextXAlignment.Left,Text=scope:Computed(function(use) return HELP[use(slot)] end)}),
  collection,
  stack(scope,{Name="Details",LayoutOrder=3,AutomaticSize=Enum.AutomaticSize.Y,Size=UDim2.new(1,0,0,0)},{
   label(scope,{Name="Selection",TextXAlignment=Enum.TextXAlignment.Left,Text=scope:Computed(function(use)
    if use(feedback)~="" then return use(feedback) end
    local id=use(current)
    local def=Styles.Items[id]
    if def.RequiredLevel and not available(use,id) then return `{def.RequiredLevel-use(level)} more levels to unlock · Preview only` end
    return def.Name..(if use(isEquipped) then " · Equipped" else " · Preview")
   end)}),
   equip,
   CommerceActions(scope,{
    entry=scope:Computed(function(use) return Commerce.Get("Nametags",use(current)) end),owned=canUse,layoutOrder=2,
    purchaseHint="Equip it here in Nametag > Name after buying.",
    onBought=function() if alive then feedback:set("Unlocked! Select Equip to apply.") end end,
   }),
  }),
 })
end

function App.Build()
 return {title="Nametag",tabs={{label="Customize",build=page}}}
end

return App
