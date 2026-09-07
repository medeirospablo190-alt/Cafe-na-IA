pcall(function()
	if getgenv().QenturyJossCleanup then
		getgenv().QenturyJossCleanup()
	end
end)
pcall(function()
	local hui = gethui and gethui() or game:GetService("CoreGui")
	for _, old in ipairs(hui:GetDescendants()) do
		if old:IsA("ScreenGui") and old.Name == "Obsidian" then
			local isJoss = false
			for _, lbl in ipairs(old:GetDescendants()) do
				if lbl:IsA("TextLabel") and lbl.Text == "QenturyJoss" then
					isJoss = true
					break
				end
			end
			if isJoss then
				old:Destroy()
			end
		end
	end
end)
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LP = Players.LocalPlayer
local function ownPlot()
	local slots = workspace:FindFirstChild("Things") and workspace.Things:FindFirstChild("Plots") and workspace.Things.Plots:FindFirstChild("Slots")
	if not slots then
		return nil
	end
	for _, m in ipairs(slots:GetChildren()) do
		if m:IsA("Model") and m.Name == LP.Name then
			return m
		end
	end
	return nil
end
local function takeOutAll()
	local plot = ownPlot()
	if not plot then
		Library:Notify({ Title = "Take Out", Description = "No plot", Time = 2 })
		return false
	end
	local remote = ReplicatedStorage.Remotes:FindFirstChild("TakeOutAllCrystals")
	if not remote then
		return false
	end
	return pcall(function()
		remote:FireServer()
	end)
end
local function crystalTools()
	local tools = {}
	local function scan(c)
		if not c then
			return
		end
		for _, t in ipairs(c:GetChildren()) do
			if t:IsA("Tool") and t:GetAttribute("Tier") ~= nil and t:GetAttribute("Value") ~= nil then
				tools[#tools + 1] = t
			end
		end
	end
	scan(LP:FindFirstChildOfClass("Backpack"))
	scan(LP.Character)
	return tools
end
local function unfavoriteAll()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local fav = remotes and remotes:FindFirstChild("ToggleFavorite")
	if not fav then
		return 0
	end
	local n = 0
	for _, tool in ipairs(crystalTools()) do
		if not tool.Parent then
			continue
		end
		local ok = pcall(function()
			fav:FireServer(tool, false)
		end)
		if ok then
			n = n + 1
			task.wait(0.03)
		end
	end
	return n
end
local function sellAll()
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local goHome = remotes and remotes:FindFirstChild("GoHome")
	local sellReq = remotes and remotes:FindFirstChild("SellRequest")
	if not sellReq then
		return false, "no SellRequest"
	end
	if goHome then
		pcall(function()
			goHome:FireServer("sell")
		end)
		task.wait(0.6)
	end
	local ok = pcall(function()
		sellReq:FireServer("all")
	end)
	task.wait(0.5)
	return ok
end
local function forceKick()
	local plr = Players.LocalPlayer
	warn("[ForceKick] firing kick x3")
	for i = 1, 3 do
		pcall(function()
			plr:Kick("\nCrystal Already Duped, Rejoin for Check")
		end)
		task.wait(0.1)
	end
	warn("[ForceKick] done")
end
local function comboTakeUnfavSell()
	takeOutAll()
	task.wait(2.5)
	local unfavN = unfavoriteAll()
	task.wait(0.5)
	local okSell, errSell = sellAll()
	Library:Notify({
		Title = okSell and "Combo done" or "Combo sell failed",
		Description = string.format("unfav %s / %s", tostring(unfavN), okSell and "sold" or tostring(errSell)),
		Time = 3,
	})
	forceKick()
end
local Window = Library:CreateWindow({
	Title = "Qentury Dupe",
	Subtitle = "Dupe Tool",
	TabWidth = 120,
	Size = UDim2.fromOffset(420, 240),
	Acrylic = true,
	Theme = "Dark",
	MinimizeKey = Enum.KeyCode.LeftControl,
})
local PlotTab = Window:AddTab("Dupe", "gem")
local PlotBox = PlotTab:AddLeftGroupbox("Dupe Tool", "gem")
PlotBox:AddButton({
	Text = "Reset Character (Dupe Tool)",
	Func = function()
		comboTakeUnfavSell()
	end,
})
local function forceFullWidthTabs()
	local root = Library.ScreenGui
	if not root then
		return
	end
	for _, parent in ipairs(root:GetDescendants()) do
		local halves = {}
		for _, ch in ipairs(parent:GetChildren()) do
			if ch:IsA("ScrollingFrame") then
				local sx = ch.Size.X.Scale
				if sx > 0.4 and sx < 0.6 then
					table.insert(halves, ch)
				end
			end
		end
		if #halves >= 2 then
			table.sort(halves, function(a, b)
				return a.AbsoluteSize.X > b.AbsoluteSize.X
			end)
			local left = halves[1]
			for _, h in ipairs(halves) do
				if #h:GetChildren() >= #left:GetChildren() then
					left = h
				end
			end
			for _, h in ipairs(halves) do
				if h == left then
					h.Visible = true
					h.Size = UDim2.new(1, -6, 1, 0)
					h.Position = UDim2.fromScale(0, 0)
				else
					h.Visible = false
					h.Size = UDim2.new(0, 0, 1, 0)
				end
			end
		end
	end
end
task.spawn(function()
	for _ = 1, 20 do
		task.wait(0.3)
		if Library.Unloaded then
			break
		end
		forceFullWidthTabs()
	end
end)
getgenv().QenturyJossCleanup = function()
	pcall(function()
		if Library and not Library.Unloaded then
			Library:Unload()
		end
	end)
end
Library:Notify({ Title = "QenturyJoss", Description = "loaded (combo only)", Time = 3 })