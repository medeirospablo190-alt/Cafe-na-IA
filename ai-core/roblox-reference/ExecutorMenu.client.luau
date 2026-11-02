--[[
  CAFEÍNA AI · EXECUTOR UI PREVIEW · v0.1
  Client-only demonstration for a Roblox Luau executor in the owner's
  own/authorized experience. No privileged executor API is required.
  No HTTP, remotes, collector access, code loading, or Roblox commands.
  Decisions are synthetic and local to this UI session only.
]]
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
assert(player, "CAFEINA: execute no cliente Roblox, nao no servidor.")
local playerGui = player:WaitForChild("PlayerGui", 10)
assert(playerGui, "CAFEINA: PlayerGui indisponivel neste executor.")

local GUI_NAME = "CAFEINA_AI_EXECUTOR_PREVIEW"
local existing = playerGui:FindFirstChild(GUI_NAME)
if existing then
    existing:Destroy()
end

local function color(r, g, b)
    return Color3.fromRGB(r, g, b)
end

local palette = {
    base = color(15, 19, 28),
    panel = color(23, 29, 43),
    surface = color(34, 42, 59),
    border = color(64, 79, 101),
    accent = color(102, 216, 176),
    orange = color(255, 187, 96),
    white = color(236, 244, 249),
    muted = color(171, 189, 208),
    red = color(245, 127, 137)
}

local function create(className, parent, properties)
    local instance = Instance.new(className)
    for key, value in pairs(properties or {}) do
        instance[key] = value
    end
    instance.Parent = parent
    return instance
end

local function round(target, radius)
    create("UICorner", target, {
        CornerRadius = UDim.new(0, radius)
    })
end

local function stroke(target)
    create("UIStroke", target, {
        Color = palette.border,
        Thickness = 1,
        Transparency = 0.28
    })
end

local gui = create("ScreenGui", playerGui, {
    Name = GUI_NAME,
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    DisplayOrder = 700,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling
})

local window = create("Frame", gui, {
    Name = "Window",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.new(0.91, 0, 0.76, 0),
    BackgroundColor3 = palette.base,
    BorderSizePixel = 0
})
round(window, 17)
stroke(window)
create("UISizeConstraint", window, {
    MaxSize = Vector2.new(420, 610)
})

local header = create("Frame", window, {
    Name = "DragHandle",
    Size = UDim2.new(1, 0, 0, 62),
    BackgroundTransparency = 1,
    Active = true
})

create("TextLabel", header, {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(18, 10),
    Size = UDim2.new(1, -125, 0, 26),
    Font = Enum.Font.GothamBold,
    Text = "CAFEÍNA AI",
    TextSize = 22,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = palette.accent
})

create("TextLabel", header, {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(19, 36),
    Size = UDim2.new(1, -125, 0, 16),
    Font = Enum.Font.Gotham,
    Text = "EXECUTOR  /  TESTE OFFLINE",
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextColor3 = palette.muted
})

local function smallButton(parent, caption, xOffset, callback)
    local button = create("TextButton", parent, {
        Size = UDim2.fromOffset(38, 36),
        Position = UDim2.new(1, xOffset, 0, 13),
        BackgroundColor3 = palette.surface,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = caption,
        TextSize = 18,
        TextColor3 = palette.white
    })
    round(button, 9)
    button.Activated:Connect(callback)
    return button
end

local bubble = create("TextButton", gui, {
    Name = "OpenMenu",
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -15, 0.5, 0),
    Size = UDim2.fromOffset(56, 56),
    BorderSizePixel = 0,
    BackgroundColor3 = palette.accent,
    Text = "C",
    TextSize = 28,
    Font = Enum.Font.GothamBold,
    TextColor3 = palette.base,
    Visible = false
})
round(bubble, 28)

local activeTab = "Missões"
local request = {
    missionId = "mission-synthetic-preview",
    toolId = "watch_state",
    status = "PENDING_REVIEW",
    decision = nil,
    expiresAt = os.clock() + 120,
    maxTrials = 2,
    secondsPerTrial = 10
}

local journal = {}
local function log(code)
    table.insert(journal, 1, code)
    if #journal > 8 then
        table.remove(journal)
    end
end
log("INTERFACE_OPENED")
log("NETWORK_DISABLED")

local tabs = create("Frame", window, {
    Name = "Tabs",
    Position = UDim2.fromOffset(12, 67),
    Size = UDim2.new(1, -24, 0, 40),
    BackgroundTransparency = 1
})
create("UIListLayout", tabs, {
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    Padding = UDim.new(0, 6),
    SortOrder = Enum.SortOrder.LayoutOrder
})

local content = create("ScrollingFrame", window, {
    Name = "Content",
    Position = UDim2.fromOffset(14, 114),
    Size = UDim2.new(1, -28, 1, -157),
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = palette.muted,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.fromOffset(0, 0)
})

local footer = create("TextLabel", window, {
    Name = "Footer",
    Position = UDim2.new(0, 14, 1, -39),
    Size = UDim2.new(1, -28, 0, 28),
    BackgroundColor3 = palette.panel,
    BorderSizePixel = 0,
    Font = Enum.Font.Gotham,
    Text = "OFFLINE  •  AÇÕES NO JOGO: 0",
    TextSize = 11,
    TextColor3 = palette.orange
})
round(footer, 8)

local tabButtons = {}
local render

local function updateExpiry()
    if request.status == "PENDING_REVIEW" and os.clock() >= request.expiresAt then
        request.status = "EXPIRED"
        log("REQUEST_EXPIRED")
        return true
    end
    return false
end

local function clearContent()
    for _, child in ipairs(content:GetChildren()) do
        child:Destroy()
    end
    create("UIListLayout", content, {
        Padding = UDim.new(0, 9),
        SortOrder = Enum.SortOrder.LayoutOrder
    })
    create("UIPadding", content, {
        PaddingBottom = UDim.new(0, 12)
    })
end

local function label(text, height, strong, tint)
    return create("TextLabel", content, {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -8, 0, height),
        Text = text,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Font = strong and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextSize = strong and 17 or 13,
        TextColor3 = tint or palette.white
    })
end

local function box(text, height)
    local frame = create("Frame", content, {
        Size = UDim2.new(1, -8, 0, height),
        BackgroundColor3 = palette.panel,
        BorderSizePixel = 0
    })
    round(frame, 10)
    create("TextLabel", frame, {
        BackgroundTransparency = 1,
        Position = UDim2.fromOffset(11, 7),
        Size = UDim2.new(1, -22, 1, -14),
        Text = text,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Font = Enum.Font.Gotham,
        TextSize = 13,
        TextColor3 = palette.muted
    })
    return frame
end

local function action(text, kind, callback)
    local button = create("TextButton", content, {
        Size = UDim2.new(1, -8, 0, 44),
        BackgroundColor3 = kind == "danger" and palette.surface or palette.accent,
        TextColor3 = kind == "danger" and palette.white or palette.base,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        TextSize = 14,
        Text = text
    })
    round(button, 10)
    button.Activated:Connect(callback)
    return button
end

local function review(decision)
    updateExpiry()
    if request.status ~= "PENDING_REVIEW" then
        return
    end
    if decision ~= "DENIED" and decision ~= "SIMULATION_ALLOWED" then
        return
    end
    request.decision = decision
    request.status = "REVIEWED"
    log(decision)
    render()
end

render = function()
    updateExpiry()
    clearContent()
    for name, button in pairs(tabButtons) do
        button.BackgroundColor3 = activeTab == name and palette.accent or palette.surface
        button.TextColor3 = activeTab == name and palette.base or palette.white
    end

    if activeTab == "Missões" then
        label("Centro de missões", 34, true)
        box("Modo de diagnóstico local. Nenhuma missão foi recebida do GitHub ou do Roblox.", 72)
        label("Solicitação demonstrativa", 26, true, palette.orange)
        box("Ferramenta: watch_state\nFonte: dados fictícios\nMissão: " .. request.missionId, 82)
        action("Ver permissões", "normal", function()
            activeTab = "Permissões"
            render()
        end)
    elseif activeTab == "Permissões" then
        label("Revisão de ferramentas", 34, true)
        box("A aprovação abaixo permite apenas uma PRÉVIA FICTÍCIA. Não autoriza observações reais nem comandos Roblox.", 90)
        label("watch_state · até 2 prévias / 10 s", 35, true)
        local remaining = math.max(0, math.ceil(request.expiresAt - os.clock()))
        local status = request.status == "REVIEWED" and request.decision or request.status
        box("Estado: " .. status .. "\nTempo restante: " .. remaining ..
            " s\nAções reais habilitadas: NÃO", 82)
        if request.status == "PENDING_REVIEW" then
            action("Recusar solicitação", "danger", function()
                review("DENIED")
            end)
            action("Permitir prévia FICTÍCIA", "normal", function()
                review("SIMULATION_ALLOWED")
            end)
        else
            label("Decisão encerrada. Reabra o script para iniciar outra simulação.", 65, false, palette.muted)
        end
    else
        label("Diagnóstico", 34, true)
        box("Conectividade: DESATIVADA\nGitHub: SEM ACESSO\nGateway: SEM ACESSO\nColetor: NÃO CONECTADO", 100)
        box("Execuções Roblox: 0\nRemoteEvents enviados: 0\nCredenciais armazenadas: 0", 82)
        label("Registro da interface", 28, true, palette.orange)
        for index, item in ipairs(journal) do
            label(tostring(index) .. ". " .. item, 26, false, palette.muted)
        end
    end
end

for index, name in ipairs({"Missões", "Permissões", "Diagnóstico"}) do
    local button = create("TextButton", tabs, {
        Name = "Tab_" .. index,
        Size = UDim2.new(1 / 3, -5, 1, 0),
        BackgroundColor3 = palette.surface,
        BorderSizePixel = 0,
        Font = Enum.Font.GothamBold,
        Text = name,
        TextSize = 12,
        TextColor3 = palette.white,
        LayoutOrder = index
    })
    round(button, 9)
    tabButtons[name] = button
    button.Activated:Connect(function()
        activeTab = name
        render()
    end)
end

smallButton(header, "–", -94, function()
    window.Visible = false
    bubble.Visible = true
end)
smallButton(header, "×", -48, function()
    gui:Destroy()
end)
bubble.Activated:Connect(function()
    bubble.Visible = false
    window.Visible = true
end)

-- Touch and mouse dragging; disconnect on GUI destruction or reinjection.
local dragging = false
local dragStart
local startPosition
local dragInput
local dragConnection

header.InputBegan:Connect(function(input)
    local kind = input.UserInputType
    if kind ~= Enum.UserInputType.Touch and kind ~= Enum.UserInputType.MouseButton1 then
        return
    end
    dragging = true
    dragStart = input.Position
    startPosition = window.Position
    input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then
            dragging = false
        end
    end)
end)
header.InputChanged:Connect(function(input)
    local kind = input.UserInputType
    if kind == Enum.UserInputType.Touch or kind == Enum.UserInputType.MouseMovement then
        dragInput = input
    end
end)
dragConnection = UserInputService.InputChanged:Connect(function(input)
    if dragging and input == dragInput then
        local delta = input.Position - dragStart
        window.Position = UDim2.new(
            startPosition.X.Scale, startPosition.X.Offset + delta.X,
            startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
        )
    end
end)
gui.Destroying:Connect(function()
    if dragConnection then
        dragConnection:Disconnect()
    end
end)

task.spawn(function()
    while gui.Parent do
        task.wait(1)
        if gui.Parent and updateExpiry() and activeTab == "Permissões" then
            render()
        end
    end
end)

render()
print("[CAFEINA AI] Interface do executor carregada. Modo sintético offline; execução real desativada.")
