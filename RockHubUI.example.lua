-- Place RockHubUI.lua in your executor's workspace beside this example.
-- For GitHub loading, replace the next line with:
-- local UI = loadstring(game:HttpGet("YOUR_RAW_URL/RockHubUI.lua"))()
local UI = loadstring(readfile("RockHubUI.lua"), "RockHubUI")()

-- Re-running the example replaces its previous window.
local env = getgenv and getgenv() or _G
if env.RockHubUIExample then env.RockHubUIExample:Destroy() end

local window = UI:CreateWindow({
    Name = "RockHubUIExample",
    Title = "Rock Hub · UI Example",
    Version = "v1.0",
    ToggleKey = Enum.KeyCode.RightShift,
    MenuButton = true,
    Open = true,
})
env.RockHubUIExample = window

local main = window:AddTab({ Name = "Main", Icon = "grid", Description = "Standalone Rock Hub interface" })
local basics = main:AddSection("Basic controls")
basics:AddLabel({ Name = "Welcome", Description = "Right Shift or the Rock Hub button opens the menu." })
local enabled = basics:AddToggle({
    Name = "Enable", Description = "Example toggle", Default = true,
    Callback = function(value) print("Toggle:", value) end,
})
local amount = basics:AddSlider({
    Name = "Amount", Min = 0, Max = 100, Default = 35,
    Format = function(value) return tostring(value) .. "%" end,
    Callback = function(value) print("Amount:", value) end,
})
basics:AddButton({
    Name = "Notify", Description = "Show a notification",
    Callback = function() window:Notify("Rock Hub", "UI library is ready", 3) end,
})

local choices = main:AddSection({ Name = "Choices", Collapsible = true, Open = true })
local dropdown = choices:AddDropdown({
    Name = "Preset", Options = { "Default", "Minimal", "Custom", "Dark", "Bright", "Test" }, Default = "Default",
    Callback = function(value) print("Preset:", value) end,
})
choices:AddSelect({ Name = "Mode", Options = { "One", "Two", "Three" }, Default = "One", Callback = print })
choices:AddSegmented({ Name = "Quality", Options = { "Low", "Mid", "High" }, Default = "Mid", Callback = print })

local settings = window:AddTab({ Name = "Settings", Icon = "gear", Description = "Inputs and appearance" })
settings:SetSubTabs({ "General", "Appearance" })
local general = settings:AddSection({ Name = "Inputs", Group = "General" })
local input = general:AddInput({
    Name = "Text", Placeholder = "enter text", Default = "Hello",
    Callback = function(text, enterPressed) print("Input:", text, "Enter:", enterPressed) end,
})
local keybind = general:AddKeybind({
    Name = "Action key", Default = Enum.KeyCode.F,
    Callback = function(key) window:Notify("Keybind", key.Name .. " pressed") end,
    Changed = function(key) print("New key:", key.Name) end,
})
general:AddButton({ Name = "Alert", Callback = function() window:Alert("Rock Hub UI", "Original controls, independent library.", "Done") end })
local appearance = settings:AddSection({ Name = "Colors", Group = "Appearance" })
local color = appearance:AddColorPicker({
    Name = "Example color", Default = Color3.fromRGB(100, 210, 255),
    Callback = function(value) print("Color:", value:ToHex()) end,
})

window:AddSeparator("Utilities")
local tools = window:AddTab({ Name = "Utilities", Icon = "sliders", Description = "Search, configuration and cleanup" })
local utilities = tools:AddSection("Window")
local savedConfig
utilities:AddInput({ Name = "Search", Placeholder = "filter controls", Callback = function(text) window:Search(text) end })
utilities:AddButton({ Name = "Save config", Callback = function()
    savedConfig = window:ExportConfig()
    window:Notify("Config", "Saved to memory")
end })
utilities:AddButton({ Name = "Load config", Callback = function()
    if savedConfig then window:ImportConfig(savedConfig) end
end })
utilities:AddButton({ Name = "Reset search", Callback = function() window:Search("") end })
utilities:AddButton({ Name = "Destroy UI", Callback = function() window:Destroy() end })

-- Set(value, true) changes a control without calling its callback.
-- Both control.Set(value) and control:Set(value) are supported.
enabled:Set(true, true)
amount:Set(35, true)
dropdown:Set("Default", true)

return { Window = window, Toggle = enabled, Slider = amount, Dropdown = dropdown, Input = input, Keybind = keybind, Color = color }
