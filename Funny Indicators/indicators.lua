local function RendererIndicator(...) end
do
    local g_flScale = 0;
    local g_mapFonts = {};

    local g_iY = 0;
    local g_iYOffset = 0;
    local g_iXOffset = 0;
    local g_iFadeXAdd = 0;

    local g_texture = (function()
        local chars = {}
        for _ = 1, 2 do
            for i = 0, 255 do
                local n = #chars
                chars[n + 1], chars[n + 2], chars[n + 3], chars[n + 4] = 255, 255, 255,
                    math.floor(math.sin(math.rad((i / 255) * 180)) * 100);
            end
        end
        return draw.CreateTextureRGBA(string.char(table.unpack(chars)), 256, 2);
    end)();

    callbacks.Register("Unload", function()
        draw.DeleteTexture(g_texture);
    end);

    callbacks.Register("RenderView", function(ctx)
        local flScale = ctx.height / 1080;
        if(flScale == 0)then
            return;
        end
        
        if(not g_mapFonts[flScale])then
            g_mapFonts[flScale] = { 
                draw.CreateFont("Calibri", math.floor(flScale * 28), 600, 1168),
                draw.CreateFont("Calibri", math.floor(flScale * 28), 600, 0)
            };
        end

        g_flScale = flScale;
        g_iY = ctx.height - math.floor(flScale * 349);
        g_iYOffset = math.floor(g_flScale * 41);
        g_iTextOffset = math.floor(g_flScale * 3);
        g_iFadeOffset = math.floor(g_flScale * 33);
        g_iX = math.floor(g_flScale * 30);
        g_iFadeAdd = math.floor(g_flScale * 20);
    end);

    function RendererIndicator(aColor, sText, flFraction)
        local aFonts = g_mapFonts[g_flScale];
        if(not aFonts)then
            return;
        end

        local iTextWidth = draw.GetTextSize(sText)
        draw.Color(0, 0, 0, aColor[4]);
        draw.TexturedRect(g_texture, g_iX - g_iFadeAdd, g_iY, g_iX + g_iFadeAdd + iTextWidth, g_iY + g_iFadeOffset);
        draw.Color(0, 0, 0, math.floor(aColor[4] * 155 / 255));
        draw.SetFont(aFonts[2]);
        draw.Text(g_iX + 1, g_iY + g_iTextOffset + 1, sText);
        draw.SetFont(aFonts[1]);
        draw.Color(aColor[1], aColor[2], aColor[3], aColor[4]);
        draw.Text(g_iX, g_iY + g_iTextOffset, sText);

        if(flFraction and flFraction > 0 and flFraction < 1)then
            draw.Color(0, 0, 0, math.floor(aColor[4] * 155 / 255));
            draw.FilledRect(g_iX + 1, 
                g_iY + math.floor(g_flScale * 28) + 1,
                g_iX + math.floor(iTextWidth * flFraction + 0.5) + 1,
                g_iY + math.floor(g_flScale * 31) + 1);

            draw.Color(aColor[1], aColor[2], aColor[3], aColor[4]);
            draw.FilledRect(g_iX, 
                g_iY + math.floor(g_flScale * 28),
                g_iX + math.floor(iTextWidth * flFraction + 0.5),
                g_iY + math.floor(g_flScale * 31));
        end

        g_iY = g_iY - g_iYOffset;
    end
end

local CanWeaponRandomCrit = (function()
    local blacklist = (function()
        local t = {};
        for i = 0, 109 do
            for _, v in pairs({0,7,17,45,46,47,48,49,50,59,60,61,62,64,67,69,70,74,77,79,80,84,86,99,103,104,105,107,109}) do
                if v == i then
                    t[i] = true
                    break;
                end
            end
        end
        return t;
    end)()
    local function CanRandomCrit(c)
        local a, b = client.GetConVar("tf_weapon_criticals_melee") or 0, client.GetConVar("tf_weapon_criticals") or 0
        return ((c & b) | (a & b & -3) | (~c & (a >> 1))) == 1;
    end
    return function(ent)
        if(not ent or not CanRandomCrit(ent:IsMeleeWeapon() and 0 or 1))then
            return false;
        end

        local tokenBucket = ent:GetCritTokenBucket();
        local critCost = math.floor(ent:GetCritCost(tokenBucket, ent:GetCritSeedRequestCount(), ent:GetCritCheckCount()) or 0);
        return critCost ~= 0 and not blacklist[ent:GetWeaponID()] and ent:GetCritChance() > math.max(0, ent:CalcObservedCritChance() - 0.1) and tokenBucket >= critCost;
    end
end)();

local can_crit, is_ducking = false, false
callbacks.Register("CreateMove", function(cmd)
    local pLocal = entities.GetLocalPlayer()
    if not pLocal then
        return
    end
    can_crit, is_ducking = CanWeaponRandomCrit(pLocal:GetPropEntity("m_hActiveWeapon")), gui.GetValue("Duck Speed") == 1 and ((pLocal:GetPropInt("m_fFlags") or 0) & 3) == 3;
end);

callbacks.Register("Draw", function()
    local pLocalPlayer = entities.GetLocalPlayer();
    local pLocal = entities.GetLocalPlayer()
    if not pLocal or not pLocal:IsAlive() then
        return
    end

    local goal_latency = gui.GetValue("Fake Latency Value (ms)")
    local fake_latency = math.min(math.floor((clientstate.GetLatencyIn() or 0) * 1000) / goal_latency, 1)

    local aWhite = { 205, 205, 205, 255 };
    local aRed = { 204, 45, 45, 255 };

    if goal_latency > 50 and fake_latency > 0.25 then
        RendererIndicator({
            205 - math.floor(46 * fake_latency), 
            45 + math.floor(159 * fake_latency), 
            45, 255}, "PING");
    end

    if is_ducking then
        RendererIndicator(aWhite, "DUCK");
    end



    do
        local iCharge = warp.GetChargedTicks();
        RendererIndicator((iCharge >= 23) and aWhite or aRed, "DT", iCharge / 23);
    end
    
    RendererIndicator((can_crit) and aWhite or aRed, "CRIT");

    if gui.GetValue("Fake Lag") == 1 then
        RendererIndicator(aWhite, "FL");
    end

    if gui.GetValue("Anti Backstab") == 1 then
        RendererIndicator(aWhite, "AB");
    end
end)
