
local _G = GLOBAL

TUNING.ACTION_QUEUE_DEBUG_MODE = GetModConfigData("debug_mode")

local DebugPrint = TUNING.ACTION_QUEUE_DEBUG_MODE and function(...)
  local msg = "[ActionQueue]"
  for i = 1, arg.n do
    msg = msg.." "..tostring(arg[i])
  end
  print(msg)
end or function() --[[disabled]] end

local SpawnPrefab = _G.SpawnPrefab
local TheInput = _G.TheInput
local unpack = _G.unpack
local CONTROL_ACTION = _G.CONTROL_ACTION
local CONTROL_FORCE_INSPECT = _G.CONTROL_FORCE_INSPECT
local CONTROL_FORCE_TRADE = _G.CONTROL_FORCE_TRADE
local PLAYERCOLOURS
local function RGB(r,g,b,a)
  if a == nil then
    a = 255
  end
  return { r/255, g/255, b/255, a/255 }
end
-- Copy-pasta from DST's constants.lua
PLAYERCOLOURS = {
  WHITE = {1, 1, 1, 1},
  FIREBRICK = RGB(178, 34, 34),
  TAN = RGB(255, 165, 79 ),
  LIGHTGOLD = RGB(255, 236, 139),
  GREEN = RGB(59,  222, 99 ),
  TEAL = RGB(150, 206, 169),
  OTHERBLUE = RGB(113, 125, 194),
  DARKPLUM = RGB(139, 102, 139),
  ROSYBROWN = RGB(255, 193, 193),
  GOLDENROD = RGB(255, 193, 37 )
}

local STRINGS = _G.STRINGS
local ActionQueuer
local ThePlayer
local TheWorld

Assets = {
  Asset("ATLAS", "images/selection_square.xml"),
  Asset("IMAGE", "images/selection_square.tex"),
}

local interrupt_controls = {}
for control = _G.CONTROL_ATTACK, _G.CONTROL_MOVE_RIGHT do
  interrupt_controls[control] = true
end
local mouse_controls = {[_G.CONTROL_PRIMARY] = false, [_G.CONTROL_SECONDARY] = true}

local function GetKeyFromConfig(config)
  local key = GetModConfigData(config, true)
  if type(key) == "string" and _G:rawget(key) then
    key = _G[key]
  end
  return type(key) == "number" and key or -1
end

local function InGame()
  local screen = _G.TheFrontEnd:GetActiveScreen()
  return (screen ~= nil and screen.name:find("HUD") ~= nil and screen.owner ~= nil)
end

local turf_grid = {}
local turf_size = 4
local turf_grid_visible = false
local turf_grid_radius = GetModConfigData("turf_grid_radius")
local turf_grid_color = PLAYERCOLOURS[GetModConfigData("turf_grid_color")]
TheInput:AddKeyUpHandler(GetKeyFromConfig("turf_grid_key"), function()
  if not InGame() then return end
  if turf_grid_visible then
    for _, grid in pairs(turf_grid) do
      grid:Hide()
    end
    turf_grid_visible = false
    return
  end
  local center_x, _, center_z = TheWorld.Map:GetTileCenterPoint(ThePlayer.Transform:GetWorldPosition())
  local radius = turf_grid_radius * turf_size
  local count = 1
  for x = center_x - radius, center_x + radius, turf_size do
    for z = center_z - radius, center_z + radius, turf_size do
      if not turf_grid[count] then
        turf_grid[count] = SpawnPrefab("gridplacer")
        turf_grid[count].AnimState:SetAddColour(unpack(turf_grid_color))
      end
      turf_grid[count].Transform:SetPosition(x, 0, z)
      turf_grid[count]:Show()
      count = count + 1
    end
  end
  turf_grid_visible = true
end)

TheInput:AddKeyUpHandler(GetKeyFromConfig("auto_collect_key"), function()
  if not InGame() then return end
  ActionQueuer.auto_collect = not ActionQueuer.auto_collect
  ThePlayer.components.talker:Say("Auto Collect: "..tostring(ActionQueuer.auto_collect))
end)

TheInput:AddKeyUpHandler(GetKeyFromConfig("endless_deploy_key"), function()
  if not InGame() then return end
  ActionQueuer.endless_deploy = not ActionQueuer.endless_deploy
  ThePlayer.components.talker:Say("Endless deploy: "..tostring(ActionQueuer.endless_deploy))
end)

local last_recipe, last_skin
TheInput:AddKeyUpHandler(GetKeyFromConfig("last_recipe_key"), function()
  if not InGame() then return end
  if not last_recipe then
    ThePlayer.components.talker:Say("No previous recipe found")
    return
  end
  local last_recipe_name = STRINGS.NAMES[last_recipe.name:upper()]
  local builder = ThePlayer.components.builder
  if not builder:CanBuild(last_recipe.name) and not builder:IsBuildBuffered(last_recipe.name) then
    ThePlayer.components.talker:Say("Unable to craft: "..last_recipe_name)
    return
  end
  if last_recipe.placer then
    if not builder:IsBuildBuffered(last_recipe.name) then
      builder:BufferBuild(last_recipe.name)
    end
    ThePlayer.components.playercontroller:StartBuildPlacementMode(last_recipe, last_skin)
  else
    builder:MakeRecipe(last_recipe)
  end
  ThePlayer.components.talker:Say("Crafting last recipe: "..last_recipe_name)
end)

local function ActionQueuerInit()
  print("[ActionQueue] Adding ActionQueuer component")
  ThePlayer:AddComponent("actionqueuer")
  ActionQueuer = ThePlayer.components.actionqueuer
  ActionQueuer.double_click_speed = GetModConfigData("double_click_speed")
  ActionQueuer.double_click_range = GetModConfigData("double_click_range")
  ActionQueuer.deploy_on_grid = GetModConfigData("deploy_on_grid")
  ActionQueuer.auto_collect = GetModConfigData("auto_collect")
  ActionQueuer.endless_deploy = GetModConfigData("endless_deploy")
  ActionQueuer:SetToothTrapSpacing(GetModConfigData("tooth_trap_spacing"))
  local r, g, b = unpack(PLAYERCOLOURS[GetModConfigData("selection_color")])
  ActionQueuer:SetSelectionColor(r, g, b, GetModConfigData("selection_opacity"))
end

local action_queue_key = GetKeyFromConfig("action_queue_key")
--maybe i won't need this one day...
local use_control = TheInput:GetLocalizedControl(0, CONTROL_FORCE_TRADE) == STRINGS.UI.CONTROLSSCREEN.INPUTS[1][action_queue_key]
action_queue_key = use_control and CONTROL_FORCE_TRADE or action_queue_key
TheInput.IsAqModifierDown = use_control and TheInput.IsControlPressed or TheInput.IsKeyDown
local always_clear_queue = GetModConfigData("always_clear_queue")
AddComponentPostInit("playercontroller", function(self, inst)
  if (inst ~= _G.GetPlayer()) then return end
  ThePlayer = _G.GetPlayer()
  TheWorld = _G.GetWorld()
  ActionQueuerInit()
  local should_autofish_fn = function(inst, target)
    local handitem = inst.components.inventory:GetEquippedItem(_G.EQUIPSLOTS.HANDS)
    if not (handitem ~= nil and handitem.prefab == "fishingrod") then return false end
    if not (target
      and (target:HasTag("fishable")
        or (target.components.fishable))
      and target.active ~= false) -- this is used by shoals
    then return false
    end
    -- this is the condition from FISH.strfn to use "retrieve" - don't use autofisher on things like flotsam, watery graves, etc.
    if target and (target.components.workable or target.components.sinkable) then
      return false
    end
    for _, act in ipairs(self.inst.components.playeractionpicker:GetLeftClickActions(target:GetPosition(), target)) do

      if act
          and act.action.id == "FISH" then
        return true
      end
    end
    return false
  end
  local PlayerControllerOnControl = self.OnControl
  self.OnControl = function(self, control, down)
    local mouse_control = mouse_controls[control]
    -- DebugPrint("PCOnControl; control: ", control, ", down: ", down)
    if mouse_control ~= nil then
      if down then
        if TheInput:IsAqModifierDown(action_queue_key) then
          local target = TheInput:GetWorldEntityUnderMouse()
          if should_autofish_fn(inst, target) then
            DebugPrint("PC-OnControl - starting autofisher")
            ActionQueuer:StartAutoFisher(target)
          elseif not ActionQueuer.auto_fishing then
            ActionQueuer:OnDown(mouse_control)
          end
          return
        end
      else
        ActionQueuer:OnUp(mouse_control)
      end
    end
    PlayerControllerOnControl(self, control, down)
    local screen = _G.TheFrontEnd:GetActiveScreen()
    if down and ActionQueuer.action_thread and not ActionQueuer.selection_thread and InGame()
    and (interrupt_controls[control] or mouse_control ~= nil and not TheInput:GetHUDEntityUnderMouse()) then
      DebugPrint("Down handler entered, clearing action thread")
      ActionQueuer:ClearActionThread()
      if always_clear_queue or control == CONTROL_ACTION then
        -- DebugPrint("Down handler - clearing selected entities")
        ActionQueuer:ClearSelectedEntities()
      end
    end
  end
end)

AddClassPostConstruct("components/builder", function(self)
  local BuilderMakeRecipe = self.MakeRecipe
  self.MakeRecipe = function(self, recipe, pt, rot, onsuccess, modifydata)
    last_recipe = recipe
    if not ActionQueuer.action_thread and TheInput:IsAqModifierDown(action_queue_key)
    and not recipe.placer and self:CanBuild(recipe.name) then
      ActionQueuer:RepeatRecipe(self, recipe, skin)
    else
      BuilderMakeRecipe(self, recipe, pt, rot, onsuccess, modifydata)
    end
  end

end)

Highlight = _G.require("components/highlight")
Highlight.UnHighlight = (function()
  local UnHighlight = _G.assert(Highlight.UnHighlight)
  return function(self, ...)
    local p = ThePlayer
    if p and p.components.actionqueuer and p.components.actionqueuer:IsSelectedEntity(self.inst) then
      return
    end
    return UnHighlight(self, ...)
  end
end)()

--for minimizing the memory leak in geo
--hides the geo grid during an action queue
AddComponentPostInit("placer", function(self, inst)
  local PlacerOnUpdate = self.OnUpdate
  self.OnUpdate = function(self, ...)
    self.disabled = ActionQueuer.action_thread ~= nil
    PlacerOnUpdate(self, ...)
  end
end)

AddComponentPostInit("playeractionpicker", function(self, inst)
  self.GetLeftClickActions = function(self,a,b)
    if TheInput:IsControlPressed(CONTROL_FORCE_INSPECT) and ActionQueuer and ActionQueuer.action_thread then
      return self:GetRightClickActions(b,a)
    else
      return self:GetClickActions(b,a)
    end
  end
end
)
AddComponentPostInit("playercontroller", function(self, inst)
  self.IsDoingOrWorking = function()
    if self.inst.sg == nil then
      return self.inst:HasTag("doing")
      or self.inst:HasTag("working")
    end
    return self.inst.sg:HasStateTag("doing")
    or self.inst.sg:HasStateTag("working")
    or self.inst:HasTag("doing")
    or self.inst:HasTag("working")
  end
end
)
