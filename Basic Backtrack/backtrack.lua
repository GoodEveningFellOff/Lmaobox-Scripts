local FLOOR = math.floor;
local SQRT  = math.sqrt;
local ATAN  = math.atan;
local MIN   = math.min;
local MAX   = math.max;
local ABS   = math.abs;

local CLAMP = function(a,b,c)return(a<b)and b or(a>c)and c or a;end;
local NORMALIZE_ANGLE = function(a)local i=FLOOR(a);return((i+180)%360)+a-i-180;end;


--* https://github.com/ValveSoftware/source-sdk-2013/blob/master/mp/src/game/shared/shareddefs.h#L14-L20
local TICK_INTERVAL = globals.TickInterval();

local TIME_TO_TICKS  = function(dt) return FLOOR(0.5 + dt / TICK_INTERVAL);  end;
local TICKS_TO_TIME  = function(t)  return TICK_INTERVAL * t;                end;
local ROUND_TO_TICKS = function(t)  return TICK_INTERVAL * TIME_TO_TICKS(t); end;
--*

local function CalculateFov(vecViewAngles, vecFrom, vecTo)
	local vecDelta = vecFrom - vecTo;

	return MIN(SQRT(CLAMP(
        NORMALIZE_ANGLE(ATAN(vecDelta.z / SQRT(vecDelta.x^2 + vecDelta.y^2)) * 57.295779513082 - vecViewAngles.x), 
        -89, 89)^2 + NORMALIZE_ANGLE((ATAN(vecDelta.y / vecDelta.x) * 57.295779513082) + ((vecDelta.x >= 0) and 180 or 0) - vecViewAngles.y)^2), 
        180); 
end

local aHeadshotWeapons = {
    [14]    = true; --Sniper Rifle                           tf_weapon_sniperrifle
    [201]   = true; --Sniper Rifle (Renamed/Strange)         tf_weapon_sniperrifle
    [230]   = true; --The Sydney Sleeper                     tf_weapon_sniperrifle
    [402]   = true; --The Bazaar Bargain                     tf_weapon_sniperrifle_decap
    [526]   = true; --The Machina                            tf_weapon_sniperrifle
    [664]   = true; --Festive Sniper Rifle                   tf_weapon_sniperrifle
    [752]   = true; --The Hitman's Heatmaker                 tf_weapon_sniperrifle
    [792]   = true; --Silver Botkiller Sniper Rifle Mk.I     tf_weapon_sniperrifle
    [801]   = true; --Gold Botkiller Sniper Rifle Mk.I       tf_weapon_sniperrifle
    [851]   = true; --The AWPer Hand                         tf_weapon_sniperrifle
    [881]   = true; --Rust Botkiller Sniper Rifle Mk.I       tf_weapon_sniperrifle
    [890]   = true; --Blood Botkiller Sniper Rifle Mk.I      tf_weapon_sniperrifle
    [899]   = true; --Carbonado Botkiller Sniper Rifle Mk.I  tf_weapon_sniperrifle
    [908]   = true; --Diamond Botkiller Sniper Rifle Mk.I    tf_weapon_sniperrifle
    [957]   = true; --Silver Botkiller Sniper Rifle Mk.II    tf_weapon_sniperrifle
    [966]   = true; --Gold Botkiller Sniper Rifle Mk.II      tf_weapon_sniperrifle
    [1098]  = true; --The Classic                            tf_weapon_sniperrifle_classic
    [15000] = true; --Night Owl                              tf_weapon_sniperrifle
    [15007] = true; --Purple Range                           tf_weapon_sniperrifle
    [15019] = true; --Lumber From Down Under                 tf_weapon_sniperrifle
    [15023] = true; --Shot in the Dark                       tf_weapon_sniperrifle
    [15033] = true; --Bogtrotter                             tf_weapon_sniperrifle
    [15059] = true; --Thunderbolt                            tf_weapon_sniperrifle
    [15070] = true; --Pumpkin Patch                          tf_weapon_sniperrifle
    [15071] = true; --Boneyard                               tf_weapon_sniperrifle
    [15072] = true; --Wildwood                               tf_weapon_sniperrifle
    [15111] = true; --Balloonicorn                           tf_weapon_sniperrifle
    [15112] = true; --Rainbow                                tf_weapon_sniperrifle
    [15135] = true; --Coffin Nail                            tf_weapon_sniperrifle
    [15136] = true; --Dressed to Kill                        tf_weapon_sniperrifle
    [15154] = true; --Airwolf                                tf_weapon_sniperrifle
    [30665] = true; --Shooting Star                          tf_weapon_sniperrifle

    [61]    = true; --The Ambassador                         tf_weapon_revolver
    [1006]  = true; --Festive Ambassador                     tf_weapon_revolver
};

local function ShouldTargetHead(pLocalPlayer, pLocalWeapon)
    local iClass = pLocalPlayer:GetPropInt("m_iClass");

    if (iClass ~= 2 and iClass ~= 8) or (not aHeadshotWeapons[pLocalWeapon:GetPropInt("m_iItemDefinitionIndex")]) then
        return false;
    end

    if iClass == 2 then --TF2_Sniper
        return pLocalWeapon:GetPropFloat("SniperRifleLocalData", "m_flChargedDamage") > 0;
    end

    return true;
end

local g_stLatency = {
    m_flOutgoing = 0;
    m_flIncoming = 0;
};

local g_aRecords = {};

callbacks.Register("CreateMove", function(cmd)
    local pLocalPlayer = entities.GetLocalPlayer();
    if not pLocalPlayer then
        return;
    end

    local pNetChannel = clientstate.GetNetChannel();
    if pNetChannel then
        g_stLatency.m_flOutgoing = pNetChannel:GetLatency(0); -- FLOW_OUTGOING
        g_stLatency.m_flIncoming = pNetChannel:GetLatency(1); -- FLOW_INCOMING
    end

    local iTick = globals.TickCount();
    local iLocalTeam = pLocalPlayer:GetTeamNumber();   

    local laPlayers = entities.FindByClass("CTFPlayer");
    laPlayers[pLocalPlayer:GetIndex()] = nil;


    for i, pEnt in pairs(laPlayers) do
        if pEnt:IsAlive() and pEnt:GetTeamNumber() ~= iLocalTeam and not pEnt:IsDormant() then
            if not g_aRecords[i] then
                g_aRecords[i] = {};
            end
        
            local pRecords = g_aRecords[i];
            local aSurroundingBox = pEnt:HitboxSurroundingBox();
            local aHitboxes = pEnt:GetHitboxes();
            local aChest = aHitboxes[4];
            local aHead = aHitboxes[1];

            table.insert(pRecords, 1, {
                m_iTick    = iTick;
                m_vecChest = aChest[1] + (aChest[2] - aChest[1]) * 0.5;
                m_vecHead  = aHead[1]  + (aHead[2]  - aHead[1])  * 0.5;
            });
            
            if #pRecords > 80 then
                table.remove(pRecords, 81);
            end

        else
            if g_aRecords[i] then
                g_aRecords[i] = nil;
            end
        end
    end

    if (cmd.buttons & IN_ATTACK) == 0 then
        return;
    end

    local pLocalWeapon = pLocalPlayer:GetPropEntity("m_hActiveWeapon");
    if not pLocalWeapon then
        return;
    end

    if (pLocalWeapon:GetWeaponProjectileType() or 0) > 1 and not pLocalWeapon:IsMeleeWeapon() then
        return;
    end

    local bShouldTargetHead = ShouldTargetHead(pLocalPlayer, pLocalWeapon);

    local iLatencyTicks = TIME_TO_TICKS(g_stLatency.m_flIncoming);

    local iCurrentTick = iTick - iLatencyTicks;
    local iLatestTick = iCurrentTick + MIN(iLatencyTicks, TIME_TO_TICKS(0.2));
    local iOldestTick = iCurrentTick - TIME_TO_TICKS(0.2);

    local vecLocalEyePos = pLocalPlayer:GetAbsOrigin() + pLocalPlayer:GetPropVector("localdata", "m_vecViewOffset[0]");
    local vecViewAngles = cmd.viewangles;

    local flCheckedFov = 0;
    local flBestFov = 180;
    local iBestTick = -1;

    if bShouldTargetHead then
        for i, pRecords in pairs(g_aRecords) do
            if #pRecords == 0 then
                g_aRecords[i] = nil;
                goto continue;
            end

            if ABS(pRecords[1].m_iTick - iTick) >= 660 then
                g_aRecords[i] = nil;
                goto continue;
            end

            for _, stRecord in pairs(pRecords) do
                if stRecord.m_iTick <= iLatestTick and stRecord.m_iTick >= iOldestTick then
                    flCheckedFov = CalculateFov(vecViewAngles, vecLocalEyePos, stRecord.m_vecHead);

                    if flCheckedFov < flBestFov then
                        flBestFov, iBestTick = flCheckedFov, stRecord.m_iTick;
                    end
                end
            end

            ::continue::
        end

    else
        for i, pRecords in pairs(g_aRecords) do
            if #pRecords == 0 then
                g_aRecords[i] = nil;
                goto continue;
            end

            if ABS(pRecords[1].m_iTick - iTick) >= 660 then
                g_aRecords[i] = nil;
                goto continue;
            end

            for _, stRecord in pairs(pRecords) do
                if stRecord.m_iTick <= iLatestTick and stRecord.m_iTick >= iOldestTick then
                    flCheckedFov = CalculateFov(vecViewAngles, vecLocalEyePos, stRecord.m_vecChest);

                    if flCheckedFov < flBestFov then
                        flBestFov, iBestTick = flCheckedFov, stRecord.m_iTick;
                    end
                end
            end

            ::continue::
        end
    end

    if iBestTick ~= -1 then
        cmd.tick_count = iBestTick;
    end
end)
