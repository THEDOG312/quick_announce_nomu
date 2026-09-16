local HANDPET = {
    {
        anim = "handpet",
        sound = "Petpet_Anything/Petpet_Anything/rubber_duck",
        scale = 3,
    },
    {
        anim = "metal_pipe",
        sound = "Petpet_Anything/Petpet_Anything/metal_pipe",
        scale = 2,
    },
}

table.insert(Assets, Asset("ANIM", "anim/handpet.zip"))
table.insert(Assets, Asset("SOUNDPACKAGE", "sound/Petpet_Anything.fev"))
table.insert(Assets, Asset("SOUND", "sound/Petpet_Anything.fsb"))

-- 弹性形变
local function DoWobble(inst)
    if not inst or not inst:IsValid() or not inst.Transform then return end
    local duration = 0.3
    local intensity = 1

    if inst._wobble_task then
        inst._wobble_task:Cancel()
        inst._wobble_task = nil
    end

    if not inst._wobble_original_scale then
        inst._wobble_original_scale = { inst.Transform:GetScale() }
    end

    inst._momo_pet_count = (inst._momo_pet_count or 0) + 1
    if inst._momo_reset_task then
        inst._momo_reset_task:Cancel()
    end
    inst._momo_reset_task = inst:DoTaskInTime(3, function()
        inst._momo_pet_count = 0
    end)

    -- 连摸 10 次播放专属彩蛋 BGM
    if inst._momo_pet_count >= 10 then
        inst._momo_pet_count = 0
        if inst.SoundEmitter then
            pcall(function()
                inst.SoundEmitter:PlaySound("Petpet_Anything/Petpet_Anything/petpet_music")
            end)
        end
    end

    local sx, sy, sz = inst._wobble_original_scale[1], inst._wobble_original_scale[2], inst._wobble_original_scale[3]
    inst._wobble_time = 0

    inst._wobble_task = inst:DoPeriodicTask(0.016, function()
        if not inst:IsValid() then return end
        inst._wobble_time = inst._wobble_time + 0.016

        if inst._wobble_time >= duration then
            inst.Transform:SetScale(sx, sy, sz)
            if inst._wobble_task then
                inst._wobble_task:Cancel()
                inst._wobble_task = nil
            end
            inst._wobble_original_scale = nil
            return
        end

        local t = inst._wobble_time
        local decay = (1 - t / duration) ^ 2
        local wy = math.sin(t * 30) * 0.35 * decay * intensity
        local wxz = -math.sin(t * 30) * 0.15 * decay * intensity
        local micro = math.sin(t * 50 + 1.2) * 0.08 * decay * intensity

        inst.Transform:SetScale(
            sx * (1 + wxz + micro),
            sy * (1 + wy + micro),
            sz * (1 + wxz + micro)
        )
    end)
end

-- 生成摸摸特效实体
local function SpawnMomoFX(target, tool_index)
    if not target or not target:IsValid() then return end
    local data = HANDPET[tool_index] or HANDPET[math.random(1, #HANDPET)]

    local fx = GLOBAL.CreateEntity()
    fx.entity:AddTransform()
    fx.entity:AddAnimState()
    fx.entity:AddSoundEmitter()

    fx.AnimState:SetBank("handpet")
    fx.AnimState:SetBuild("handpet")
    fx.AnimState:PlayAnimation(data.anim)
    pcall(function() fx.SoundEmitter:PlaySound(data.sound) end)

    fx.Transform:SetScale(data.scale, data.scale, data.scale)
    fx.Transform:SetNoFaced()
    fx:AddTag("FX")
    fx:AddTag("NOCLICK")

    fx.entity:SetParent(target.entity)

    local height = 1.5
    if target.AnimState and target.AnimState.GetVisualBB then
        local x1, y1, x2, y2 = target.AnimState:GetVisualBB()
        if y1 and y2 then
            height = (-y1 + y2) * 0.75
        end
    end
    fx.Transform:SetPosition(0, height, 0)

    fx:ListenForEvent("animover", function()
        fx:Remove()
    end)
    fx:DoTaskInTime(1.5, function()
        if fx:IsValid() then fx:Remove() end
    end)
end

-- 播放摸摸整体逻辑
local function PlayMomo(target, tool_index)
    if not target or not target:IsValid() then return end
    SpawnMomoFX(target, tool_index)
    DoWobble(target)
end

GLOBAL.NOMU_QA.PlayMomo = PlayMomo

-- 根据 UserID 查找世界中的玩家实体
local function FindPlayerByUserID(uid)
    if not uid or uid == "" then return nil end
    if GLOBAL.ThePlayer and GLOBAL.ThePlayer.userid == uid then
        return GLOBAL.ThePlayer
    end
    if GLOBAL.AllPlayers then
        for _, player in ipairs(GLOBAL.AllPlayers) do
            if player.userid == uid then
                return player
            end
        end
    end
    return nil
end

-- 发送摸摸网络聊天信息
local function SendMomoChatMessage(target_userid, target_name, whisper)
    if GLOBAL.TheNet and target_userid then
        local tool_idx = math.random(1, #HANDPET)
        local template = (GLOBAL.NOMU_QA and GLOBAL.NOMU_QA.SCHEME and GLOBAL.NOMU_QA.SCHEME.PLAYER and GLOBAL.NOMU_QA.SCHEME.PLAYER.FORMATS and GLOBAL.NOMU_QA.SCHEME.PLAYER.FORMATS.MOMO)
            or (GLOBAL.STRINGS.DEFAULT_NOMU_QA and GLOBAL.STRINGS.DEFAULT_NOMU_QA.PLAYER and GLOBAL.STRINGS.DEFAULT_NOMU_QA.PLAYER.FORMATS and GLOBAL.STRINGS.DEFAULT_NOMU_QA.PLAYER.FORMATS.MOMO)
        local action_text = GLOBAL.subfmt(template, { NAME = target_name or "" })
        local msg = string.format("%s [Momo:%s:%d]", action_text, target_userid, tool_idx)
        GLOBAL.TheNet:Say(msg, whisper == true)
    end
end

GLOBAL.NOMU_QA.SendMomoChatMessage = SendMomoChatMessage

local oldNetworking_Say = GLOBAL.Networking_Say
GLOBAL.Networking_Say = function(guid, userid, name, prefab, message, colour, whisper, isemote, user_vanity)
    if type(message) == "string" then
        local target_uid, tool_idx = string.match(message, "%[Momo:([%w_]+):?(%d*)%]")
        if target_uid then
            local target_player = FindPlayerByUserID(target_uid)
            if target_player then
                PlayMomo(target_player, tonumber(tool_idx))
            end
            message = message:gsub("%s*%[Momo:[%w_]+:?%d*%]", "")
            if message == "" then
                local client = GLOBAL.TheNet and GLOBAL.TheNet.GetClientTableForUser and GLOBAL.TheNet:GetClientTableForUser(target_uid)
                local target_name = client and client.name or "你"
                local template = (GLOBAL.NOMU_QA and GLOBAL.NOMU_QA.SCHEME and GLOBAL.NOMU_QA.SCHEME.PLAYER and GLOBAL.NOMU_QA.SCHEME.PLAYER.FORMATS and GLOBAL.NOMU_QA.SCHEME.PLAYER.FORMATS.MOMO)
                    or (GLOBAL.STRINGS.DEFAULT_NOMU_QA and GLOBAL.STRINGS.DEFAULT_NOMU_QA.PLAYER and GLOBAL.STRINGS.DEFAULT_NOMU_QA.PLAYER.FORMATS and GLOBAL.STRINGS.DEFAULT_NOMU_QA.PLAYER.FORMATS.MOMO)
                    or "摸了摸 {NAME}。"
                message = GLOBAL.subfmt(template, { NAME = target_name })
            end
        end
    end
    return oldNetworking_Say(guid, userid, name, prefab, message, colour, whisper, isemote, user_vanity)
end