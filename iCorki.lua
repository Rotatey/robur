--[[
    iCorki
]]

module("iCorki", package.seeall, log.setup)
clean.module("iCorki", package.seeall, log.setup)

-- Globals
local CoreEx = _G.CoreEx
local Libs = _G.Libs
local mathRad = _G.math.rad
local tInsert = _G.table.insert

local Geometry = CoreEx.Geometry
local BestCoveringCone = Geometry.BestCoveringCone

local Menu = Libs.NewMenu
local Prediction = Libs.Prediction
local Orbwalker = Libs.Orbwalker
local CollisionLib = Libs.CollisionLib
local DamageLib = Libs.DamageLib
local ImmobileLib = Libs.ImmobileLib
local SpellLib = Libs.Spell
local TS = Libs.TargetSelector()
local HealthPrediction = Libs.HealthPred

local ObjectManager = CoreEx.ObjectManager
local EventManager = CoreEx.EventManager
local Input = CoreEx.Input
local Enums = CoreEx.Enums
local Game = CoreEx.Game
local Geometry = CoreEx.Geometry
local Renderer = CoreEx.Renderer

local SpellSlots = Enums.SpellSlots
local SpellStates = Enums.SpellStates
local BuffTypes = Enums.BuffTypes
local Events = Enums.Events
local HitChance = Enums.HitChance
local HitChanceStrings = { "Collision", "OutOfRange", "VeryLow", "Low", "Medium", "High", "VeryHigh", "Dashing", "Immobile" };

local LocalPlayer = ObjectManager.Player.AsHero

if LocalPlayer.CharName ~= "Corki" then return false end

local smiteSpell = nil
-- Check if Player has smite
if string.find(string.lower(LocalPlayer:GetSpell(SpellSlots.Summoner1).Name), "flash") then
    smiteSpell = SpellSlots.Summoner1
elseif string.find(string.lower(LocalPlayer:GetSpell(SpellSlots.Summoner2).Name), "flash") then
    smiteSpell = SpellSlots.Summoner2
end

if smiteSpell == nil then return false end

-- Globals
local Corki = {}
local Utils = {}
Corki.Logic = {}

Corki.Q = SpellLib.Skillshot({
    Slot = SpellSlots.Q,
    Range = 825,
    Type = "Circular",
    Delay = 0.3,
    Speed = 1000,
    Radius = 250,
})

Corki.W = SpellLib.Skillshot({
    Slot = SpellSlots.W,
    Range = 800,
    Type = "Linear",
    Delay = 180,
    Speed = 1500,
    Radius = 200,
})

Corki.E = SpellLib.Skillshot({
    Slot = SpellSlots.E,
    --Range = 690,
    Type = "Cone",
    ConeAngleRad = 35,
})

Corki.R = SpellLib.Skillshot({
    Slot = SpellSlots.R,
    Range = 1300,
    Radius = 40,
    Speed = 2000,
    Delay = 0.2,
    Collisions = { Heroes = true, WindWall = true, Minions = true },
    Type = "Linear",
    UseHitbox = true
})

-- Utils
function Utils.IsGameAvailable()
    -- Is game available to automate stuff
    return not (Game.IsChatOpen() or Game.IsMinimized() or LocalPlayer.IsDead)
end

function Utils.IsInRange(From, To, Min, Max)
    -- Is Target in range
    local Distance = From:Distance(To)
    return Distance > Min and Distance <= Max
end

function Utils.GetBoundingRadius(Target)
    if not Target then return 0 end

    -- Bounding boxes
    return LocalPlayer.BoundingRadius + Target.BoundingRadius
end

function Utils.IsValidTarget(Target)
    return Target and Target.IsTargetable and Target.IsAlive
end

function Utils.TargetsInRange(Target, Range, Team, Type, Condition)
    -- return target in range
    local Objects = ObjectManager.Get(Team, Type)
    local Array = {}
    local Index = 0

    for _, Object in pairs(Objects) do
        if Object and Object ~= Target then
            Object = Object.AsAI
            if
            Utils.IsValidTarget(Object) and
                    (not Condition or Condition(Object))
            then
                local Distance = Target:Distance(Object.Position)
                if Distance <= Range then
                    Array[Index] = Object
                    Index = Index + 1
                end
            end
        end
    end

    return { Array = Array, Count = Index }
end

function Utils.ValidMinion(minion)
    return minion and minion.IsTargetable and minion.MaxHealth > 6 -- check if not plant or shroom
end

function Utils.IsBigUlt()
    return LocalPlayer:GetBuff("mbcheck2")
end

function Utils.TotalDamage(Target)
    return 0
end

function Utils.CalculateQDamage(Target)
    local Level = Corki.Q:GetLevel()
    local TotalDamage = 0
    if Level == 0 then return false end

    local BaseDamage = ({75, 120, 165, 210, 255})[Level]
    local TotalAP = LocalPlayer.TotalAP * 0.5
    local TotalAD = LocalPlayer.TotalAD * 0.7
    TotalDamage = BaseDamage + TotalAD + TotalAP
    return DamageLib.CalculateMagicalDamage(LocalPlayer, Target, TotalDamage)
end

function Utils.CalculateRDamage(Target)
    local Level = Corki.R:GetLevel()
    local TotalDamage = 0

    if Level == 0 then return false end

    if Utils.IsBigUlt() then
        local BaseDamage = ({180, 250, 320})[Level]
        local TotalADRation = ({0.3, 0.9, 1.5})[Level]
        local TotalAP = LocalPlayer.TotalAP * 0.4
        local TotalAD = LocalPlayer.TotalAD * TotalADRation
        TotalDamage = BaseDamage + TotalAD + TotalAP
    else
        local BaseDamage = ({90, 125, 160})[Level]
        local TotalADRation = ({0.15, 0.45, 0.75})[Level]
        local TotalAP = LocalPlayer.TotalAP * 0.2
        local TotalAD = LocalPlayer.TotalAD * TotalADRation
        TotalDamage = BaseDamage + TotalAD + TotalAP
    end

    return DamageLib.CalculateMagicalDamage(LocalPlayer, Target, TotalDamage)
end

function Corki.Logic.Q(Target, Enable, HitChance)
    if not Corki.Q:IsReady() then return false end
    if not Utils.IsValidTarget(Target) then return false end

    if Enable and Utils.IsInRange(LocalPlayer.Position, Target.Position, 0, Corki.Q.Range) then
        return Corki.Q:CastOnHitChance(Target, HitChance)
    end
end

function Corki.Logic.E(Target, Enable)
    if not Corki.E:IsReady() then return false end
    if not Utils.IsValidTarget(Target) then return false end

    if Enable and Utils.IsInRange(LocalPlayer.Position, Target.Position, 0, Corki.E.Range) then
        return Corki.E:Cast(Target)
    end
end

function Corki.Logic.R(Target, Enable, HitChance)
    if not Corki.R:IsReady() then return false end
    if not Utils.IsValidTarget(Target) then return false end

    if Enable and Utils.IsInRange(LocalPlayer.Position, Target.Position, 0, Corki.R.Range) then
        return Corki.R:CastOnHitChance(Target, HitChance)
    end
end

function Corki.Logic.Flee()
    if not Corki.W:IsReady() then return false end

    local mousePos = Renderer.GetMousePos()
    Corki.W:Cast(mousePos)
end

function Corki.Logic.Waveclear()

    if not LocalPlayer:GetSpellState(SpellSlots.Q) == SpellStates.Ready then return false end
    if not LocalPlayer:GetSpellState(SpellSlots.E) == SpellStates.Ready then return false end
    if not LocalPlayer:GetSpellState(SpellSlots.R) == SpellStates.Ready then return false end
    if not Menu.Get("Waveclear.Q.Use") then return false end
    if not Menu.Get("Waveclear.E.Use") then return false end
    if not Menu.Get("Waveclear.R.Use") then return false end

    local castPoints = {}

    for k, v in pairs(ObjectManager.Get("enemy", "minions")) do
        local minion = v.AsMinion
        if Utils.ValidMinion(minion) then
            local posR = minion:FastPrediction(Corki.Q.Delay)
            if posR:Distance(LocalPlayer.Position) < Corki.Q.Range and minion.IsTargetable then
                table.insert(castPoints, posR)
                Orbwalker.IgnoreMinion(minion)
            end
        end
    end

    local bestPos, hitCountR = Geometry.BestCoveringCircle(castPoints, Corki.Q.Radius)

    if bestPos and hitCountR >= Menu.Get("Waveclear.Q.Count") then
        Input.Cast(SpellSlots.Q, bestPos)
        Input.Cast(SpellSlots.E, bestPos)
        Input.Cast(SpellSlots.R, bestPos)
    end
end

function Corki.Logic.Harass()
    local Target = TS:GetTarget(Corki.Q.Range, true)
    Corki.Logic.Q(Target, Menu.Get("Harass.Q.Use"), Menu.Get("Combo.Q.HitChance"))
    Corki.Logic.E(Target, Menu.Get("Harass.E.Use"))
end

function Corki.Logic.Combo()
    local Target = TS:GetTarget(Corki.R.Range, true)

    Corki.Logic.R(Target, Menu.Get("Combo.R.Use"), Menu.Get("Combo.R.HitChance"))
    Corki.Logic.Q(Target, Menu.Get("Combo.Q.Use"), Menu.Get("Combo.Q.HitChance"))
    Corki.Logic.E(Target, Menu.Get("Combo.E.Use"))
end

function Corki.LoadMenu()
    Menu.RegisterMenu("iCorki", "iCorki", function()
        Menu.NewTree("Combo", "Combo", function()
            Menu.Dropdown("Combo.Q.HitChance", "Q HitChance", 6, HitChanceStrings)
            Menu.Checkbox("Combo.Q.Use", "Use Q", true)
            Menu.Checkbox("Combo.E.Use", "Use E", true)
            Menu.Checkbox("Combo.R.Use", "Use R", true)
            Menu.Dropdown("Combo.R.HitChance", "R HitChance", 6, HitChanceStrings)
            Menu.NextColumn()
        end)
        Menu.NewTree("Harass", "Harass", function()
            Menu.Checkbox("Harass.Q.Use", "Use Q", true)
            Menu.Dropdown("Harass.Q.HitChance", "Q HitChance", 6, HitChanceStrings)
            Menu.Checkbox("Harass.E.Use", "Use E", true)
            Menu.NextColumn()
        end)
        Menu.Separator()
        Menu.NewTree("Waveclear", "Waveclear", function()
            Menu.Checkbox("Waveclear.Q.Use", "Use Q", true)
            Menu.Slider("Waveclear.Q.Count", "Minimum Q hit count",  1, 0, 5, 1)
            Menu.Checkbox("Waveclear.E.Use", "Use E", true)
            Menu.Checkbox("Waveclear.R.Use", "Use R", true)
            Menu.NextColumn()
        end)
        Menu.NewTree("Misc", "Misc", function()
            Menu.Checkbox("SOON", "Comming Soon", false)
            Menu.NextColumn()
        end)
        Menu.Separator()
        Menu.Separator()
        Menu.NewTree("Drawings", "Drawings", function()
            Menu.Checkbox("Drawings.Q", "Draw Q Range", true)
            Menu.Checkbox("Drawings.E", "Draw E Range", true)
            Menu.Checkbox("Drawings.R", "Draw R Range", true)
        end)
    end)
end

function Corki.OnDraw()
    -- If player is not on screen than don't draw
    if not LocalPlayer.IsOnScreen then return false end;

    -- Get spells ranges
    local Spells = { Q = Corki.Q, E = Corki.E, R = Corki.R }

    -- Draw them all
    for k, v in pairs(Spells) do
        if Menu.Get("Drawings." .. k) then
            Renderer.DrawCircle3D(LocalPlayer.Position, v.Range, 30, 1, 0xFF31FFFF)
        end
    end

    return true
end

function Corki.OnTick()
    if not Utils.IsGameAvailable() then return false end

    local OrbwalkerMode = Orbwalker.GetMode()

    local OrbwalkerLogic = Corki.Logic[OrbwalkerMode]

    if OrbwalkerLogic then
        -- Calculate spell data

        -- Do logic
        if OrbwalkerLogic() then return true end
    end

    return false
end

function OnLoad()

    Corki.LoadMenu()

    for EventName, EventId in pairs(Events) do
        if Corki[EventName] then
            EventManager.RegisterCallback(EventId, Corki[EventName])
        end
    end

    return true

end
