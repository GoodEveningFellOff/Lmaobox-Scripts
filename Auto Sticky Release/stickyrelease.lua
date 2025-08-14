local config = {
	-- Only use the final stickybomb location to determine if attack should be released (default false).
	only_final_position = false;

	-- 0 to 1, Lower to decrease the size of the explosion radius to scan for (default 0.8).
	explosion_radius_scale = 0.8;

	-- 1 to 10, Trace explosion every n simulation ticks (default 3).
	measure_ticks_mod = 3;
};

-- Boring shit ahead!
local CLAMP = (function(a,b,c)return(a<b)and b or(a>c)and c or a;end);
local VEC_CLAMP = (function(a,b,c)return Vector3(CLAMP(a.x,b.x,c.x),CLAMP(a.y,b.y,c.y),CLAMP(a.z,b.z,c.z));end);
local VEC_ROT = (function(a,b)return(b:Forward()*a.x)+(b:Right()*a.y)+(b:Up()*a.z);end);
local VEC_BBOX_DIST = (function(a,b,c,d)return(b+VEC_CLAMP(a-b,c,d)-a):Length();end);
local TRACE_HULL = engine.TraceHull;
local TRACE_LINE = engine.TraceLine;

local PhysicsEnvironment = physics.CreateEnvironment();
PhysicsEnvironment:SetGravity(Vector3(0, 0, -800));
PhysicsEnvironment:SetAirDensity(2.0);
PhysicsEnvironment:SetSimulationTimestep(1 / 66);

local GetPhysicsObject = {};
do
	GetPhysicsObject.m_mapObjects = {};
	GetPhysicsObject.m_sActiveObject = "";

	function GetPhysicsObject:Shutdown()
		self.m_sActiveObject = "";

		for sKey, pObject in pairs(self.m_mapObjects) do
			PhysicsEnvironment:DestroyObject(pObject);
		end
	end;

	setmetatable(GetPhysicsObject, {
		__call = function(self, sRequestedObject)
			local pObject = self.m_mapObjects[sRequestedObject];
			if(self.m_sActiveObject == sRequestedObject)then
				return pObject;
			end

			local pActiveObject = self.m_mapObjects[self.m_sActiveObject];
			if(pActiveObject)then
				pActiveObject:Sleep();
			end

			if(not pObject and sRequestedObject:len() > 0)then
				local solid, model = physics.ParseModelByName(sRequestedObject);
				if(not solid or not model)then
					error(string.format("Invalid object path \"%s\"!", sRequestedObject));
				end

				self.m_mapObjects[sRequestedObject] = PhysicsEnvironment:CreatePolyObject(model, solid:GetSurfacePropName(), solid:GetObjectParameters());
				pObject = self.m_mapObjects[sRequestedObject];
			end
			
			self.m_sActiveObject = sRequestedObject;
			pObject:Wake();
			return pObject;
		end;
	});
end

local g_flTraceInterval = 1 / 66;
local g_iLocalTeamNumber = 0;

local function GetEntityEyePosition(pEntity)
	local sClass = pEntity:GetClass();
	local vecMins = pEntity:GetMins();
	local vecMaxs = pEntity:GetMaxs();
	local vecAbsOrigin = pEntity:GetAbsOrigin();
	local flModelScale = pEntity:GetPropFloat("m_flModelScale");

	if(sClass == "CObjectSentrygun")then
		local iUpgradeLevel = pEntity:GetPropInt("m_iUpgradeLevel");
		if(iUpgradeLevel == 1)then
			return vecAbsOrigin + Vector3(0, 0, 32) * flModelScale;

		elseif(iUpgradeLevel == 2)then
			return vecAbsOrigin + Vector3(0, 0, 40) * flModelScale;

		else
			return vecAbsOrigin + Vector3(0, 0, 46) * flModelScale;
		end

	elseif(sClass == "CTFPlayer")then
		if(pEntity:GetPropInt("m_fFlags") & FL_DUCKING ~= 0)then
			return vecAbsOrigin + Vector3(0, 0, 45) * flModelScale;
		end

		local iClass = pEntity:GetPropInt("m_iClass");
		if(iClass == 0)then -- TF_CLASS_UNDEFINED
			return vecAbsOrigin + Vector3(0, 0, 72) * flModelScale;

		elseif(iClass == 1)then -- TF_CLASS_SCOUT, TF_FIRST_NORMAL_CLASS
			return vecAbsOrigin + Vector3(0, 0, 65) * flModelScale;

		elseif(iClass == 2)then -- TF_CLASS_SNIPER
			return vecAbsOrigin + Vector3(0, 0, 75) * flModelScale;

		elseif(iClass == 3)then -- TF_CLASS_SOLDIER
			return vecAbsOrigin + Vector3(0, 0, 68) * flModelScale;

		elseif(iClass == 4)then -- TF_CLASS_DEMOMAN
			return vecAbsOrigin + Vector3(0, 0, 68) * flModelScale;

		elseif(iClass == 5)then -- TF_CLASS_MEDIC
			return vecAbsOrigin + Vector3(0, 0, 75) * flModelScale;

		elseif(iClass == 6)then -- TF_CLASS_HEAVYWEAPONS
			return vecAbsOrigin + Vector3(0, 0, 75) * flModelScale;

		elseif(iClass == 7)then -- TF_CLASS_PYRO
			return vecAbsOrigin + Vector3(0, 0, 68) * flModelScale;

		elseif(iClass == 8)then -- TF_CLASS_SPY
			return vecAbsOrigin + Vector3(0, 0, 75) * flModelScale;

		elseif(iClass == 9)then -- TF_CLASS_ENGINEER
			return vecAbsOrigin + Vector3(0, 0, 68) * flModelScale;

		elseif(iClass == 10)then -- TF_CLASS_CIVILIAN, TF_LAST_NORMAL_CLASS
			return vecAbsOrigin + Vector3(0, 0, 65) * flModelScale;
		end
	end

	return vecAbsOrigin + vecMins + (vecMaxs - vecMins) / 2;
end

local function DoRadialDamageTrace(vecStartPos, vecEndPos, iEntityIndex)
	local resultTrace = TRACE_LINE(vecStartPos, vecEndPos, 1174421507, function(pEntity, iMask) -- MASK_SHOT_BRUSHONLY | CONTENTS_MONSTER | CONTENTS_HITBOX
		if(not pEntity:IsValid() or pEntity:GetTeamNumber() == g_iLocalTeamNumber)then
			return false;
		end

		local iCollisionGroup = pEntity:GetPropInt("m_CollisionGroup");
		if(iCollisionGroup == 25 or   -- TFCOLLISION_GROUP_RESPAWNROOMS 
			iCollisionGroup == 1)then -- COLLISION_GROUP_DEBRIS
			return false;
		end
		
		if(iCollisionGroup == 0)then -- COLLISION_GROUP_NONE
			return true;
		end

		if(iCollisionGroup == 20  or   -- TF_COLLISIONGROUP_GRENADES
			iCollisionGroup == 24 or   -- TFCOLLISION_GROUP_ROCKETS
			iCollisionGroup == 27)then -- TFCOLLISION_GROUP_ROCKET_BUT_NOT_WITH_OTHER_ROCKETS   
			return false;
		end

		return true;
	end);

	return resultTrace.fraction == 1 or resultTrace.entity:GetIndex() == iEntityIndex;
end

local g_aEnemies = {};

local function UpdateEnemies()
	g_aEnemies = {};

	for _, sKey in pairs({
		"CTFPlayer"
	}) do
		local aEnts = entities.FindByClass(sKey) or {};
		for _, pEntity in pairs(aEnts)do
			local vecOrigin = pEntity:GetAbsOrigin();
			if(pEntity:GetTeamNumber() ~= g_iLocalTeamNumber and pEntity:IsAlive() and not pEntity:IsDormant())then
				g_aEnemies[#g_aEnemies + 1] = {
					pEntity:GetIndex(),
					pEntity:GetAbsOrigin(), 
					pEntity:GetMins(), 
					pEntity:GetMaxs(), 
					GetEntityEyePosition(pEntity)
				};
			end
		end
	end

	for _, sKey in pairs({
		"CObjectTeleporter",
		"CObjectSentrygun",
		"CObjectDispenser",
		"CZombie",
		"CMerasmus", -- Merasmus' collision for projectiles and explosions is just fucked...
		"CEyeballBoss",
		"CHeadlessHatman",
		"CBotNPC",
		"CTFTankBoss"
	}) do
		local aEnts = entities.FindByClass(sKey) or {};
		for _, pEntity in pairs(aEnts)do
			if(pEntity:GetTeamNumber() ~= g_iLocalTeamNumber and not pEntity:IsDormant())then
				g_aEnemies[#g_aEnemies + 1] = {
					pEntity:GetIndex(),
					pEntity:GetAbsOrigin(), 
					pEntity:GetMins(), 
					pEntity:GetMaxs(), 
					GetEntityEyePosition(pEntity)
				};
			end
			
		end
	end
end

local function CanDealRadialDamage(flRadius, vecCenter)
	if(flRadius <= 0)then
		return false;
	end

	for _, stEnemy in pairs(g_aEnemies)do
		if(VEC_BBOX_DIST(vecCenter, stEnemy[2], stEnemy[3], stEnemy[4]) <= flRadius)then
			if(DoRadialDamageTrace(vecCenter, stEnemy[5], stEnemy[1]))then
				return true;
			end
		end
	end

	return false;
end

local function ShouldReleaseSticky(pObject, flPrimerTime, flExplosionRadius)
	UpdateEnemies();

	local vecMins = Vector3(-3.5, -3.5, -3.5);
	local vecMaxs = Vector3(3.5, 3.5, 3.5);

	local mapCollisions = {};
	for i = 1, 330 do
		local vecStart = pObject:GetPosition();
		PhysicsEnvironment:Simulate(g_flTraceInterval);

		local bHitEnemy = false;
		local resultTrace = TRACE_HULL(vecStart, pObject:GetPosition(), vecMins, vecMaxs, 33570827, function(pEntity, iMask)
			if(not pEntity:IsValid())then
				return false;
			end

			local iCollisionGroup = pEntity:GetPropInt("m_CollisionGroup");
			if(iCollisionGroup == 25 or   -- TFCOLLISION_GROUP_RESPAWNROOMS 
				iCollisionGroup == 1)then -- COLLISION_GROUP_DEBRIS
				return false;
			end
			
			if(iCollisionGroup == 0)then -- COLLISION_GROUP_NONE
				return true;
			end

			if(pEntity:GetTeamNumber() ~= g_iLocalTeamNumber)then
				bHitEnemy = true;
				return true;
			end

			if(iCollisionGroup == 20  or   -- TF_COLLISIONGROUP_GRENADES
				iCollisionGroup == 24 or   -- TFCOLLISION_GROUP_ROCKETS
				iCollisionGroup == 27)then -- TFCOLLISION_GROUP_ROCKET_BUT_NOT_WITH_OTHER_ROCKETS   
				return false;
			end

			if(not pEntity:IsPlayer() or mapCollisions[pEntity:GetIndex()])then
				return false;
			end

			return i * g_flTraceInterval > 0.25;
		end);
		
		if(bHitEnemy and resultTrace.entity:IsValid() and resultTrace.entity:GetPropInt("m_CollisionGroup") ~= 0)then
			PhysicsEnvironment:ResetSimulationClock();
			return true;
		end

		if(resultTrace.fraction ~= 1)then
			if(CanDealRadialDamage(flExplosionRadius, resultTrace.endpos))then
				PhysicsEnvironment:ResetSimulationClock();
				return true;
			end
			break;
		end

		if(i * g_flTraceInterval > flPrimerTime and not config.only_final_position and i % config.measure_ticks_mod == 0)then
			if(CanDealRadialDamage(flExplosionRadius * (0.85 + CLAMP(((i * g_flTraceInterval) - 0.8) / 2, 0, 1) * 0.15), resultTrace.endpos))then
				PhysicsEnvironment:ResetSimulationClock();
				return true; 
			end
		end
	end

	PhysicsEnvironment:ResetSimulationClock();
	return false;
end

callbacks.Register("CreateMove", function(cmd)
	local pLocalPlayer = entities.GetLocalPlayer();
	if(not pLocalPlayer or pLocalPlayer:InCond(7) or not pLocalPlayer:IsAlive())then
		return;
	end

	g_iLocalTeamNumber = pLocalPlayer:GetTeamNumber();

	local pLocalWeapon = pLocalPlayer:GetPropEntity("m_hActiveWeapon");
	if(not pLocalWeapon)then
		return;
	end

	if(pLocalWeapon:GetWeaponID() ~= 24)then -- TF_WEAPON_PIPEBOMBLAUNCHER
		return;
	end

	-- Make sure we are starting to charge the sticky launcher and that we are not using the sticky jumper.
	local iItemDefIdx = pLocalWeapon:GetPropInt("m_iItemDefinitionIndex");
	local flChargeBeginTime = pLocalWeapon:GetChargeBeginTime() or 0;
	if(iItemDefIdx == 265 or flChargeBeginTime == 0)then -- Sticky Jumper
		return;
	end

	local vecVelocity = Vector3(0, 0, 0);
	local sModel = "";

	-- Get the stickybomb model and the velocity of the projectile with the current charge.
	if(iItemDefIdx == 1150)then -- The Quickiebomb Launcher
		sModel = "models/workshop/weapons/c_models/c_kingmaker_sticky/w_kingmaker_stickybomb.mdl";
		vecVelocity = Vector3(900 + CLAMP((globals.CurTime() - flChargeBeginTime) / 1.2, 0, 1) * 1500, 0, 200);

	else
		-- The Scottish Resistance
		sModel = (iItemDefIdx == 130) and "models/weapons/w_models/w_stickybomb_d.mdl" or "models/weapons/w_models/w_stickybomb.mdl";
		vecVelocity = Vector3(900 + CLAMP((globals.CurTime() - flChargeBeginTime) / 4, 0, 1) * 1500, 0, 200);
	end

	-- Get the shoot position and angle.
	local vecLocalView = pLocalPlayer:GetAbsOrigin() + pLocalPlayer:GetPropVector("localdata", "m_vecViewOffset[0]");
	local vecViewAngles = engine.GetViewAngles();
	local resultTrace = TRACE_HULL(vecLocalView, 
		vecLocalView + VEC_ROT(pLocalWeapon:IsViewModelFlipped() and Vector3(16, -8, -6) or Vector3(16, 8, -6), vecViewAngles), 
		-Vector3(8, 8, 8), Vector3(8, 8, 8), 100679691);

	if(resultTrace.startsolid)then
		return;
	end

	-- Get the time it takes before the stickybomb can be detonated.
	local flPrimerTime = pLocalWeapon:AttributeHookFloat("sticky_arm_time", 0.8);
	if(pLocalPlayer:GetCarryingRuneType() == 1)then -- RUNE_HASTE
		flPrimerTime = flPrimerTime / 2;

	elseif(pLocalPlayer:GetCarryingRuneType() == 9 or pLocalPlayer:InCond(109))then -- RUNE_KING, TF_COND_KING_BUFFED
		flPrimerTime = flPrimerTime * 0.75;
	end

	-- Prepare the object for simulation.
	local pObject = GetPhysicsObject(sModel);
	pObject:SetPosition(resultTrace.endpos, vecViewAngles, true);
	pObject:SetVelocity(VEC_ROT(vecVelocity, vecViewAngles), Vector3(600, 0, 0));

	-- Simulate the object.
	if(ShouldReleaseSticky(pObject, flPrimerTime, config.explosion_radius_scale * pLocalWeapon:AttributeHookFloat("mult_explosion_radius", 150)))then
		cmd:SetButtons(cmd.buttons & (~1)); -- IN_ATTACK
	end
end);

callbacks.Register("Unload", function()
	GetPhysicsObject:Shutdown();
	physics.DestroyEnvironment(PhysicsEnvironment);
end)
