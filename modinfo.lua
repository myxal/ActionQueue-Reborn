
--[[
TODO:
- Implement autobuyer
- try to use boat inventory for tool re-equip
- Auto-disarming will probably require a more substantial rework on action filter functions. The problem - There are multiple different prefabs for the striking carvings, so double-clicking one of them doesn't work. Highlighting the whole room with a selection box also doesn't work, as the hidden action "weighdown pressure plate with disarming tools" will take over, and I can't currently filter that out.
- AutoCollect should be able to work with active item - this will require getting the action via action button, and picking how many actions we should do according to what were doing -> shaving beefalo do 3 actions, disarming a trap do 1 action, etc.
BUG:
- See thread: https://steamcommunity.com/workshop/filedetails/discussion/1930794331/1754646083690807574/
]]

name = "ActionQueue Reborn"
version = "1.049+myxal_4"
description = "version: "..version
author = "myxal(DSA port) / eXiGe / simplex(Original Author)"

icon_atlas = "modicon.xml"
icon = "modicon.tex"

api_version = 6
dont_starve_compatible = true
reign_of_giants_compatible = true
shipwrecked_compatible = true
hamlet_compatible = true
forumthread = ''

-- This, sadly, doesn't work in DSA
-- folder_name = folder_name or "action queue"
-- if not folder_name:find("workshop-") then
--   name = name.."-dev"
-- end

local boolean = {{description = "Yes", data = true}, {description = "No", data = false}}
local string = ""
local keys = {"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z","F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12","LAlt","RAlt","LCtrl","RCtrl","LShift","RShift","Tab","Capslock","Space","Minus","Equals","Backspace","Insert","Home","Delete","End","Pageup","Pagedown","Print","Scrollock","Pause","Period","Slash","Semicolon","Leftbracket","Rightbracket","Backslash","Up","Down","Left","Right"}
local keylist = {}
for i = 1, #keys do
  keylist[i] = {description = keys[i], data = "KEY_"..string.upper(keys[i])}
end
keylist[#keylist + 1] = {description = "Disabled", data = false}

local colorlist = {
  {description = "White",  data = "WHITE"},
  {description = "Red",    data = "FIREBRICK"},
  {description = "Orange", data = "TAN"},
  {description = "Yellow", data = "LIGHTGOLD"},
  {description = "Green",  data = "GREEN"},
  {description = "Teal",   data = "TEAL"},
  {description = "Blue" ,  data = "OTHERBLUE"},
  {description = "Purple", data = "DARKPLUM"},
  {description = "Pink" ,  data = "ROSYBROWN"},
  {description = "Gold",   data = "GOLDENROD"},
}

local function BuildNumConfig(start_num, end_num, step, percent)
  local num_table = {}
  local iterator = 1
  local suffix = percent and "%" or ""
  for i = start_num, end_num, step do
    num_table[iterator] = {description = i..suffix, data = percent and i / 100 or i}
    iterator = iterator + 1
  end
  return num_table
end

local function AddConfig(label, name, options, default, hover)
  return {label = label, name = name, options = options, default = default, hover = hover or ""}
end

configuration_options = {
  AddConfig("ActionQueue key", "action_queue_key", keylist, "KEY_LSHIFT"),
  AddConfig("Always clear queue", "always_clear_queue", boolean, true),
  AddConfig("Selection color", "selection_color", colorlist, "WHITE"),
  AddConfig("Selection opacity", "selection_opacity", BuildNumConfig(5, 95, 5, true), 0.5),
  AddConfig("Double click speed", "double_click_speed", BuildNumConfig(0, 0.5, 0.05), 0.3),
  AddConfig("Double click range", "double_click_range", BuildNumConfig(10, 60, 5), 25),
  AddConfig("Turf grid toggle key", "turf_grid_key", keylist, "KEY_F3"),
  AddConfig("Turf grid radius", "turf_grid_radius", BuildNumConfig(1, 50, 1), 5),
  AddConfig("Turf grid color", "turf_grid_color", colorlist, "WHITE"),
  AddConfig("Always deploy on grid", "deploy_on_grid", boolean, false),
  AddConfig("Auto-collect toggle key", "auto_collect_key", keylist, "KEY_F4"),
  AddConfig("Enable auto-collect by default", "auto_collect", boolean, false),
  AddConfig("Endless deploy toggle key", "endless_deploy_key", keylist, "KEY_F5"),
  AddConfig("Enable endless deploy by default", "endless_deploy", boolean, false),
  AddConfig("Craft last recipe key","last_recipe_key", keylist, "KEY_C"),
  AddConfig("Tooth-trap spacing", "tooth_trap_spacing", BuildNumConfig(1, 4, 0.5), 2),
  AddConfig("Extended lookalikes", "extend_lookalikes", boolean, false),
  AddConfig("Enable Debug Mode", "debug_mode", boolean, false),
}
