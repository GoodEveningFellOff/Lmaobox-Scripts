local screen_size = (function()
	local w, h = draw.GetScreenSize();

	return {x=w;y=h;}
end)();


local function clamp(a,b,c) return (a > c) and c or (a < b) and b or a end

local function rgb_to_hsv(r, g, b)
	local r, g, b = r/255, g/255, b/255;

	local c_max = math.max(r, g, b);
	local delta = c_max - math.min(r, g, b);

	return (delta == 0) and 0 or (c_max == r) and 60 * ((g - b) / delta % 6) or (c_max == g) and 60 * ((b - r) / delta + 2) or 60 * ((r - g) / delta + 4), (c_max == 0) and 0 or delta / c_max, c_max
end

local function hsv_to_rgb(h, s, v)
	local c = v*s;
	local x = c*(1-math.abs((h/60)%2-1));
	local m = v-c;

	c = math.floor((c+m)*255);
	x = math.floor((x+m)*255);
	m = math.floor(m*255);

	if h < 60 then 
		return c, x, m
			
	elseif h < 120 then 
		return x, c, m
			
	elseif h < 180 then 
		return m, c, x
		
	elseif h < 240 then 
		return m, x, c
			
	elseif h < 300 then 
		return x, m, c
		
	else 
		return c, m, x

	end
end

local function hsv_to_hex(h, s, v, a)
	local r, g, b = hsv_to_rgb(h, s, v);
	return ("%02x%02x%02x%02x"):format(r, g, b, math.floor(a*255))
end

local function hex_to_hsv(str)
	local h, s, v = rgb_to_hsv(tonumber("0x" .. str:sub(1,2)), tonumber("0x" .. str:sub(3,4)), tonumber("0x" .. str:sub(5,6)));
	return h, s, v, tonumber("0x" .. str:sub(7,8))/255
end

local groups = {
	"backtrack ticks color",
	"blue team color",
	"blue team (invisible)",
	"red team color",
	"red team (invisible)",
	"aimbot target color",
	"gui color",
	"night mode color",
	"anti aim indicator color",
	"prop color"
}

local function set_gui_value(gui_item, value)
	if gui.GetValue(gui_item) == value then
		return
	end
	
	gui.SetValue(gui_item, value)
end

local on_blue_team = false;

local Props = {
	stored = "ffffffff";

	r =	1;
	g = 1;
	b = 1;
	a = 1;
	
	set = function(self, hex)
		if hex == self.stored then
			return
		end
		
		self.stored = hex;
		self.r = tonumber("0x" .. hex:sub(1, 2)) / 255;
		self.g = tonumber("0x" .. hex:sub(3, 4)) / 255;
		self.b = tonumber("0x" .. hex:sub(5, 6)) / 255;
		self.a = tonumber("0x" .. hex:sub(7, 8)) / 255;
	end
};

local Config = {
	path = engine.GetGameDir() .. "\\cfg\\coolcolors.cfg";

	data = {
		"808080ff",
		"0080ffff",
		"0015ffff",
		"ff8000ff",		
		"ff0400ff",
		"00ff00ff",
		"ffffffff",
		"808080ff",
		"ffd500ff",
		"ffffffff"
	};

	team_based = false;

	set_values = function(self)
		local data = self.data;

		for _, key in pairs({1, 6, 7, 8, 9}) do
			set_gui_value(groups[key], tonumber("0x" .. data[key]))
		end

		Props:set(data[10])

		if self.team_based and not on_blue_team then
			set_gui_value(groups[4], tonumber("0x" .. data[2]))
			set_gui_value(groups[5], tonumber("0x" .. data[3]))
			set_gui_value(groups[2], tonumber("0x" .. data[4]))
			set_gui_value(groups[3], tonumber("0x" .. data[5]))

			return
		end

		set_gui_value(groups[2], tonumber("0x" .. data[2]))
		set_gui_value(groups[3], tonumber("0x" .. data[3]))
		set_gui_value(groups[4], tonumber("0x" .. data[4]))
		set_gui_value(groups[5], tonumber("0x" .. data[5]))
	end;

	write = function(self)
		local file = io.open(self.path, 'w');

		local fstr = self.team_based and "1" or "0";

		for i = 1, 10 do
			fstr = fstr .. self.data[i];
		end

		file:write(fstr)

		file:close()
	end;


	read = function(self)
		local file = io.open(self.path, 'r');

		if not file then
			return
		end

		local fstr = file:read('a');

		self.team_based = fstr:sub(1,1) == '1';

		for i = 1, 10 do
			local this_str = fstr:sub((i-1)*8 + 2, i*8 + 1);

			if tonumber("0x" .. this_str) then
				self.data[i] = this_str;
			end
		end

		file:close()
	end;

	save = function(self)
		self:write()
		self:set_values()
	end;
};

local init_file = io.open(Config.path, 'r');
if not init_file then
	(io.open(Config.path, 'w')):close()

else
	init_file:close()
	Config:read()

end

local textures = {
	main_box = (function()
		local tbl = {};

		local sfunc = {
			[0]=function(a,b,c,d,e)d[e+1],d[e+2],d[e+3],d[e+4]=a,b,c,255;end;
			[1]=function(a,b,c,d,e)d[e+1],d[e+2],d[e+3],d[e+4]=b,a,c,255;end;
			[2]=function(a,b,c,d,e)d[e+1],d[e+2],d[e+3],d[e+4]=c,a,b,255;end;
			[3]=function(a,b,c,d,e)d[e+1],d[e+2],d[e+3],d[e+4]=c,b,a,255;end;
			[4]=function(a,b,c,d,e)d[e+1],d[e+2],d[e+3],d[e+4]=b,c,a,255;end;
			[5]=function(a,b,c,d,e)d[e+1],d[e+2],d[e+3],d[e+4]=a,c,b,255;end;
		};
		
		local size = 2^6;
		local increment_per_pixel = 1/(size - 1);
		local floor = math.floor;

		local function create_box(hue)
			local chars = {};

			local hue_const = 1-math.abs((hue / 60)%2-1);

			local set = sfunc[floor(hue/60)];

			for i_h = 0, 1, increment_per_pixel do
				local v = (1 - i_h)*255;

				for i_w = 0, 1, increment_per_pixel do
					local c = v*i_w;
					local m = floor(v-c);

					set(floor(c)+m, floor(c*hue_const)+m, m, chars, #chars)
				end
			end

			return draw.CreateTextureRGBA(string.char(table.unpack(chars)), size, size)
		end
		

		for i = 1, 360, 4 do
			tbl[(i - 1) / 4] = create_box(i - 1);
		end

		return tbl
	end)();

	hue_rect = (function()
		local chars = {};

		local correction =  360 / 255;

		for i = 0, 255 do
			local r, g, b = hsv_to_rgb(math.floor(i * correction), 1, 1);
			
			local p = #chars

			chars[p + 1], chars[p + 5] = r, r;
			chars[p + 2], chars[p + 6] = g, g;
			chars[p + 3], chars[p + 7] = b, b;
			chars[p + 4], chars[p + 8] = 255, 255;
		end
		
		return draw.CreateTextureRGBA(string.char(table.unpack(chars)), 2, 256)
	end)();

	alpha_rect = (function()
		local chars = {};

		for i = 255, 0, -1 do
			local p = #chars

			chars[p + 1], chars[p + 1025] = i, i;
			chars[p + 2], chars[p + 1026] = i, i;
			chars[p + 3], chars[p + 1027] = i, i;
			chars[p + 4], chars[p + 1028] = 255, 255;
		end
		
		return draw.CreateTextureRGBA(string.char(table.unpack(chars)), 256, 2)
	end)();

	trans_box = draw.CreateTextureRGBA(string.char(
		0xff, 0xff, 0xff, 0xff,
		0x88, 0x88, 0x88, 0xff,
		0x88, 0x88, 0x88, 0xff,
		0xff, 0xff, 0xff, 0xff
	), 2, 2);

	fill_circle = (function()
		local chars = {};

		local size = 2^6;
		local increment_per_pixel = 2/(size - 1);

		for h = -1, 1, increment_per_pixel do
			local hh = h*h;

			for w = -1, 1, increment_per_pixel do
				local p, r = #chars, math.sqrt(hh + w*w);

				chars[p + 1], chars[p + 2], chars[p + 3] = 255, 255, 255;
				chars[p + 4] = (r <= 1) and 255 or math.floor(clamp(1 - ((r-1)/0.005), 0, 1)*255);
			end
		end

		return draw.CreateTextureRGBA(string.char(table.unpack(chars)), size, size)
	end)();

	unload = function(self)
		for _, id in pairs(self.main_box) do
			draw.DeleteTexture(id)
		end

		draw.DeleteTexture(self.hue_rect)
		draw.DeleteTexture(self.alpha_rect)
		draw.DeleteTexture(self.trans_box)
		draw.DeleteTexture(self.fill_circle)
	end;
};

local Mouse = {
	x = 0;
	dx = 0;
	y = 0;
	dy = 0;

	m1 = false;
	m1t = 0;
	m1p = false;

	interact_id = 0;

	update = function(self)
		local pos = input.GetMousePos();

		self.x = pos[1];
		self.y = pos[2];

		if self.x < 0 or self.x > screen_size.x or self.y < 0 or self.y > screen_size.y then
			self.interact_id = 0;
		end

		self.m1 = input.IsButtonDown(MOUSE_LEFT);
		self.m1t = self.m1 and (self.m1t + 1) or 0;
		self.m1p = self.m1t == 1;
	end;

};

local ColorPicker = {
	h = 0;
	s = 1;
	v = 0.75;
	a = 1;

	x = 10;
	y = 10;

	visible_group = 1;

	font = draw.CreateFont("Verdana", 12, 11);

	input = function(self)
		if (Mouse.interact_id == 0 and not Mouse.m1p) or Mouse.interact_id > 7 then return end
		local mx, my, x, y = Mouse.x, Mouse.y, self.x, self.y;

		if Mouse.interact_id == 0 then
			if mx>=x and mx<=x+200 and my>=y and my<=y+200 then
				Mouse.interact_id = 1;
	
			elseif mx>=x+210 and mx<=x+220 and my>=y and my<=y+200 then
				Mouse.interact_id = 2;

			elseif mx>=x and mx<=x+200 and my>=y+210 and my<=y+220 then
				Mouse.interact_id = 3;

			elseif mx>=x+180 and mx<=x+190 and my>=y+229 and my<=y+239 then
				Mouse.interact_id = 4;
				self.visible_group = (self.visible_group <= 1) and #groups or self.visible_group - 1;
				self.h, self.s, self.v, self.a = hex_to_hsv(Config.data[self.visible_group]);

			elseif mx>=x+200 and mx<=x+210 and my>=y+229 and my<=y+239 then
				Mouse.interact_id = 5;
				self.visible_group = (self.visible_group >= #groups) and 1 or self.visible_group + 1;
				self.h, self.s, self.v, self.a = hex_to_hsv(Config.data[self.visible_group]);

			elseif mx>=x+200 and mx<=x+210 and my>=y+249 and my<=y+259 then
				Mouse.interact_id = 6;
				Config.team_based = not Config.team_based;

			elseif mx>=x-3 and mx<=x+223 and my>=y-3 and my<=y+264 then
				Mouse.interact_id = 7;
				Mouse.dx = mx - x;
				Mouse.dy = my - y;

			end

			return
		end

		if not Mouse.m1 then
			Mouse.interact_id = 0;
			return
		end

		if Mouse.interact_id == 1 then
			self.s = clamp((mx - x)/200, 0, 1);
			self.v = 1 - clamp((my - y)/200, 0, 1);

		elseif Mouse.interact_id == 2 then
			self.h = clamp(math.floor(359*(my - y)/200), 0, 359);

		elseif Mouse.interact_id == 3 then
			self.a = 1 - clamp((mx - x)/200, 0, 1);

		elseif Mouse.interact_id == 7 then
			self.x = clamp(mx - Mouse.dx, 3, screen_size.x - 223)
			self.y = clamp(my - Mouse.dy, 3, screen_size.y - 264)

		elseif Mouse.interact_id ~= 6 then 
			return 
		end

		Config.data[self.visible_group] = hsv_to_hex(self.h, self.s, self.v, self.a);
		Config:save()
	end;


	render = function(self)
		local x, y, h, s, v, a = self.x, self.y, self.h, self.s, self.v, self.a;
		local r, g, b = hsv_to_rgb(h, s, v);

		draw.SetFont(self.font)

		-- Background
		draw.Color(33, 33, 33, 255)
		draw.FilledRect(x - 2, y - 2, x + 222, y + 263)

		-- Textures
		draw.Color(255, 255, 255, 255)
		draw.TexturedRect(textures.main_box[math.floor(h/4)] or 1, x, y, x + 200, y + 200)
		draw.TexturedRect(textures.hue_rect, x + 210, y, x + 220, y + 200)
		draw.TexturedRect(textures.alpha_rect, x, y + 210, x + 200, y + 220)
		draw.TexturedRect(textures.trans_box, x + 210, y + 210, x + 220, y + 220)

		-- Color in bottom right
		draw.Color(r, g, b, math.floor(a*255))
		draw.FilledRect(x + 210, y + 210, x + 220, y + 220)

		-- Outlining Rects
		draw.Color(100, 100, 100, 255)
		draw.OutlinedRect(x - 3, y - 3, x + 223, y + 264)
		draw.OutlinedRect(x - 1, y - 1, x + 221, y + 221)
		draw.OutlinedRect(x + 200, y + 229, x + 210, y + 239)
		draw.OutlinedRect(x + 180, y + 229, x + 190, y + 239)
		draw.OutlinedRect(x + 200, y + 249, x + 210, y + 259)

		-- Inner Outlining Lines
		draw.Line(x, y + 200, x + 201, y + 200)
		draw.Line(x + 200, y, x + 200, y + 200)
		draw.Line(x, y + 209, x + 200, y + 209)
		draw.Line(x + 200, y + 209, x + 200, y + 220)
		draw.Line(x + 209, y + 200, x + 220, y + 200)
		draw.Line(x + 209, y, x + 209, y + 200)
		draw.Line(x + 209, y + 209, x + 220, y + 209)
		draw.Line(x + 209, y + 209, x + 209, y + 220)
		draw.Line(x - 2, y + 244, x + 222, y + 244)

		-- Selection Indicator Outline
		local x_1 = x + math.floor(s * 200);
		local y_1 = y + 200 - math.floor(v * 200);
		local x_2 = x + 200 - math.floor(a * 200);
		local y_2 = y + math.floor(200 * h / 360);

		draw.Color(33, 33, 33, 50)
		draw.TexturedRect(textures.fill_circle, x_1 - 6, y_1 - 6, x_1 + 6, y_1 + 6)
		draw.OutlinedRect(x_2 - 4, y + 206, x_2 + 4, y + 224)
		draw.OutlinedRect(x + 206, y_2 - 4, x + 224, y_2 + 4)

		draw.Color(100, 100, 100, 255)
		draw.TexturedRect(textures.fill_circle, x_1 - 5, y_1 - 5, x_1 + 5, y_1 + 5)
		draw.OutlinedRect(x_2 - 3, y + 207, x_2 + 3, y + 223)
		draw.OutlinedRect(x + 207, y_2 - 3, x + 223, y_2 + 3)
	
		-- Selection Indicator Magnification
		draw.Color(r, g, b, 255)
		draw.TexturedRect(textures.fill_circle, x_1 - 4, y_1 - 4, x_1 + 4, y_1 + 4)

		local clr = math.floor(a * 255);
		draw.Color(clr, clr, clr, 255)
		draw.FilledRect(x_2 - 2, y + 208, x_2 + 2, y + 222)

		local r, g, b = hsv_to_rgb(h, 1, 1);
		draw.Color(r, g, b, 255)
		draw.FilledRect(x + 208, y_2 - 2, x + 222, y_2 + 2)

		-- Checkbox
		if Config.team_based then
			draw.Color(0, 255, 0, 255)
		else
			draw.Color(255, 0, 0, 255)
		end

		draw.FilledRect(x + 201, y + 250, x + 209, y + 258)

		-- Text
		draw.Color(255, 255, 255, 255)
		draw.Text(x + 3, y + 229, groups[self.visible_group])
		draw.Text(x + 3, y + 249, "use friend/enemy instead of blue/red")
	end;


	main = function(self)
		self:input()
		self:render()
	end;
};

ColorPicker.h, ColorPicker.s, ColorPicker.v, ColorPicker.a = hex_to_hsv(Config.data[ColorPicker.visible_group]);

local update_time = 0;
local visible = false;

callbacks.Register("Draw", function()
	if visible then
		Mouse:update()
		ColorPicker:main()
	end

	if math.abs(globals.CurTime() - update_time) < 0.5 then
		return
	end

	update_time = globals.CurTime();

	local plocal = entities.GetLocalPlayer();

	if not plocal then 
		on_blue_team = true;
		Config:set_values()
		return 
	end

	on_blue_team = (plocal:GetTeamNumber() or 3) ~= 2;
	Config:set_values()
	
end)

callbacks.Register("SendStringCmd", function(cmd)
	local cmd_str_lwr = string.lower(cmd:Get());
	if cmd_str_lwr:find("colorpicker") then
		visible = not visible;
		cmd:Set('')
	end
end)

callbacks.Register("DrawStaticProps", function(ctx)
	ctx:StudioSetColorModulation(Props.r, Props.g, Props.b)
	ctx:StudioSetAlphaModulation(Props.a)
end)

callbacks.Register("Unload", function()
	textures:unload()
end)
