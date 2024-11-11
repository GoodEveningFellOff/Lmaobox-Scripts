local function ShouldFakeLatency()
	pLocal = entities.GetLocalPlayer();
	if not pLocal or not pLocal:IsAlive() then 
		return true
	end
	
	pWeapon = pLocal:GetPropEntity("m_hActiveWeapon");
	if not pWeapon then 
		return true
	end

	local projectile_type = pWeapon:GetWeaponProjectileType() or 0;
	if projectile_type <= 1 then
		return true
	end

	return false
end

local function SetValue(element, value)
	if gui.GetValue(element) == value then
		return
	end

	gui.SetValue(element, value)
end

callbacks.Register("CreateMove", function(cmd)
	SetValue("Fake Latency", ShouldFakeLatency() and 1 or 0)
end)
