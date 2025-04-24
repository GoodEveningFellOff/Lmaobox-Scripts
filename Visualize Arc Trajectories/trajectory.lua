local function LOG(sMsg)
	--printc(0x9b, 0xff, 0x37, 0xff, string.format("[ln: %d, cl: %0.3f] %s", debug.getinfo(2, 'l').currentline, os.clock(), sMsg));
end

LOG("Script load started!");

local config = {
	polygon = {
		enabled = true;
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

		thickness = 2;
	};

	flags = {
		enabled = true;
		r = 255;
		g = 0;
		b = 0;
		a = 255;

		size = 5;
		thickness = 2;
	};

	outline = {
		line_and_flags = true;
		polygon = true;

		r = 0;
		g = 0;
		b = 0;
		a = 155;

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

	-- 0.5 to 8, determines the size of the segments traced, lower values = worse performance (default 2.5)
	measure_segment_size = 2.5;

	-- This will disable the line thickness which may be causing performance issues.
	ignore_thickness = true;
};


-- Boring shit ahead!
local CROSS = (function(a, b, c) return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]); end);
local CLAMP = (function(a, b, c) return (a<b) and b or (a>c) and c or a; end);
local VEC_ROT = (function(a,b) return (b:Forward() * a.x) + (b:Right() * a.y) + (b:Up() * a.z); end);
local FLOOR = math.floor;
local TRACE_HULL = engine.TraceHull;
local TRACE_LINE = engine.TraceLine;
local WORLD2SCREEN = client.WorldToScreen;
local POLYGON = draw.TexturedPolygon;
local LINE = draw.Line;
local OUTLINED_RECT = draw.OutlinedRect;
local COLOR = draw.Color;

if(((not config.line.enabled or config.line.thickness <= 1) and 
	(not config.flags.enabled or config.flags.thickness <= 1) and 
	(not config.outline.line_and_flags or config.outline.thickness <= 1)) or config.ignore_thickness)then
	config.ignore_thickness = true;
else
	if(config.line.thickness <= 0)then
		config.line.enabled = false;
	end

	if(config.flags.thickness <= 0)then
		config.flags.enabled = false;
	end

	if(config.outline.thickness <= 0)then
		config.outline.line_and_flags = false;
	end
end

local flFillAlpha = 255;
local flOutlineAlpha = 255;
local textureFill = draw.CreateTextureRGBA(string.char(0xff, 0xff, 0xff, flFillAlpha, 0xff, 0xff, 0xff, flFillAlpha, 0xff, 0xff, 0xff, flFillAlpha, 0xff, 0xff, 0xff, flFillAlpha), 2, 2);
local g_iPolygonTexture = draw.CreateTextureRGBA("\xff\xff\xff" .. string.char(config.polygon.a), 1, 1);

local PhysicsEnvironment = physics.CreateEnvironment();
PhysicsEnvironment:SetGravity(Vector3( 0, 0, -800));
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

local function ConvertCords(aPositions, vecFlagOffset)
	local aCords = {};
	for i = #aPositions, 1, -1 do
		local p1 = WORLD2SCREEN(aPositions[i]);
		local p2 = WORLD2SCREEN(aPositions[i] + vecFlagOffset);
		if(p1)then
			local n = #aCords + 1;
			aCords[n] = { p1[1], p1[2], nil, nil };
			if(p2)then
				aCords[n][3] = p2[1];
				aCords[n][4] = p2[2];
			end
		end
	end

	local aReturned = {};
	if(#aCords < 2)then
		return {};
	end

	local x1, y1, x2, y2 = aCords[1][1], aCords[1][2], aCords[2][1], aCords[2][2];

	local flAng = math.atan(y2 - y1, x2 - x1) + math.pi / 2;
	local flCos, flSin = math.cos(flAng), math.sin(flAng);
	aReturned[#aReturned + 1] = { x1, y1, flCos, flSin, aCords[1][3], aCords[1][4] };

	if(#aCords == 2)then
		aReturned[#aReturned + 1] = { x2, y2, flCos, flSin, aCords[2][3], aCords[2][4] };
		return aReturned;
	end

	for i = 3, #aCords do
		x1, y1 = x2, y2;
		x2, y2 = aCords[i][1], aCords[i][2];

		local flAng2 = math.atan(y2 - y1, x2 - x1) + math.pi / 2;
		local flHalfAngle = (flAng2 - flAng) / 2 + flAng;
		flAng = flAng2;

		aReturned[#aReturned + 1] = { x1, y1, math.cos(flAng), math.sin(flAng), aCords[i - 1][3], aCords[i - 1][4] };
		flCos, flSin = math.cos(flAng), math.sin(flAng);
	end

	aReturned[#aReturned + 1] = { x2, y2, flCos, flSin, aCords[#aCords][3], aCords[#aCords][4] }; 
	return aReturned;
end

local function DrawBasicThickLine(aCords, flSize)
	if #aCords < 2 then
		return;
	end

	local flSize = flSize / 2;

	local verts = {
		{aCords[1][1] - (flSize * aCords[1][3]), aCords[1][2] - (flSize * aCords[1][4]), 0, 0},
		{aCords[1][1] + (flSize * aCords[1][3]), aCords[1][2] + (flSize * aCords[1][4]), 0, 0},
		{0, 0, 0, 0},
		{0, 0, 0, 0}
	};

	for i = 2, #aCords do
		verts[4][1], verts[4][2] = verts[1][1], verts[1][2];
		verts[3][1], verts[3][2] = verts[2][1], verts[2][2];
		verts[1][1], verts[1][2] = aCords[i][1] - (flSize * aCords[i][3]), aCords[i][2] - (flSize * aCords[i][4]);
		verts[2][1], verts[2][2] = aCords[i][1] + (flSize * aCords[i][3]), aCords[i][2] + (flSize * aCords[i][4]);
		
		draw.TexturedPolygon(textureFill, verts, true);
	end
end


local function DrawProjectileLine(aCords, flSize, flFlagSize, flOutlineSize, aColorLine, aColorFlags, aColorOutline)
	if(#aCords < 2)then
		return;
	end

	if(flOutlineSize > 0 and config.outline.line_and_flags)then
		draw.Color(table.unpack(aColorOutline));
		local flOff = flSize / 2;
		local flFlagSize = flFlagSize / 2;
		local aVerts1 = {
			{aCords[1][1] - ((flOff + flOutlineSize) * aCords[1][3]), aCords[1][2] - ((flOff + flOutlineSize) * aCords[1][4]), 0, 0},
			{aCords[1][1] - (flOff * aCords[1][3]), aCords[1][2] - (flOff * aCords[1][4]), 0, 0},
			{0, 0, 0, 0},
			{0, 0, 0, 0}
		};

		local aVerts2 = {
			{aCords[1][1] + (flOff * aCords[1][3]), aCords[1][2] + (flOff * aCords[1][4]), 0, 0},
			{aCords[1][1] + ((flOff + flOutlineSize) * aCords[1][3]), aCords[1][2] + ((flOff + flOutlineSize) * aCords[1][4]), 0, 0},
			{0, 0, 0, 0},
			{0, 0, 0, 0}
		};

		local iFlagX, iFlagY = aCords[1][5], aCords[1][6];
		if(iFlagX and iFlagY and config.flags.enabled)then
			local iX, iY = aCords[1][1], aCords[1][2];
			local flAng = math.atan(iFlagY - iY, iFlagX - iX) + math.pi / 2;
			local flCos, flSin = math.cos(flAng), math.sin(flAng);

			local flS1, flS2 = flFlagSize, flFlagSize + flOutlineSize;
			local flO1, flO2, flO3, flO4 = flS1 * flCos, flS2 * flCos, flS1 * flSin, flS2 * flSin;


			draw.TexturedPolygon(textureFill, {
				{ iX - flO1, iY - flO3, 0, 0 },
				{ iX - flO2, iY - flO4, 0, 0 },
				{ iFlagX - flO2, iFlagY - flO4, 0, 0 },
				{ iFlagX - flO1, iFlagY - flO3, 0, 0 }	
			}, true);

			
			draw.TexturedPolygon(textureFill, {
				{ iX + flO2, iY + flO4, 0, 0 },
				{ iX + flO1, iY + flO3, 0, 0 },
				{ iFlagX + flO1, iFlagY + flO3, 0, 0 },
				{ iFlagX + flO2, iFlagY + flO4, 0, 0 }	
				
			}, true);
		end

		for i = 2, #aCords do
			aVerts1[4][1], aVerts1[4][2] = aVerts1[1][1], aVerts1[1][2];
			aVerts1[3][1], aVerts1[3][2] = aVerts1[2][1], aVerts1[2][2];
			aVerts1[1][1], aVerts1[1][2] = aCords[i][1] - ((flOff + flOutlineSize) * aCords[i][3]), aCords[i][2] - ((flOff + flOutlineSize) * aCords[i][4]);
			aVerts1[2][1], aVerts1[2][2] = aCords[i][1] - (flOff * aCords[i][3]), aCords[i][2] - (flOff * aCords[i][4]);

			aVerts2[4][1], aVerts2[4][2] = aVerts2[1][1], aVerts2[1][2];
			aVerts2[3][1], aVerts2[3][2] = aVerts2[2][1], aVerts2[2][2];
			aVerts2[1][1], aVerts2[1][2] = aCords[i][1] + (flOff * aCords[i][3]), aCords[i][2] + (flOff * aCords[i][4]);
			aVerts2[2][1], aVerts2[2][2] = aCords[i][1] + ((flOff + flOutlineSize) * aCords[i][3]), aCords[i][2] + ((flOff + flOutlineSize) * aCords[i][4]);

			if(config.line.enabled)then
				draw.TexturedPolygon(textureFill, aVerts1, true);
				draw.TexturedPolygon(textureFill, aVerts2, true);
			end
			
			if(config.flags.enabled)then
				local iFlagX, iFlagY = aCords[i][5], aCords[i][6];
				if(iFlagX and iFlagY)then
					local iX, iY = aCords[i][1], aCords[i][2];
					local flAng = math.atan(iFlagY - iY, iFlagX - iX) + math.pi / 2;
					local flCos, flSin = math.cos(flAng), math.sin(flAng);

					local flS1, flS2 = flFlagSize, flFlagSize + flOutlineSize;
					local flO1, flO2, flO3, flO4 = flS1 * flCos, flS2 * flCos, flS1 * flSin, flS2 * flSin;
		

					draw.TexturedPolygon(textureFill, {
						{ iX - flO1, iY - flO3, 0, 0 },
						{ iX - flO2, iY - flO4, 0, 0 },
						{ iFlagX - flO2, iFlagY - flO4, 0, 0 },
						{ iFlagX - flO1, iFlagY - flO3, 0, 0 }	
					}, true);

					
					draw.TexturedPolygon(textureFill, {
						{ iX + flO2, iY + flO4, 0, 0 },
						{ iX + flO1, iY + flO3, 0, 0 },
						{ iFlagX + flO1, iFlagY + flO3, 0, 0 },
						{ iFlagX + flO2, iFlagY + flO4, 0, 0 }	
						
					}, true);
				end
			end
		end
	end

	if(config.line.enabled)then
		draw.Color(table.unpack(aColorLine));	
		DrawBasicThickLine(aCords, flSize);
	end

	if(not config.flags.enabled)then
		return;
	end

	draw.Color(table.unpack(aColorFlags));
	local flSize = flSize / 2;
	for i = 1, #aCords do
		local iFlagX, iFlagY = aCords[i][5], aCords[i][6];
		if(iFlagX and iFlagY)then
			local iX, iY = aCords[i][1], aCords[i][2];
			local flAng = math.atan(iFlagY - iY, iFlagX - iX) + math.pi / 2;
			local flO1, flO2 = (flFlagSize / 2) * math.cos(flAng), (flFlagSize / 2) * math.sin(flAng);

			draw.TexturedPolygon(textureFill, {
				{iX + flO1, iY + flO2, 0, 0},
				{iX - flO1, iY - flO2, 0, 0},
				{iFlagX - flO1, iFlagY - flO2, 0, 0},
				{iFlagX + flO1, iFlagY + flO2, 0, 0}
			}, true);
		end
	end
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
	if(not config.line.enabled and not config.flags.enabled)then
		function metatable:__call() end

	elseif(not config.ignore_thickness)then
		function metatable:__call() 
			DrawProjectileLine(ConvertCords(self.m_aPositions, self.m_vFlagOffset), 
			config.line.thickness, config.flags.thickness, config.outline.thickness,
			{ config.line.r, config.line.g, config.line.b, config.line.a }, 
			{ config.flags.r, config.flags.g, config.flags.b, config.flags.a },
			{ config.outline.r, config.outline.g, config.outline.b, config.outline.a });
		end
	
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


					POLYGON(g_iPolygonTexture, (sum < 0) and reverse_cords or cords, true)
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


					POLYGON(g_iPolygonTexture, (sum < 0) and reverse_cords or cords, true)
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

	-- Creating materials can just fail sometimes so we will just try to do it 128 times and if it still fails its not my problem!
	local Material;
	for i = 1, 128 do
		Material = materials.Create("ProjectileCameraMat", [[ UnlitGeneric { $basetexture "ProjectileCamera" }]] );
		if(Material)then
			break;
		end
	end

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

local PROJECTILE_TYPE_BASIC = 0;
local PROJECTILE_TYPE_PSEUDO = 1;
local PROJECTILY_TYPE_SIMUL = 2;

local function GetProjectileInformation(...) end
do
	LOG("Creating GetProjectileInformation");

	local aItemDefinitions = {};
	local function AppendItemDefinitions(iType, ...)
		for _, i in pairs({...})do
			aItemDefinitions[i] = iType;
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
			m_iAlignDistance = tbl.iAlignDistance or 0;
			m_sModelName = tbl.sModelName or "";

			

			GetOffset = (not tbl.GetOffset) and (function(self, bDucking, bIsFlipped) 
				return bIsFlipped and Vector3(self.m_vecOffset.x, -self.m_vecOffset.y, self.m_vecOffset.z) or self.m_vecOffset;   
			end) or tbl.GetOffset;  -- self, bDucking, bIsFlipped

			GetFirePosition = tbl.GetFirePosition or function(self, pLocalPlayer, vecLocalView, vecViewAngles, bIsFlipped)
				local resultTrace = TRACE_HULL( 
					vecLocalView, 
					vecLocalView + VEC_ROT(
						self:GetOffset((pLocalPlayer:GetPropInt("m_fFlags") & FL_DUCKING) ~= 0, bIsFlipped), 
						vecViewAngles
					), 
					-Vector3(8, 8, 8), 
					Vector3(8, 8, 8), 
					100679691); -- MASK_SOLID_BRUSHONLY

				return (not resultTrace.startsolid) and resultTrace.endpos or nil;
			end;

			GetVelocity = (not tbl.GetVelocity) and (function(self, ...) return self.m_vecVelocity; end) or tbl.GetVelocity; -- self, flChargeBeginTime

			GetAngularVelocity = (not tbl.GetAngularVelocity) and (function(self, ...) return self.m_vecAngularVelocity; end) or tbl.GetAngularVelocity; -- self, flChargeBeginTime

			GetGravity = (not tbl.GetGravity) and (function(self, ...) return self.m_flGravity; end) or tbl.GetGravity; -- self, flChargeBeginTime
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

	local function DefineDerivedProjectileDefinition(def, tbl)
		local stReturned = {};
		for k, v in pairs(def) do stReturned[k] = v; end
		for k, v in pairs(tbl) do stReturned[((type(v) ~= "function") and "m_" or "") .. k] = v; end

		if(not tbl.GetOffset and tbl.vecOffset)then
			stReturned.GetOffset = function(self, bDucking, bIsFlipped) 
				return bIsFlipped and Vector3(self.m_vecOffset.x, -self.m_vecOffset.y, self.m_vecOffset.z) or self.m_vecOffset; 
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
	
		return stReturned;
	end

	local aProjectileInfo = {};

	AppendItemDefinitions(1, 
		18,    -- Rocket Launcher tf_weapon_rocketlauncher
		205,   -- Rocket Launcher (Renamed/Strange) 	tf_weapon_rocketlauncher
		228,   -- The Black Box 	tf_weapon_rocketlauncher
		237,   -- Rocket Jumper 	tf_weapon_rocketlauncher
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
	aProjectileInfo[1] = DefineBasicProjectileDefinition({
		vecVelocity = Vector3(1100, 0, 0);
		vecMaxs = Vector3(0, 0, 0);
		iAlignDistance = 2000;

		GetOffset = function(self, bDucking, bIsFlipped)
			return Vector3(23.5, 12 * (bIsFlipped and -1 or 1), bDucking and 8 or -3);
		end;
	});
	
	AppendItemDefinitions(2, 
		127 -- The Direct Hit
	);
	aProjectileInfo[2] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
		vecVelocity = Vector3(2000, 0, 0);
	});

	AppendItemDefinitions(3,
		414 -- The Liberty Launcher
	);
	aProjectileInfo[3] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
		vecVelocity = Vector3(1550, 0, 0);
	});

	AppendItemDefinitions(4,
		513 -- The Original
	);
	aProjectileInfo[4] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
		GetOffset = function(self, bDucking)
			return Vector3(23.5, 0, bDucking and 8 or -3);
		end;
	});

	-- https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/shared/tf/tf_weapon_dragons_fury.cpp
	AppendItemDefinitions(5,
		1178 -- Dragon's Fury
	);
	aProjectileInfo[5] = DefineBasicProjectileDefinition({
		vecVelocity = Vector3(600, 0, 0);
		vecMaxs = Vector3(1, 1, 1);

		GetOffset = function(self, bDucking, bIsFlipped)
			return Vector3(3, 7, -9);
		end;
	});
	
	AppendItemDefinitions(6, 
		442 -- The Righteous Bison
	);
	aProjectileInfo[6] = DefineBasicProjectileDefinition({
		vecVelocity = Vector3(1200, 0, 0);
		vecMaxs = Vector3(1, 1, 1);
		iAlignDistance = 2000;

		GetOffset = function(self, bDucking, bIsFlipped)
			return Vector3(23.5, -8 * (bIsFlipped and -1 or 1), bDucking and 8 or -3);
		end;
	});

	AppendItemDefinitions(7,
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
	aProjectileInfo[7] = DefineSimulProjectileDefinition({
		vecOffset = Vector3(16, 8, -6);
		vecAngularVelocity = Vector3(600, 0, 0);
		vecMaxs = Vector3(2, 2, 2);
		sModelName = "models/weapons/w_models/w_stickybomb.mdl";

		GetVelocity = function(self, flChargeBeginTime)
			return Vector3(900 + CLAMP(flChargeBeginTime / 4, 0, 1) * 1500, 0, 200);
		end;
	});

	AppendItemDefinitions(8, 
		1150 -- The Quickiebomb Launcher
	);
	aProjectileInfo[8] = DefineDerivedProjectileDefinition(aProjectileInfo[7], {
		sModelName = "models/workshop/weapons/c_models/c_kingmaker_sticky/w_kingmaker_stickybomb.mdl";

		GetVelocity = function(self, flChargeBeginTime)
			return Vector3(900 + CLAMP(flChargeBeginTime / 1.2, 0, 1) * 1500, 0, 200); 
		end;
	});

	AppendItemDefinitions(9, 
		130, -- The Scottish Resistance
		265  -- Sticky Jumper
	);
	aProjectileInfo[9] = DefineDerivedProjectileDefinition(aProjectileInfo[7], {
		sModelName = "models/weapons/w_models/w_stickybomb_d.mdl";
	});

	AppendItemDefinitions(10,
		19,    -- Grenade Launcher
		206,   -- Grenade Launcher (Renamed/Strange)
		1007,  -- Festive Grenade Launcher
		1151,  -- The Iron Bomber
		15077, -- Autumn
		15079, -- Macabre Web
		15091, -- Rainbow
		15092, -- Sweet Dreams
		15116, -- Coffin Nail
		15117, -- Top Shelf
		15142, -- Warhawk
		15158  -- Butcher Bird 
	);
	aProjectileInfo[10] = DefinePseudoProjectileDefinition({
		vecOffset = Vector3(16, 8, -6);
		vecVelocity = Vector3(1200, 0, 200);
		vecMaxs = Vector3(2, 2, 2);
		flGravity = 1;
		flDrag = 0.45;
	});

	AppendItemDefinitions(11,
		308 -- The Loch-n-Load
	);
	aProjectileInfo[11] = DefineDerivedProjectileDefinition(aProjectileInfo[10], {
		vecVelocity = Vector3(1500, 0, 200);
		flDrag = 0.225;
	});

	AppendItemDefinitions(12,
		996 -- The Loose Cannon
	);
	aProjectileInfo[12] = DefineDerivedProjectileDefinition(aProjectileInfo[10], {
		vecVelocity = Vector3(1440, 0, 200),
		flGravity = 1.4;
		flDrag = 0.5;
	});

	AppendItemDefinitions(13,
		56,   -- The Huntsman
		1005, -- Festive Huntsman
		1092  --The Fortified Compound
	);
	aProjectileInfo[13] = DefinePseudoProjectileDefinition({
		vecOffset = Vector3(23.5, -8, -3);
		vecMaxs = Vector3(0, 0, 0);
		iAlignDistance = 2000;

		GetVelocity = function(self, flChargeBeginTime)
			return Vector3(1800 + CLAMP(flChargeBeginTime, 0, 1) * 800, 0, 0);
		end;

		GetGravity = function(self, flChargeBeginTime)
			return 0.5 - CLAMP(flChargeBeginTime, 0, 1) * 0.4;
		end;
	});

	AppendItemDefinitions(14,
		39,   -- The Flare Gun
		595,  -- The Manmelter
		740,  -- The Scorch Shot
		1081  -- Festive Flare Gun
	);
	aProjectileInfo[14] = DefinePseudoProjectileDefinition({
		vecVelocity = Vector3(2000, 0, 0);
		vecMaxs = Vector3(0, 0, 0);
		flGravity = 0.3;
		iAlignDistance = 2000;

		GetOffset = function(self, bDucking, bIsFlipped)
			return Vector3(23.5, 12 * (bIsFlipped and -1 or 1), bDucking and 8 or -3);
		end;
	});

	AppendItemDefinitions(15, 
		305, -- Crusader's Crossbow
		1079 -- Festive Crusader's Crossbow
	);
	aProjectileInfo[15] = DefinePseudoProjectileDefinition({
		vecOffset = Vector3(23.5, -8, -3);
		vecVelocity = Vector3(2400, 0, 0);
		vecMaxs = Vector3(3, 3, 3);
		flGravity = 0.2;
		iAlignDistance = 2000;
	});

	AppendItemDefinitions(16, 
		997 -- The Rescue Ranger
	);
	aProjectileInfo[16] = DefineDerivedProjectileDefinition(aProjectileInfo[15], {
		vecMaxs = Vector3(1, 1, 1);
	});

	AppendItemDefinitions(17,
		17,  -- Syringe Gun
		36,  -- The Blutsauger
		204, -- Syringe Gun (Renamed/Strange)
		412  -- The Overdose
	);
	aProjectileInfo[17] = DefinePseudoProjectileDefinition({
		vecOffset = Vector3(16, 6, -8);
		vecVelocity = Vector3(1000, 0, 0);
		vecMaxs = Vector3(1, 1, 1);
		flGravity = 0.3;
	});

	AppendItemDefinitions(18,
		58,   -- Jarate
		222,  -- Mad Milk
		1083, -- Festive Jarate
		1105, -- The Self-Aware Beauty Mark
		1121  -- Mutated Milk
	);
	aProjectileInfo[18] = DefinePseudoProjectileDefinition({
		vecOffset = Vector3(16, 8, -6);
		vecVelocity = Vector3(1000, 0, 200);
		vecMaxs = Vector3(8, 8, 8);
		flGravity = 1.125;
	});

	AppendItemDefinitions(19,
		812, -- The Flying Guillotine
		833  -- The Flying Guillotine (Genuine)
	);
	aProjectileInfo[19] = DefinePseudoProjectileDefinition({
		vecOffset = Vector3(23.5, 8, -3);
		vecVelocity = Vector3(3000, 0, 300);
		vecMaxs = Vector3(2, 2, 2);
		flGravity = 2.25;
		flDrag = 1.3;
	});

	AppendItemDefinitions(20,
		44  -- The Sandman
	);
	aProjectileInfo[20] = DefineSimulProjectileDefinition({
		vecVelocity = Vector3(2985.1118164063, 0, 298.51116943359);
		vecAngularVelocity = Vector3(0, 50, 0);
		vecMaxs = Vector3(4.25, 4.25, 4.25);
		sModelName = "models/weapons/w_models/w_baseball.mdl";

		GetFirePosition = function(self, pLocalPlayer, vecLocalView, vecViewAngles, bIsFlipped)
			--https://github.com/ValveSoftware/source-sdk-2013/blob/0565403b153dfcde602f6f58d8f4d13483696a13/src/game/shared/tf/tf_weapon_bat.cpp#L232
			return pLocalPlayer:GetAbsOrigin() + ((Vector3(0, 0, 50) + (vecViewAngles:Forward() * 32)) * pLocalPlayer:GetPropFloat("m_flModelScale"));
		end;
	});
	
	AppendItemDefinitions(21,
		648  -- The Wrap Assassin
	);
	aProjectileInfo[21] = DefineDerivedProjectileDefinition(aProjectileInfo[20], {
		vecMins = Vector3(-2.990180015564, -2.5989532470703, -2.483987569809);
		vecMaxs = Vector3(2.6593606472015, 2.5989530086517, 2.4839873313904);
		sModelName = "models/weapons/c_models/c_xms_festive_ornament.mdl";
	});

	AppendItemDefinitions(22,
		441 -- The Cow Mangler 5000
	);
	aProjectileInfo[22] = DefineDerivedProjectileDefinition(aProjectileInfo[1], {
		GetOffset = function(self, bDucking, bIsFlipped)
			return Vector3(23.5, 8 * (bIsFlipped and 1 or -1), bDucking and 8 or -3);
		end;
	});

	--https://github.com/ValveSoftware/source-sdk-2013/blob/0565403b153dfcde602f6f58d8f4d13483696a13/src/game/shared/tf/tf_weapon_raygun.cpp#L249
	AppendItemDefinitions(23,
		588  -- The Pomson 6000	
	);
	aProjectileInfo[23] = DefineDerivedProjectileDefinition(aProjectileInfo[6], {
		vecAbsoluteOffset = Vector3(0, 0, -13);
	});

	AppendItemDefinitions(24,
		1180  -- Gas Passer
	);
	aProjectileInfo[24] = DefinePseudoProjectileDefinition({
		vecOffset = Vector3(16, 8, -6);
		vecVelocity = Vector3(2000, 0, 200);
		vecMaxs = Vector3(8, 8, 8);
		flGravity = 1;
		flDrag = 1.32;
	});

	AppendItemDefinitions(25,
		528  -- The Short Circuit
	);
	aProjectileInfo[25] = DefineBasicProjectileDefinition({
		vecOffset = Vector3(40, 15, -10);
		vecVelocity = Vector3(700, 0, 0);
		vecMaxs = Vector3(1, 1, 1);
	});

	AppendItemDefinitions(26,
		42,   -- Sandvich
		159,  -- The Dalokohs Bar
		311,  -- The Buffalo Steak Sandvich
		433,  -- Fishcake
		863,  -- Robo-Sandvich
		1002, -- Festive Sandvich
		1190  -- Second Banana
	);
	aProjectileInfo[26] = DefinePseudoProjectileDefinition({
		vecOffset = Vector3(0, 0, -8);
		vecAngleOffset = Vector3(-10, 0, 0);
		vecVelocity = Vector3(500, 0, 0);
		vecMaxs = Vector3(17, 17, 10);
		flGravity = 1.02;
	});

	function GetProjectileInformation(iItemDefinitionIndex)
		return aProjectileInfo[aItemDefinitions[iItemDefinitionIndex or 0]];
	end

	LOG("GetProjectileInformation ready!");
end

local g_flTraceInterval = CLAMP(config.measure_segment_size, 0.5, 8) / 66;
local g_fFlagInterval = g_flTraceInterval * 1320;
local g_vEndOrigin = Vector3(0, 0, 0);

local function DoBasicProjectileTrace(vecSource, vecForward, vecMins, vecMaxs)
	local resultTrace = TRACE_HULL(vecSource, vecSource + (vecForward * 10000), vecMins, vecMaxs, 100679691);
	if resultTrace.startsolid then 
		return resultTrace; 
	end
		
	local iSegments = FLOOR((resultTrace.endpos - resultTrace.startpos):Length() / g_fFlagInterval);
	for i = 1, iSegments do
		TrajectoryLine:Insert(vecForward * (i * g_fFlagInterval) + vecSource);
	end

	TrajectoryLine:Insert(resultTrace.endpos);
	return resultTrace;
end

local function DoPseudoProjectileTrace(vecSource, vecVelocity, flGravity, flDrag, vecMins, vecMaxs)
	local flGravity = flGravity * 400;
	local vecPosition = vecSource;
	local resultTrace;

	for i = 0.01515, 5, g_flTraceInterval do
		local flScalar = (flDrag == 0) and i or ((1 - math.exp(-flDrag * i)) / flDrag);

		local scalar = (not fDrag) and i or ((1 - math.exp(-fDrag * i)) / fDrag);

		resultTrace = TRACE_HULL(vecPosition, Vector3(
			vecVelocity.x * flScalar + vecSource.x,
			vecVelocity.y * flScalar + vecSource.y,
			(vecVelocity.z - flGravity * i) * flScalar + vecSource.z
		), vecMins, vecMaxs, 100679691);

		vecPosition = resultTrace.endpos;
		TrajectoryLine:Insert(resultTrace.endpos);

		if(resultTrace.fraction ~= 1)then 
			break; 
		end
	end

	return resultTrace;
end

local function DoSimulProjectileTrace(pObject, vecMins, vecMaxs)
	local resultTrace;
	for i = 1, 330 do
		local vecStart = pObject:GetPosition();
		PhysicsEnvironment:Simulate(g_flTraceInterval);
		
		resultTrace = TRACE_HULL(vecStart, pObject:GetPosition(), vecMins, vecMaxs, 100679691);
		TrajectoryLine:Insert(resultTrace.endpos);
		if(resultTrace.fraction ~= 1)then 
			break; 
		end

		if(i == 330)then
			LOG("Hit the end of alotted simulation time!");
		end
	end

	PhysicsEnvironment:ResetSimulationClock();
	return resultTrace;
end

callbacks.Register("Draw", function()
	TrajectoryLine.m_aPositions, TrajectoryLine.m_iSize = {}, 0;


	if(engine.Con_IsVisible() or engine.IsGameUIVisible())then
		return;
	end

	local pLocalPlayer = entities.GetLocalPlayer();
	if(not pLocalPlayer or pLocalPlayer:InCond(7) or not pLocalPlayer:IsAlive())then
		return;
	end

	local pLocalWeapon = pLocalPlayer:GetPropEntity("m_hActiveWeapon");
	if(not pLocalWeapon)then
		return;
	end

	local stInfo = GetProjectileInformation(pLocalWeapon:GetPropInt("m_iItemDefinitionIndex"));
	if(not stInfo)then
		return;
	end

	local flChargeBeginTime = pLocalWeapon:GetPropFloat("PipebombLauncherLocalData", "m_flChargeBeginTime") or 0;
	if(flChargeBeginTime > 0)then
		flChargeBeginTime = globals.CurTime() - flChargeBeginTime;
	end

	local vecLocalView = pLocalPlayer:GetAbsOrigin() + pLocalPlayer:GetPropVector("localdata", "m_vecViewOffset[0]");
	local vecViewAngles = engine.GetViewAngles() + stInfo.m_vecAngleOffset;
	local vecSource = stInfo:GetFirePosition(pLocalPlayer, vecLocalView, vecViewAngles, pLocalWeapon:IsViewModelFlipped());
	if(not vecSource)then
		return;
	end

	if(stInfo.m_iAlignDistance > 0)then
		local vecGoalPoint = vecLocalView + (vecViewAngles:Forward() * stInfo.m_iAlignDistance);
		local res = engine.TraceLine(vecLocalView, vecGoalPoint, 100679691);
		vecViewAngles = (((res.fraction <= 0.1) and vecGoalPoint or res.endpos) - vecSource):Angles();
	end

	vecSource = vecSource + stInfo.m_vecAbsoluteOffset;

	TrajectoryLine.m_vFlagOffset = vecViewAngles:Right() * -config.flags.size;
	TrajectoryLine:Insert(vecSource);


	if(stInfo.m_iType == PROJECTILE_TYPE_BASIC)then
		resultTrace = DoBasicProjectileTrace(
			vecSource,
			vecViewAngles:Forward(),
			stInfo.m_vecMins,
			stInfo.m_vecMaxs
		);

	elseif(stInfo.m_iType == PROJECTILE_TYPE_PSEUDO)then
		resultTrace = DoPseudoProjectileTrace(
			vecSource,
			VEC_ROT(stInfo:GetVelocity(flChargeBeginTime), vecViewAngles),
			stInfo:GetGravity(flChargeBeginTime),
			stInfo.m_flDrag,
			stInfo.m_vecMins,
			stInfo.m_vecMaxs
		);

	elseif(stInfo.m_iType == PROJECTILE_TYPE_SIMUL)then
		local pObject = GetPhysicsObject(stInfo.m_sModelName);
		pObject:SetPosition(vecSource, vecViewAngles, true);
		pObject:SetVelocity(VEC_ROT(stInfo:GetVelocity(flChargeBeginTime), vecViewAngles), stInfo:GetAngularVelocity(flChargeBeginTime));

		resultTrace = DoSimulProjectileTrace(
			pObject,
			stInfo.m_vecMins,
			stInfo.m_vecMaxs
		);

	else
		LOG(string.format("Unknown projectile type \"%s\"!", stInfo.m_iType));
		return;
	end

	if TrajectoryLine.m_iSize == 0 then return end
	if(resultTrace)then
		ImpactPolygon(resultTrace.plane, resultTrace.endpos);
		g_vEndOrigin = resultTrace.endpos;
	end

	if TrajectoryLine.m_iSize == 1 then 
		ImpactCamera();
		return; 
	end

	TrajectoryLine();
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
end)

LOG("Script fully loaded!");
