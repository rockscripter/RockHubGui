# RockHubUI

**Ссылка на GUI:** [RockHubUI.lua](https://raw.githubusercontent.com/rockscripter/RockHubGui/refs/heads/main/RockHubUI.lua)

Самостоятельная Roblox/Luau UI-библиотека, выделенная из интерфейса Rock Hub. Сохранены исходные карточки, палитра, иконки, анимации, вкладки и элементы управления. Размер окна — 680 × 470; оно автоматически масштабируется под экран. Поддерживаются мышь и touch.

## Файлы

- `RockHubUI.lua` — готовая библиотека; возвращает таблицу `UI`.
- `RockHubUI.example.lua` — полный запускаемый пример.

Запустите `RockHubUI.example.lua` в исполнителе — библиотека автоматически загрузится с GitHub:

```lua
local UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/rockscripter/RockHubGui/refs/heads/main/RockHubUI.lua"))()
```

В Roblox Studio библиотеку можно поместить в `ModuleScript` и вызвать `require` из `LocalScript`. Без доступа к CoreGui она использует `PlayerGui`. Загрузка через `game:HttpGet` и `loadstring` в example предназначена для исполнителя.

## Минимальный пример

```lua
local UI = loadstring(game:HttpGet("https://raw.githubusercontent.com/rockscripter/RockHubGui/refs/heads/main/RockHubUI.lua"))()
local window = UI:CreateWindow({ Title = "My Hub", ToggleKey = Enum.KeyCode.RightShift })
local tab = window:AddTab({ Name = "Main", Icon = "grid" })
local section = tab:AddSection("Features")

local toggle = section:AddToggle({
    Name = "Enable",
    Default = false,
    Callback = function(value) print(value) end,
})

toggle:Set(true)       -- вызывает Callback
toggle:Set(false, true) -- без Callback
print(toggle:Get())
```

## Окно и вкладки

`UI:CreateWindow(options)` принимает:

| Опция | По умолчанию | Назначение |
|---|---|---|
| `Title` | `"Rock Hub"` | Заголовок |
| `Name` | `"RockHubUI"` | Имя ScreenGui |
| `Version` | `"UI"` | Текст версии |
| `ToggleKey` | `Enum.KeyCode.RightShift` | Открытие/закрытие |
| `Open` | `true` | Начальная видимость |
| `MenuButton` | `true` | Экранная кнопка открытия |
| `ButtonText` | `"rock hub"` | Название в панели открытия |
| `Logo` | Логотип MM2-хаба, fallback `rh` | Необязательный asset URI своего изображения; оригинал кэшируется при наличии `writefile`/`getcustomasset` |
| `Blur` | `0` | Размытие фона при открытом меню |
| `Parent` | Автоматически | Родитель ScreenGui |
| `Theme` | Исходная палитра | Цвета `Background`, `Panel`, `Element`, `Hover`, `Stroke`, `Text`, `Dim`, `Muted`, `Accent` |
| `OnOpenChanged` | — | Callback с boolean |

Методы окна:

- `window:AddTab({ Name, Icon, Description })` или `window:AddTab("Main")`.
- `window:AddSeparator("Utilities")` — разделитель в sidebar.
- `window:SetOpen(boolean)`, `window:Toggle()`, `window:IsOpen()`.
- `window:Search("text")` — фильтр элементов; `window:Search("")` сбрасывает его.
- `window:Notify("Title", "Message", 3)` — уведомление с длительностью в секундах.
- `window:Alert("Title", "Message", "Done")` — модальное сообщение.
- `window:Destroy()` — отключает обработчики и удаляет принадлежащий окну UI/blur; повторный вызов допустим.

Окно можно перетаскивать за верхнюю панель. Кнопка открытия повторяет watermark из MM2-хаба: логотип, название, FPS, пинг, время и анимированная иконка menu/close. Панель перетаскивается отдельно, обычный клик открывает/закрывает меню; при наведении показывается подсказка.

`window.Gui`, `window.Main`, `window.Sidebar`, `window.Tabs`, `window.MenuButton`, `window.MenuHolder` доступны для расширений.

Иконки: `grid`, `move`, `eye`, `wing`, `sliders`, `star`, `gear`, `target`, `cart`, `pin`, `smile`, `bolt`, `globe`, `drone`.

```lua
local tab = window:AddTab({ Name = "Settings", Icon = "gear" })
tab:SetSubTabs({ "General", "Appearance" }) -- до создания секций, один раз
local section = tab:AddSection({
    Name = "Colors",
    Group = "Appearance",
    Priority = 10,
    Collapsible = true,
    Open = true,
})
tab:Select()
tab:SelectSubTab("Appearance")
```

## Элементы

Общие поля: `Name`, необязательные `Description` и `Callback`. По умолчанию создание элемента **не вызывает callback**. `AddSegmented` и `AddSlider` используют компактный вариант без описания.

| Метод секции | Дополнительные опции | Возвращаемые методы |
|---|---|---|
| `AddToggle` | `Default: boolean` | `Get`, `Set(value, silent)` |
| `AddButton` | — | `Fire()` |
| `AddSlider` | `Min`, `Max`, `Default`, `Format(number)` | `Get`, `Set(value, silent)` |
| `AddDropdown` | `Options`, `Default`, `Placeholder`, `Thumbnail(value)` | `Get`, `Set(value, silent)`, `Update(options)` |
| `AddSelect` | `Options`, `Default` | `Get`, `Set(value, silent)` |
| `AddSegmented` | `Options`, `Default`, `CanSelect(value)` | `Get`, `Set(value, silent)` |
| `AddInput` | `Default`, `Placeholder` | `Get`, `Set(value, silent)`, `SetPlaceholder`, `Focus`; также `Box` |
| `AddKeybind` | `Default: Enum.KeyCode`, `Changed(key)` | `Get`, `Set(key, silent)` |
| `AddColorPicker` | `Default: Color3` | `Get`, `Set(color, silent)` |
| `AddLabel` | `Height` | `Set(text)`; также `Instance` |

Для контролов с состоянием подходят обе формы: `control.Set(value)` и `control:Set(value)`. У label используется `label.Set(text)`.

`Options` — непустой массив строк. Slider требует `Max > Min`; при перетаскивании использует целочисленные значения. Dropdown допускает сброс через `Set(nil, true)`.

- `Input.Callback(text, enterPressed)` вызывается при потере фокуса; программный `Set` передаёт `false` вторым аргументом.
- `Keybind.Callback(key)` вызывается при нажатии назначенной клавиши, `Changed(key)` — при смене назначения. Escape отменяет захват. `Enum.KeyCode.Unknown` отключает назначение.
- `ColorPicker.Callback(color)` получает `Color3`; в popup есть HSV, HEX, пресеты и возврат к исходному цвету.
- Ошибки пользовательских callbacks выводятся в консоль с префиксом `[RockHubUI callback]`.

Сохранены и исходные позиционные методы `Section:Toggle`, `Button`, `Slider`, `Dropdown`, `Input`, `Keybind`, `Select`, `Segmented`, `ColorPicker`, `Collapsible`. Для новых скриптов удобнее использовать `Add*`.

## Конфигурация

```lua
local values = window:GetConfig()       -- обычная таблица
local errors = window:LoadConfig(values)
local json = window:ExportConfig()      -- строка JSON
local errors = window:ImportConfig(json)

-- При наличии файловых функций исполнителя:
writefile("my-ui-config.json", json)
window:ImportConfig(readfile("my-ui-config.json"))
```

Ключи имеют вид `Tab/Section/Control`. Используйте уникальные имена контролов внутри секции. Цвета сериализуются как HEX, клавиши — как имена `Enum.KeyCode`. Загрузка применяет callbacks; ошибки отдельных значений возвращаются таблицей `errors`. Автоматической записи на диск нет.

`window.Controls["Main/Features/Enable"]` возвращает созданный через `Add*` контрол. Labels и кнопки не входят в сохраняемую конфигурацию.

## Повторный запуск

Каждое окно независимо. Для замены предыдущего сохраняйте его ссылку и вызывайте `Destroy()` — это показано в example. Библиотека сама не устанавливает глобальный singleton.

## Проверка и пересборка

`tools/extract_ui.py` собирает `RockHubUI.lua` из исходных UI-блоков хаба и адаптеров `tools/ui_header.lua`, `tools/ui_api.lua`; проверяет компиляцию. Эти tools не нужны для запуска библиотеки.

Проверено в подключённом клиенте: example, callbacks и тихие изменения, JSON-конфигурация, поиск, sidebar при масштабе 0.35, dropdown, subtabs, HEX color picker, очистка popup при закрытии меню, независимая очистка окон и повторный запуск example.
