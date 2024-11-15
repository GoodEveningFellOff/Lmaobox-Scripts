local DEBUG=(function()local aColorPrint={function(a)printc(0x37,0xff,0x37,0xff,a)end,function(a)printc(0x9b,0xff,0x37,0xff,a)end,function(a)printc(0xff,0xff,0x37,0xff,a)end,function(a)printc(0xff,0x9b,0x37,0xff,a)end,function(a)printc(0xff,0x37,0x37,0xff,a)end};return function(sComment, iLine, iPriority)aColorPrint[iPriority or 5](("[DEBUG] " .. sComment .. " (Line: %i, Time %s)"):format(iLine,os.clock()))end end)();
DEBUG("Script load started!", 2, 2);

local config = {
	polygon = {
		enabled = false;
		r = 255;
		g = 200;
		b = 155;
		a = 50;

		size = 10;
		segments = 20;
	};
	
	line = {
		enabled = true;
		r = 255;
		g = 255;
		b = 255;
		a = 255;
	};

	flags = {
		enabled = true;
		r = 255;
		g = 0;
		b = 0;
		a = 255;

		size = 5;
	};

	outline = {
		line_and_flags = true;
		polygon = true;
		r = 0;
		g = 0;
		b = 0;
		a = 155;
	};

	camera = {
		enabled = true;
		
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

	-- 0.5 to 8, determines the size of the segments traced, lower values = worse performance (default 2.5)
	measure_segment_size = 2.5;
};


-- Boring shit ahead!
local CROSS = (function(a, b, c) return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]); end);
local CLAMP = (function(a, b, c) return (a<b) and b or (a>c) and c or a; end);
local FLOOR = math.floor;
local TRACE_HULL = engine.TraceHull;
local TRACE_LINE = engine.TraceLine;
local WORLD2SCREEN = client.WorldToScreen;
local POLYGON = draw.TexturedPolygon;
local LINE = draw.Line;
local OUTLINED_RECT = draw.OutlinedRect;
local COLOR = draw.Color;

local aItemDefinitions = {};
do
	local laDefinitions = {
		[222]	= 11;		--Mad Milk                                      tf_weapon_jar_milk
		[812]	= 12;		--The Flying Guillotine                         tf_weapon_cleaver
		[833]	= 12;		--The Flying Guillotine (Genuine)               tf_weapon_cleaver
		[1121]	= 11;		--Mutated Milk                                  tf_weapon_jar_milk

		[18]	= -1;		--Rocket Launcher                               tf_weapon_rocketlauncher
		[205]	= -1;		--Rocket Launcher (Renamed/Strange)             tf_weapon_rocketlauncher
		[127]	= -1;		--The Direct Hit                                tf_weapon_rocketlauncher_directhit
		[228]	= -1;		--The Black Box                                 tf_weapon_rocketlauncher
		[237]	= -1;		--Rocket Jumper                                 tf_weapon_rocketlauncher
		[414]	= -1;		--The Liberty Launcher                          tf_weapon_rocketlauncher
		[441]	= -1;		--The Cow Mangler 5000                          tf_weapon_particle_cannon	
		[513]	= -1;		--The Original                                  tf_weapon_rocketlauncher
		[658]	= -1;		--Festive Rocket Launcher                       tf_weapon_rocketlauncher
		[730]	= -1;		--The Beggar's Bazooka                          tf_weapon_rocketlauncher
		[800]	= -1;		--Silver Botkiller Rocket Launcher Mk.I         tf_weapon_rocketlauncher
		[809]	= -1;		--Gold Botkiller Rocket Launcher Mk.I           tf_weapon_rocketlauncher
		[889]	= -1;		--Rust Botkiller Rocket Launcher Mk.I           tf_weapon_rocketlauncher
		[898]	= -1;		--Blood Botkiller Rocket Launcher Mk.I          tf_weapon_rocketlauncher
		[907]	= -1;		--Carbonado Botkiller Rocket Launcher Mk.I      tf_weapon_rocketlauncher
		[916]	= -1;		--Diamond Botkiller Rocket Launcher Mk.I        tf_weapon_rocketlauncher
		[965]	= -1;		--Silver Botkiller Rocket Launcher Mk.II        tf_weapon_rocketlauncher
		[974]	= -1;		--Gold Botkiller Rocket Launcher Mk.II          tf_weapon_rocketlauncher
		[1085]	= -1;		--Festive Black Box                             tf_weapon_rocketlauncher
		[1104]	= -1;		--The Air Strike                                tf_weapon_rocketlauncher_airstrike
		[15006]	= -1;		--Woodland Warrior                              tf_weapon_rocketlauncher
		[15014]	= -1;		--Sand Cannon                                   tf_weapon_rocketlauncher
		[15028]	= -1;		--American Pastoral                             tf_weapon_rocketlauncher
		[15043]	= -1;		--Smalltown Bringdown                           tf_weapon_rocketlauncher
		[15052]	= -1;		--Shell Shocker                                 tf_weapon_rocketlauncher
		[15057]	= -1;		--Aqua Marine                                   tf_weapon_rocketlauncher
		[15081]	= -1;		--Autumn                                        tf_weapon_rocketlauncher
		[15104]	= -1;		--Blue Mew                                      tf_weapon_rocketlauncher
		[15105]	= -1;		--Brain Candy                                   tf_weapon_rocketlauncher
		[15129]	= -1;		--Coffin Nail                                   tf_weapon_rocketlauncher
		[15130]	= -1;		--High Roller's                                 tf_weapon_rocketlauncher
		[15150]	= -1;		--Warhawk                                       tf_weapon_rocketlauncher

		[442]	= -1;		--The Righteous Bison                           tf_weapon_raygun

		[1178]	= -1;		--Dragon's Fury                                 tf_weapon_rocketlauncher_fireball

		[39]	= 8;		--The Flare Gun                                 tf_weapon_flaregun
		[351]	= 8;		--The Detonator                                 tf_weapon_flaregun
		[595]	= 8;		--The Manmelter                                 tf_weapon_flaregun_revenge
		[740]	= 8;		--The Scorch Shot                               tf_weapon_flaregun
		[1180]	= 0;		--Gas Passer                                    tf_weapon_jar_gas

		[19]	= 5;		--Grenade Launcher                              tf_weapon_grenadelauncher
		[206]	= 5;		--Grenade Launcher (Renamed/Strange)            tf_weapon_grenadelauncher
		[308]	= 5;		--The Loch-n-Load                               tf_weapon_grenadelauncher
		[996]	= 6;		--The Loose Cannon                              tf_weapon_cannon
		[1007]	= 5;		--Festive Grenade Launcher                      tf_weapon_grenadelauncher
		[1151]	= 4;		--The Iron Bomber                               tf_weapon_grenadelauncher
		[15077]	= 5;		--Autumn                                        tf_weapon_grenadelauncher
		[15079]	= 5;		--Macabre Web                                   tf_weapon_grenadelauncher
		[15091]	= 5;		--Rainbow                                       tf_weapon_grenadelauncher
		[15092]	= 5;		--Sweet Dreams                                  tf_weapon_grenadelauncher
		[15116]	= 5;		--Coffin Nail                                   tf_weapon_grenadelauncher
		[15117]	= 5;		--Top Shelf                                     tf_weapon_grenadelauncher
		[15142]	= 5;		--Warhawk                                       tf_weapon_grenadelauncher
		[15158]	= 5;		--Butcher Bird                                  tf_weapon_grenadelauncher

		[20]	= 1;		--Stickybomb Launcher                           tf_weapon_pipebomblauncher
		[207]	= 1;		--Stickybomb Launcher (Renamed/Strange)         tf_weapon_pipebomblauncher
		[130]	= 3;		--The Scottish Resistance                       tf_weapon_pipebomblauncher
		[265]	= 3;		--Sticky Jumper                                 tf_weapon_pipebomblauncher
		[661]	= 1;		--Festive Stickybomb Launcher                   tf_weapon_pipebomblauncher
		[797]	= 1;		--Silver Botkiller Stickybomb Launcher Mk.I     tf_weapon_pipebomblauncher
		[806]	= 1;		--Gold Botkiller Stickybomb Launcher Mk.I       tf_weapon_pipebomblauncher
		[886]	= 1;		--Rust Botkiller Stickybomb Launcher Mk.I       tf_weapon_pipebomblauncher
		[895]	= 1;		--Blood Botkiller Stickybomb Launcher Mk.I      tf_weapon_pipebomblauncher
		[904]	= 1;		--Carbonado Botkiller Stickybomb Launcher Mk.I  tf_weapon_pipebomblauncher
		[913]	= 1;		--Diamond Botkiller Stickybomb Launcher Mk.I    tf_weapon_pipebomblauncher
		[962]	= 1;		--Silver Botkiller Stickybomb Launcher Mk.II    tf_weapon_pipebomblauncher
		[971]	= 1;		--Gold Botkiller Stickybomb Launcher Mk.II      tf_weapon_pipebomblauncher
		[1150]	= 2;		--The Quickiebomb Launcher                      tf_weapon_pipebomblauncher
		[15009]	= 1;		--Sudden Flurry                                 tf_weapon_pipebomblauncher
		[15012]	= 1;		--Carpet Bomber                                 tf_weapon_pipebomblauncher
		[15024]	= 1;		--Blasted Bombardier                            tf_weapon_pipebomblauncher
		[15038]	= 1;		--Rooftop Wrangler                              tf_weapon_pipebomblauncher
		[15045]	= 1;		--Liquid Asset                                  tf_weapon_pipebomblauncher
		[15048]	= 1;		--Pink Elephant                                 tf_weapon_pipebomblauncher
		[15082]	= 1;		--Autumn                                        tf_weapon_pipebomblauncher
		[15083]	= 1;		--Pumpkin Patch                                 tf_weapon_pipebomblauncher
		[15084]	= 1;		--Macabre Web                                   tf_weapon_pipebomblauncher
		[15113]	= 1;		--Sweet Dreams                                  tf_weapon_pipebomblauncher
		[15137]	= 1;		--Coffin Nail                                   tf_weapon_pipebomblauncher
		[15138]	= 1;		--Dressed to Kill                               tf_weapon_pipebomblauncher
		[15155]	= 1;		--Blitzkrieg                                    tf_weapon_pipebomblauncher

		[588]	= -1;		--The Pomson 6000                               tf_weapon_drg_pomson
		[997]	= 9;		--The Rescue Ranger                             tf_weapon_shotgun_building_rescue

		[17]	= 10;		--Syringe Gun                                   tf_weapon_syringegun_medic
		[204]	= 10;		--Syringe Gun (Renamed/Strange)                 tf_weapon_syringegun_medic
		[36]	= 10;		--The Blutsauger                                tf_weapon_syringegun_medic
		[305]	= 9;		--Crusader's Crossbow                           tf_weapon_crossbow
		[412]	= 10;		--The Overdose                                  tf_weapon_syringegun_medic
		[1079]	= 9;		--Festive Crusader's Crossbow                   tf_weapon_crossbow

		[56]	= 7;		--The Huntsman                                  tf_weapon_compound_bow
		[1005]	= 7;		--Festive Huntsman                              tf_weapon_compound_bow
		[1092]	= 7;		--The Fortified Compound                        tf_weapon_compound_bow

		[58]	= 11;		--Jarate                                        tf_weapon_jar
		[1083]	= 11;		--Festive Jarate                                tf_weapon_jar
		[1105]	= 11;		--The Self-Aware Beauty Mark                    tf_weapon_jar
	};

	local iHighestItemDefinitionIndex = 0;
	for i, _ in pairs(laDefinitions) do
		iHighestItemDefinitionIndex = math.max(iHighestItemDefinitionIndex, i);
	end

	for i = 1, iHighestItemDefinitionIndex do
		table.insert(aItemDefinitions, laDefinitions[i] or false)
	end
end

local PhysicsEnvironment = physics.CreateEnvironment();
do
	PhysicsEnvironment:SetGravity( Vector3( 0, 0, -800 ) )
	PhysicsEnvironment:SetAirDensity( 2.0 )
	PhysicsEnvironment:SetSimulationTimestep(1/66)
end

local PhysicsObjectHandler = {};
do
	PhysicsObjectHandler.m_aObjects = {};
	PhysicsObjectHandler.m_iActiveObject = 0;

	function PhysicsObjectHandler:Initialize()
		if #self.m_aObjects > 0 then
			return;
		end

		local function new(path)
			local solid, model = physics.ParseModelByName(path);
			table.insert(self.m_aObjects, PhysicsEnvironment:CreatePolyObject(model, solid:GetSurfacePropName(), solid:GetObjectParameters()));
		end

		new("models/weapons/w_models/w_stickybomb.mdl");										--Stickybomb
		new("models/workshop/weapons/c_models/c_kingmaker_sticky/w_kingmaker_stickybomb.mdl");	--QuickieBomb
		new("models/weapons/w_models/w_stickybomb_d.mdl");										--ScottishResistance, StickyJumper
		
		self.m_aObjects[1]:Wake();
		self.m_iActiveObject = 1;
	end

	function PhysicsObjectHandler:Destroy()
		self.m_iActiveObject = 0;
		
		if #self.m_aObjects == 0 then
			return;
		end
		
		for i, obj in pairs(self.m_aObjects) do
			PhysicsEnvironment:DestroyObject(obj)
			self.m_aObjects[i] = nil;
		end
	end

	setmetatable(PhysicsObjectHandler, {
		__call = function(self, iRequestedObject)
			if iRequestedObject ~= self.m_iActiveObject then
				self.m_aObjects[self.m_iActiveObject]:Sleep();
				self.m_aObjects[iRequestedObject]:Wake();

				self.m_iActiveObject = iRequestedObject;
			end
			
			return self.m_aObjects[self.m_iActiveObject];
		end;
	});
end

local TrajectoryLine = {};
do
	TrajectoryLine.m_aPositions = {};
	TrajectoryLine.m_iSize = 0;
	TrajectoryLine.m_vFlagOffset = Vector3(0, 0, 0);

	function TrajectoryLine:Insert(vec)
		self.m_iSize = self.m_iSize + 1;
		self.m_aPositions[self.m_iSize] = vec;
	end

	local iLineRed,    iLineGreen,    iLineBlue,    iLineAlpha    = config.line.r,    config.line.g,    config.line.b,    config.line.a;
	local iFlagRed,    iFlagGreen,    iFlagBlue,    iFlagAlpha    = config.flags.r,   config.flags.g,   config.flags.b,   config.flags.a;
	local iOutlineRed, iOutlineGreen, iOutlineBlue, iOutlineAlpha = config.outline.r, config.outline.g, config.outline.b, config.outline.a;
	local iOutlineOffsetInner = (config.flags.size < 1) and -1 or 0;
	local iOutlineOffsetOuter = (config.flags.size < 1) and -1 or 1;

	local metatable = {__call = nil;};
	if not config.line.enabled and not config.flags.enabled then
		function metatable:__call() end
	
	elseif config.outline.line_and_flags then
		if config.line.enabled and config.flags.enabled then
			function metatable:__call()
				local positions, offset, last = self.m_aPositions, self.m_vFlagOffset, nil;
				
				COLOR(iOutlineRed, iOutlineGreen, iOutlineBlue, iOutlineAlpha);
				for i = self.m_iSize, 1, -1 do
					local this_pos = positions[i];
					local new, newf = WORLD2SCREEN(this_pos), WORLD2SCREEN(this_pos + offset);
				
					if last and new then
						if math.abs(last[1] - new[1]) > math.abs(last[2] - new[2]) then
							LINE(last[1], last[2] - 1, new[1], new[2] - 1);
							LINE(last[1], last[2] + 1, new[1], new[2] + 1);

						else
							LINE(last[1] - 1, last[2], new[1] - 1, new[2]);
							LINE(last[1] + 1, last[2], new[1] + 1, new[2]);
						end
					end

					if new and newf then
						LINE(newf[1], newf[2] - 1, new[1], new[2] - 1);
						LINE(newf[1], newf[2] + 1, new[1], new[2] + 1);
						LINE(newf[1] - iOutlineOffsetOuter, newf[2] - 1, newf[1] - iOutlineOffsetOuter, newf[2] + 2);
					end
					
					last = new;
				end

				last = nil;

				for i = self.m_iSize, 1, -1 do
					local this_pos = positions[i];
					local new, newf = WORLD2SCREEN(this_pos), WORLD2SCREEN(this_pos + offset);
				
					if last and new then
						COLOR(iLineRed, iLineGreen, iLineBlue, iLineAlpha);
						LINE(last[1], last[2], new[1], new[2]);
					end

					if new and newf then
						COLOR(iFlagRed, iFlagGreen, iFlagBlue, iFlagAlpha);
						LINE(newf[1], newf[2], new[1], new[2]);
					end
					
					last = new;
				end
			end

		elseif config.line.enabled then
			function metatable:__call()
				local positions, offset, last = self.m_aPositions, self.m_vFlagOffset, nil;
				
				for i = self.m_iSize, 1, -1 do
					local this_pos = positions[i];
					local new = WORLD2SCREEN(this_pos);
				
					if last and new then
						COLOR(iOutlineRed, iOutlineGreen, iOutlineBlue, iOutlineAlpha);
						if math.abs(last[1] - new[1]) > math.abs(last[2] - new[2]) then
							LINE(last[1], last[2] - 1, new[1], new[2] - 1);
							LINE(last[1], last[2] + 1, new[1], new[2] + 1);

						else
							LINE(last[1] - 1, last[2], new[1] - 1, new[2]);
							LINE(last[1] + 1, last[2], new[1] + 1, new[2]);
						end

						COLOR(iLineRed, iLineGreen, iLineBlue, iLineAlpha);
						LINE(last[1], last[2], new[1], new[2]);
					end
					
					last = new;
				end
			end

		else
			function metatable:__call()
				local positions, offset = self.m_aPositions, self.m_vFlagOffset;
				
				for i = self.m_iSize, 1, -1 do
					local this_pos = positions[i];
					local new, newf = WORLD2SCREEN(this_pos), WORLD2SCREEN(this_pos + offset);
				
					if new and newf then
						COLOR(iOutlineRed, iOutlineGreen, iOutlineBlue, iOutlineAlpha);
						LINE(new[1] + iOutlineOffsetInner, new[2] - 1, new[1] + iOutlineOffsetInner, new[2] + 2);
						LINE(newf[1], newf[2] - 1, new[1], new[2] - 1);
						LINE(newf[1], newf[2] + 1, new[1], new[2] + 1);
						LINE(newf[1] - iOutlineOffsetOuter, newf[2] - 1, newf[1] - iOutlineOffsetOuter, newf[2] + 2);

						COLOR(iFlagRed, iFlagGreen, iFlagBlue, iFlagAlpha);
						LINE(newf[1], newf[2], new[1], new[2]);
					end
				end
			end
		end

	elseif config.line.enabled and config.flags.enabled then
		function metatable:__call()
			local positions, offset, last = self.m_aPositions, self.m_vFlagOffset, nil;
				
			for i = self.m_iSize, 1, -1 do
				local this_pos = positions[i];
				local new, newf = WORLD2SCREEN(this_pos), WORLD2SCREEN(this_pos + offset);
				
				if last and new then
					COLOR(iLineRed, iLineGreen, iLineBlue, iLineAlpha);
					LINE(last[1], last[2], new[1], new[2]);
				end

				if new and newf then
					COLOR(iFlagRed, iFlagGreen, iFlagBlue, iFlagAlpha);
					LINE(newf[1], newf[2], new[1], new[2]);
				end
					
				last = new;
			end
		end

	elseif config.line.enabled then
		function metatable:__call()
			local positions, last = self.m_aPositions, nil;
			
			COLOR(iLineRed, iLineGreen, iLineBlue, iLineAlpha);
			for i = self.m_iSize, 1, -1 do
				local new = WORLD2SCREEN(positions[i]);
				
				if last and new then
					LINE(last[1], last[2], new[1], new[2]);
				end
					
				last = new;
			end
		end

	else
		function metatable:__call()
			local positions, offset = self.m_aPositions, self.m_vFlagOffset;
			
			COLOR(iFlagRed, iFlagGreen, iFlagBlue, iFlagAlpha);
			for i = self.m_iSize, 1, -1 do
				local this_pos = positions[i];
				local new, newf = WORLD2SCREEN(this_pos), WORLD2SCREEN(this_pos + offset);
				
				if new and newf then
					LINE(newf[1], newf[2], new[1], new[2]);
				end
			end
		end
	end

	setmetatable(TrajectoryLine, metatable);
end

local ImpactPolygon = {};
do
	ImpactPolygon.m_iTexture = draw.CreateTextureRGBA(string.char(0xff, 0xff, 0xff, config.polygon.a, 0xff, 0xff, 0xff, config.polygon.a, 0xff, 0xff, 0xff, config.polygon.a, 0xff, 0xff, 0xff, config.polygon.a), 2, 2);

	local vPlane, vOrigin = Vector3(0, 0, 0), Vector3(0, 0, 0);
	local iSegments = config.polygon.segments;
	local fSegmentAngleOffset = math.pi / iSegments;
	local fSegmentAngle = fSegmentAngleOffset * 2;

	local metatable = { __call = function(self, plane, origin) end; };
	if config.polygon.enabled then

		if config.outline.polygon then
			function metatable:__call(plane, origin)
				vPlane, vOrigin = plane or vPlane, origin or vOrigin;

				local positions = {};
				local radius = config.polygon.size;

				if math.abs(vPlane.z) >= 0.99 then
					for i = 1, iSegments do
						local ang = i * fSegmentAngle + fSegmentAngleOffset;
						positions[i] = WORLD2SCREEN(vOrigin + Vector3(radius * math.cos(ang), radius * math.sin(ang), 0));
						if not positions[i] then
							return;
						end
					end
	
				else
					local right = Vector3(-vPlane.y, vPlane.x, 0);
					local up = Vector3(vPlane.z * right.y, -vPlane.z * right.x, (vPlane.y * right.x) - (vPlane.x * right.y));

					radius = radius / math.cos(math.asin(vPlane.z))

					for i = 1, iSegments do
						local ang = i * fSegmentAngle + fSegmentAngleOffset;
						positions[i] = WORLD2SCREEN(vOrigin + (right * (radius * math.cos(ang))) + (up * (radius * math.sin(ang))));

						if not positions[i] then
							return;
						end
					end
				end

				COLOR(config.outline.r, config.outline.g, config.outline.b, config.outline.a);
				local last = positions[#positions];
				for i = 1, #positions do
					local new = positions[i]

					if math.abs(new[1] - last[1]) > math.abs(new[2] - last[2]) then
						LINE(last[1], last[2] + 1, new[1], new[2] + 1);
						LINE(last[1], last[2] - 1, new[1], new[2] - 1);
					else
						LINE(last[1] + 1, last[2], new[1] + 1, new[2]);
						LINE(last[1] - 1, last[2], new[1] - 1, new[2]);
					end


					last = new;
				end

				COLOR(config.polygon.r, config.polygon.g, config.polygon.b, 255);
				do
					local cords, reverse_cords = {}, {};
					local sizeof = #positions;
					local sum = 0;

					for i, pos in pairs(positions) do
						local convertedTbl = {pos[1], pos[2], 0, 0};

						cords[i], reverse_cords[sizeof - i + 1] = convertedTbl, convertedTbl;

						sum = sum + CROSS(pos, positions[(i % sizeof) + 1], positions[1]);
					end


					POLYGON(self.m_iTexture, (sum < 0) and reverse_cords or cords, true)
				end

				local last = positions[#positions];
				for i = 1, #positions do
					local new = positions[i];
				
					LINE(last[1], last[2], new[1], new[2]);

					last = new;
				end

			end

		else
			function metatable:__call(plane, origin)
				vPlane, vOrigin = plane or vPlane, origin or vOrigin;

				local positions = {};
				local radius = config.polygon.size;

				if math.abs(vPlane.z) >= 0.99 then
					for i = 1, iSegments do
						local ang = i * fSegmentAngle + fSegmentAngleOffset;
						positions[i] = WORLD2SCREEN(vOrigin + Vector3(radius * math.cos(ang), radius * math.sin(ang), 0));
						if not positions[i] then
							return;
						end
					end
	
				else
					local right = Vector3(-vPlane.y, vPlane.x, 0);
					local up = Vector3(vPlane.z * right.y, -vPlane.z * right.x, (vPlane.y * right.x) - (vPlane.x * right.y));

					radius = radius / math.cos(math.asin(vPlane.z))

					for i = 1, iSegments do
						local ang = i * fSegmentAngle + fSegmentAngleOffset;
						positions[i] = WORLD2SCREEN(vOrigin + (right * (radius * math.cos(ang))) + (up * (radius * math.sin(ang))));

						if not positions[i] then
							return;
						end
					end
				end

				COLOR(config.polygon.r, config.polygon.g, config.polygon.b, 255);
				do
					local cords, reverse_cords = {}, {};
					local sizeof = #positions;
					local sum = 0;

					for i, pos in pairs(positions) do
						local convertedTbl = {pos[1], pos[2], 0, 0};

						cords[i], reverse_cords[sizeof - i + 1] = convertedTbl, convertedTbl;

						sum = sum + CROSS(pos, positions[(i % sizeof) + 1], positions[1]);
					end


					POLYGON(self.m_iTexture, (sum < 0) and reverse_cords or cords, true)
				end

				local last = positions[#positions];
				for i = 1, #positions do
					local new = positions[i];
				
					LINE(last[1], last[2], new[1], new[2]);

					last = new;
				end

			end
		end
	end

	setmetatable(ImpactPolygon, metatable);
end

local ImpactCamera = {};
do
	local iX, iY, iWidth, iHeight = config.camera.x, config.camera.y, FLOOR(config.camera.height * config.camera.aspect_ratio), config.camera.height;
	local iResolutionX, iResolutionY = FLOOR(iWidth * config.camera.source.scale), FLOOR(iHeight * config.camera.source.scale);
	ImpactCamera.Texture = materials.CreateTextureRenderTarget("ProjectileCamera", iResolutionX, iResolutionY);
	local Material = materials.Create("ProjectileCameraMat", [[ UnlitGeneric { $basetexture "ProjectileCamera" }]] );

	local metatable = {__call = function(self) end;};

	if config.camera.enabled then
		function metatable:__call()
			COLOR(0, 0, 0, 255);
			OUTLINED_RECT(iX - 1, iY - 1, iX + iWidth + 1, iY + iHeight + 1);

			COLOR(255, 255, 255, 255);
			render.DrawScreenSpaceRectangle(Material, iX, iY, iWidth, iHeight, 0, 0, iResolutionX, iResolutionY, iResolutionX, iResolutionY);
		end
	end

	setmetatable(ImpactCamera, metatable);
end

local GetProjectileInformation = (function()
	local aOffsets = {
		Vector3(16, 8, -6),
		Vector3(23.5, -8, -3),
		Vector3(23.5, 12, -3),
		Vector3(16, 6, -8)
	};

	local aCollisionMaxs = {
		Vector3(0, 0, 0),
		Vector3(1, 1, 1),
		Vector3(2, 2, 2),
		Vector3(3, 3, 3)
	};

	return function(pLocal, bDucking, iCase, iDefIndex, iWepID)
		local fChargeBeginTime =  (pLocal:GetPropFloat("PipebombLauncherLocalData", "m_flChargeBeginTime") or 0);

		if fChargeBeginTime ~= 0 then
			fChargeBeginTime = globals.CurTime() - fChargeBeginTime;
		end

		if iCase == -1 then -- RocketLauncher, DragonsFury, Pomson, Bison
			local vOffset, vCollisionMax, fForwardVelocity = Vector3(23.5, -8, bDucking and 8 or -3), aCollisionMaxs[2], 0;
			
			if iWepID == 22 or iWepID == 65 then
				vOffset.y, vCollisionMax, fForwardVelocity = (iDefIndex == 513) and 0 or 12, aCollisionMaxs[1], (iWepID == 65) and 2000 or (iDefIndex == 414) and 1550 or 1100;

			elseif iWepID == 109 then
				vOffset.y, vOffset.z = 6, -3;

			else
				fForwardVelocity = 1200;

			end
			
			return vOffset, fForwardVelocity, 0, vCollisionMax, 0;

		elseif iCase == 1  then return aOffsets[1], 900 + CLAMP(fChargeBeginTime / 4, 0, 1) * 1500, 200, aCollisionMaxs[3], 0;                                   -- StickyBomb
		elseif iCase == 2  then return aOffsets[1], 900 + CLAMP(fChargeBeginTime / 1.2, 0, 1) * 1500, 200, aCollisionMaxs[3], 0;                                 -- QuickieBomb
		elseif iCase == 3  then return aOffsets[1], 900 + CLAMP(fChargeBeginTime / 4, 0, 1) * 1500, 200, aCollisionMaxs[3], 0;                                   -- ScottishResistance, StickyJumper
		elseif iCase == 4  then return aOffsets[1], 1200, 200, aCollisionMaxs[3], 400, 0.45;                                                                     -- TheIronBomber
		elseif iCase == 5  then return aOffsets[1], (iDefIndex == 308) and 1500 or 1200, 200, aCollisionMaxs[3], 400, (iDefIndex == 308) and 0.225 or 0.45;      -- GrenadeLauncher, LochnLoad
		elseif iCase == 6  then return aOffsets[1], 1440, 200, aCollisionMaxs[3], 560, 0.5;                                                                      -- LooseCannon
		elseif iCase == 7  then return aOffsets[2], 1800 + CLAMP(fChargeBeginTime, 0, 1) * 800, 0, aCollisionMaxs[2], 200 - CLAMP(fChargeBeginTime, 0, 1) * 160; -- Huntsman
		elseif iCase == 8  then return Vector3(23.5, 12, bDucking and 8 or -3), 2000, 0, aCollisionMaxs[1], 120;                                                 -- FlareGuns
		elseif iCase == 9  then return aOffsets[2], 2400, 0, aCollisionMaxs[((iDefIndex == 997) and 2 or 4)], 80;                                                -- CrusadersCrossbow, RescueRanger
		elseif iCase == 10 then return aOffsets[4], 1000, 0, aCollisionMaxs[2], 120;                                                                             -- SyringeGuns
		elseif iCase == 11 then return Vector3(23.5, 8, -3), 1000, 200, aCollisionMaxs[4], 450;                                                                  -- Jarate, MadMilk
		elseif iCase == 12 then return Vector3(23.5, 8, -3), 3000, 300, aCollisionMaxs[3], 900, 1.3;                                                             -- FlyingGuillotine
		end
	end
end)();


local g_fTraceInterval = CLAMP(config.measure_segment_size, 0.5, 8) / 66;
local g_fFlagInterval = g_fTraceInterval * 1320;
local g_vEndOrigin = Vector3(0, 0, 0);

callbacks.Register("CreateMove", "LoadPhysicsObjects", function()
	callbacks.Unregister("CreateMove", "LoadPhysicsObjects")

	PhysicsObjectHandler:Initialize()

	DEBUG("PhysicsObjectHandler initialized!", 676, 1);

	callbacks.Register("Draw", function()
		TrajectoryLine.m_aPositions, TrajectoryLine.m_iSize = {}, 0;

		if engine.Con_IsVisible() or engine.IsGameUIVisible() then
			return;
		end

		local pLocal = entities.GetLocalPlayer();
		if not pLocal or pLocal:InCond(7) or not pLocal:IsAlive() then 
			return;
		end
	
		local pWeapon = pLocal:GetPropEntity("m_hActiveWeapon");
		if not pWeapon or (pWeapon:GetWeaponProjectileType() or 0) < 2 then 
			return;
		end

		local iItemDefinitionIndex = pWeapon:GetPropInt("m_iItemDefinitionIndex");
		local iItemDefinitionType = aItemDefinitions[iItemDefinitionIndex] or 0;
		if iItemDefinitionType == 0 then return end

		local vOffset, fForwardVelocity, fUpwardVelocity, vCollisionMax, fGravity, fDrag = GetProjectileInformation(pWeapon, (pLocal:GetPropInt("m_fFlags") & FL_DUCKING) == 2, iItemDefinitionType, iItemDefinitionIndex, pWeapon:GetWeaponID());
		local vCollisionMin = -vCollisionMax;

		local vStartPosition, vStartAngle = pLocal:GetAbsOrigin() + pLocal:GetPropVector("localdata", "m_vecViewOffset[0]"), engine.GetViewAngles();

		local results = TRACE_HULL(vStartPosition, vStartPosition + (vStartAngle:Forward() * vOffset.x) + (vStartAngle:Right() * (vOffset.y * (pWeapon:IsViewModelFlipped() and -1 or 1))) + (vStartAngle:Up() * vOffset.z), vCollisionMin, vCollisionMax, 100679691);
		if results.fraction ~= 1 then return end

		vStartPosition = results.endpos;

		if iItemDefinitionType == -1 or (iItemDefinitionType >= 7 and iItemDefinitionType < 11) and fForwardVelocity ~= 0 then
			local res = engine.TraceLine(results.startpos, results.startpos + (vStartAngle:Forward() * 2000), 100679691);
			vStartAngle = (((res.fraction <= 0.1) and (results.startpos + (vStartAngle:Forward() * 2000)) or res.endpos) - vStartPosition):Angles();
		end
			
		local vVelocity = (vStartAngle:Forward() * fForwardVelocity) + (vStartAngle:Up() * fUpwardVelocity);

		TrajectoryLine.m_vFlagOffset = vStartAngle:Right() * -config.flags.size;
		TrajectoryLine:Insert(vStartPosition);

		if iItemDefinitionType == -1 then
			results = TRACE_HULL(vStartPosition, vStartPosition + (vStartAngle:Forward() * 10000), vCollisionMin, vCollisionMax, 100679691);

			if results.startsolid then return end
				
			local iSegments = FLOOR((results.endpos - results.startpos):Length() / g_fFlagInterval);
			local vForward = vStartAngle:Forward();
				
			for i = 1, iSegments do
				TrajectoryLine:Insert(vForward * (i * g_fFlagInterval) + vStartPosition);
			end

			TrajectoryLine:Insert(results.endpos);

		elseif iItemDefinitionType > 3 then
		
			local vPosition = Vector3(0, 0, 0);
			for i = 0.01515, 5, g_fTraceInterval do
				local scalar = (not fDrag) and i or ((1 - math.exp(-fDrag * i)) / fDrag);

				vPosition.x = vVelocity.x * scalar + vStartPosition.x;
				vPosition.y = vVelocity.y * scalar + vStartPosition.y;
				vPosition.z = (vVelocity.z - fGravity * i) * scalar + vStartPosition.z;

				results = TRACE_HULL(results.endpos, vPosition, vCollisionMin, vCollisionMax, 100679691);

				TrajectoryLine:Insert(results.endpos);

				if results.fraction ~= 1 then break; end
			end
		
		else
			local obj = PhysicsObjectHandler(iItemDefinitionType);

			obj:SetPosition(vStartPosition, vStartAngle, true)
			obj:SetVelocity(vVelocity, Vector3(0, 0, 0))

			for i = 2, 330 do
				results = TRACE_HULL(results.endpos, obj:GetPosition(), vCollisionMin, vCollisionMax, 100679691);
				TrajectoryLine:Insert(results.endpos);

				if results.fraction ~= 1 then break; end
				PhysicsEnvironment:Simulate(g_fTraceInterval);
			end

			PhysicsEnvironment:ResetSimulationClock();
		end

		if TrajectoryLine.m_iSize == 0 then return end
		if results then
			ImpactPolygon(results.plane, results.endpos)
			g_vEndOrigin = results.endpos;
		end

		if TrajectoryLine.m_iSize == 1 then 
			ImpactCamera();
			return; 
		end

		TrajectoryLine();
		ImpactCamera();
	end)
end)

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
	DEBUG("Script unload started!", 811, 2)

	PhysicsObjectHandler:Destroy();
	physics.DestroyEnvironment(PhysicsEnvironment);
	draw.DeleteTexture(ImpactPolygon.m_iTexture);

	DEBUG("Script fully unloaded!", 817, 1);
end)

DEBUG("Script fully loaded!", 820, 1);
