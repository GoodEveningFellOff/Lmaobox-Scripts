--[[
set this to a number between 0 and 1 for what charge you want to release the sticky at
example:
0 = instant release
1 = wait until fully charge
0.5 = wait for %50 charge
]]
local release_value = 0;


local function clamp(a,b,c) return (a<b) and b or (a>c) and c or a; end

local function GetCharge(wep)
	local m_flChargeBeginTime = (wep:GetPropFloat("PipebombLauncherLocalData", "m_flChargeBeginTime") or 0);

	if wep:GetWeaponProjectileType() ~= 4 or m_flChargeBeginTime == 0 then
		return -1
	end

	return clamp((globals.CurTime() - m_flChargeBeginTime) / ((wep:GetPropInt("m_iItemDefinitionIndex") == 1150) and 1.2 or 4), 0, 1);
end


callbacks.Register("CreateMove", function(cmd)
	local pLocal = entities.GetLocalPlayer();

	if not pLocal then
		return
	end
	
	local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon");
	
	if not pWeapon then
		return
	end

	if GetCharge(pWeapon) >= release_value then
		cmd:SetButtons(cmd.buttons & (~IN_ATTACK))
	end
end)
