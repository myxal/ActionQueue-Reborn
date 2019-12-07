
local _G = GLOBAL
local _isDST = (_G.TheSim:GetGameID() == 'DST')
local function isDST()
  return _isDST
end

if (isDST() and
  (_G.TheNet:IsDedicated() or
    _G.TheNet:GetServerGameMode() == "lavaarena"))
  then return end

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
if isDST() then
  PLAYERCOLOURS = _G.PLAYERCOLOURS
  PLAYERCOLOURS.WHITE = {1, 1, 1, 1}
else
  -- Copy-pasta from DST's constants.lua
  local function RGB(r,g,b,a)
    if a == nil then
      a = 255
    end
    return { r/255, g/255, b/255, a/255 }
  end
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
end
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
  if (screen ~= nil and screen.name:find("HUD") ~= nil) then
    if _isDST then return true end
    return screen.owner ~= nil
    -- and screen.owner == _G:GetPlayer()
  else
    return false
  end

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
    local builder = isDST() and ThePlayer.replica.builder or ThePlayer.components.builder
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
        if isDST() then
          builder:MakeRecipeFromMenu(last_recipe, last_skin)
        else
          builder:MakeRecipe(last_recipe)
        end
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
    if (isDST() and inst ~= _G.ThePlayer) then return end
    ThePlayer = isDST() and _G.ThePlayer or _G.GetPlayer()
    TheWorld = isDST() and _G.TheWorld or _G.GetWorld()
    ActionQueuerInit()

    local PlayerControllerOnControl = self.OnControl
    self.OnControl = function(self, control, down)
        local mouse_control = mouse_controls[control]
        -- DebugPrint("PCOnControl; control: ", control, ", down: ", down)
        if mouse_control ~= nil then
            if down then
                if TheInput:IsAqModifierDown(action_queue_key) then
                    local target = TheInput:GetWorldEntityUnderMouse()
                    if target and target:HasTag("fishable") and ((isDST() and inst.replica.inventory:EquipHasTag("fishingrod")) or inst.components.inventory:EquipHasTag("fishingrod")) then
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
        -- DebugPrint("PCOnControl; control: ", control, ", down: ", down, ", inGame: ", InGame(), ", ActionThread: ", ActionQueuer.action_thread ~= nil, ", SelectionThread: ", ActionQueuer.selection_thread ~= nil)
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
    local PlayerControllerIsControlPressed = self.IsControlPressed
    self.IsControlPressed = function(self, control)
        if control == CONTROL_FORCE_INSPECT and ActionQueuer.action_thread then return false end
        return _isDST and PlayerControllerIsControlPressed(self, control) or TheInput:IsControlPressed(control)
    end
end)

if isDST() then
    AddClassPostConstruct("components/builder_replica", function(self)
        local BuilderReplicaMakeRecipeFromMenu = self.MakeRecipeFromMenu
        self.MakeRecipeFromMenu = function(self, recipe, skin)
            last_recipe, last_skin = recipe, skin
            if not ActionQueuer.action_thread and TheInput:IsAqModifierDown(action_queue_key)
              and not recipe.placer and self:CanBuild(recipe.name) then
                ActionQueuer:RepeatRecipe(self, recipe, skin)
            else
                BuilderReplicaMakeRecipeFromMenu(self, recipe, skin)
            end
        end
        local BuilderReplicaMakeRecipeAtPoint = self.MakeRecipeAtPoint
        self.MakeRecipeAtPoint = function(self, recipe, pt, rot, skin)
            last_recipe, last_skin = recipe, skin
            BuilderReplicaMakeRecipeAtPoint(self, recipe, pt, rot, skin)
        end
    end)
else
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
end

AddComponentPostInit("highlight", function(self, inst)
    local HighlightHighlight = self.Highlight
    self.Highlight = function(self, ...)
        -- DebugPrint("Entered Highlight() with item: ", inst)
        if ActionQueuer.selection_thread or ActionQueuer:IsSelectedEntity(inst) then return end
        -- DebugPrint("Calling game's Highlight for item: ", inst)
        HighlightHighlight(self, ...)
    end
    local HighlightUnHighlight = self.UnHighlight
    self.UnHighlight = function(self)
        -- DebugPrint("Entered UnHighlight() with item: ", inst)
        if ActionQueuer:IsSelectedEntity(inst) then DebugPrint(inst," is selected - skipping unhighlight")return end
        -- DebugPrint("Calling game's UnHighlight for item: ", inst)
        if isDST() then
          HighlightUnHighlight(self)
        else
          -- TODO: This seems broken in DSA
          DebugPrint("Unhighlighting ", self)
          HighlightUnHighlight(self)
        end
    end
end)
--for minimizing the memory leak in geo
--hides the geo grid during an action queue
AddComponentPostInit("placer", function(self, inst)
    local PlacerOnUpdate = self.OnUpdate
    self.OnUpdate = function(self, ...)
        self.disabled = ActionQueuer.action_thread ~= nil
        PlacerOnUpdate(self, ...)
    end
end)

if not isDST() then
  AddComponentPostInit("playeractionpicker", function(self, inst)
      self.GetLeftClickActions = function(self,a,b) return self:GetClickActions(b,a) end
    end
  )
  AddComponentPostInit("playercontroller", function(self, inst)
      -- self.IsAnyOfControlsPressed = function(self,...)
      --   for i, v in ipairs({...}) do
      --       if TheInput:IsControlPressed(v) then
      --           return true
      --       end
      --   end
      -- end
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
  AddComponentPostInit("inventory", function(self, inst)
      -- local oldfn = self.TakeActiveItemFromAllOfSlot
      self.TakeActiveItemFromAllOfSlot = function(self, slot)
        local item = self:GetItemInSlot(slot)
        if item ~= nil and
            self:GetActiveItem() == nil then

            self:RemoveItemBySlot(slot)
            self:GiveActiveItem(item)
        end
      end
  end)

  AddComponentPostInit("container", function(self, inst)
      -- local oldfn = self.TakeActiveItemFromAllOfSlot
      self.GetItems = function(self)
        if self.inst.components.container then return self.inst.components.container.slots end
      end
      self.QueryActiveItem = function(self)
        local inventory = self.opener ~= nil and self.opener.components.inventory or nil
        return inventory, inventory ~= nil and inventory:GetActiveItem() or nil
      end
      self.TakeActiveItemFromAllOfSlot = function(self, slot)
        local inventory, active_item = self:QueryActiveItem()
        local item = self:GetItemInSlot(slot)
        if item ~= nil and
            active_item == nil and
            inventory ~= nil then

            self:RemoveItemBySlot(slot)
            inventory:GiveActiveItem(item)
        end
      end
  end)
end
