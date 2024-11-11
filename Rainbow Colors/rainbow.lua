local Config = {
	Speed = 1; -- go crazy -- Default 1
	Saturation = 0.75; -- between 0 and 1 -- Default 0.75
	Lightness = 1; -- between 0 and 1 -- Default 1


	-- Set to true to rainbowize ;)
	Backtrack = true; 
	BlueTeam = true;
	BlueTeamInvis = false;
	RedTeam = true;
	RedTeamInvis = false;
	Target = true;
	Gui = true;
	AAIndicator = false;
	-- Night mode was removed due to it lagging the shit out of your game
	-- Set to true to rainbowize
};


local a,b,c,d,e,f,g=(function()local a,b,c,d,e={},math.floor,math.sin,255*Config.Lightness*Config.Saturation/2,255*(Config.Lightness-(Config.Lightness*Config.Saturation/2));for i=0,6.27882198405,0.00436332312999 do table.insert(a,b(c(i)*d+e) << 24 | b(c(i+2.1)*d+e) << 16 | b(c(i+4.2)*d+e) << 8 | 255)end return a;end)(),math.floor,globals.CurTime,gui.SetValue,gui.GetValue,Config.Speed*240,{};
for k,v in pairs({["backtrack ticks color"]=Config.Backtrack;["blue team color"]=Config.BlueTeam;["blue team (invisible)"]=Config.BlueTeamInvis;["red team color"]=Config.RedTeam;["red team (invisible)"]=Config.RedTeamInvis;["aimbot target color"]=Config.Target;["gui color"]=Config.Gui;["anti aim indicator color"]=Config.AAIndicator;})do if v then table.insert(g,k)end end
callbacks.Register("Draw",function()local h=a[(b(c()*f)%1439)+1];if h==e(g[1])then return end for _,i in pairs(g)do d(i,h)end end)
