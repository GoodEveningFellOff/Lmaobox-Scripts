local g_flDebugStartTime = os.clock();
local function LOG(sMsg)
	printc(0x9b, 0xff, 0x37, 0xff, string.format("[ln: %d, cl: %0.3f] %s", debug.getinfo(2, 'l').currentline, os.clock() - g_flDebugStartTime, sMsg));
end

LOG("Script load started!");

local config = {
	polygon = {
		enabled = true;
		size = 10;
	};
	
	line = {
		color_hit = {
			r = 150;
			g = 200;
			b = 59;
			a = 255;
		};

		color_miss = {
			r = 255;
			g = 50;
			b = 50;
			a = 179;
		};

		thickness = 2;
	};

	camera = {
		enabled = false;
		
		x = 100;
		y = 300;

		aspect_ratio = 4 / 3; -- (4 / 3) (16 / 10) (16 / 9)
		height = 400;

		source = {
			scale = 0.5; -- Increase to upscale or downscale the image quality
			fov = 110;
			distance = 200;
			angle = 30;
		};
	};

	spells = {
		prefer_showing_spells = false; -- prefer showing spells over current projectile weapon
		show_other_key = -1; -- https://lmaobox.net/lua/Lua_Constants/
		is_toggle = false;
	};

	-- 0.5 to 8, determines the size of the segments traced, lower values = worse performance (default 2)
	measure_segment_size = 2;

	-- Projectile bounce visualization can be extremely inaccurate. (default false)
	enable_bounce = true;

	-- Can improve performance while using any weapons with radial damage with the the downside of reduced accuracy (short circuit and dragon's fury) 
	disable_extra_radial_points = false;
};


-- Boring shit ahead!
local CROSS = (function(a,b,c)return(b[1]-a[1])*(c[2]-a[2])-(b[2]-a[2])*(c[1]-a[1]);end);
local CLAMP = (function(a,b,c)return(a<b)and b or(a>c)and c or a;end);
local VEC_CLAMP = (function(a,b,c)return Vector3(CLAMP(a.x,b.x,c.x),CLAMP(a.y,b.y,c.y),CLAMP(a.z,b.z,c.z));end);
local VEC_ROT = (function(a,b)return(b:Forward()*a.x)+(b:Right()*a.y)+(b:Up()*a.z);end);
local VEC_BBOX_DIST = (function(a,b,c,d)return(b+VEC_CLAMP(a-b,c,d)-a):Length();end);
local FLOOR = math.floor;
local TRACE_HULL = engine.TraceHull;
local TRACE_LINE = engine.TraceLine;
local WORLD2SCREEN = client.WorldToScreen;
local POLYGON = draw.TexturedPolygon;
local LINE = draw.Line;
local OUTLINED_RECT = draw.OutlinedRect;
local COLOR = draw.Color;

local textureFill = draw.CreateTextureRGBA(string.char(255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255), 2, 2);
local g_bIsZombieInfection = false;
local g_iPolygonTexture;
do
	local iRad = 128;
	local aData = {};
	for i = 1, iRad * 2 do
		local flY = (i / (iRad * 2) - 0.5) * 2; 
		for i2 = 1, iRad * 2 do
			local flX = (i2 / (iRad * 2) - 0.5) * 2;
			local flDist = math.sqrt(flY^2 + flX^2);

			local n = #aData;
			if(flDist > 1)then
				aData[n + 1] = 0;
				aData[n + 2] = 0;
				aData[n + 3] = 0;
				aData[n + 4] = 0;
			
			else
				aData[n + 1] = 0xff;
				aData[n + 2] = 0xff;
				aData[n + 3] = 0xff;
				aData[n + 4] = math.floor((math.cos((flDist) * math.pi / 2 + math.pi / 2) + 1) * 255 + 0.5);
			end
		end
	end

	g_iPolygonTexture = draw.CreateTextureRGBA(string.char(table.unpack(aData)), 256, 256);
end

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

local function DrawMarkerPolygon(vecOrigin, vecPlane)
	local aCords = {};
	local positions = {};
	local radius = config.polygon.size;

	if math.abs(vecPlane.z) >= 0.99 then
		for i = 1, 12 do
			local ang = i * 0.523598776 + 0.261799388;
			local flCos, flSin = math.cos(ang), math.sin(ang);
			local pos = WORLD2SCREEN(vecOrigin + Vector3(radius * math.cos(ang), radius * math.sin(ang), 0));
			if(not pos)then
				return;
			end

			aCords[i] = { pos[1], pos[2], (flCos + 1) / 2, (flSin + 1) / 2};	
		end

	else
		local right = Vector3(-vecPlane.y, vecPlane.x, 0);
		local up = Vector3(vecPlane.z * right.y, -vecPlane.z * right.x, (vecPlane.y * right.x) - (vecPlane.x * right.y));

		radius = radius / math.cos(math.asin(vecPlane.z))

		for i = 1, 12 do
			local ang = i * 0.523598776 + 0.261799388;
			local flCos, flSin = math.cos(ang), math.sin(ang);
			local pos = WORLD2SCREEN(vecOrigin + (right * (radius * flCos)) + (up * (radius * flSin)));
			if(not pos)then
				return;
			end

			aCords[i] = { pos[1], pos[2], (flCos + 1) / 2, (flSin + 1) / 2};	
		end
	end

	do
		local aReverseCords = {};
		local flSum = 0;

		for i, pos in pairs(aCords) do
			aReverseCords[#aCords - i + 1] = pos;
			flSum = flSum + CROSS(pos, aCords[(i % #aCords) + 1], aCords[1]);
		end

		POLYGON(g_iPolygonTexture, (flSum < 0) and aReverseCords or aCords, true)
	end
end

local ImpactMarkers = {};
do
	ImpactMarkers.m_bIsHit = false;
	ImpactMarkers.m_aPositions = {};
	ImpactMarkers.m_iSize = 0;
	ImpactMarkers.m_iTexture = 0;

	local aData = {};
	local function IClr(b,a,n)
		for i = 1, (n or 1) do
			local s = #aData;
			aData[s + 1] = b and 0 or 255;
			aData[s + 2] = b and 0 or 255;
			aData[s + 3] = b and 0 or 255;
			aData[s + 4] = a;
		end
	end

	IClr(true, 0, 1);
	IClr(true, 155, 4);
	IClr(true, 0, 3);

	IClr(true, 155, 1);
	IClr(false, 255, 3);
	IClr(true, 155, 2);
	IClr(true, 0, 2);

	for i = 1, 2 do
		IClr(true, 155, 1);
		IClr(false, 255, 4);
		IClr(true, 155, 1);
		IClr(true, 0, 2);
	end

	IClr(true, 155, 2);
	IClr(false, 255, 3);
	IClr(true, 155, 1);
	IClr(true, 0, 2);

	IClr(true, 0, 1);
	IClr(true, 155, 4);
	IClr(true, 0, 3);

	for i = 1, 2 do
		IClr(true, 0, 8);
	end

	ImpactMarkers.m_iTexture = draw.CreateTextureRGBA(string.char(table.unpack(aData)), 8, 8);

	function ImpactMarkers:Insert(vecOrigin, vecPlane)
		self.m_iSize = self.m_iSize + 1;
		self.m_aPositions[self.m_iSize] = { vecOrigin, vecPlane };
	end

	local function Quicksort(...)end
	function Quicksort(aInput, iLeft, iRight)
		if(iLeft >= iRight)then
			return;
		end

		local iSwapIndex = iLeft;
		for i = iLeft + 1, iRight do
			if(aInput[i][1] < aInput[iSwapIndex][1])then
				if(i == iSwapIndex + 1)then
					aInput[iSwapIndex], aInput[iSwapIndex + 1] = aInput[iSwapIndex + 1], aInput[iSwapIndex];
				else
					aInput[iSwapIndex], aInput[iSwapIndex + 1], aInput[i] = aInput[i], aInput[iSwapIndex], aInput[iSwapIndex + 1];
				end

				iSwapIndex = iSwapIndex + 1;
			end
		end
	end

	function ImpactMarkers:Sort()
		if(self.m_iSize == 0)then
			return;
		end

		local vecView = client.GetPlayerView().origin;
		local aPositions = {};
		for i = 1, self.m_iSize do
			aPositions[i] = { (self.m_aPositions[i][1] - vecView):LengthSqr(), self.m_aPositions[i][1], self.m_aPositions[i][2], i == self.m_iSize };
		end

		Quicksort(aPositions, 1, self.m_iSize);
		self.m_aPositions = aPositions;
	end

	function ImpactMarkers:DrawPolygons()
		if(self.m_iSize == 0 or not config.polygon.enabled)then
			return;
		end

		for i = self.m_iSize, 1, -1 do
			if(self.m_aPositions[i][3])then
				if(self.m_aPositions[i][4])then
					if(not self.m_bIsHit)then
						COLOR(255, 0, 40, 75);
					else
						COLOR(0, 255, 40, 75);
					end
				else
					COLOR(255, 255, 255, 35);
				end

				DrawMarkerPolygon(self.m_aPositions[i][2], self.m_aPositions[i][3]);
			end
		end
	end

	setmetatable(ImpactMarkers, {
		__call = function(self)
			for i = self.m_iSize, 1, -1 do
				local pos = WORLD2SCREEN(self.m_aPositions[i][2]);
				if(pos)then
					if(self.m_aPositions[i][4])then
						if(not self.m_bIsHit)then
							COLOR(255, 0, 40, 255);
						else
							COLOR(0, 255, 40, 255);
						end
					else
						COLOR(200, 200, 200, 200);
					end

					draw.TexturedRect(self.m_iTexture, pos[1] - 3, pos[2] - 3, pos[1] + 5, pos[2] + 5);
				end
			end

			self.m_bIsHit = false;
			self.m_aPositions = {};
			self.m_iSize = 0;
		end;
	});
end

local TrajectoryLine = {};
do
	TrajectoryLine.m_aPositions = {};
	TrajectoryLine.m_iSize = 0;

	function TrajectoryLine:Insert(vec)
		self.m_iSize = self.m_iSize + 1;
		self.m_aPositions[self.m_iSize] = vec;
	end

	setmetatable(TrajectoryLine, {
		__call = (config.line.thickness > 1.5) and (function(self)
			if(self.m_iSize <= 1)then
				return;
			end
			
			local stColor = ImpactMarkers.m_bIsHit and config.line.color_hit or config.line.color_miss;
			COLOR(stColor.r, stColor.g, stColor.b, stColor.a);

			local aCords = {};
			for i = self.m_iSize, 1, -1 do
				local p1 = WORLD2SCREEN(self.m_aPositions[i]);
				if(p1)then
					local n = #aCords + 1;
					aCords[n] = p1;
				end
			end

			if(#aCords < 2)then
				return;
			end

			local flSize = config.line.thickness / 2;

			local x1, y1, x2, y2 = aCords[1][1], aCords[1][2], aCords[2][1], aCords[2][2];

			local flAng = math.atan(y2 - y1, x2 - x1) + math.pi / 2;
			local flCos, flSin = math.cos(flAng), math.sin(flAng);

			if(#aCords == 2)then
				draw.TexturedPolygon(textureFill, {
					{x2 - (flSize * flCos), y2 - (flSize * flSin), 0, 0},
					{x2 + (flSize * flCos), y2 + (flSize * flSin), 0, 0},
					{x1 + (flSize * flCos), y1 + (flSize * flSin), 0, 0},
					{x1 - (flSize * flCos), y1 - (flSize * flSin), 0, 0}
				}, true);
				return;
			end

			local verts = {
				{x1 - (flSize * flCos), y1 - (flSize * flSin), 0, 0},
				{x1 + (flSize * flCos), y1 + (flSize * flSin), 0, 0},
				{0, 0, 0, 0},
				{0, 0, 0, 0}
			};

			for i = 3, #aCords do
				x1, y1 = x2, y2;
				x2, y2 = aCords[i][1], aCords[i][2];

				flAng = math.atan(y2 - y1, x2 - x1) + math.pi / 2;
				flCos, flSin = math.cos(flAng), math.sin(flAng);

				verts[4][1], verts[4][2] = verts[1][1], verts[1][2];
				verts[3][1], verts[3][2] = verts[2][1], verts[2][2];
				verts[1][1], verts[1][2] = x1 - (flSize * flCos), y1 - (flSize * flSin);
				verts[2][1], verts[2][2] = x1 + (flSize * flCos), y1 + (flSize * flSin);
				
				draw.TexturedPolygon(textureFill, verts, true);
			end

			verts[4][1], verts[4][2] = verts[1][1], verts[1][2];
			verts[3][1], verts[3][2] = verts[2][1], verts[2][2];
			verts[1][1], verts[1][2] = x2 - (flSize * flCos), y2 - (flSize * flSin);
			verts[2][1], verts[2][2] = x2 + (flSize * flCos), y2 + (flSize * flSin);
			
			draw.TexturedPolygon(textureFill, verts, true); 
		end) or (function(self)
			if(self.m_iSize <= 1)then
				return;
			end

			local positions, last = self.m_aPositions, nil;
			
			local stColor = ImpactMarkers.m_bIsHit and config.line.color_hit or config.line.color_miss;
			COLOR(stColor.r, stColor.g, stColor.b, stColor.a);

			for i = self.m_iSize, 1, -1 do
				local new = WORLD2SCREEN(positions[i]);
				
				if last and new then
					LINE(last[1], last[2], new[1], new[2]);
				end
					
				last = new;
			end
		end);
	});
end

local ImpactCamera = {};
do
	local metatable = {__call = function(self) end;};

	if config.camera.enabled then
		local iX, iY, iWidth, iHeight = config.camera.x, config.camera.y, FLOOR(config.camera.height * config.camera.aspect_ratio), config.camera.height;
		local iResolutionX, iResolutionY = FLOOR(iWidth * config.camera.source.scale), FLOOR(iHeight * config.camera.source.scale);
		ImpactCamera.Texture = materials.CreateTextureRenderTarget("ProjectileCamera", iResolutionX, iResolutionY);

		-- Creating materials can just fail sometimes so we will just try to do it 128 times and if it still fails its not my problem!
		local Material = nil;
		local iAttempts = 0;
		for i = 1, 128 do
			Material = materials.Create("ProjectileCameraMat", [[ UnlitGeneric { $basetexture "ProjectileCamera" }]] );
			iAttempts = i;
			if(Material)then
				break;
			end
		end

		LOG(string.format("ProjectileCameraMaterial took %d attempts!", iAttempts));

		function metatable:__call()
			COLOR(0, 0, 0, 255);
			OUTLINED_RECT(iX - 1, iY - 1, iX + iWidth + 1, iY + iHeight + 1);

			COLOR(255, 255, 255, 255);
			render.DrawScreenSpaceRectangle(Material, iX, iY, iWidth, iHeight, 0, 0, iResolutionX, iResolutionY, iResolutionX, iResolutionY);
		end
	end

	setmetatable(ImpactCamera, metatable);
end

local PROJECTILE_TYPE_BASIC  = 0;
local PROJECTILE_TYPE_PSEUDO = 1;
local PROJECTILE_TYPE_SIMUL  = 2;
local PROJECTILE_TYPE_STICKY = 3;

local COLLISION_NORMAL         = 0;
local COLLISION_HEAL_TEAMMATES = 1;
local COLLISION_HEAL_BUILDINGS = 2;
local COLLISION_HEAL_HURT      = 3;
local COLLISION_NONE           = 4;

local function GetProjectileInformation(...) end
local function GetSpellInformation(...) end
local function GetZombieInformation(...) end
local function SetProjectileContext(...) end
do
	LOG("Creating GetProjectileInformation");
	LOG("Creating GetSpellInformation");
	LOG("Creating GetZombieInformation");

	local iCurrentIndex = 0;
	local ctxProjectile = {
		m_flWeaponCharge = 0;
		m_bIsCrouched = false;
		m_vecOrigin = Vector3(0, 0, 0);
		m_vecEyePos = Vector3(0, 0, 0);
		m_vecViewAngles = EulerAngles(0, 0, 0);
		m_vecFirePos = Vector3(0, 0, 0);
		m_vecFireAngles = EulerAngles(0, 0, 0);
		m_pPlayer = nil;
		m_pWeapon = nil;
	};

	local aItemDefinitions = {};
	local aSpellDefinitions = {};
	local aZombieDefinitions = {};
	local aProjectileInfo = {};
	local aSpellInfo = {};
	local aZombieInfo = {};

	function SetProjectileContext(pPlayer, vecOrigin, vecShootOffset, vecShootAngles, flWeaponChargeOverride)
		if(not pPlayer)then
			return false;
		end

		local pWeapon = pPlayer:GetPropEntity("m_hActiveWeapon");
		if(not pWeapon)then
			return false;
		end
		
		local fPlayerFlags = pPlayer:GetPropInt("m_fFlags") or 0;

		local flWeaponCharge = 0;
		local stWeaponInfo = aProjectileInfo[aItemDefinitions[pWeapon:GetPropInt("m_iItemDefinitionIndex") or 0]];
		if(stWeaponInfo and not flWeaponChargeOverride)then
			if(stWeaponInfo.m_flMaxCharge > 0)then
				flWeaponCharge = pWeapon:GetChargeBeginTime() or 0;
				if(flWeaponCharge ~= 0)then
					flWeaponCharge = globals.CurTime() - flWeaponCharge;
				end

				flWeaponCharge = flWeaponCharge / stWeaponInfo.m_flMaxCharge;
			end
		elseif(flWeaponChargeOverride)then
			flWeaponCharge = tonumber(flWeaponChargeOverride);
		end

		local fPlayerFlags = fPlayerFlags or 0;

		ctxProjectile.m_flWeaponCharge = CLAMP(flWeaponCharge, 0, 1);
		ctxProjectile.m_bIsCrouched = (fPlayerFlags & FL_DUCKING) ~= 0;
		ctxProjectile.m_vecOrigin = vecOrigin or Vector3(0, 0, 0);
		ctxProjectile.m_vecEyePos = ctxProjectile.m_vecOrigin + (vecShootOffset or Vector3(0, 0, 0));
		ctxProjectile.m_vecViewAngles = vecShootAngles or EulerAngles(0, 0, 0);
		ctxProjectile.m_pPlayer = pPlayer;
		ctxProjectile.m_pWeapon = pWeapon;

		return true;
	end
	
	local function AppendItemDefinitions(...)
		iCurrentIndex = iCurrentIndex + 1;
		for _, i in pairs({...})do
			aItemDefinitions[i] = iCurrentIndex;
		end
	end;

	local function AppendSpellDefinitions(...)
		iCurrentIndex = iCurrentIndex + 1;
		for _, i in pairs({...})do
			aSpellDefinitions[i] = iCurrentIndex;
		end
	end;

	local function AppendZombieDefinitions(...)
		iCurrentIndex = iCurrentIndex + 1;
		for _, i in pairs({...})do
			aZombieDefinitions[i] = iCurrentIndex;
		end
	end;

	local function DefineProjectileDefinition(tbl)
		return {
			m_iType = PROJECTILE_TYPE_BASIC;
			m_vecOffset = tbl.vecOffset or Vector3(0, 0, 0);
			m_vecAbsoluteOffset = tbl.vecAbsoluteOffset or Vector3(0, 0, 0);
			m_vecAngleOffset = tbl.vecAngleOffset or Vector3(0, 0, 0);
			m_vecVelocity = tbl.vecVelocity or Vector3(0, 0, 0);
			m_vecAngularVelocity = tbl.vecAngularVelocity or Vector3(0, 0, 0);
			m_vecMins = tbl.vecMins or (not tbl.vecMaxs) and Vector3(0, 0, 0) or -tbl.vecMaxs;
			m_vecMaxs = tbl.vecMaxs or (not tbl.vecMins) and Vector3(0, 0, 0) or -tbl.vecMins;
			m_flGravity = tbl.flGravity or 0.001;
			m_flDrag = tbl.flDrag or 0;
			m_flElasticity = tbl.flElasticity or 0;
			m_iAlignDistance = tbl.iAlignDistance or 0;
			m_iTraceMask = tbl.iTraceMask or 33570827; -- MASK_SOLID
			m_iCollisionType = tbl.iCollisionType or COLLISION_NORMAL;
			m_flCollideWithTeammatesDelay = tbl.flCollideWithTeammatesDelay or 0.25;
			m_flLifetime = tbl.flLifetime or 99999;
			m_flDamageRadius = tbl.flDamageRadius or 0;
			m_flExplosionRadius = tbl.flExplosionRadius or 0;
			m_bStopOnHittingEnemy = tbl.bStopOnHittingEnemy ~= false;
			m_flMaxCharge = tbl.flMaxCharge or 0;
			m_sModelName = tbl.sModelName or "";

			GetOffset = (not tbl.GetOffset) and (function(self) 
				return ctxProjectile.m_pWeapon:IsViewModelFlipped() and Vector3(self.m_vecOffset.x, -self.m_vecOffset.y, self.m_vecOffset.z) or self.m_vecOffset;   
			end) or tbl.GetOffset;

			GetAngleOffset = (not tbl.GetAngleOffset) and (function(self)
				return self.m_vecAngleOffset;
			end) or tbl.GetAngleOffset; -- self

			SetPreFirePosition = tbl.SetPreFirePosition or function(self)
				local resultTrace = TRACE_HULL( 
					ctxProjectile.m_vecEyePos, 
					ctxProjectile.m_vecEyePos + VEC_ROT(
						self:GetOffset(), 
						ctxProjectile.m_vecViewAngles
					), 
					-Vector3(8, 8, 8), 
					Vector3(8, 8, 8), 
					100679691); -- MASK_SOLID_BRUSHONLY

				return (not resultTrace.startsolid) and resultTrace.endpos or nil;
			end;

			GetVelocity = (not tbl.GetVelocity) and (function(self) return self.m_vecVelocity; end) or tbl.GetVelocity;

			GetAngularVelocity = (not tbl.GetAngularVelocity) and (function(self) return self.m_vecAngularVelocity; end) or tbl.GetAngularVelocity;

			GetGravity = (not tbl.GetGravity) and (function(self) return self.m_flGravity; end) or tbl.GetGravity;

			GetLifetime = (not tbl.GetLifetime) and (function(self) return self.m_flLifetime; end) or tbl.GetLifetime;

			GetExplosionRadius = tbl.GetExplosionRadius or (function(self)
				if(self.m_flExplosionRadius <= 0)then
					return 0;
				end

				return ctxProjectile.m_pWeapon:AttributeHookFloat("mult_explosion_radius", self.m_flExplosionRadius);
			end);

			GetFirePosition = function(self)
				return ctxProjectile.m_vecFirePos;
			end;

			GetFireAngles = function(self)
				return ctxProjectile.m_vecFireAngles;
			end;

			UpdateContext = function(self)
				local vecSource = self:SetPreFirePosition();
				if(not vecSource)then
					return false;
				end

				local vecAngles = ctxProjectile.m_vecViewAngles;

				if(self.m_iAlignDistance > 0)then
					local vecGoalPoint = ctxProjectile.m_vecEyePos + (vecAngles:Forward() * self.m_iAlignDistance);
					local res = TRACE_LINE(ctxProjectile.m_vecEyePos, vecGoalPoint, 100679691);
					vecAngles = (((res.fraction <= 0.1) and vecGoalPoint or res.endpos) - vecSource):Angles();
				end

				ctxProjectile.m_vecFirePos = vecSource + self.m_vecAbsoluteOffset;
				ctxProjectile.m_vecFireAngles = vecAngles + self:GetAngleOffset();

				return true;
			end;
		};
	end

	local function DefineBasicProjectileDefinition(tbl)
		local stReturned = DefineProjectileDefinition(tbl);
		stReturned.m_iType = PROJECTILE_TYPE_BASIC;
		
		return stReturned;
	end

	local function DefinePseudoProjectileDefinition(tbl)
		local stReturned = DefineProjectileDefinition(tbl);
		stReturned.m_iType = PROJECTILE_TYPE_PSEUDO;

		return stReturned;
	end

	local function DefineSimulProjectileDefinition(tbl)
		local stReturned = DefineProjectileDefinition(tbl);
		stReturned.m_iType = PROJECTILE_TYPE_SIMUL;
		
		return stReturned;
	end

	local function DefineStickyProjectileDefinition(tbl)
		local stReturned = DefineProjectileDefinition(tbl);
		stReturned.m_iType = PROJECTILE_TYPE_STICKY;

		return stReturned;
	end

	local function DefineDerivedProjectileDefinition(def, tbl)
		local stReturned = {};
		for k, v in pairs(def) do stReturned[k] = v; end
		for k, v in pairs(tbl) do stReturned[((type(v) ~= "function") and "m_" or "") .. k] = v; end

		if(not tbl.GetOffset and tbl.vecOffset)then
			stReturned.GetOffset = function(self) 
				return ctxProjectile.m_pWeapon:IsViewModelFlipped() and Vector3(self.m_vecOffset.x, -self.m_vecOffset.y, self.m_vecOffset.z) or self.m_vecOffset; 
			end;
		end

		if(not tbl.GetAngleOffset and tbl.vecAngleOffset)then
			stReturned.GetAngleOffset = function(self)
				return self.m_vecAngleOffset;
			end;
		end

		if(not tbl.GetVelocity and tbl.vecVelocity)then
			stReturned.GetVelocity = function(self, ...) return self.m_vecVelocity; end;
		end

		if(not tbl.GetAngularVelocity and tbl.vecAngularVelocity)then
			stReturned.GetAngularVelocity = function(self, ...) return self.m_vecAngularVelocity; end;
		end

		if(not tbl.GetGravity and tbl.flGravity)then
			stReturned.GetGravity = function(self, ...) return self.m_flGravity; end;
		end

		if(not tbl.GetLifetime and tbl.flLifetime)then
			stReturned.GetLifetime = function(self, ...) return self.m_flLifetime; end;
		end
	
		return stReturned;
	end

	AppendZombieDefinitions(
		2 -- TF2_Sniper
	);
	aZombieInfo[iCurrentIndex] = DefinePseudoProjectileDefinition({
		vecOffset = Vector3(50, 0, 0);
		vecMins = Vector3(-6.438000202179, -3.5, -6.1882195472717);
		vecMaxs = Vector3(6.6380000114441, 3.5, 6.3878774642944);
		flCollideWithTeammatesDelay = 9999.0;
		flDrag = 0.75;
		flLifetime = 2.5;

		GetVelocity = function(self)
			local vecBaseVelocity = ctxProjectile.m_pPlayer:EstimateAbsVelocity();
			return Vector3(
				ctxProjectile.m_vecViewAngles:Forward():Dot(vecBaseVelocity) + 2000,
				ctxProjectile.m_vecViewAngles:Right():Dot(vecBaseVelocity),
				ctxProjectile.m_vecViewAngles:Up():Dot(vecBaseVelocity)
			);
		end;

		GetGravity = function(self)
			return 1.05;
		end;

		GetExplosionRadius = function(self)
			return 80;
		end;
	});
	local iZombieSpitIndex = iCurrentIndex;

	AppendZombieDefinitions(
		9 -- TF2_Engineer
	);
	aZombieInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aZombieInfo[iZombieSpitIndex], {
		vecOffset = Vector3(-20, 0, 0);
		flDrag = 0.41;
		iCollisionType = COLLISION_NONE;
		flLifetime = 3.5;

		GetVelocity = function(self)
			local vecBaseVelocity = ctxProjectile.m_pPlayer:EstimateAbsVelocity();
			return Vector3(
				ctxProjectile.m_vecViewAngles:Forward():Dot(vecBaseVelocity) + 1500,
				ctxProjectile.m_vecViewAngles:Right():Dot(vecBaseVelocity),
				ctxProjectile.m_vecViewAngles:Up():Dot(vecBaseVelocity)
			);
		end;

		GetExplosionRadius = function(self)
			return 0;
		end
	});

	iCurrentIndex = 0;
	AppendItemDefinitions(
		18,    -- Rocket Launcher
		127,   -- The Direct Hit
		205,   -- Rocket Launcher (Renamed/Strange)
		228,   -- The Black Box
		414,   -- The Liberty Launcher
		658,   -- Festive Rocket Launcher
		730,   -- The Beggar's Bazooka
		800,   -- Silver Botkiller Rocket Launcher Mk.I
		809,   -- Gold Botkiller Rocket Launcher Mk.I
		889,   -- Rust Botkiller Rocket Launcher Mk.I
		898,   -- Blood Botkiller Rocket Launcher Mk.I
		907,   -- Carbonado Botkiller Rocket Launcher Mk.I
		916,   -- Diamond Botkiller Rocket Launcher Mk.I
		965,   -- Silver Botkiller Rocket Launcher Mk.II
		974,   -- Gold Botkiller Rocket Launcher Mk.II
		1085,  -- Festive Black Box
		1104,  -- The Air Strike
		15006, -- Woodland Warrior
		15014, -- Sand Cannon
		15028, -- American Pastoral
		15043, -- Smalltown Bringdown
		15052, -- Shell Shocker
		15057, -- Aqua Marine
		15081, -- Autumn
		15104, -- Blue Mew
		15105, -- Brain Candy
		15129, -- Coffin Nail
		15130, -- High Roller's
		15150  -- Warhawk 
	);
	aProjectileInfo[iCurrentIndex] = DefineBasicProjectileDefinition({
		vecVelocity = Vector3(1100, 0, 0);
		vecMaxs = Vector3(0, 0, 0);
		iAlignDistance = 2000;
		flExplosionRadius = 146;

		GetOffset = function(self)
			return Vector3(23.5, 12 * (ctxProjectile.m_pWeapon:IsViewModelFlipped() and -1 or 1), (ctxProjectile.m_bIsCrouched and 8 or -3));
		end;

		GetVelocity = function(self)
			local flVelocity = ctxProjectile.m_pWeapon:AttributeHookFloat("mult_projectile_speed", 1100);

			-- This should be AttributeHookInt...
			local iRocketSpecialist = ctxProjectile.m_pPlayer:AttributeHookFloat("rocket_specialist", 0);
			if(iRocketSpecialist ~= 0)then
				flVelocity = CLAMP(flVelocity * (1.15 + ((CLAMP(iRocketSpecialist, 1, 4) - 1) / 3) * 0.45), 0, 3000);
			end

			if(ctxProjectile.m_pPlayer:GetCarryingRuneType() == 6)then -- RUNE_PRECISION
				flVelocity = 3000;
			end

			return Vector3(flVelocity, 0, 0);
		end;

		GetExplosionRadius = function(self)
			if(self.m_flExplosionRadius <= 0)then
				return 0;
			end

			if(ctxProjectile.m_pPlayer:AttributeHookFloat("rocketjump_attackrate_bonus", 1) ~= 1)then
				return ctxProjectile.m_pWeapon:AttributeHookFloat("mult_explosion_radius", self.m_flExplosionRadius) * 0.8;
			end

			return ctxProjectile.m_pWeapon:AttributeHookFloat("mult_explosion_radius", self.m_flExplosionRadius);
		end;
	});
	local iRocketLauncherIndex = iCurrentIndex;

	AppendItemDefinitions(
		237 -- Rocket Jumper
	);
	aProjectileInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aProjectileInfo[iRocketLauncherIndex], {
		iCollisionType = COLLISION_NONE;
	});

	AppendItemDefinitions(
		513 -- The Original
	);
	aProjectileInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aProjectileInfo[iRocketLauncherIndex], {
		GetOffset = function(self)
			return Vector3(23.5, 0, ctxProjectile.m_bIsCrouched and 8 or -3);
		end;
	});

	-- https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/tf/tf_weapon_dragons_fury.cpp
	AppendItemDefinitions(
		1178 -- Dragon's Fury
	);
	aProjectileInfo[iCurrentIndex] = DefineBasicProjectileDefinition({
		vecVelocity = Vector3(600, 0, 0);
		vecMaxs = Vector3(1, 1, 1);
		flDamageRadius = 22.5;
		flLifetime = 0.835;

		GetOffset = function(self)
			return Vector3(3, 7, -9);
		end;
	});
	
	AppendItemDefinitions( 
		442 -- The Righteous Bison
	);
	aProjectileInfo[iCurrentIndex] = DefineBasicProjectileDefinition({
		vecVelocity = Vector3(1200, 0, 0);
		vecMaxs = Vector3(1, 1, 1);
		iAlignDistance = 2000;

		GetOffset = function(self)
			return Vector3(23.5, -8 * (ctxProjectile.m_pWeapon:IsViewModelFlipped() and -1 or 1), ctxProjectile.m_bIsCrouched and 8 or -3);
		end;
	});
	local iRighteousBisonIndex = iCurrentIndex;

	AppendItemDefinitions(
		20,    -- Stickybomb Launcher
		207,   -- Stickybomb Launcher (Renamed/Strange) 	
		661,   -- Festive Stickybomb Launcher 	
		797,   -- Silver Botkiller Stickybomb Launcher Mk.I 	
		806,   -- Gold Botkiller Stickybomb Launcher Mk.I 	
		886,   -- Rust Botkiller Stickybomb Launcher Mk.I 	
		895,   -- Blood Botkiller Stickybomb Launcher Mk.I 	
		904,   -- Carbonado Botkiller Stickybomb Launcher Mk.I 	
		913,   -- Diamond Botkiller Stickybomb Launcher Mk.I 	
		962,   -- Silver Botkiller Stickybomb Launcher Mk.II 	
		971,   -- Gold Botkiller Stickybomb Launcher Mk.II 	
		15009, -- Sudden Flurry 	
		15012, -- Carpet Bomber 	
		15024, -- Blasted Bombardier 	
		15038, -- Rooftop Wrangler 	
		15045, -- Liquid Asset 	
		15048, -- Pink Elephant 	
		15082, -- Autumn 	
		15083, -- Pumpkin Patch 	
		15084, -- Macabre Web 	
		15113, -- Sweet Dreams 	
		15137, -- Coffin Nail 	
		15138, -- Dressed to Kill 	
		15155  -- Blitzkrieg 	 
	);
	aProjectileInfo[iCurrentIndex] = DefineSimulProjectileDefinition({
		vecOffset = Vector3(16, 8, -6);
		vecAngularVelocity = Vector3(600, 0, 0);
		vecMaxs = Vector3(3.5, 3.5, 3.5);
		flExplosionRadius = 150;
		flMaxCharge = 4;
		sModelName = "models/weapons/w_models/w_stickybomb.mdl";

		GetVelocity = function(self)
			return Vector3(900 + ctxProjectile.m_flWeaponCharge * 1500, 0, 200);
		end;
	});
	local iStickybombLauncherIndex = iCurrentIndex;

	AppendItemDefinitions( 
		1150 -- The Quickiebomb Launcher
	);
	aProjectileInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aProjectileInfo[iStickybombLauncherIndex], {
		flMaxCharge = 1.2;
		sModelName = "models/workshop/weapons/c_models/c_kingmaker_sticky/w_kingmaker_stickybomb.mdl";
	});

	AppendItemDefinitions( 
		130 -- The Scottish Resistance
	);
	aProjectileInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aProjectileInfo[iStickybombLauncherIndex], {
		sModelName = "models/weapons/w_models/w_stickybomb_d.mdl";
	});
	local iScottishResistanceIndex = iCurrentIndex;

	AppendItemDefinitions(
		265 -- Sticky Jumper
	);
	aProjectileInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aProjectileInfo[iScottishResistanceIndex], {
		iCollisionType = COLLISION_NONE;
	});

	AppendItemDefinitions(
		19,    -- Grenade Launcher
		206,   -- Grenade Launcher (Renamed/Strange)
		1007,  -- Festive Grenade Launcher
		15077, -- Autumn
		15079, -- Macabre Web
		15091, -- Rainbow
		15092, -- Sweet Dreams
		15116, -- Coffin Nail
		15117, -- Top Shelf
		15142, -- Warhawk
		15158  -- Butcher Bird 
	);
	aProjectileInfo[iCurrentIndex] = DefineSimulProjectileDefinition({
		vecOffset = Vector3(16, 8, -6);
		vecAngularVelocity = Vector3(600, 0, 0);
		vecMaxs = Vector3(2, 2, 2);
		flElasticity = 0.45;
		flLifetime = 2.175;
		flExplosionRadius = 146;
		sModelName = "models/weapons/w_models/w_grenade_grenadelauncher.mdl";

		GetVelocity = function(self)
			if(ctxProjectile.m_pPlayer:GetCarryingRuneType() == 6)then -- RUNE_PRECISION
				return Vector3(3000, 0, 200);
			end

			return Vector3(ctxProjectile.m_pWeapon:AttributeHookFloat("mult_projectile_speed", 1200), 0, 200);
		end;
	});
	local iGrenadeLauncherIndex = iCurrentIndex;

	AppendItemDefinitions(
		1151 -- The Iron Bomber
	);
	aProjectileInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aProjectileInfo[iGrenadeLauncherIndex], {
		flElasticity = 0.09;
		flLifetime = 1.6;
		flExplosionRadius = 124;
	});

	AppendItemDefinitions(
		308 -- The Loch-n-Load
	);
	aProjectileInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aProjectileInfo[iGrenadeLauncherIndex], {
		iType = PROJECTILE_TYPE_PSEUDO;
		flGravity = 1;
		flDrag = 0.225;
		flLifetime = 2.3;
		flExplosionRadius = 0;
	});

	AppendItemDefinitions(
		996 -- The Loose Cannon
	);
	aProjectileInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aProjectileInfo[iGrenadeLauncherIndex], {
		vecMaxs = Vector3(6, 6, 6);
		bStopOnHittingEnemy = false;
		flMaxCharge = 1;
		sModelName = "models/weapons/w_models/w_cannonball.mdl";

		GetLifetime = function(self)
			return 1 * ctxProjectile.m_flWeaponCharge;
		end;
	});

	AppendItemDefinitions(
		56,   -- The Huntsman
		1005, -- Festive Huntsman
		1092  -- The Fortified Compound
	);
	aProjectileInfo[iCurrentIndex] = DefinePseudoProjectileDefinition({
		vecOffset = Vector3(23.5, -8, -3);
		vecMaxs = Vector3(0, 0, 0);
		iAlignDistance = 2000;
		flMaxCharge = 1;

		GetVelocity = function(self)
			return Vector3(1800 + ctxProjectile.m_flWeaponCharge * 800, 0, 0);
		end;

		GetGravity = function(self)
			return 0.5 - ctxProjectile.m_flWeaponCharge * 0.4;
		end;
	});

	AppendItemDefinitions(
		39,   -- The Flare Gun
		351,  -- The Detonator
		595,  -- The Manmelter
		1081  -- Festive Flare Gun
	);
	aProjectileInfo[iCurrentIndex] = DefinePseudoProjectileDefinition({
		vecMaxs = Vector3(0, 0, 0);
		iAlignDistance = 2000;
		flCollideWithTeammatesDelay = 0.25;

		GetOffset = function(self)
			return Vector3(23.5, 12 * (ctxProjectile.m_pWeapon:IsViewModelFlipped() and -1 or 1), ctxProjectile.m_bIsCrouched and 8 or -3);
		end;

		GetVelocity = function(self)
			return Vector3(ctxProjectile.m_pWeapon:AttributeHookFloat("mult_projectile_speed", 2000), 0, 0);
		end;

		GetGravity = function(self)
			return ctxProjectile.m_pWeapon:AttributeHookFloat("mult_projectile_speed", 0.3);
		end;
	});
	local iFlareGunIndex = iCurrentIndex;

	AppendItemDefinitions(
		740 -- The Scorch Shot
	);
	aProjectileInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aProjectileInfo[iFlareGunIndex], {
		flExplosionRadius = 110;
	});

	AppendItemDefinitions(
		305, -- Crusader's Crossbow
		1079 -- Festive Crusader's Crossbow
	);
	aProjectileInfo[iCurrentIndex] = DefinePseudoProjectileDefinition({
		vecOffset = Vector3(23.5, -8, -3);
		vecVelocity = Vector3(2400, 0, 0);
		vecMaxs = Vector3(3, 3, 3);
		flGravity = 0.2;
		iAlignDistance = 2000;
		iCollisionType = COLLISION_HEAL_TEAMMATES;
	});
	local iCrusadersCrossbowIndex = iCurrentIndex;

	AppendItemDefinitions(
		997 -- The Rescue Ranger
	);
	aProjectileInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aProjectileInfo[iCrusadersCrossbowIndex], {
		vecMaxs = Vector3(1, 1, 1);
		iCollisionType = COLLISION_HEAL_BUILDINGS;
	});

	AppendItemDefinitions(
		17,  -- Syringe Gun
		36,  -- The Blutsauger
		204, -- Syringe Gun (Renamed/Strange)
		412  -- The Overdose
	);
	aProjectileInfo[iCurrentIndex] = DefinePseudoProjectileDefinition({
		vecOffset = Vector3(16, 6, -8);
		vecVelocity = Vector3(1000, 0, 0);
		vecMaxs = Vector3(1, 1, 1);
		flGravity = 0.3;
		flCollideWithTeammatesDelay = 0;
	});

	AppendItemDefinitions(
		58,   -- Jarate
		222,  -- Mad Milk
		1083, -- Festive Jarate
		1105, -- The Self-Aware Beauty Mark
		1121  -- Mutated Milk
	);
	aProjectileInfo[iCurrentIndex] = DefinePseudoProjectileDefinition({
		vecOffset = Vector3(16, 8, -6);
		vecVelocity = Vector3(1000, 0, 200);
		vecMaxs = Vector3(8, 8, 8);
		flGravity = 1.125;
		flCollideWithTeammatesDelay = 0.006; 
		flExplosionRadius = 200;

		GetLifetime = function(self)
			local flLifetime = ctxProjectile.m_pWeapon:AttributeHookFloat("throwable_detonation_time", 0);
			if(flLifetime ~= 0)then
				return flLifetime;
			end

			return 2;
		end;
	});

	AppendItemDefinitions(
		812, -- The Flying Guillotine
		833  -- The Flying Guillotine (Genuine)
	);
	aProjectileInfo[iCurrentIndex] = DefinePseudoProjectileDefinition({
		vecOffset = Vector3(23.5, 8, -3);
		vecVelocity = Vector3(3000, 0, 300);
		vecMaxs = Vector3(2, 2, 2);
		flGravity = 2.25;
		flDrag = 1.3;
	});

	AppendItemDefinitions(
		44  -- The Sandman
	);
	aProjectileInfo[iCurrentIndex] = DefineSimulProjectileDefinition({
		vecVelocity = Vector3(2985.1118164063, 0, 298.51116943359);
		vecAngularVelocity = Vector3(0, 50, 0);
		vecMaxs = Vector3(4.25, 4.25, 4.25);
		flElasticity = 0.45;
		sModelName = "models/weapons/w_models/w_baseball.mdl";

		SetPreFirePosition = function(self)
			--https://github.com/ValveSoftware/source-sdk-2013/blob/0565403b153dfcde602f6f58d8f4d13483696a13/src/game/shared/tf/tf_weapon_bat.cpp#L232
			local vecFirePos = ctxProjectile.m_vecOrigin + ((Vector3(0, 0, 50) + (ctxProjectile.m_vecViewAngles:Forward() * 32)) * ctxProjectile.m_pPlayer:GetPropFloat("m_flModelScale"));

			local resultTrace = TRACE_HULL( 
				ctxProjectile.m_vecEyePos, 
				vecFirePos, 
				-Vector3(8, 8, 8), 
				Vector3(8, 8, 8), 
				100679691); -- MASK_SOLID_BRUSHONLY

			return (resultTrace.fraction == 1) and resultTrace.endpos or nil;
		end;
	});
	local iSandmanIndex = iCurrentIndex;
	
	AppendItemDefinitions(
		648  -- The Wrap Assassin
	);
	aProjectileInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aProjectileInfo[iSandmanIndex], {
		vecMins = Vector3(-2.990180015564, -2.5989532470703, -2.483987569809);
		vecMaxs = Vector3(2.6593606472015, 2.5989530086517, 2.4839873313904);
		flElasticity = 0;
		flExplosionRadius = 50;
		sModelName = "models/weapons/c_models/c_xms_festive_ornament.mdl";
	});

	AppendItemDefinitions(
		441 -- The Cow Mangler 5000
	);
	aProjectileInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aProjectileInfo[iRocketLauncherIndex], {
		GetOffset = function(self)
			return Vector3(23.5, 8 * (ctxProjectile.m_pWeapon:IsViewModelFlipped() and 1 or -1), ctxProjectile.m_bIsCrouched and 8 or -3);
		end;
	});

	--https://github.com/ValveSoftware/source-sdk-2013/blob/0565403b153dfcde602f6f58d8f4d13483696a13/src/game/shared/tf/tf_weapon_raygun.cpp#L249
	AppendItemDefinitions(
		588  -- The Pomson 6000	
	);
	aProjectileInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aProjectileInfo[iRighteousBisonIndex], {
		vecAbsoluteOffset = Vector3(0, 0, -13);
		flCollideWithTeammatesDelay = 0;
	});

	AppendItemDefinitions(
		1180  -- Gas Passer
	);
	aProjectileInfo[iCurrentIndex] = DefinePseudoProjectileDefinition({
		vecOffset = Vector3(16, 8, -6);
		vecVelocity = Vector3(2000, 0, 200);
		vecMaxs = Vector3(8, 8, 8);
		flGravity = 1;
		flDrag = 1.32;
		flExplosionRadius = 200;
	});

	AppendItemDefinitions(
		528  -- The Short Circuit
	);
	aProjectileInfo[iCurrentIndex] = DefineBasicProjectileDefinition({
		vecOffset = Vector3(40, 15, -10);
		vecVelocity = Vector3(700, 0, 0);
		vecMaxs = Vector3(1, 1, 1);
		flCollideWithTeammatesDelay = 99999;
		flLifetime = 1.25;
		flDamageRadius = 100;
	});

	AppendItemDefinitions(
		42,   -- Sandvich
		159,  -- The Dalokohs Bar
		311,  -- The Buffalo Steak Sandvich
		433,  -- Fishcake
		863,  -- Robo-Sandvich
		1002, -- Festive Sandvich
		1190  -- Second Banana
	);
	aProjectileInfo[iCurrentIndex] = DefinePseudoProjectileDefinition({
		vecOffset = Vector3(0, 0, -8);
		vecAngleOffset = Vector3(-10, 0, 0);
		vecVelocity = Vector3(500, 0, 0);
		vecMaxs = Vector3(17, 17, 10);
		flGravity = 1.02;
		iTraceMask = 33636363; -- MASK_PLAYERSOLID
		iCollisionType = COLLISION_HEAL_HURT;
	});

	iCurrentIndex = 0;

	AppendSpellDefinitions(
		9 -- TF_Spell_Meteor
	);
	aSpellInfo[iCurrentIndex] = DefinePseudoProjectileDefinition({
		vecVelocity = Vector3(1000, 0, 200);
		vecMaxs = Vector3(0, 0, 0);
		flGravity = 1.025;
		flDrag = 0.15;
		flExplosionRadius = 200;

		GetOffset = function(self)
			return Vector3(3, 7, -9);
		end;
	});
	local iMeteorSpellIndex = iCurrentIndex;

	AppendSpellDefinitions(
		1, -- TF_Spell_Bats
		6  -- TF_Spell_Teleport
	);
	aSpellInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aSpellInfo[iMeteorSpellIndex], {
		vecMins = Vector3(-0.019999999552965, -0.019999999552965, -0.019999999552965);
		vecMaxs = Vector3(0.019999999552965, 0.019999999552965, 0.019999999552965);
		flExplosionRadius = 250;
	});

	AppendSpellDefinitions(
		3 -- TF_Spell_MIRV
	);
	aSpellInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aSpellInfo[iMeteorSpellIndex], {
		vecMaxs = Vector3(1.5, 1.5, 1.5);
		flDrag = 0.525;
	});

	AppendSpellDefinitions(
		10 -- TF_Spell_SpawnBoss
	);
	aSpellInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aSpellInfo[iMeteorSpellIndex], {
		vecMaxs = Vector3(3.0, 3.0, 3.0);
		flDrag = 0.35;
	});
	local iSpawnBossSpellIndex = iCurrentIndex;

	AppendSpellDefinitions(
		11 -- TF_Spell_SkeletonHorde
	);
	aSpellInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aSpellInfo[iSpawnBossSpellIndex], {
		vecMaxs = Vector3(2.0, 2.0, 2.0);
	});

	AppendSpellDefinitions(
		0 -- TF_Spell_Fireball
	);
	aSpellInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aSpellInfo[iMeteorSpellIndex], {
		iType = PROJECTILE_TYPE_BASIC;
		vecVelocity = Vector3(1200, 0, 0);
	});
	local iFireballSpellIndex = iCurrentIndex;

	AppendSpellDefinitions(
		7 -- TF_Spell_LightningBall
	);
	aSpellInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aSpellInfo[iFireballSpellIndex], {
		vecVelocity = Vector3(480, 0, 0);
	});

	AppendSpellDefinitions(
		12 -- TF_Spell_Fireball
	);
	aSpellInfo[iCurrentIndex] = DefineDerivedProjectileDefinition(aSpellInfo[iFireballSpellIndex], {
		vecVelocity = Vector3(1500, 0, 0);
	});

	function GetProjectileInformation()
		return aProjectileInfo[aItemDefinitions[ctxProjectile.m_pWeapon:GetPropInt("m_iItemDefinitionIndex") or 0]];	
	end

	function GetSpellInformation()
		local pSpellBook = ctxProjectile.m_pPlayer:GetEntityForLoadoutSlot(9); -- LOADOUT_POSITION_ACTION
		if(not pSpellBook or not pSpellBook:IsValid() or pSpellBook:GetClass() ~= "CTFSpellBook")then--pSpellBook:GetWeaponID() ~= 97)then -- TF_WEAPON_SPELLBOOK
			return;
		end

		local i = pSpellBook:GetPropInt("m_iSelectedSpellIndex");
		local iOverride = client.GetConVar("tf_test_spellindex");
		if(iOverride > -1)then
			i = iOverride;

		elseif(pSpellBook:GetPropInt("m_iSpellCharges") <= 0 or i == -2)then -- SPELL_UNKNOWN
			return;
		end

		return aSpellInfo[aSpellDefinitions[i or 0]];
	end

	function GetZombieInformation()
		return aZombieInfo[aZombieDefinitions[ctxProjectile.m_pPlayer:GetPropInt("m_iClass") or 0]];
	end

	LOG("GetProjectileInformation ready!");
	LOG("GetSpellInformation ready!");
	LOG("GetZombieInformation ready!");
end

local g_flTraceInterval = CLAMP(config.measure_segment_size, 0.5, 8) / 66;
local g_vEndOrigin = Vector3(0, 0, 0);
local g_bSpellPreferState = config.spells.prefer_showing_spells;
local g_iLastPollTick = 0;
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


local function CanDealRadialDamageLine(vecLineBegin, vecLineEnd, flRadius)
	if(flRadius <= 0)then
		return false;
	end

	local vecDirection = vecLineEnd - vecLineBegin;
	local flLength = vecDirection:Length();
	vecDirection = vecDirection / flLength;

	for _, sKey in pairs({
		"CTFPlayer"
	}) do
		for _, pEntity in pairs(entities.FindByClass(sKey) or {})do
			if(pEntity:GetTeamNumber() ~= g_iLocalTeamNumber and pEntity:IsAlive() and not pEntity:IsDormant())then
				local vecOrigin = pEntity:GetAbsOrigin();
				local flBestLength = (vecOrigin - vecLineBegin):Dot(vecDirection); 
				local vecMins = pEntity:GetMins();
				local vecMaxs = pEntity:GetMaxs();
				local vecEntityEyePos = GetEntityEyePosition(pEntity);
				local iEntityIndex = pEntity:GetIndex();
				local flBaseOffset = CLAMP((vecMaxs - vecMins):Length2D() / 2, 16, 1024);

				-- Make sure the closest point is within the radius
				-- The best line might not actually hit the enemy so we need to check more points.
				if(VEC_BBOX_DIST(vecLineBegin + vecDirection * flBestLength, vecOrigin, vecMins, vecMaxs) <= flRadius)then
					local flCloseLength = flBestLength;
					local flFarLength = flBestLength;
					
					if(not config.disable_extra_radial_points)then
						-- Go backwards on the line.
						local flOffset = flBaseOffset;
						while(flOffset > 1 and flCloseLength > 0)do
							if(VEC_BBOX_DIST(vecLineBegin + vecDirection * (flCloseLength - flOffset), vecOrigin, vecMins, vecMaxs) <= flRadius)then
								flCloseLength = CLAMP(flCloseLength - flOffset, 0, flBestLength);
							else
								flOffset = flOffset / 2;
							end
						end

						-- Go forwards on the line.
						flOffset = flBaseOffset;
						while(flOffset > 1 and flFarLength < flLength)do
							if(VEC_BBOX_DIST(vecLineBegin + vecDirection * (flFarLength + flOffset), vecOrigin, vecMins, vecMaxs) <= flRadius)then
								flFarLength = CLAMP(flFarLength + flOffset, flBestLength, flLength);
							else
								flOffset = flOffset / 2;
							end
						end
					end

					-- Now do the three traces with our close, best, and far lengths.
					if(flCloseLength <= flLength and flCloseLength >= 0 and 
						DoRadialDamageTrace(vecLineBegin + vecDirection * flCloseLength, vecEntityEyePos, iEntityIndex))then
						return true;
					end

					if(flBestLength <= flLength and flBestLength >= 0 and 
						DoRadialDamageTrace(vecLineBegin + vecDirection * flBestLength, vecEntityEyePos, iEntityIndex))then
						return true;
					end

					if(flFarLength <= flLength and flFarLength >= 0 and 
						DoRadialDamageTrace(vecLineBegin + vecDirection * flFarLength, vecEntityEyePos, iEntityIndex))then
						return true;
					end
				end
			end
		end
	end

	-- Do cheap calculations for anything that isnt a player.
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
		for _, pEntity in pairs(entities.FindByClass(sKey) or {})do
			if(pEntity:GetTeamNumber() ~= g_iLocalTeamNumber and not pEntity:IsDormant())then
				local vecOrigin = pEntity:GetAbsOrigin();
				local flBestLength = (vecOrigin - vecLineBegin):Dot(vecDirection); 
				local vecMins = pEntity:GetMins();
				local vecMaxs = pEntity:GetMaxs();
				local vecEntityEyePos = GetEntityEyePosition(pEntity);
				local iEntityIndex = pEntity:GetIndex();
				local flBaseOffset = CLAMP((vecMaxs - vecMins):Length2D() / 2, 16, 1024);

				-- Make sure the closest point is within the radius
				-- The best line might not actually hit the enemy so we need to check more points.
				if(VEC_BBOX_DIST(vecLineBegin + vecDirection * flBestLength, vecOrigin, vecMins, vecMaxs) <= flRadius)then					
					local flCloseLength = flBestLength;
					local flFarLength = flBestLength;
					
					if(not config.disable_extra_radial_points)then
						-- Go backwards on the line.
						local flOffset = flBaseOffset;
						while(flOffset > 1 and flCloseLength > 0)do
							if(VEC_BBOX_DIST(vecLineBegin + vecDirection * (flCloseLength - flOffset), vecOrigin, vecMins, vecMaxs) <= flRadius)then
								flCloseLength = CLAMP(flCloseLength - flOffset, 0, flBestLength);
							else
								flOffset = flOffset / 2;
							end
						end

						-- Go forwards on the line.
						flOffset = flBaseOffset;
						while(flOffset > 1 and flFarLength < flLength)do
							if(VEC_BBOX_DIST(vecLineBegin + vecDirection * (flFarLength + flOffset), vecOrigin, vecMins, vecMaxs) <= flRadius)then
								flFarLength = CLAMP(flFarLength + flOffset, flBestLength, flLength);
							else
								flOffset = flOffset / 2;
							end
						end
					end

					-- Now do the three traces with our close, best, and far lengths.
					if(flCloseLength <= flLength and flCloseLength >= 0 and 
						DoRadialDamageTrace(vecLineBegin + vecDirection * flCloseLength, vecEntityEyePos, iEntityIndex))then
						return true;
					end

					if(flBestLength <= flLength and flBestLength >= 0 and 
						DoRadialDamageTrace(vecLineBegin + vecDirection * flBestLength, vecEntityEyePos, iEntityIndex))then
						return true;
					end

					if(flFarLength <= flLength and flFarLength >= 0 and 
						DoRadialDamageTrace(vecLineBegin + vecDirection * flFarLength, vecEntityEyePos, iEntityIndex))then
						return true;
					end
				end
			end
		end
	end

	return false;
end

local function CanDealRadialDamage(flRadius, vecCenter)
	if(flRadius <= 0)then
		return false;
	end

	for _, sKey in pairs({
		"CTFPlayer"
	}) do
		local aEnts = entities.FindByClass(sKey) or {};
		for _, pEntity in pairs(aEnts)do
			local vecOrigin = pEntity:GetAbsOrigin();
			if(VEC_BBOX_DIST(vecCenter, vecOrigin, pEntity:GetMins(), pEntity:GetMaxs()) <= flRadius 
				and pEntity:GetTeamNumber() ~= g_iLocalTeamNumber and pEntity:IsAlive() and not pEntity:IsDormant())then
				if(DoRadialDamageTrace(vecCenter, GetEntityEyePosition(pEntity), pEntity:GetIndex()))then
					return true;
				end
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
			local vecOrigin = pEntity:GetAbsOrigin();
			if(VEC_BBOX_DIST(vecCenter, vecOrigin, pEntity:GetMins(), pEntity:GetMaxs()) <= flRadius 
				and pEntity:GetTeamNumber() ~= g_iLocalTeamNumber and not pEntity:IsDormant())then
				if(DoRadialDamageTrace(vecCenter, GetEntityEyePosition(pEntity), pEntity:GetIndex()))then
					return true;
				end
			end
			
		end
	end

	return false;
end

local function UpdateSpellPreference()
	if(config.spells.show_other_key == -1)then
		return;
	end

	if(config.spells.is_toggle)then
		local bPressed, iTick = input.IsButtonPressed(config.spells.show_other_key);
		
		if(bPressed and iTick ~= g_iLastPollTick)then
			g_iLastPollTick = iTick;
			g_bSpellPreferState = not g_bSpellPreferState;
		end

	elseif(input.IsButtonDown(config.spells.show_other_key))then
		g_bSpellPreferState = not config.spells.prefer_showing_spells;

	else
		g_bSpellPreferState = config.spells.prefer_showing_spells;
	end
end

local function DoBasicProjectileTrace(
	vecSource, 
	vecForward, 
	vecVelocity, 
	vecMins, 
	vecMaxs, 
	flCollideWithTeammatesDelay, 
	flLifetime, 
	bStopOnHittingEnemy,
	flDamageRadius, 
	iTraceMask, 
	iCollisionType)

	local bHitEnemy = false;
	local resultTrace = TRACE_HULL(vecSource, vecSource + (vecForward * (vecVelocity:Length() * flLifetime)), vecMins, vecMaxs, iTraceMask, function(pEntity, iMask)
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
			bHitEnemy = bHitEnemy or iCollisionType ~= COLLISION_NONE;
			return true;
		end

		if(iCollisionGroup == 20  or   -- TF_COLLISIONGROUP_GRENADES
			iCollisionGroup == 24 or   -- TFCOLLISION_GROUP_ROCKETS
			iCollisionGroup == 27)then -- TFCOLLISION_GROUP_ROCKET_BUT_NOT_WITH_OTHER_ROCKETS   
			return false;
		end

		if(not pEntity:IsPlayer())then
			return false;
		end

		local vecBBoxSize = pEntity:GetMaxs() - pEntity:GetMins();
		local vecDistance = pEntity:GetAbsOrigin();

		return (vecDistance - vecSource):Length() + ((vecBBoxSize.x + vecBBoxSize.y + vecBBoxSize.z) / 3) >= (vecVelocity * flCollideWithTeammatesDelay):Length();
	end);

	if resultTrace.startsolid then 
		return true; 
	end
	
	if(bHitEnemy and resultTrace.entity:IsValid() and resultTrace.entity:GetPropInt("m_CollisionGroup") ~= 0)then
		ImpactMarkers.m_bIsHit = true;

	elseif(CanDealRadialDamageLine(resultTrace.startpos, resultTrace.endpos, flDamageRadius))then
		ImpactMarkers.m_bIsHit = true;
	end

	TrajectoryLine:Insert(resultTrace.endpos);
	ImpactMarkers:Insert(resultTrace.endpos, resultTrace.plane);
	return true;
end

local function DoPseudoProjectileTrace(
	vecSource, 
	vecVelocity, 
	flGravity, 
	flDrag, 
	vecMins, 
	vecMaxs, 
	flCollideWithTeammatesDelay, 
	flLifetime, 
	bStopOnHittingEnemy,
	iTraceMask, 
	iCollisionType)

	local flGravity = flGravity * 400;
	local vecPosition = vecSource;
	local resultTrace;
	local mapCollisions = {};
	for i = 0.01515, 5, g_flTraceInterval do
		local flScalar = (flDrag == 0) and i or ((1 - math.exp(-flDrag * i)) / flDrag);
		local vecEndPos = Vector3(
			vecVelocity.x * flScalar + vecSource.x,
			vecVelocity.y * flScalar + vecSource.y,
			(vecVelocity.z - flGravity * i) * flScalar + vecSource.z
		);

		local bHitEnemy = false;
		resultTrace = TRACE_HULL(vecPosition, vecEndPos, vecMins, vecMaxs, iTraceMask, function(pEntity, iMask)
			if(not pEntity:IsValid())then
				return true;
			end

			local iCollisionGroup = pEntity:GetPropInt("m_CollisionGroup");
			if(iCollisionGroup == 25 or   -- TFCOLLISION_GROUP_RESPAWNROOMS 
				iCollisionGroup == 13 or -- COLLISION_GROUP_PROJECTILE
				iCollisionGroup == 1)then -- COLLISION_GROUP_DEBRIS
				return false;
			end
			
			if(iCollisionGroup == 0)then -- COLLISION_GROUP_NONE
				return true;
			end

			if(pEntity:GetTeamNumber() ~= g_iLocalTeamNumber)then
				if(iCollisionType == COLLISION_HEAL_HURT)then
					if(pEntity:IsPlayer() and pEntity:GetHealth() < pEntity:GetMaxHealth())then
						bHitEnemy = true;
						return true;
					end

					return false;
				end

				bHitEnemy = iCollisionType ~= COLLISION_NONE;
				return true;
			end

			if(iCollisionGroup == 20  or   -- TF_COLLISIONGROUP_GRENADES
				iCollisionGroup == 24 or   -- TFCOLLISION_GROUP_ROCKETS
				iCollisionGroup == 27)then -- TFCOLLISION_GROUP_ROCKET_BUT_NOT_WITH_OTHER_ROCKETS   
				return false;
			end

			if(not pEntity:IsPlayer() or mapCollisions[pEntity:GetIndex()])then
				if(iCollisionType == COLLISION_HEAL_BUILDINGS and (
					iCollisionGroup == 21 or    -- TFCOLLISION_GROUP_OBJECT
					iCollisionGroup == 22))then -- TFCOLLISION_GROUP_OBJECT_SOLIDTOPLAYERMOVEMENT
					bHitEnemy = true;
					return true;
				end

				return false;
			end

			if(pEntity:GetHealth() < pEntity:GetMaxHealth() and iCollisionType == COLLISION_HEAL_HURT)then
				bHitEnemy = true;
				return true;
			end

			if(iCollisionType == COLLISION_HEAL_TEAMMATES)then
				bHitEnemy = true;
				return true;
			end

			mapCollisions[pEntity:GetIndex()] = true;
			return i * g_flTraceInterval > flCollideWithTeammatesDelay;
		end);

		if(i > flLifetime)then
			local flFraction = (i - flLifetime) / g_flTraceInterval;		
			local vecEndPos = vecEndPos - ((vecEndPos - resultTrace.startpos) * flFraction);
			
			if((vecEndPos - vecPosition):LengthSqr() >= (resultTrace.endpos - vecPosition):LengthSqr())then
				vecEndPos = resultTrace.endpos;
				flFraction = 1;

				if(bHitEnemy and resultTrace.entity:IsValid() and resultTrace.entity:GetPropInt("m_CollisionGroup") ~= 0)then
					ImpactMarkers.m_bIsHit = true;
				end 
			end

			ImpactMarkers:Insert(vecEndPos, (flFraction == 1) and resultTrace.plane or nil);
			TrajectoryLine:Insert(vecEndPos);
			return true;
		end

		if(bHitEnemy and resultTrace.entity:IsValid() and resultTrace.entity:GetPropInt("m_CollisionGroup") ~= 0)then
			ImpactMarkers.m_bIsHit = true;
		end 

		vecPosition = resultTrace.endpos;
		TrajectoryLine:Insert(resultTrace.endpos);

		if(resultTrace.fraction ~= 1)then 
			break; 
		end
	end

	if(resultTrace)then
		ImpactMarkers:Insert(resultTrace.endpos, resultTrace.plane);
	end

	return true;
end

local function PhysicsClipVelocity(vecVelocity, vecNormal, flOverbounce)
	local vecOut = vecVelocity - (vecNormal * (vecVelocity:Dot(vecNormal) * flOverbounce));
	
	if(vecOut.x > -0.1 and vecOut.x < 0.1)then
		vecOut.x = 0;
	end

	if(vecOut.y > -0.1 and vecOut.y < 0.1)then
		vecOut.y = 0;
	end

	if(vecOut.z > -0.1 and vecOut.z < 0.1)then
		vecOut.z = 0;
	end

	return vecOut, ((vecNormal.z > 0) and 1 or (vecNormal.z == 0) and 2 or 0);
end

local function DoSimulProjectileTrace(
	pObject, 
	flElasticity, 
	vecMins, 
	vecMaxs, 
	flCollideWithTeammatesDelay, 
	flLifetime, 
	bStopOnHittingEnemy, 
	iTraceMask, 
	iCollisionType)

	local iBounces = 0;
	local mapCollisions = {};
	local vecLastBounce;
	local iSizeHack = 0;
	local bDied = false;
	for i = 1, 330 do
		local vecStart = pObject:GetPosition();
		PhysicsEnvironment:Simulate(g_flTraceInterval);

		local bIsPlayer = false;
		local bDeadStop = false;
		local bHitEnemy = false;
		local resultTrace = TRACE_HULL(vecStart, pObject:GetPosition(), vecMins, vecMaxs, iTraceMask, function(pEntity, iMask)
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
				if((bStopOnHittingEnemy and iBounces == 0) or pEntity:GetClass() == "CTFGenericBomb")then
					bDeadStop = true;
				end

				bIsPlayer = true;
				if(iBounces == 0 or pEntity:GetClass() == "CTFGenericBomb")then 
					bHitEnemy = iCollisionType ~= COLLISION_NONE;
				end

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

			mapCollisions[pEntity:GetIndex()] = true;
			bIsPlayer = i * g_flTraceInterval > flCollideWithTeammatesDelay;
			return bIsPlayer;
		end);
		
		if(i * g_flTraceInterval > flLifetime)then
			local flFraction = ((i * g_flTraceInterval) - flLifetime) / g_flTraceInterval;			
			local vecEndPos = pObject:GetPosition();
			local vecEndPos = vecEndPos - ((vecEndPos - resultTrace.startpos) * flFraction);
			
			if((vecEndPos - vecStart):LengthSqr() >= (resultTrace.endpos - vecStart):LengthSqr())then
				vecEndPos = resultTrace.endpos;
				flFraction = 1;

				if(bHitEnemy and resultTrace.entity:IsValid() and resultTrace.entity:GetPropInt("m_CollisionGroup") ~= 0)then
					ImpactMarkers.m_bIsHit = true;
				end
			end

			ImpactMarkers:Insert(vecEndPos, (flFraction == 1) and resultTrace.plane or nil);
			TrajectoryLine:Insert(vecEndPos);
			bDied = true;
			break;
		end

		if(bHitEnemy and resultTrace.entity:IsValid() and resultTrace.entity:GetPropInt("m_CollisionGroup") ~= 0)then
			ImpactMarkers.m_bIsHit = true;
		end

		TrajectoryLine:Insert(resultTrace.endpos);

		if(resultTrace.fraction ~= 1)then
			if(vecLastBounce)then
				if((vecLastBounce - resultTrace.endpos):Length() < 4)then
					TrajectoryLine.m_iSize = iSizeHack;
					break;
				end
			end

			ImpactMarkers:Insert(resultTrace.endpos, resultTrace.plane);
			if(flElasticity == 0)then				bDied = true;
				break;
			end

			if(resultTrace.startsolid or bDeadStop or not config.enable_bounce)then
				break;
			end

			local vecVelocity, vecAngularVelocity = pObject:GetVelocity();
			local vecPosition, vecAngles = pObject:GetPosition();

			pObject:SetPosition(resultTrace.endpos, vecAngles);

			local vecVelocity = PhysicsClipVelocity(vecVelocity, resultTrace.plane, 2);
			local flSurfaceElasticity = 1;
			if(bIsPlayer)then
				flSurfaceElasticity = 0.3;
			end

			vecVelocity = vecVelocity * CLAMP(flSurfaceElasticity * flElasticity, 0, 0.9);
			if(vecVelocity:LengthSqr() < 30 * 30 or resultTrace.plane.z > 0.7)then
				break;
			end

			pObject:SetVelocity(vecVelocity, vecAngularVelocity * -0.5);

			iBounces = iBounces + 1;

			vecLastBounce = resultTrace.endpos;
			iSizeHack = TrajectoryLine.m_iSize;
			if(iBounces > 10)then
				break;
			end
		end
	end

	PhysicsEnvironment:ResetSimulationClock();
	return bDied and iBounces == 0;
end

callbacks.Register("Draw", function()
	UpdateSpellPreference();

	TrajectoryLine.m_aPositions, TrajectoryLine.m_iSize = {}, 0;
	if(engine.Con_IsVisible() or engine.IsGameUIVisible())then
		return;
	end

	local pLocalPlayer = entities.GetLocalPlayer();
	if(not pLocalPlayer or pLocalPlayer:InCond(7) or not pLocalPlayer:IsAlive())then
		return;
	end

	g_iLocalTeamNumber = pLocalPlayer:GetTeamNumber();

	if(not SetProjectileContext(pLocalPlayer, pLocalPlayer:GetAbsOrigin(), 
		pLocalPlayer:GetPropVector("localdata", "m_vecViewOffset[0]"), engine.GetViewAngles()))then
		return;
	end

	local stInfo = nil;
	if(g_bIsZombieInfection and g_iLocalTeamNumber == 3)then -- Blue
		stInfo = GetZombieInformation();
	else
		local stProjectileInfo = GetProjectileInformation();
		local stSpellInfo = GetSpellInformation();
		if(g_bSpellPreferState)then
			stInfo = stSpellInfo or stProjectileInfo;
		else
			stInfo = stProjectileInfo or stSpellInfo;
		end
	end
	
	

	if(not stInfo)then
		return;
	end

	if(not stInfo:UpdateContext())then
		return;
	end

	local vecSource = stInfo:GetFirePosition();
	local vecAngles = stInfo:GetFireAngles();

	TrajectoryLine:Insert(vecSource);

	local bDied = false;
	if(stInfo.m_iType == PROJECTILE_TYPE_BASIC)then
		bDied = DoBasicProjectileTrace(
			vecSource,
			vecAngles:Forward(),
			stInfo:GetVelocity(),
			stInfo.m_vecMins,
			stInfo.m_vecMaxs,
			stInfo.m_flCollideWithTeammatesDelay,
			stInfo:GetLifetime(),
			stInfo.m_bStopOnHittingEnemy,
			stInfo.m_flDamageRadius,
			stInfo.m_iTraceMask,
			stInfo.m_iCollisionType
		);

	elseif(stInfo.m_iType == PROJECTILE_TYPE_PSEUDO)then
		bDied = DoPseudoProjectileTrace(
			vecSource,
			VEC_ROT(stInfo:GetVelocity(), vecAngles),
			stInfo:GetGravity(),
			stInfo.m_flDrag,
			stInfo.m_vecMins,
			stInfo.m_vecMaxs,
			stInfo.m_flCollideWithTeammatesDelay,
			stInfo:GetLifetime(),
			stInfo.m_bStopOnHittingEnemy,
			stInfo.m_iTraceMask,
			stInfo.m_iCollisionType
		);

	elseif(stInfo.m_iType == PROJECTILE_TYPE_SIMUL)then
		local pObject = GetPhysicsObject(stInfo.m_sModelName);
		pObject:SetPosition(vecSource, vecAngles, true);
		pObject:SetVelocity(VEC_ROT(stInfo:GetVelocity(), vecAngles), stInfo:GetAngularVelocity());

		bDied = DoSimulProjectileTrace(
			pObject,
			stInfo.m_flElasticity,
			stInfo.m_vecMins,
			stInfo.m_vecMaxs,
			stInfo.m_flCollideWithTeammatesDelay,
			stInfo:GetLifetime(),
			stInfo.m_bStopOnHittingEnemy,
			stInfo.m_iTraceMask,
			stInfo.m_iCollisionType
		);

	else
		return;
	end

	if(ImpactMarkers.m_iSize > 0)then
		g_vEndOrigin = ImpactMarkers.m_aPositions[ImpactMarkers.m_iSize][1];

		if(not ImpactMarkers.m_bIsHit and stInfo.m_iCollisionType ~= COLLISION_NONE and bDied)then
			ImpactMarkers.m_bIsHit = CanDealRadialDamage(stInfo:GetExplosionRadius(), ImpactMarkers.m_aPositions[ImpactMarkers.m_iSize][1]);
		end
	end

	ImpactMarkers:Sort();
	ImpactMarkers:DrawPolygons();
	TrajectoryLine();
	ImpactMarkers();
	ImpactCamera();
end);

if config.camera.enabled then
	callbacks.Register("PostRenderView", function(view)
		local CustomCtx = client.GetPlayerView();
		local source = config.camera.source;
		local distance, angle = source.distance, source.angle;

		CustomCtx.fov = source.fov;

		local stDTrace = TRACE_LINE(g_vEndOrigin, g_vEndOrigin - (Vector3( angle, CustomCtx.angles.y, CustomCtx.angles.z):Forward() * distance), 100679683, function() return false; end);
		local stUTrace = TRACE_LINE(g_vEndOrigin, g_vEndOrigin - (Vector3(-angle, CustomCtx.angles.y, CustomCtx.angles.z):Forward() * distance), 100679683, function() return false; end);

		if stDTrace.fraction >= stUTrace.fraction - 0.1 then
			CustomCtx.angles = EulerAngles( angle, CustomCtx.angles.y, CustomCtx.angles.z);
			CustomCtx.origin = stDTrace.endpos;

		else
			CustomCtx.angles = EulerAngles(-angle, CustomCtx.angles.y, CustomCtx.angles.z);
			CustomCtx.origin = stUTrace.endpos;
		end

		render.Push3DView(CustomCtx, 0x37, ImpactCamera.Texture)
		render.ViewDrawScene(true, true, CustomCtx)
		render.PopView();
	end)
end

callbacks.Register("Unload", function()
	GetPhysicsObject:Shutdown();
	physics.DestroyEnvironment(PhysicsEnvironment);
	draw.DeleteTexture(g_iPolygonTexture);
	draw.DeleteTexture(textureFill);
	draw.DeleteTexture(ImpactMarkers.m_iTexture);
end);

callbacks.Register("FrameStageNotify", function(iStage)
	if(iStage ~= 4)then -- FRAME_NET_UPDATE_END
		return;
	end

	g_bIsZombieInfection = (engine.GetMapName() or ""):gsub(".*/", ""):find("zi_") == 1;
end);

LOG("Script fully loaded!");
