local function Rainbow(flSpeed, flSaturation, flLightness, iAlpha)return{(type(tonumber(flSpeed)) ~= "number") and 1 or tonumber(flSpeed);(type(tonumber(flSaturation)) ~= "number") and 1 or math.min(math.max(math.abs(tonumber(flSaturation)), 0), 1);(type(tonumber(flLightness)) ~= "number") and 1 or math.min(math.max(math.abs(tonumber(flLightness)), 0), 1);(type(tonumber(iAlpha)) ~= "number") and 255 or math.floor(math.min(math.max(math.abs(tonumber(iAlpha)), 0), 255));};end
local function Static(iR, iG, iB, iA)return(((type(tonumber(iR)) ~= "number") and 255 or math.floor(math.min(math.max(math.abs(tonumber(iR)), 0), 255))) << 24) | (((type(tonumber(iG)) ~= "number") and 255 or math.floor(math.min(math.max(math.abs(tonumber(iG)), 0), 255))) << 16) | (((type(tonumber(iB)) ~= "number") and 255 or math.floor(math.min(math.max(math.abs(tonumber(iB)), 0), 255))) << 8) | ((type(tonumber(iA)) ~= "number") and 255 or math.floor(math.min(math.max(math.abs(tonumber(iA)), 0), 255)));end
local function Disabled()return false;end

local config = {
    -- If true: use enemy_or_red and friend_or_blue for red and blue teams.
    -- If false: use enemy_or_red and friend_or_blue for enemy and friend.
    team_based = false;

    --[[
    To have an item with the rainbow effect use 
        Rainbow(speed [-inf, inf], saturation [0, 1], lightness [0, 1], alpha [0, 255]);

    To have an item with a static color use
        Static(red [0, 255], green [0, 255], blue [0, 255], alpha [0, 255]);

    To disable changing of a color use
        Disabled();
    ]]
    enemy_or_red = Rainbow(1, 0.75, 1, 255);
    enemy_or_red_invis = Rainbow(1, 0.5, 0.5, 127);
    friend_or_blue = Static(0, 127, 255, 255);
    friend_or_blue_invis = Static(0, 127, 255, 127);
    backtrack = Rainbow(1, 0.75, 1, 55);
    target = Rainbow(10, 1, 1, 255);
    gui = Rainbow(1, 0.8, 1, 255);
    hands = Disabled();
    anti_aim_indicator = Disabled();

    -- Using a rainbow color on night mode may lead to lag.
    night_mode = Disabled();
};

local g_bOnBlueTeam = false;

local g_aSetData = {
    [true] = {
        ["backtrack indicator color"] = config.backtrack;
        ["blue team color"] = config.friend_or_blue;
        ["blue team (invisible)"] = config.friend_or_blue_invis;
        ["red team color"] = config.enemy_or_red;
        ["red team (invisible)"] = config.enemy_or_red_invis;
        ["aimbot target color"] = config.target;
        ["gui color"] = config.gui;
        ["hands color"] = config.hands;
        ["anti aim indicator color"] = config.anti_aim_indicator;
        ["night mode color"] = config.night_mode;
    };

    [false] = {
        ["backtrack indicator color"] = config.backtrack;
        ["red team color"] = config.friend_or_blue;
        ["red team (invisible)"] = config.friend_or_blue_invis;
        ["blue team color"] = config.enemy_or_red;
        ["blue team (invisible)"] = config.enemy_or_red_invis;
        ["aimbot target color"] = config.target;
        ["gui color"] = config.gui;
        ["hands color"] = config.hands;
        ["anti aim indicator color"] = config.anti_aim_indicator;
        ["night mode color"] = config.night_mode;
    };
};

callbacks.Register("Draw", function()
    local pLocalPlayer = entities.GetLocalPlayer();
    if(pLocalPlayer)then
        g_bOnBlueTeam = pLocalPlayer:GetTeamNumber() ~= 2;
    end

    local flCurTime = globals.CurTime();
    
    for sElement, tData in pairs(g_aSetData[config.team_based or g_bOnBlueTeam])do
        local iValue = gui.GetValue(sElement);
        
        if(type(tData) == "number")then
            if(iValue ~= tData)then
                gui.SetValue(sElement, tData);
            end

        elseif(type(tData) == "table")then
            local flTime, flV1, flV2 = flCurTime * tData[1], 255 * tData[3] * tData[2] / 2, 255 * (tData[3] - (tData[3] * tData[2] / 2));
            local iNewColor = (math.floor(math.sin(flTime) * flV1 + flV2) << 24) | (math.floor(math.sin(flTime + 2.09439510239) * flV1 + flV2) << 16) | (math.floor(math.sin(flTime + 4.18879020479) * flV1 + flV2) << 8) | tData[4]
            
            if(iValue ~= iNewColor)then
                gui.SetValue(sElement, iNewColor);
            end
        end

    
    end
end);
