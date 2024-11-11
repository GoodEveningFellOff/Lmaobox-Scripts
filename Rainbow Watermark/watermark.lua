local text_velocity = 200; -- <- Change this to the speed you want the text to bounce around at

local bg_font = draw.CreateFont("TF2 Build", 25, 23, 512)
local font = draw.CreateFont("TF2 Build", 25, 23, 528);
local str = {'L', 'M', 'A', 'O', 'B', 'O', 'X'};
local cached_colors = {};

draw.SetFont(font)

local screen_width, screen_height = (function()
	local sw, sh = draw.GetScreenSize();
	local tw, th = draw.GetTextSize("LMAOBOX");

	return sw - tw, sh - th
end)();

local char_sizes = (function()
	local tbl, offset = {}, 0;

	for i, char in pairs(str) do
		tbl[i] = offset;
		offset = offset + draw.GetTextSize(char);
	end
	
	return tbl
end)();

local function set_rainbow_color(deg)
	local cached_value = cached_colors[deg];

	if cached_value then
		draw.Color(table.unpack(cached_value))
		return
	end

	local rad = math.rad(deg);
	local r, g, b = math.floor(math.sin(rad)*126+127), math.floor(math.sin(rad+2.1)*126+127), math.floor(math.sin(rad+4.2)*126+127);

	cached_colors[deg] = {r, g, b, 255};
	draw.Color(r, g, b, 255)
end

local text_x, text_y = 0, 0;
local text_dx, text_dy = text_velocity, text_velocity;


callbacks.Register("Draw", function()
	local time = -math.floor(globals.CurTime()*80);
	local render_x, render_y = math.floor(text_x), math.floor(text_y);

	--[[
		why render the text twice, once with no aa and then a second time with aa...
		because the font seems to have ugly ass holes in it when aa is on that my adhd ass gets annoyed by
		this is the easiest fix...

		and yes we need the aa to match the LMAOBOX text when the menu is open
	]]

	draw.SetFont(bg_font)
	draw.Color(0, 0, 0, 255)
	draw.Text(render_x, render_y, "LMAOBOX")

	draw.SetFont(font)
	for i, char in pairs(str) do
		set_rainbow_color((time + (i-1)*10) % 360)

		draw.Text(render_x + char_sizes[i], render_y, char)
	end

	text_x, text_y = text_x + text_dx*globals.FrameTime(), text_y + text_dy*globals.FrameTime();
	
	if text_x < 0 then
		text_x, text_dx = 0, text_velocity;

	elseif text_x > screen_width then
		text_x, text_dx = screen_width, -text_velocity;
	end

	if text_y < 0 then
		text_y, text_dy = 0, text_velocity;

	elseif text_y > screen_height then
		text_y, text_dy = screen_height, -text_velocity;
	end
end)
