
local function FOR_ALL_GLOBALS(pfn)
	for k, v in pairs(_G) do
		pfn(k, v)
	end
end


local function KILL_EM_ALL()
	FOR_ALL_GLOBALS(function(k, v)
		if tostring(k):find("E") == 1 and type(v) == "table" then
			for _k, _v in pairs(v) do
				if type(_v) ~= "number" then
					return;
				end
			end

			for _k, _ in pairs(v) do
				_G[_k] = nil;
			end
			
			_G[k] = nil;
		end
	end)
end

local function PRINT_EM_ALL()
	FOR_ALL_GLOBALS(function(k, v)
		print(k)
	end)
end

local function DUMP_GLOBAL_CONSTANT_TABLES()
	FOR_ALL_GLOBALS(function(k, v)
		if type(v) ~= "table" then
			return;
		end

		local max_len = 0;
		for _k, _v in pairs(v) do
			max_len = math.max(tostring(_k):len() + 1, max_len);

			if type(_v) ~= "number" then
				return;
			end
		end

		print(("_DEFINE_GLOBAL_CONSTANT_TABLE(\"%s\", {"):format(k));
		for _k, _v in pairs(v) do
			local str = tostring(_k);

			for i = 1, max_len - str:len() do
				str = str .. ' ';
			end

			print(("\x09%s= %s;"):format(str, _v));
		end
		print("});\n")
	end)
end

KILL_EM_ALL()
