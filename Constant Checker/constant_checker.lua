local function CheckConstants(bIncludeUnknownTables, bLogInfo, bDontRedefine)
	local LOG = bLogInfo and printc or function(...) end;

	local aKnownConstantTables = {};
	local aUnknownConstantTables = {};

	-- Create a table with all known global constant table names so we can check to make sure all known tables are defined
	for _, k in pairs({
		"E_UserCmd", "E_ButtonCode", "E_LifeState", "E_UserMessage", "E_WeaponBaseID", 
		"E_TFCOND", "E_SignonState", "E_KillEffect", "E_Character", "E_TraceLine", 
		"E_MaterialFlag", "E_LoadoutSlot", "E_RoundState", "E_PlayerFlag", "E_FontFlag", 
		"E_MatchAbandonStatus", "E_FileAttribute", "E_TeamNumber", "E_RuneType", "E_ProjectileType",
		"E_MoveType", "E_Hitbox", "E_BoneMask", "E_GCResults", "E_ClearFlags"
	}) do
		aKnownConstantTables[k] = false;
	end

	LOG(55, 255, 255, 255, [[
/-----------------------------------------------------------\
|                 Starting constant check!                  |
|-----------------------------------------------------------|
|                                                           |]]);

	-- Search the _G table for global constant tables using the fact that they are named with E_ as a prefix and have a type of table
	for G_key, G_tbl in pairs(_G) do
		if tostring(G_key):find("E") == 1 and type(G_tbl) == "table" then
			local bContinue = true;

			
			for k, v in pairs(G_tbl) do
				if type(v) ~= "number" then
					bContinue = false;
				end
			end
			
			if (aKnownConstantTables[G_key] ~= nil or bIncludeUnknownTables) and bContinue then
				if aKnownConstantTables[G_key] ~= nil then
					aKnownConstantTables[G_key] = true;

				else
					aUnknownConstantTables[#aUnknownConstantTables + 1] = G_key;
				end


				local iSize = 0;
				local iMissing = 0;
		
				-- Go through this global constant table and collect the number of elements that are missing globally and define them using the value from the table
				for k, v in pairs(G_tbl) do
					iSize = iSize + 1;

					if not _G[k] then
						iMissing = iMissing + 1;	

						if not bDontRedefine then
							_G[k] = v;
						end
					end
				end
				
				local sText = ("%s (%i / %i missing)"):format(G_key, iMissing, iSize);

				-- Center the text so it looks nice when printed
				local iFiller = 57 - sText:len();
				for i = 1, math.ceil(iFiller / 2) do sText = ' ' .. sText; end
				for i = 1, math.floor(iFiller / 2) do sText = sText .. ' '; end

				LOG((iMissing ~= 0) and 255 or 55, (iMissing ~= 0) and 55 or 255, 55, 255, "|>" .. sText .. "<|");
			end
		end
	end

	LOG(55, 255, 255, 255, [[
|                                                           |
|-----------------------------------------------------------|
|               Missing known constant tables               |
|-----------------------------------------------------------|
|                                                           |]]);

	-- Log known global constant tables that we did not find
	-- Sometimes these get resolved simply by reloading the script
	for k, v in pairs(aKnownConstantTables) do
		if not v then
			local sText = tostring(k);

			-- Center the text so it looks nice when printed
			local iFiller = 57 - sText:len();
			for i = 1, math.ceil(iFiller / 2) do sText = " " .. sText; end
			for i = 1, math.floor(iFiller / 2) do sText = sText .. " "; end

			LOG(255, 55, 55, 255, "|>" .. sText .. "<|");
		end
	end

	if bIncludeUnknownTables then

		LOG(55, 255, 255, 255, [[
|                                                           |
|-----------------------------------------------------------|
|             Refreshed unknown constant tables             |
|-----------------------------------------------------------|
|                                                           |]]);
		-- Log unknown global constant tables that we checked
		for _, k in pairs(aUnknownConstantTables) do
			local sText = tostring(k);

			-- Center the text so it looks nice when printed
			local iFiller = 57 - sText:len();
			for i = 1, math.ceil(iFiller / 2) do sText = " " .. sText; end
			for i = 1, math.floor(iFiller / 2) do sText = sText .. " "; end

			LOG(255, 100, 55, 255, "|>" .. sText .. "<|");
		end
	end

	LOG(55, 255, 255, 255, [[
|                                                           |
|-----------------------------------------------------------|
|                   Constants refreshed!                    |
\-----------------------------------------------------------/]]);
end

CheckConstants(true, true)
