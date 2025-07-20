local config = {
	r = 255;
	g = 0;
	b = 0;
	a = 255;

	duration = 4;
	fadeout = 0.25;
    max_records = 1;
};

if(config.fadeout > config.duration)then
	config.fadeout = config.duration;
end

local function GetEntityHitboxes(pEntity)
	if(not pEntity:IsValid())then
		return {};
	end

	local aHitboxes = {};
	local model = pEntity:GetModel();
	if(not model)then
		return {};
	end	

	local studiomodel = models.GetStudioModel(model);
	if(not studiomodel)then
		return {};
	end

	local setHitboxes = studiomodel:GetHitboxSet(pEntity:GetPropInt("m_nHitboxSet"));
	if(not setHitboxes)then
		return {};
	end

	local flModelScale = pEntity:GetPropFloat("m_flModelScale") or 1;
	local aBones = pEntity:SetupBones(0x7ff00, globals.CurTime());
	local aReturned = {};

	for _, hitbox in pairs(setHitboxes:GetHitboxes())do
		local mat = aBones[hitbox:GetBone()];

		if(mat)then -- aBones doesn't have an entry at index 0 so it can fail for some hitboxes.
			local vecMins = hitbox:GetBBMin() * flModelScale;
			local vecMaxs = hitbox:GetBBMax() * flModelScale;

            --[[
                Vector RotateVector(const Vector& vec, const matrix3x4_t& mat){
                    return Vector{ 
                        vec.x*mat[0][0] + vec.y*mat[0][1] + vec.z*mat[0][2],
                        vec.x*mat[1][0] + vec.y*mat[1][1] + vec.z*mat[1][2],
                        vec.x*mat[2][0] + vec.y*mat[2][1] + vec.z*mat[2][2]
                    }; // + Vector(mat[0][3], mat[1][3], mat[2][3]);
                }
            ]]
            local x11, x12, x13 = mat[1][4] + vecMins.x*mat[1][1], mat[2][4] + vecMins.x*mat[2][1], mat[3][4] + vecMins.x*mat[3][1];
            local x21, x22, x23 = mat[1][4] + vecMaxs.x*mat[1][1], mat[2][4] + vecMaxs.x*mat[2][1], mat[3][4] + vecMaxs.x*mat[3][1];
            local y11, y12, y13 = vecMins.y*mat[1][2], vecMins.y*mat[2][2], vecMins.y*mat[3][2];
            local y21, y22, y23 = vecMaxs.y*mat[1][2], vecMaxs.y*mat[2][2], vecMaxs.y*mat[3][2];
            local z11, z12, z13 = vecMins.z*mat[1][3], vecMins.z*mat[2][3], vecMins.z*mat[3][3];
            local z21, z22, z23 = vecMaxs.z*mat[1][3], vecMaxs.z*mat[2][3], vecMaxs.z*mat[3][3];

			aReturned[#aReturned + 1] = {
                Vector3(x11+y11+z11,x12+y12+z12,x13+y13+z13),
                Vector3(x21+y11+z11,x22+y12+z12,x23+y13+z13),
                Vector3(x11+y21+z11,x12+y22+z12,x13+y23+z13),
                Vector3(x21+y21+z11,x22+y22+z12,x23+y23+z13),
                Vector3(x11+y11+z21,x12+y12+z22,x13+y13+z23),
                Vector3(x21+y11+z21,x22+y12+z22,x23+y13+z23),
                Vector3(x11+y21+z21,x12+y22+z22,x13+y23+z23),
                Vector3(x21+y21+z21,x22+y22+z22,x23+y23+z23)
            };
		end		
	end

	return aReturned;
end

local g_aDrawList = {};
local g_aBBoxWeapons = (function(...)
	local aReturned = {};
	for _, i in pairs({...})do
		aReturned[i] = true;	
	end

	return aReturned;
end)(1,2,3,4,5,6,7,8,9,10,11,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,51,52,53,55,58,60,61,63,64,65,70,72,73,74,78,79,80,81,82,83,84,86,87,88,89,91,92,93,95,97,98,101,104,105,106,107,108,109);

local function TryAddHit(pAttacker, pVictim, iDamage, iWeaponID)
    local pLocalPlayer = entities.GetLocalPlayer();
    if(not pLocalPlayer or not pVictim:IsValid() or iDamage == 0 or
        pLocalPlayer:GetIndex() == pVictim:GetIndex() or pLocalPlayer:GetIndex() ~= pAttacker:GetIndex())then
        return;
    end

    if(g_aBBoxWeapons[iWeaponID])then
        local vecMins = pVictim:GetMins() + pVictim:GetAbsOrigin();
        local vecMaxs = pVictim:GetMaxs() + pVictim:GetAbsOrigin();
        table.insert(g_aDrawList, 1, {
            globals.RealTime(),
            {{
                Vector3(vecMins.x, vecMins.y, vecMins.z),
                Vector3(vecMaxs.x, vecMins.y, vecMins.z),
                Vector3(vecMins.x, vecMaxs.y, vecMins.z),
                Vector3(vecMaxs.x, vecMaxs.y, vecMins.z),
                Vector3(vecMins.x, vecMins.y, vecMaxs.z),
                Vector3(vecMaxs.x, vecMins.y, vecMaxs.z),
                Vector3(vecMins.x, vecMaxs.y, vecMaxs.z),
                Vector3(vecMaxs.x, vecMaxs.y, vecMaxs.z)
            }}
        });
    else
        table.insert(g_aDrawList, 1, {
            globals.RealTime(),
            GetEntityHitboxes(pVictim)
        });
    end

    if(#g_aDrawList <= config.max_records)then
        return;
    end

    for i = #g_aDrawList, config.max_records + 1, -1 do
        table.remove(g_aDrawList, i);
    end
end

callbacks.Register("FireGameEvent", function(ctx)
    local sEventName = ctx:GetName();
	if(sEventName == "player_hurt")then
        TryAddHit(
            entities.GetByUserID(ctx:GetInt("attacker")),
            entities.GetByUserID(ctx:GetInt("userid")),
            ctx:GetInt("damageamount"),
            ctx:GetInt("weaponid")
        );

    elseif(sEventName == "npc_hurt")then
        TryAddHit(
            entities.GetByUserID(ctx:GetInt("attacker_player")),
            entities.GetByIndex(ctx:GetInt("entindex")),
            ctx:GetInt("damageamount"),
            ctx:GetInt("weaponid")
        );

    elseif(sEventName == "player_healed")then
        TryAddHit(
            entities.GetByUserID(ctx:GetInt("healer")),
            entities.GetByUserID(ctx:GetInt("patient")),
            1,
            73 -- Only seems to trigger with crusader's crossbow
        );

	end
end);

local g_flMaxAlphaDuration = config.duration - config.fadeout;

local WORLD2SCREEN = client.WorldToScreen;
local LINE = draw.Line;
local COLOR = draw.Color;
callbacks.Register("Draw", function()
    if(engine.Con_IsVisible() or engine.IsGameUIVisible())then
		return;
	end

	local pLocalPlayer = entities.GetLocalPlayer();
	if(not pLocalPlayer)then
		return;
	end

	local iLocalPlayerIndex = pLocalPlayer:GetIndex();

	local iRemoveIndex = 0;
	local flRealTime = globals.RealTime();
	
	COLOR(255, 255, 255, 255);
	for i, aData in pairs(g_aDrawList)do
		local flDelta = math.abs(flRealTime - aData[1]); 
		if(flDelta >= config.duration)then
			iRemoveIndex = i;
			break;
		end

		if(flDelta <= g_flMaxAlphaDuration)then
			COLOR(config.r, config.g, config.b, config.a);
		else
			COLOR(config.r, config.g, config.b, math.floor((1 - (flDelta - g_flMaxAlphaDuration) / config.fadeout) * config.a));
		end

        -- No errors here but it keeps saying that the color isn't set...
        pcall(function()
            for _, aVerts in pairs(aData[2])do
                if(#aVerts == 8)then
                    local p1 = WORLD2SCREEN(aVerts[1]);
                    local p2 = WORLD2SCREEN(aVerts[2]);
                    local p3 = WORLD2SCREEN(aVerts[3]);
                    local p4 = WORLD2SCREEN(aVerts[4]);
                    local p5 = WORLD2SCREEN(aVerts[5]);
                    local p6 = WORLD2SCREEN(aVerts[6]);
                    local p7 = WORLD2SCREEN(aVerts[7]);
                    local p8 = WORLD2SCREEN(aVerts[8]);
        
                    if(p1 and p2 and p3 and p4 and p5 and p6 and p7 and p8)then
                        LINE(p1[1], p1[2], p2[1], p2[2]);
                        LINE(p1[1], p1[2], p3[1], p3[2]);
                        LINE(p1[1], p1[2], p5[1], p5[2]);
                        LINE(p2[1], p2[2], p4[1], p4[2]);
                        LINE(p2[1], p2[2], p6[1], p6[2]);
                        LINE(p3[1], p3[2], p4[1], p4[2]);
                        LINE(p3[1], p3[2], p7[1], p7[2]);
                        LINE(p4[1], p4[2], p8[1], p8[2]);
                        LINE(p5[1], p5[2], p6[1], p6[2]);
                        LINE(p5[1], p5[2], p7[1], p7[2]);
                        LINE(p6[1], p6[2], p8[1], p8[2]);
                        LINE(p7[1], p7[2], p8[1], p8[2]);
                    end
                end
            end
        end);
	end

	if(iRemoveIndex ~= 0)then
		for i = #g_aDrawList, iRemoveIndex, -1 do
            table.remove(g_aDrawList, i);
        end
	end
end);
