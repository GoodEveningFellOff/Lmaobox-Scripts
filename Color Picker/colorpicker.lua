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
	"backtrack indicator color",
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
        return draw.CreateTextureRGBA("\xff\xff\xff\xff\xfe\xfe\xfe\xff\xfd\xfd\xfd\xff\xfc\xfc\xfc\xff\xfb\xfb\xfb\xff\xfa\xfa\xfa\xff\xf9\xf9\xf9\xff\xf8\xf8\xf8\xff\xf7\xf7\xf7\xff\xf6\xf6\xf6\xff\xf5\xf5\xf5\xff\xf4\xf4\xf4\xff\xf3\xf3\xf3\xff\xf2\xf2\xf2\xff\xf1\xf1\xf1\xff\xf0\xf0\xf0\xff\xef\xef\xef\xff\xee\xee\xee\xff\xed\xed\xed\xff\xec\xec\xec\xff\xeb\xeb\xeb\xff\xea\xea\xea\xff\xe9\xe9\xe9\xff\xe8\xe8\xe8\xff\xe7\xe7\xe7\xff\xe6\xe6\xe6\xff\xe5\xe5\xe5\xff\xe4\xe4\xe4\xff\xe3\xe3\xe3\xff\xe2\xe2\xe2\xff\xe1\xe1\xe1\xff\xe0\xe0\xe0\xff\xdf\xdf\xdf\xff\xde\xde\xde\xff\xdd\xdd\xdd\xff\xdc\xdc\xdc\xff\xdb\xdb\xdb\xff\xda\xda\xda\xff\xd9\xd9\xd9\xff\xd8\xd8\xd8\xff\xd7\xd7\xd7\xff\xd6\xd6\xd6\xff\xd5\xd5\xd5\xff\xd4\xd4\xd4\xff\xd3\xd3\xd3\xff\xd2\xd2\xd2\xff\xd1\xd1\xd1\xff\xd0\xd0\xd0\xff\xcf\xcf\xcf\xff\xce\xce\xce\xff\xcd\xcd\xcd\xff\xcc\xcc\xcc\xff\xcb\xcb\xcb\xff\xca\xca\xca\xff\xc9\xc9\xc9\xff\xc8\xc8\xc8\xff\xc7\xc7\xc7\xff\xc6\xc6\xc6\xff\xc5\xc5\xc5\xff\xc4\xc4\xc4\xff\xc3\xc3\xc3\xff\xc2\xc2\xc2\xff\xc1\xc1\xc1\xff\xc0\xc0\xc0\xff\xbf\xbf\xbf\xff\xbe\xbe\xbe\xff\xbd\xbd\xbd\xff\xbc\xbc\xbc\xff\xbb\xbb\xbb\xff\xba\xba\xba\xff\xb9\xb9\xb9\xff\xb8\xb8\xb8\xff\xb7\xb7\xb7\xff\xb6\xb6\xb6\xff\xb5\xb5\xb5\xff\xb4\xb4\xb4\xff\xb3\xb3\xb3\xff\xb2\xb2\xb2\xff\xb1\xb1\xb1\xff\xb0\xb0\xb0\xff\xaf\xaf\xaf\xff\xae\xae\xae\xff\xad\xad\xad\xff\xac\xac\xac\xff\xab\xab\xab\xff\xaa\xaa\xaa\xff\xa9\xa9\xa9\xff\xa8\xa8\xa8\xff\xa7\xa7\xa7\xff\xa6\xa6\xa6\xff\xa5\xa5\xa5\xff\xa4\xa4\xa4\xff\xa3\xa3\xa3\xff\xa2\xa2\xa2\xff\xa1\xa1\xa1\xff\xa0\xa0\xa0\xff\x9f\x9f\x9f\xff\x9e\x9e\x9e\xff\x9d\x9d\x9d\xff\x9c\x9c\x9c\xff\x9b\x9b\x9b\xff\x9a\x9a\x9a\xff\x99\x99\x99\xff\x98\x98\x98\xff\x97\x97\x97\xff\x96\x96\x96\xff\x95\x95\x95\xff\x94\x94\x94\xff\x93\x93\x93\xff\x92\x92\x92\xff\x91\x91\x91\xff\x90\x90\x90\xff\x8f\x8f\x8f\xff\x8e\x8e\x8e\xff\x8d\x8d\x8d\xff\x8c\x8c\x8c\xff\x8b\x8b\x8b\xff\x8a\x8a\x8a\xff\x89\x89\x89\xff\x88\x88\x88\xff\x87\x87\x87\xff\x86\x86\x86\xff\x85\x85\x85\xff\x84\x84\x84\xff\x83\x83\x83\xff\x82\x82\x82\xff\x81\x81\x81\xff\x80\x80\x80\xff\x7f\x7f\x7f\xff~~~\xff}}}\xff|||\xff{{{\xffzzz\xffyyy\xffxxx\xffwww\xffvvv\xffuuu\xffttt\xffsss\xffrrr\xffqqq\xffppp\xffooo\xffnnn\xffmmm\xfflll\xffkkk\xffjjj\xffiii\xffhhh\xffggg\xfffff\xffeee\xffddd\xffccc\xffbbb\xffaaa\xff```\xff___\xff^^^\xff]]]\xff\\\\\\\xff[[[\xffZZZ\xffYYY\xffXXX\xffWWW\xffVVV\xffUUU\xffTTT\xffSSS\xffRRR\xffQQQ\xffPPP\xffOOO\xffNNN\xffMMM\xffLLL\xffKKK\xffJJJ\xffIII\xffHHH\xffGGG\xffFFF\xffEEE\xffDDD\xffCCC\xffBBB\xffAAA\xff@@@\xff???\xff>>>\xff===\xff<<<\xff;;;\xff:::\xff999\xff888\xff777\xff666\xff555\xff444\xff333\xff222\xff111\xff000\xff///\xff...\xff---\xff,,,\xff+++\xff***\xff)))\xff(((\xff'''\xff&&&\xff%%%\xff$$$\xff###\xff\"\"\"\xff!!!\xff   \xff\x1f\x1f\x1f\xff\x1e\x1e\x1e\xff\x1d\x1d\x1d\xff\x1c\x1c\x1c\xff\x1b\x1b\x1b\xff\x1a\x1a\x1a\xff\x19\x19\x19\xff\x18\x18\x18\xff\x17\x17\x17\xff\x16\x16\x16\xff\x15\x15\x15\xff\x14\x14\x14\xff\x13\x13\x13\xff\x12\x12\x12\xff\x11\x11\x11\xff\x10\x10\x10\xff\x0f\x0f\x0f\xff\x0e\x0e\x0e\xff\x0d\x0d\x0d\xff\x0c\x0c\x0c\xff\x0b\x0b\x0b\xff\x0a\x0a\x0a\xff\x09\x09\x09\xff\x08\x08\x08\xff\x07\x07\x07\xff\x06\x06\x06\xff\x05\x05\x05\xff\x04\x04\x04\xff\x03\x03\x03\xff\x02\x02\x02\xff\x01\x01\x01\xff\x00\x00\x00\xff\xff\xff\xff\xff\xfe\xfe\xfe\xff\xfd\xfd\xfd\xff\xfc\xfc\xfc\xff\xfb\xfb\xfb\xff\xfa\xfa\xfa\xff\xf9\xf9\xf9\xff\xf8\xf8\xf8\xff\xf7\xf7\xf7\xff\xf6\xf6\xf6\xff\xf5\xf5\xf5\xff\xf4\xf4\xf4\xff\xf3\xf3\xf3\xff\xf2\xf2\xf2\xff\xf1\xf1\xf1\xff\xf0\xf0\xf0\xff\xef\xef\xef\xff\xee\xee\xee\xff\xed\xed\xed\xff\xec\xec\xec\xff\xeb\xeb\xeb\xff\xea\xea\xea\xff\xe9\xe9\xe9\xff\xe8\xe8\xe8\xff\xe7\xe7\xe7\xff\xe6\xe6\xe6\xff\xe5\xe5\xe5\xff\xe4\xe4\xe4\xff\xe3\xe3\xe3\xff\xe2\xe2\xe2\xff\xe1\xe1\xe1\xff\xe0\xe0\xe0\xff\xdf\xdf\xdf\xff\xde\xde\xde\xff\xdd\xdd\xdd\xff\xdc\xdc\xdc\xff\xdb\xdb\xdb\xff\xda\xda\xda\xff\xd9\xd9\xd9\xff\xd8\xd8\xd8\xff\xd7\xd7\xd7\xff\xd6\xd6\xd6\xff\xd5\xd5\xd5\xff\xd4\xd4\xd4\xff\xd3\xd3\xd3\xff\xd2\xd2\xd2\xff\xd1\xd1\xd1\xff\xd0\xd0\xd0\xff\xcf\xcf\xcf\xff\xce\xce\xce\xff\xcd\xcd\xcd\xff\xcc\xcc\xcc\xff\xcb\xcb\xcb\xff\xca\xca\xca\xff\xc9\xc9\xc9\xff\xc8\xc8\xc8\xff\xc7\xc7\xc7\xff\xc6\xc6\xc6\xff\xc5\xc5\xc5\xff\xc4\xc4\xc4\xff\xc3\xc3\xc3\xff\xc2\xc2\xc2\xff\xc1\xc1\xc1\xff\xc0\xc0\xc0\xff\xbf\xbf\xbf\xff\xbe\xbe\xbe\xff\xbd\xbd\xbd\xff\xbc\xbc\xbc\xff\xbb\xbb\xbb\xff\xba\xba\xba\xff\xb9\xb9\xb9\xff\xb8\xb8\xb8\xff\xb7\xb7\xb7\xff\xb6\xb6\xb6\xff\xb5\xb5\xb5\xff\xb4\xb4\xb4\xff\xb3\xb3\xb3\xff\xb2\xb2\xb2\xff\xb1\xb1\xb1\xff\xb0\xb0\xb0\xff\xaf\xaf\xaf\xff\xae\xae\xae\xff\xad\xad\xad\xff\xac\xac\xac\xff\xab\xab\xab\xff\xaa\xaa\xaa\xff\xa9\xa9\xa9\xff\xa8\xa8\xa8\xff\xa7\xa7\xa7\xff\xa6\xa6\xa6\xff\xa5\xa5\xa5\xff\xa4\xa4\xa4\xff\xa3\xa3\xa3\xff\xa2\xa2\xa2\xff\xa1\xa1\xa1\xff\xa0\xa0\xa0\xff\x9f\x9f\x9f\xff\x9e\x9e\x9e\xff\x9d\x9d\x9d\xff\x9c\x9c\x9c\xff\x9b\x9b\x9b\xff\x9a\x9a\x9a\xff\x99\x99\x99\xff\x98\x98\x98\xff\x97\x97\x97\xff\x96\x96\x96\xff\x95\x95\x95\xff\x94\x94\x94\xff\x93\x93\x93\xff\x92\x92\x92\xff\x91\x91\x91\xff\x90\x90\x90\xff\x8f\x8f\x8f\xff\x8e\x8e\x8e\xff\x8d\x8d\x8d\xff\x8c\x8c\x8c\xff\x8b\x8b\x8b\xff\x8a\x8a\x8a\xff\x89\x89\x89\xff\x88\x88\x88\xff\x87\x87\x87\xff\x86\x86\x86\xff\x85\x85\x85\xff\x84\x84\x84\xff\x83\x83\x83\xff\x82\x82\x82\xff\x81\x81\x81\xff\x80\x80\x80\xff\x7f\x7f\x7f\xff~~~\xff}}}\xff|||\xff{{{\xffzzz\xffyyy\xffxxx\xffwww\xffvvv\xffuuu\xffttt\xffsss\xffrrr\xffqqq\xffppp\xffooo\xffnnn\xffmmm\xfflll\xffkkk\xffjjj\xffiii\xffhhh\xffggg\xfffff\xffeee\xffddd\xffccc\xffbbb\xffaaa\xff```\xff___\xff^^^\xff]]]\xff\\\\\\\xff[[[\xffZZZ\xffYYY\xffXXX\xffWWW\xffVVV\xffUUU\xffTTT\xffSSS\xffRRR\xffQQQ\xffPPP\xffOOO\xffNNN\xffMMM\xffLLL\xffKKK\xffJJJ\xffIII\xffHHH\xffGGG\xffFFF\xffEEE\xffDDD\xffCCC\xffBBB\xffAAA\xff@@@\xff???\xff>>>\xff===\xff<<<\xff;;;\xff:::\xff999\xff888\xff777\xff666\xff555\xff444\xff333\xff222\xff111\xff000\xff///\xff...\xff---\xff,,,\xff+++\xff***\xff)))\xff(((\xff'''\xff&&&\xff%%%\xff$$$\xff###\xff\"\"\"\xff!!!\xff   \xff\x1f\x1f\x1f\xff\x1e\x1e\x1e\xff\x1d\x1d\x1d\xff\x1c\x1c\x1c\xff\x1b\x1b\x1b\xff\x1a\x1a\x1a\xff\x19\x19\x19\xff\x18\x18\x18\xff\x17\x17\x17\xff\x16\x16\x16\xff\x15\x15\x15\xff\x14\x14\x14\xff\x13\x13\x13\xff\x12\x12\x12\xff\x11\x11\x11\xff\x10\x10\x10\xff\x0f\x0f\x0f\xff\x0e\x0e\x0e\xff\x0d\x0d\x0d\xff\x0c\x0c\x0c\xff\x0b\x0b\x0b\xff\x0a\x0a\x0a\xff\x09\x09\x09\xff\x08\x08\x08\xff\x07\x07\x07\xff\x06\x06\x06\xff\x05\x05\x05\xff\x04\x04\x04\xff\x03\x03\x03\xff\x02\x02\x02\xff\x01\x01\x01\xff\x00\x00\x00\xff", 256, 2)
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
