

local vector = require("vector")
local pui = require("gamesense/pui")
local clipboard = require("gamesense/clipboard")
local c_entity = require("gamesense/entity")
local ffi = require 'ffi'
local base64 = require("gamesense/base64")
local json = require("json")

local function vtable_bind(module, interface, index, typedef)
    local raw = client.create_interface(module, interface) or error('interface not found: '..module..' '..interface)
    local instance = ffi.cast('void***', raw)
    local fn = ffi.cast(typedef, instance[0][index])
    return function(...)
        return fn(instance, ...)
    end
end

local function toticks(x) return math.floor(0.5 + x / globals.tickinterval()) end
local krim_clantag = {}
krim_clantag.frames = {
    "         ",
    "⌖        ",
    "⌖Ｋ      ",
    "⌖ＫЯ     ",
    "⌖ＫЯＩ    ",
    "⌖ＫЯＩМ   ",
    "⌖ＫЯＩМ⌖  ",
    "⌖ＫЯＩМ   ",
    "⌖ＫЯＩ    ",
    "⌖ＫЯ      ",
    "⌖Ｋ       ",
    "⌖        ",
    "         ",
}
krim_clantag.cache = nil
krim_clantag.set = function(str)
    if str ~= krim_clantag.cache then
        client.set_clan_tag(str or "")
        krim_clantag.cache = str
    end
end
krim_clantag.handle = function()
    local iter = math.floor(math.fmod((globals.tickcount() + toticks(client.latency())) / 16, #krim_clantag.frames + 1) + 1)
    krim_clantag.set(krim_clantag.frames[iter])
end

local memory = {} do
    memory.get_client_entity = vtable_bind and vtable_bind('client.dll', 'VClientEntityList003', 3, 'void*(__thiscall*)(void***, int)') or nil

    memory.animstate = {} do
        local animstate_t = ffi.typeof 'struct { char pad0[0x18]; float anim_update_timer; char pad1[0xC]; float started_moving_time; float last_move_time; char pad2[0x10]; float last_lby_time; char pad3[0x8]; float run_amount; char pad4[0x10]; void* entity; void* active_weapon; void* last_active_weapon; float last_client_side_animation_update_time; int last_client_side_animation_update_framecount; float eye_timer; float eye_angles_y; float eye_angles_x; float goal_feet_yaw; float current_feet_yaw; float torso_yaw; float last_move_yaw; float lean_amount; char pad5[0x4]; float feet_cycle; float feet_yaw_rate; char pad6[0x4]; float duck_amount; float landing_duck_amount; char pad7[0x4]; float current_origin[3]; float last_origin[3]; float velocity_x; float velocity_y; char pad8[0x4]; float unknown_float1; char pad9[0x8]; float unknown_float2; float unknown_float3; float unknown; float m_velocity; float jump_fall_velocity; float clamped_velocity; float feet_speed_forwards_or_sideways; float feet_speed_unknown_forwards_or_sideways; float last_time_started_moving; float last_time_stopped_moving; bool on_ground; bool hit_in_ground_animation; char pad10[0x4]; float time_since_in_air; float last_origin_z; float head_from_ground_distance_standing; float stop_to_full_running_fraction; char pad11[0x4]; float magic_fraction; char pad12[0x3C]; float world_force; char pad13[0x1CA]; float min_yaw; float max_yaw; } **'
        memory.animstate.offset = 0x9960
        memory.animstate.get = function(self, ent)
            if not ent or not memory.get_client_entity then return end
            local client_entity = memory.get_client_entity(ent)
            if not client_entity then return end
            return ffi.cast(animstate_t, ffi.cast('uintptr_t', client_entity) + self.offset)[0]
        end
    end

    memory.animlayers = {} do
        if not pcall(ffi.typeof, 'bt_animlayer_t') then
            ffi.cdef[[
                typedef struct {
                    float   anim_time;
                    float   fade_out_time;
                    int     nil;
                    int     activty;
                    int     priority;
                    int     order;
                    int     sequence;
                    float   prev_cycle;
                    float   weight;
                    float   weight_delta_rate;
                    float   playback_rate;
                    float   cycle;
                    int     owner;
                    int     bits;
                } bt_animlayer_t, *pbt_animlayer_t;
            ]]
        end
        memory.animlayers.offset = ffi.cast('int*', ffi.cast('uintptr_t', client.find_signature('client.dll', '\x8B\x89\xCC\xCC\xCC\xCC\x8D\x0C\xD1')) + 2)[0]
        memory.animlayers.get = function(self, ent)
            if not memory.get_client_entity then return end
            local client_entity = memory.get_client_entity(ent)
            if not client_entity then return end
            return ffi.cast('pbt_animlayer_t*', ffi.cast('uintptr_t', client_entity) + self.offset)[0]
        end
    end

    memory.activity = {} do
        if not pcall(ffi.typeof, 'bt_get_sequence') then
            ffi.cdef[[ typedef int(__fastcall* bt_get_sequence)(void* entity, void* studio_hdr, int sequence); ]]
        end
        memory.activity.offset = 0x2950
        memory.activity.location = ffi.cast('bt_get_sequence', client.find_signature('client.dll', '\x55\x8B\xEC\x53\x8B\x5D\x08\x56\x8B\xF1\x83'))
        memory.activity.get = function(self, sequence, ent)
            if not memory.get_client_entity then return end
            local client_entity = memory.get_client_entity(ent)
            if not client_entity then return end
            local studio_hdr = ffi.cast('void**', ffi.cast('uintptr_t', client_entity) + self.offset)[0]
            if not studio_hdr then return end
            return self.location(client_entity, studio_hdr, sequence)
        end
    end

    memory.user_input = {} do
        if not pcall(ffi.typeof, 'bt_cusercmd_t') then
            ffi.cdef[[
                typedef struct {
                    struct bt_cusercmd_t (*cusercmd)();
                    int     command_number;
                    int     tick_count;
                    float   view[3];
                    float   aim[3];
                    float   move[3];
                    int     buttons;
                } bt_cusercmd_t;
            ]]
        end
        if not pcall(ffi.typeof, 'bt_get_usercmd') then
            ffi.cdef[[ typedef bt_cusercmd_t*(__thiscall* bt_get_usercmd)(void* input, int, int command_number); ]]
        end
        memory.user_input.vtbl = ffi.cast('void***', ffi.cast('void**', ffi.cast('uintptr_t', client.find_signature('client.dll', '\xB9\xCC\xCC\xCC\xCC\x8B\x40\x38\xFF\xD0\x84\xC0\x0F\x85') or error('input_sig')) + 1)[0])
        memory.user_input.location = ffi.cast('bt_get_usercmd', memory.user_input.vtbl[0][8])
        memory.user_input.get_command = function(self, command_number)
            return self.location(self.vtbl, 0, command_number)
        end
    end
end

local db = {}
do
    db.name = "da2_configs"
    db.data = {}
    
    -- Initialize data from file
    local function load_data()
        local success, data = pcall(function()
            local file = io.open("da2_configs.json", "r")
            if file then
                local content = file:read("*all")
                file:close()
                return json.parse(content)
            end
            return nil
        end)
        return success and data or {}
    end
    
    local function save_data(data)
        pcall(function()
            local file = io.open("da2_configs.json", "w")
            if file then
                file:write(json.stringify(data))
                file:close()
            end
        end)
    end
    
    db.data = load_data()
    
    db.read = function(key)
        return db.data[key]
    end
    
    db.write = function(key, data)
        db.data[key] = data
        save_data(db.data)
        return true
    end
end

local vencodata_text = [[
 /$$   /$$ /$$$$$$$  /$$$$$$ /$$      /$$
| $$  /$$/| $$__  $$|_  $$_/| $$$    /$$$
| $$ /$$/ | $$  \ $$  | $$  | $$$$  /$$$$
| $$$$$/  | $$$$$$$/  | $$  | $$ $$/$$ $$
| $$  $$  | $$__  $$  | $$  | $$  $$$| $$
| $$\  $$ | $$  \ $$  | $$  | $$\  $ | $$
| $$ \  $$| $$  | $$ /$$$$$$| $$ \/  | $$
|__/  \__/|__/  |__/|______/|__/     |__/

]]
local info_script = {
    username = function() 
        local player = entity.get_local_player()
        return player and entity.get_player_name(player) or "Player"
    end,
    version = "BETA",
    basecolor = { 173, 216, 230, 255 },
    basecolor_light = { 200, 230, 250, 255 }
}







local function rgba_to_hex(r, g, b, a)
    return bit.tohex(r, 2) .. bit.tohex(g, 2) .. bit.tohex(b, 2) .. bit.tohex(a, 2)
end
local fade_text = function(rgba, text)
    local final_text = ""
    local curtime = globals.curtime()
    local r, g, b, a = unpack(rgba)

    for i = 1, #text do
        local color = rgba_to_hex(r, g, b, a * math.abs(1 * math.cos(2 * 3 * curtime / 4 + i * 5 / 30)))
        final_text = final_text .. "\a" .. color .. text:sub(i, i)
    end

    return final_text
end





local antiaim_cond = { '\vGlobal\r', '\vStand\r', '\vWalking\r', '\vRunning\r' , '\vAir\r', '\vAir+\r', '\vDuck\r' }
local short_cond = { '\vG ·\r', '\vS ·\r', '\vW ·\r', '\vR ·\r' ,'\vA ·\r', '\vA+ ·\r', '\vD ·\r' }


local menu_ref = {
    antiaim = {
        slowwalk = { ui.reference('AA', 'Other', 'Slow motion') },
        enabled = ui.reference("AA", "Anti-aimbot angles", "Enabled"),
        pitch = {ui.reference("AA", "Anti-aimbot angles", "Pitch")},
        yawbase = ui.reference("AA", "Anti-aimbot angles", "Yaw base"),
        yaw = {ui.reference("AA", "Anti-aimbot angles", "Yaw")},
        fsbodyyaw = ui.reference("AA", "Anti-aimbot angles", "Freestanding body yaw"),
        edgeyaw = ui.reference("AA", "Anti-aimbot angles", "Edge yaw"),
        body_yaw = {ui.reference("AA", "Anti-aimbot angles", "Body yaw")},
        yaw_jitter = {ui.reference("AA", "Anti-aimbot angles", "Yaw jitter")},
        freestand = {ui.reference("AA", "Anti-aimbot angles", "Freestanding")},
        roll = ui.reference("AA", "Anti-aimbot angles", "Roll"),
        double_tap = {ui.reference('RAGE', 'Aimbot', 'Double tap')},
        on_shot_anti_aim = {ui.reference('AA', 'Other', 'On shot anti-aim')}
    },
    rage = {
        dmg = ui.reference("RAGE", "Aimbot", "Minimum damage"),
        dmg_override = {ui.reference("RAGE", "Aimbot", "Minimum damage override")}
    },
    fakelag = {
        enabled = { ui.reference('AA', 'Fake lag', 'Enabled') },
        amount = ui.reference('AA', 'Fake lag', 'Amount'),
        variance = ui.reference('AA', 'Fake lag', 'Variance'),
        limit = ui.reference('AA', 'Fake lag', 'Limit')
    },
    other = {
        enabled_slw = { ui.reference('AA', 'Other', 'Slow Motion') },
        leg_movement = ui.reference('AA', 'Other', 'Leg movement'),
        osaa = {ui.reference('AA', 'Other', 'On Shot anti-aim')},
        fakepeek = {ui.reference('AA', 'Other', 'Fake peek')}
    },
    visuals = {
        scope_overlay = ui.reference('VISUALS', 'Effects', 'Remove scope overlay')
    }
}

pui.macros.dot = '\v•  \r'
pui.macros.dot_red = "\aADD8E6FF•  \r"
pui.macros.fs = '\v⟳  \r'
pui.macros.left_manual = '\v⇦  \r'
pui.macros.right_manual = '\v⇨  \r'
pui.macros.forward_manual = '\v⇧  \r'
pui.macros.antiaim_vinco = '\vKr\aADD8E6FFim \v• \r'
pui.macros.fl_vinco = '\aADD8E6FFKrim \r'
local aa_group = pui.group("aa", "anti-aimbot angles")
local cfg_group = pui.group("aa", "other")
vencolabelaa = aa_group:label("Krim")
tab_selector = aa_group:combobox('\f<dot_red> \f<fl_vinco> Tab Selector', {"Info", "Anti~Aimbot", "Ragebot", "Visuals", "Misc", "Config"})
aa_group:label("--------------------------------------")
aa_group:label("\f<dot_red>Welcome back, \aADD8E6FF"..info_script.username()):depend({tab_selector, "Info"})
aa_group:label("\f<dot_red>Version: \aADD8E6FF"..info_script.version):depend({tab_selector, "Info"})

-- Anti-Aimbot
aa_tab = aa_group:combobox("\f<antiaim_vinco>AntiAim Tab", {"Settings", "Builder"}):depend({tab_selector, "Anti~Aimbot"})
aa_group:label("--------------------------------------"):depend({tab_selector, "Anti~Aimbot"})
aa_pitch = aa_group:combobox("\f<antiaim_vinco>Pitch", {"Disabled", "Down"}):depend({tab_selector, "Anti~Aimbot"}, {aa_tab, "Settings"})
aa_yaw_base = aa_group:combobox("\f<antiaim_vinco>Yaw Base", {"Local View", "At Targets"}):depend({tab_selector, "Anti~Aimbot"}, {aa_tab, "Settings"})
aa_fs_enable = aa_group:checkbox("\f<antiaim_vinco>Enable Freestanding"):depend({tab_selector, "Anti~Aimbot"}, {aa_tab, "Settings"})
aa_fs_key = aa_group:hotkey('\f<antiaim_vinco>Freestanding'):depend({tab_selector, "Anti~Aimbot"}, {aa_tab, "Settings"}, aa_fs_enable)

safe_head_enabled = aa_group:checkbox("\f<antiaim_vinco>Safe Head"):depend({tab_selector, "Anti~Aimbot"}, {aa_tab, "Settings"})
safe_head_states = aa_group:multiselect("\f<antiaim_vinco>Safe Head States", {"Air Knife", "Air Zeus", "Standing", "Crouched", "Crouched Air"}):depend({tab_selector, "Anti~Aimbot"}, {aa_tab, "Settings"}, safe_head_enabled)

avoid_backstab_enabled = aa_group:checkbox("\f<antiaim_vinco>Avoid Backstab"):depend({tab_selector, "Anti~Aimbot"}, {aa_tab, "Settings"})

aa_condition = aa_group:combobox('\f<antiaim_vinco>Condition', antiaim_cond):depend({tab_selector, "Anti~Aimbot"}, {aa_tab, "Builder"})

local defensive_aa_settings = {}
for i = 1, #antiaim_cond do
    defensive_aa_settings[i] = {
        defensive_anti_aimbot = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Defensive AA ' .. antiaim_cond[i]),
        defensive_pitch = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Defensive Pitch ' .. antiaim_cond[i]),
        defensive_pitch1 = ui.new_combobox('AA', 'Anti-aimbot angles', 'Defensive Pitch Type ' .. antiaim_cond[i], 'Off', 'Default', 'Up', 'Down', 'Minimal', 'Random', 'Custom'),
        defensive_pitch2 = ui.new_slider('AA', 'Anti-aimbot angles', 'Defensive Pitch Value ' .. antiaim_cond[i], -89, 89, -89, true, '°'),
        defensive_pitch3 = ui.new_slider('AA', 'Anti-aimbot angles', 'Defensive Pitch Random Max ' .. antiaim_cond[i], -89, 89, 89, true, '°'),
        defensive_yaw = ui.new_checkbox('AA', 'Anti-aimbot angles', 'Defensive Yaw ' .. antiaim_cond[i]),
        defensive_yaw1 = ui.new_combobox('AA', 'Anti-aimbot angles', 'Defensive Yaw Type ' .. antiaim_cond[i], '180', 'Spin', '180 Z', 'Sideways', 'Random'),
        defensive_yaw2 = ui.new_slider('AA', 'Anti-aimbot angles', 'Defensive Yaw Value ' .. antiaim_cond[i], -180, 180, 0, true, '°')
    }
end

aa_group:label("--------------------------------------"):depend({tab_selector, "Anti~Aimbot"}, {aa_tab, "Builder"})
aa_group:label("\f<antiaim_vinco>Defensive Anti-Aim Settings"):depend({tab_selector, "Anti~Aimbot"}, {aa_tab, "Builder"})

client.set_event_callback('paint_ui', function()
    local show_defensive = tab_selector:get() == "Anti~Aimbot" and aa_tab:get() == "Builder"
    local current_condition = aa_condition:get()
    
    for i = 1, #antiaim_cond do
        local show_for_condition = show_defensive and current_condition == antiaim_cond[i]
        
        ui.set_visible(defensive_aa_settings[i].defensive_anti_aimbot, show_for_condition)
        ui.set_visible(defensive_aa_settings[i].defensive_pitch, show_for_condition and ui.get(defensive_aa_settings[i].defensive_anti_aimbot))
        ui.set_visible(defensive_aa_settings[i].defensive_pitch1, show_for_condition and ui.get(defensive_aa_settings[i].defensive_anti_aimbot) and ui.get(defensive_aa_settings[i].defensive_pitch))
        ui.set_visible(defensive_aa_settings[i].defensive_pitch2, show_for_condition and ui.get(defensive_aa_settings[i].defensive_anti_aimbot) and ui.get(defensive_aa_settings[i].defensive_pitch) and (ui.get(defensive_aa_settings[i].defensive_pitch1) == "Random" or ui.get(defensive_aa_settings[i].defensive_pitch1) == "Custom"))
        ui.set_visible(defensive_aa_settings[i].defensive_pitch3, show_for_condition and ui.get(defensive_aa_settings[i].defensive_anti_aimbot) and ui.get(defensive_aa_settings[i].defensive_pitch) and ui.get(defensive_aa_settings[i].defensive_pitch1) == "Random")
        ui.set_visible(defensive_aa_settings[i].defensive_yaw, show_for_condition and ui.get(defensive_aa_settings[i].defensive_anti_aimbot))
        ui.set_visible(defensive_aa_settings[i].defensive_yaw1, show_for_condition and ui.get(defensive_aa_settings[i].defensive_anti_aimbot) and ui.get(defensive_aa_settings[i].defensive_yaw))
        ui.set_visible(defensive_aa_settings[i].defensive_yaw2, show_for_condition and ui.get(defensive_aa_settings[i].defensive_anti_aimbot) and ui.get(defensive_aa_settings[i].defensive_yaw) and (ui.get(defensive_aa_settings[i].defensive_yaw1) == "180" or ui.get(defensive_aa_settings[i].defensive_yaw1) == "Spin" or ui.get(defensive_aa_settings[i].defensive_yaw1) == "180 Z"))
    end
end)

ragebot_tab = aa_group:combobox("\f<antiaim_vinco>Ragebot Tab", {"Prediction", "Resolver"}):depend({tab_selector, "Ragebot"})
aa_group:label("--------------------------------------"):depend({tab_selector, "Ragebot"})

prediction_enabled = aa_group:checkbox("\f<dot_red>Improved Prediction"):depend({tab_selector, "Ragebot"}, {ragebot_tab, "Prediction"})
prediction_visualize = aa_group:checkbox("\f<dot_red>Visualize Prediction"):depend({tab_selector, "Ragebot"}, {ragebot_tab, "Prediction"}, prediction_enabled)
prediction_smoothing = aa_group:slider("\f<dot_red>Prediction Smoothing", 1, 100, 50, true, "%"):depend({tab_selector, "Ragebot"}, {ragebot_tab, "Prediction"}, prediction_enabled)
prediction_min_velocity = aa_group:slider("\f<dot_red>Min Velocity", 1, 100, 20, true, "units"):depend({tab_selector, "Ragebot"}, {ragebot_tab, "Prediction"}, prediction_enabled)
prediction_ticks = aa_group:slider("\f<dot_red>Prediction Ticks", 1, 16, 8, true, "ticks"):depend({tab_selector, "Ragebot"}, {ragebot_tab, "Prediction"}, prediction_enabled)
prediction_acceleration = aa_group:checkbox("\f<dot_red>Acceleration Prediction"):depend({tab_selector, "Ragebot"}, {ragebot_tab, "Prediction"}, prediction_enabled)

resolver_enabled = aa_group:checkbox("\f<dot_red>Advanced Resolver"):depend({tab_selector, "Ragebot"}, {ragebot_tab, "Resolver"})
resolver_force_body_yaw = aa_group:checkbox("\f<dot_red>Force Body Yaw"):depend({tab_selector, "Ragebot"}, {ragebot_tab, "Resolver"}, resolver_enabled)
resolver_correction_active = aa_group:checkbox("\f<dot_red>Correction Active"):depend({tab_selector, "Ragebot"}, {ragebot_tab, "Resolver"}, resolver_enabled)



ragebot_activation_key = aa_group:hotkey("\f<dot_red>Ragebot Activation Key"):depend({tab_selector, "Ragebot"})



local fl_group = pui.group("aa", "fake lag")
vencolabelfl = fl_group:label("Krim")
enable_fl = fl_group:checkbox("\f<dot_red>Enable \f<fl_vinco>fakelag system")
fl_limit = fl_group:slider("\f<dot_red>Fakelag Limit", 1, 15, 0):depend(enable_fl)
fl_variance = fl_group:slider("\f<dot_red>Fakelag Variance", 0, 100, 0, true, "%", 1):depend(enable_fl)
fl_type = fl_group:combobox("\f<dot_red>Fakelag Type", {"Dynamic", "Maximum", "Fluctuate", "Randomized"}):depend(enable_fl)


local oth_group = pui.group("aa", "other")
vencolabeloth = oth_group:label("Krim")
oth_sw = oth_group:checkbox("\f<dot_red> Slow Walk")
oth_sw_kb = oth_group:hotkey("\f<dot_red> Slow Walk Key")
oth_lm = oth_group:combobox("\f<dot_red> Leg Movment", {"Disabled", "Always", "Never"})
oth_osaa = oth_group:checkbox("\f<dot_red> OSAA")
oth_osaa_kb = oth_group:hotkey("\f<dot_red> OSAA Key")

local cfgs = {}


hitlogs_select = aa_group:multiselect("\f<dot_red>Hitlogs", "On Screen", "On Console"):depend({tab_selector, "Visuals"})
misslogs_select = aa_group:multiselect("\f<dot_red>Misslogs", "On Screen", "On Console"):depend({tab_selector, "Visuals"})

custom_scope_enabled = aa_group:checkbox("\f<dot_red>Custom Scope Overlay"):depend({tab_selector, "Visuals"})
custom_scope_color = aa_group:color_picker("\f<dot_red>Scope Color", 255, 255, 255, 255):depend({tab_selector, "Visuals"}, custom_scope_enabled)
custom_scope_mode = aa_group:combobox("\f<dot_red>Scope Mode", {"Default", "T"}):depend({tab_selector, "Visuals"}, custom_scope_enabled)
custom_scope_position = aa_group:slider("\f<dot_red>Scope Position", 0, 500, 50, true, "px"):depend({tab_selector, "Visuals"}, custom_scope_enabled)
custom_scope_offset = aa_group:slider("\f<dot_red>Scope Offset", 0, 500, 10, true, "px"):depend({tab_selector, "Visuals"}, custom_scope_enabled)

hitrate_enabled = aa_group:checkbox("\f<dot_red>Hitrate"):depend({tab_selector, "Visuals"})
hitrate_color = aa_group:color_picker("\f<dot_red>Hitrate Color", 113, 152, 255, 255):depend({tab_selector, "Visuals"}, hitrate_enabled)







vis_desync_arrows_style = aa_group:combobox("\f<dot_red>Desync Arrows", {"Disabled", "Default"}):depend({tab_selector, "Visuals"})
vis_desync_arrows_color = aa_group:color_picker("\f<dot_red>Arrows Color", 255, 255, 255, 255):depend({tab_selector, "Visuals"}, {vis_desync_arrows_style, "Disabled", true})
vis_desync_arrows_distance = aa_group:slider("\f<dot_red>Arrows Distance", 15, 150, 60, true, "px"):depend({tab_selector, "Visuals"}, {vis_desync_arrows_style, "Disabled", true})

-- Damage Indicator
vis_dmg_indicator_enable = aa_group:checkbox("\f<dot_red>Damage Indicator"):depend({tab_selector, "Visuals"})
dmg_indicator_color = aa_group:color_picker("\f<dot_red>Damage Indicator Color", 255, 165, 0, 255):depend({tab_selector, "Visuals"}, vis_dmg_indicator_enable)




-- Watermark
vis_watermark = aa_group:checkbox('Watermark'):depend({tab_selector, "Visuals"})
vis_watermark_mode = aa_group:combobox('Watermark Mode', '#1'):depend({tab_selector, "Visuals"}, vis_watermark)
vis_watermark_position = aa_group:combobox('Position', 'Left', 'Right'):depend({tab_selector, "Visuals"}, vis_watermark, {vis_watermark_mode, '#1'})
vis_watermark_label = aa_group:label('Watermark Color First'):depend({tab_selector, "Visuals"}, vis_watermark, {vis_watermark_mode, '#1'})
vis_watermark_color = aa_group:color_picker('Watermark Color', 155, 155, 200, 255):depend({tab_selector, "Visuals"}, vis_watermark, {vis_watermark_mode, '#1'})
vis_watermark_label2 = aa_group:label('Watermark Color Second'):depend({tab_selector, "Visuals"}, vis_watermark, {vis_watermark_mode, '#1'})
vis_watermark_color2 = aa_group:color_picker('Watermark Color 2', 0, 0, 0, 255):depend({tab_selector, "Visuals"}, vis_watermark, {vis_watermark_mode, '#1'})
vis_watermark_items = aa_group:multiselect('Items', 'Username', 'Latency', 'Framerate', 'Time'):depend({tab_selector, "Visuals"}, {vis_watermark_mode, '#2'})
vis_watermark_color_mode_2 = aa_group:color_picker('Watermark Color Mode 2', 155, 155, 200, 255):depend({tab_selector, "Visuals"}, vis_watermark, {vis_watermark_mode, '#2'})



-- Misc
trash_talk_enable = aa_group:checkbox("\f<dot_red>Trash Talk"):depend({tab_selector, "Misc"})
clantag_enable = aa_group:checkbox("\f<dot_red>ClanTag (KRIM)"):depend({tab_selector, "Misc"})
-- Fast Ladder (1:1 from Emberlash V2)
fast_ladder_enable = aa_group:checkbox("\f<dot_red>Fast ladder"):depend({tab_selector, "Misc"})
-- Emberlash V2 Animation Breaker
animation_breaker_enable = aa_group:checkbox("\f<dot_red>Animation Breaker"):depend({tab_selector, "Misc"})
animation_breaker_condition = aa_group:combobox("\f<dot_red>Condition", {"Running", "In air"}):depend({tab_selector, "Misc"}, animation_breaker_enable)

-- Running animations
animation_breaker_running_type = aa_group:combobox("\f<dot_red>Running Animation", {"-", "Static", "Jitter", "Alternative jitter", "Allah"}):depend({tab_selector, "Misc"}, animation_breaker_enable, {animation_breaker_condition, "Running"})
animation_breaker_running_min_jitter = aa_group:slider("\f<dot_red>Running Min Jitter", 0, 100, 0, true, "%"):depend({tab_selector, "Misc"}, animation_breaker_enable, {animation_breaker_condition, "Running"}, {animation_breaker_running_type, "Jitter"})
animation_breaker_running_max_jitter = aa_group:slider("\f<dot_red>Running Max Jitter", 0, 100, 100, true, "%"):depend({tab_selector, "Misc"}, animation_breaker_enable, {animation_breaker_condition, "Running"}, {animation_breaker_running_type, "Jitter"})
animation_breaker_running_extra = aa_group:multiselect("\f<dot_red>Running Extra", {"Body lean"}):depend({tab_selector, "Misc"}, animation_breaker_enable, {animation_breaker_condition, "Running"})
animation_breaker_running_bodylean = aa_group:slider("\f<dot_red>Running Body Lean", 0, 100, 70, true, "%"):depend({tab_selector, "Misc"}, animation_breaker_enable, {animation_breaker_condition, "Running"}, {animation_breaker_running_extra, "Body lean"})

-- In air animations
animation_breaker_air_type = aa_group:combobox("\f<dot_red>Air Animation", {"-", "Static", "Jitter", "Allah"}):depend({tab_selector, "Misc"}, animation_breaker_enable, {animation_breaker_condition, "In air"})
animation_breaker_air_min_jitter = aa_group:slider("\f<dot_red>Air Min Jitter", 0, 100, 0, true, "%"):depend({tab_selector, "Misc"}, animation_breaker_enable, {animation_breaker_condition, "In air"}, {animation_breaker_air_type, "Jitter"})
animation_breaker_air_max_jitter = aa_group:slider("\f<dot_red>Air Max Jitter", 0, 100, 100, true, "%"):depend({tab_selector, "Misc"}, animation_breaker_enable, {animation_breaker_condition, "In air"}, {animation_breaker_air_type, "Jitter"})
animation_breaker_air_extra = aa_group:multiselect("\f<dot_red>Air Extra", {"Body lean", "Zero pitch on landing"}):depend({tab_selector, "Misc"}, animation_breaker_enable, {animation_breaker_condition, "In air"})
animation_breaker_air_bodylean = aa_group:slider("\f<dot_red>Air Body Lean", 0, 100, 70, true, "%"):depend({tab_selector, "Misc"}, animation_breaker_enable, {animation_breaker_condition, "In air"}, {animation_breaker_air_extra, "Body lean"})

-- ANNESTY CONFIG SYSTEM - EXACT COPY
local base = {}

-- Initialize base system with working persistence
-- Use the same approach as the existing config system
base = {
    name = {"Default"},
    cfg = {"{}"}
}

-- Auto-save configs to clipboard for persistence
local function auto_save_configs()
    local config_data = json.stringify(base)
    clipboard.set("KRIM_AUTO_CONFIG:" .. base64.encode(config_data))
end

-- Config system initialized silently

-- Ensure base is never nil and set your config as default
if not base then
    base = {
        name = {"Default"},
        cfg = {"eyJ0aW1lc3RhbXAiOjQwNzQ5LCJ2ZXJzaW9uIjoiMS4wIiwic2V0dGluZ3MiOnsidmlzX2Rlc3luY19hcnJvd3NfY29sb3IiOjI1NSwidHJhc2hfdGFsa19lbmFibGUiOmZhbHNlLCJjdXN0b21fc2NvcGVfZW5hYmxlZCI6dHJ1ZSwidmlzX2Rlc3luY19hcnJvd3NfZGlzdGFuY2UiOjYwLCJhYV9zeXNfN19tb2RfdHlwZSI6IlNraXR0ZXIiLCJkbWdfaW5kaWNhdG9yX2NvbG9yIjoyNTUsImFhX3N5c183X3lhd19yaWdodCI6MTYsImFhX3N5c181X2VuYWJsZSI6dHJ1ZSwiYWFfc3lzXzFfbW9kX2RtIjotMTAsImFhX3N5c180X3lhd190eXBlIjoiRGVsYXkiLCJ2aXNfd2F0ZXJtYXJrX2NvbG9yX21vZGVfMiI6MTU1LCJjdXN0b21fc2NvcGVfb2Zmc2V0IjoxMCwiYWFfc3lzXzdfZW5hYmxlIjp0cnVlLCJhYV9zeXNfMl95YXdfcmlnaHQiOjIzLCJ2aXNfd2F0ZXJtYXJrX21vZGUiOiIjMSIsImNmZ19uYW1lIjoiZGEiLCJhYV9zeXNfMV9tb2RfdHlwZSI6IlNraXR0ZXIiLCJhYV9zeXNfMV95YXdfcmlnaHQiOjIxLCJhYV9zeXNfNF9kZXN5bmNfbW9kZSI6IktyaW0iLCJhYV9zeXNfMl95YXdfZGVsYXkiOjQsImFhX3N5c182X21vZF9kbSI6MTAsImFhX3N5c18yX3lhd19sZWZ0IjotMTYsImFhX3N5c18zX3lhd190eXBlIjoiRGVsYXkiLCJhYV9zeXNfMl9lbmFibGUiOnRydWUsImN1c3RvbV9zY29wZV9wb3NpdGlvbiI6NTAsImFhX2NvbmRpdGlvbiI6Ilx1MDAwYkFpclxyIiwiY2ZnX2xpc3QiOjAsImFhX3N5c18xX3lhd19sZWZ0IjotMjcsImhpdGxvZ3Nfc2VsZWN0IjpbIk9uIFNjcmVlbiIsIk9uIENvbnNvbGUiXSwiYWFfc3lzXzRfZW5hYmxlIjp0cnVlLCJhYV9waXRjaCI6IkRvd24iLCJhYV9zeXNfMV95YXdfdHlwZSI6IkRlbGF5IiwiYWFfc3lzXzFfZW5hYmxlIjp0cnVlLCJhYV9zeXNfNF95YXdfcmlnaHQiOjE2LCJhYV9zeXNfNV9tb2RfdHlwZSI6IlNraXR0ZXIiLCJmbF9saW1pdCI6MSwiYWFfc3lzXzNfeWF3X3JpZ2h0IjoxNCwiZmxfdHlwZSI6IkR5bmFtaWMiLCJhYV9mc19rZXkiOmZhbHNlLCJhYV9zeXNfMl9tb2RfZG0iOjcsImFhX3N5c182X3lhd19sZWZ0IjotMTIsImFhX3N5c18yX2Rlc3luY19tb2RlIjoiS3JpbSIsImFhX3N5c18zX21vZF90eXBlIjoiU2tpdHRlciIsImFhX3N5c181X21vZF9kbSI6LTE2LCJ2aXNfZGVzeW5jX2Fycm93c19zdHlsZSI6IkRpc2FibGVkIiwib3RoX3N3IjpmYWxzZSwiYWFfc3lzXzFfZGVzeW5jX21vZGUiOiJLcmltIiwidmlzX3dhdGVybWFya19jb2xvciI6MTU1LCJhbmltYXRpb25fYnJlYWtlciI6WyJlYXJ0aHF1YWtlIiwic2xpZGluZyBzbG93IG1vdGlvbiIsInNsaWRpbmcgY3JvdWNoIiwib24gZ3JvdW5kIiwiYWVyb2JpYyIsInF1aWNrIHBlZWsgbGVncyJdLCJhYV9zeXNfNF9tb2RfZG0iOi0xMiwiYWFfc3lzXzVfeWF3X2RlbGF5Ijo0LCJjbGFudGFnX2VuYWJsZSI6dHJ1ZSwiYWFfc3lzXzVfeWF3X2xlZnQiOi0xMCwiaGl0cmF0ZV9jb2xvciI6MTEzLCJ2aXNfd2F0ZXJtYXJrX2NvbG9yMiI6MCwidmlzX3dhdGVybWFyayI6dHJ1ZSwiYWFfc3lzXzVfZGVzeW5jX21vZGUiOiJLcmltIiwib3RoX29zYWFfa2IiOmZhbHNlLCJhYV9zeXNfNV95YXdfdHlwZSI6IkRlbGF5IiwiYWFfc3lzXzZfeWF3X3JpZ2h0IjoxMiwidmlzX2RtZ19pbmRpY2F0b3JfZW5hYmxlIjp0cnVlLCJhYV9zeXNfN19kZXN5bmNfbW9kZSI6IktyaW0iLCJjdXN0b21fc2NvcGVfbW9kZSI6IkRlZmF1bHQiLCJjdXN0b21fc2NvcGVfY29sb3IiOjI1NSwiYWFfc3lzXzNfeWF3X2xlZnQiOi0xOCwic2FmZV9oZWFkX2VuYWJsZWQiOnRydWUsImFhX3N5c181X3lhd19yaWdodCI6MTYsIm90aF9sbSI6IkRpc2FibGVkIiwibWlzc2xvZ3Nfc2VsZWN0IjpbIk9uIFNjcmVlbiIsIk9uIENvbnNvbGUiXSwiYWFfc3lzXzJfeWF3X3R5cGUiOiJEZWxheSIsImZsX3ZhcmlhbmNlIjowLCJhYV9zeXNfM19kZXN5bmNfbW9kZSI6IktyaW0iLCJ2aXNfd2F0ZXJtYXJrX2l0ZW1zIjp7fSwiYWFfc3lzXzdfeWF3X3R5cGUiOiJEZWxheSIsImFhX3N5c18zX21vZF9kbSI6LTE0LCJ0YWJfc2VsZWN0b3IiOiJDb25maWciLCJhYV9mc19lbmFibGUiOnRydWUsInNhZmVfaGVhZF9zdGF0ZXMiOlsiQWlyIEtuaWZlIiwiQWlyIFpldXMiLCJTdGFuZGluZyIsIkNyb3VjaGVkIiwiQ3JvdWNoZWQgQWlyIl0sImVuYWJsZV9mbCI6ZmFsc2UsIm90aF9zd19rYiI6ZmFsc2UsImFhX3N5c18yX21vZF90eXBlIjoiU2tpdHRlciIsImFhX3N5c18xX3lhd19kZWxheSI6NCwiYWFfc3lzXzNfeWF3X2RlbGF5Ijo0LCJhYV9zeXNfM19lbmFibGUiOnRydWUsImF2b2lkX2JhY2tzdGFiX2VuYWJsZWQiOnRydWUsIm9uX2dyb3VuZF9vcHRpb25zIjoic3dhZyIsImFhX3N5c180X3lhd19kZWxheSI6NCwiYWFfc3lzXzdfeWF3X2RlbGF5Ijo0LCJhYV9zeXNfNF95YXdfbGVmdCI6LTE5LCJhYV9zeXNfNF9tb2RfdHlwZSI6IlNraXR0ZXIiLCJhYV90YWIiOiJCdWlsZGVyIiwiYWFfc3lzXzdfbW9kX2RtIjotMTksIm90aF9vc2FhIjpmYWxzZSwidmlzX3dhdGVybWFya19wb3NpdGlvbiI6IkxlZnQiLCJvbl9haXJfb3B0aW9ucyI6InN3YWciLCJhYV9zeXNfNl95YXdfZGVsYXkiOjQsImFhX3N5c182X2Rlc3luY19tb2RlIjoiS3JpbSIsImFhX3N5c182X21vZF90eXBlIjoiU2tpdHRlciIsImhpdHJhdGVfZW5hYmxlZCI6dHJ1ZSwiYWFfc3lzXzdfeWF3X2xlZnQiOi0xMiwiYWFfc3lzXzZfeWF3X3R5cGUiOiJEZWxheSIsImFhX3lhd19iYXNlIjoiQXQgVGFyZ2V0cyIsImFhX3N5c182X2VuYWJsZSI6dHJ1ZX19"}
    }
end
if not base.name then
    base.name = {"Default"}
end
if not base.cfg then
    base.cfg = {"{\"aa_sys_1_enable\":true,\"aa_sys_1_mod_type\":\"Skitter\",\"aa_sys_1_mod_dm\":-10,\"aa_sys_1_yaw_type\":\"Delay\",\"aa_sys_1_yaw_delay\":4,\"aa_sys_1_yaw_left\":-27,\"aa_sys_1_yaw_right\":21,\"aa_sys_1_desync_mode\":\"Krim\",\"aa_sys_2_enable\":true,\"aa_sys_2_mod_type\":\"Skitter\",\"aa_sys_2_mod_dm\":7,\"aa_sys_2_yaw_type\":\"Delay\",\"aa_sys_2_yaw_delay\":4,\"aa_sys_2_yaw_left\":-16,\"aa_sys_2_yaw_right\":23,\"aa_sys_2_desync_mode\":\"Krim\",\"aa_sys_3_enable\":true,\"aa_sys_3_mod_type\":\"Skitter\",\"aa_sys_3_mod_dm\":-14,\"aa_sys_3_yaw_type\":\"Delay\",\"aa_sys_3_yaw_delay\":4,\"aa_sys_3_yaw_left\":-18,\"aa_sys_3_yaw_right\":14,\"aa_sys_3_desync_mode\":\"Krim\",\"aa_sys_4_enable\":true,\"aa_sys_4_mod_type\":\"Skitter\",\"aa_sys_4_mod_dm\":-12,\"aa_sys_4_yaw_type\":\"Delay\",\"aa_sys_4_yaw_delay\":4,\"aa_sys_4_yaw_left\":-19,\"aa_sys_4_yaw_right\":16,\"aa_sys_4_desync_mode\":\"Krim\",\"aa_sys_5_enable\":true,\"aa_sys_5_mod_type\":\"Skitter\",\"aa_sys_5_mod_dm\":-16,\"aa_sys_5_yaw_type\":\"Delay\",\"aa_sys_5_yaw_delay\":4,\"aa_sys_5_yaw_left\":-10,\"aa_sys_5_yaw_right\":16,\"aa_sys_5_desync_mode\":\"Krim\",\"aa_sys_6_enable\":true,\"aa_sys_6_mod_type\":\"Skitter\",\"aa_sys_6_mod_dm\":10,\"aa_sys_6_yaw_type\":\"Delay\",\"aa_sys_6_yaw_delay\":4,\"aa_sys_6_yaw_left\":-12,\"aa_sys_6_yaw_right\":12,\"aa_sys_6_desync_mode\":\"Krim\",\"aa_sys_7_enable\":true,\"aa_sys_7_mod_type\":\"Skitter\",\"aa_sys_7_mod_dm\":-19,\"aa_sys_7_yaw_type\":\"Delay\",\"aa_sys_7_yaw_delay\":4,\"aa_sys_7_yaw_left\":-12,\"aa_sys_7_yaw_right\":16,\"aa_sys_7_desync_mode\":\"Krim\",\"aa_pitch\":\"Down\",\"aa_yaw_base\":\"At Targets\",\"aa_tab\":\"Builder\",\"safe_head_enabled\":true,\"avoid_backstab_enabled\":true,\"fast_ladder_enable\":false}"}
end

-- Simple Config UI Elements
local config_export_btn = aa_group:button("Export Config"):depend({tab_selector, "Config"})
local config_import_btn = aa_group:button("Import Config"):depend({tab_selector, "Config"})
local config_default_btn = aa_group:button("Load Default"):depend({tab_selector, "Config"})

-- Simple Config System - Import, Export, Default Only
local simple_config = {}

-- Helper function to count table size
local function table_size(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

local default_settings = {
    aa_pitch = "Down",
    aa_yaw_base = "At Targets", 
    aa_fs_enable = true,
    aa_fs_key = false,
    safe_head_enabled = true,
    safe_head_states = {"Air Knife", "Air Zeus", "Standing", "Crouched", "Crouched Air"},
    avoid_backstab_enabled = true,
    aa_condition = "Air",
    
    enable_fl = false,
    fl_limit = 1,
    fl_variance = 0,
    fl_type = "Dynamic",
    oth_sw = "Disabled",
    oth_sw_kb = false,
    oth_lm = "Disabled", 
    oth_osaa = false,
    oth_osaa_kb = false,
    
    hitlogs_select = {"On Screen", "On Console"},
    misslogs_select = {"On Screen", "On Console"},
    custom_scope_enabled = true,
    custom_scope_color = 255,
    custom_scope_mode = "Default",
    custom_scope_position = 50,
    custom_scope_offset = 10,
    hitrate_enabled = true,
    hitrate_color = 113,
    vis_desync_arrows_style = "Disabled",
    vis_desync_arrows_color = 255,
    vis_desync_arrows_distance = 60,
    vis_dmg_indicator_enable = true,
    dmg_indicator_color = 255,
    vis_watermark = true,
    vis_watermark_color = 155,
    vis_watermark_color_mode_2 = 155,
    vis_watermark_mode = "#1",
    vis_watermark_position = "Left",
    vis_watermark_items = {},
    
    animation_breaker = {"earthquake", "sliding slow motion", "sliding crouch", "on ground", "aerobic", "quick peek legs"},
    
    clantag_enable = true,
    
    tab_selector = "Config",
    aa_tab = "Builder",
    
    aa_sys = {
        [1] = {enable = true, mod_type = "Skitter", mod_dm = -10, yaw_type = "Delay", yaw_delay = 4, yaw_left = -27, yaw_right = 21, desync_mode = "Krim"},
        [2] = {enable = true, mod_type = "Skitter", mod_dm = 7, yaw_type = "Delay", yaw_delay = 4, yaw_left = -16, yaw_right = 23, desync_mode = "Krim"},
        [3] = {enable = true, mod_type = "Skitter", mod_dm = -14, yaw_type = "Delay", yaw_delay = 4, yaw_left = -18, yaw_right = 14, desync_mode = "Krim"},
        [4] = {enable = true, mod_type = "Skitter", mod_dm = -12, yaw_type = "Delay", yaw_delay = 4, yaw_left = -19, yaw_right = 16, desync_mode = "Krim"},
        [5] = {enable = true, mod_type = "Skitter", mod_dm = -16, yaw_type = "Delay", yaw_delay = 4, yaw_left = -10, yaw_right = 16, desync_mode = "Krim"},
        [6] = {enable = true, mod_type = "Skitter", mod_dm = 10, yaw_type = "Delay", yaw_delay = 4, yaw_left = -12, yaw_right = 12, desync_mode = "Krim"},
        [7] = {enable = true, mod_type = "Skitter", mod_dm = -19, yaw_type = "Delay", yaw_delay = 4, yaw_left = -12, yaw_right = 16, desync_mode = "Krim"}
    }
}
simple_config.export = function()
    local settings = {}
    
    if tab_selector then settings.tab_selector = tab_selector:get() end
    if aa_tab then settings.aa_tab = aa_tab:get() end
    if aa_pitch then settings.aa_pitch = aa_pitch:get() end
    if aa_yaw_base then settings.aa_yaw_base = aa_yaw_base:get() end
    if aa_fs_enable then settings.aa_fs_enable = aa_fs_enable:get() end
    if aa_fs_key then settings.aa_fs_key = aa_fs_key:get() end
    if safe_head_enabled then settings.safe_head_enabled = safe_head_enabled:get() end
    if safe_head_states then settings.safe_head_states = safe_head_states:get() end
    if avoid_backstab_enabled then settings.avoid_backstab_enabled = avoid_backstab_enabled:get() end
    if aa_condition then settings.aa_condition = aa_condition:get() end
    if enable_fl then settings.enable_fl = enable_fl:get() end
    if fl_limit then settings.fl_limit = fl_limit:get() end
    if fl_variance then settings.fl_variance = fl_variance:get() end
    if fl_type then settings.fl_type = fl_type:get() end
    if oth_sw then settings.oth_sw = oth_sw:get() end
    if oth_sw_kb then settings.oth_sw_kb = oth_sw_kb:get() end
    if oth_lm then settings.oth_lm = oth_lm:get() end
    if oth_osaa then settings.oth_osaa = oth_osaa:get() end
    if oth_osaa_kb then settings.oth_osaa_kb = oth_osaa_kb:get() end
    if hitlogs_select then settings.hitlogs_select = hitlogs_select:get() end
    if misslogs_select then settings.misslogs_select = misslogs_select:get() end
    if custom_scope_enabled then settings.custom_scope_enabled = custom_scope_enabled:get() end
    if custom_scope_color then settings.custom_scope_color = custom_scope_color:get() end
    if custom_scope_mode then settings.custom_scope_mode = custom_scope_mode:get() end
    if custom_scope_position then settings.custom_scope_position = custom_scope_position:get() end
    if custom_scope_offset then settings.custom_scope_offset = custom_scope_offset:get() end
    if hitrate_enabled then settings.hitrate_enabled = hitrate_enabled:get() end
    if hitrate_color then settings.hitrate_color = hitrate_color:get() end
    if vis_desync_arrows_style then settings.vis_desync_arrows_style = vis_desync_arrows_style:get() end
    if vis_desync_arrows_color then settings.vis_desync_arrows_color = vis_desync_arrows_color:get() end
    if vis_desync_arrows_distance then settings.vis_desync_arrows_distance = vis_desync_arrows_distance:get() end
    if vis_dmg_indicator_enable then settings.vis_dmg_indicator_enable = vis_dmg_indicator_enable:get() end
    if dmg_indicator_color then settings.dmg_indicator_color = dmg_indicator_color:get() end
    if vis_watermark then settings.vis_watermark = vis_watermark:get() end
    if vis_watermark_color then settings.vis_watermark_color = vis_watermark_color:get() end
    if vis_watermark_mode then settings.vis_watermark_mode = vis_watermark_mode:get() end
    if vis_watermark_position then settings.vis_watermark_position = vis_watermark_position:get() end
    if clantag_enable then settings.clantag_enable = clantag_enable:get() end
    if animation_breaker_enable then settings.animation_breaker_enable = animation_breaker_enable:get() end
    if animation_breaker_condition then settings.animation_breaker_condition = animation_breaker_condition:get() end
    
    if aa_sys then
        settings.aa_sys = {}
        for i = 1, 7 do
            if aa_sys[i] then
                settings.aa_sys[i] = {
                    enable = aa_sys[i].enable:get(),
                    mod_type = aa_sys[i].mod_type:get(),
                    mod_dm = aa_sys[i].mod_dm:get(),
                    yaw_type = aa_sys[i].yaw_type:get(),
                    yaw_delay = aa_sys[i].yaw_delay:get(),
                    yaw_left = aa_sys[i].yaw_left:get(),
                    yaw_right = aa_sys[i].yaw_right:get(),
                    desync_mode = aa_sys[i].desync_mode:get()
                }
            end
        end
    end
    
    -- Create config data
    local config_data = {
        timestamp = globals.tickcount(),
        version = "1.0",
        settings = settings
    }
    
    -- Export to clipboard
    local encoded = base64.encode(json.stringify(config_data))
    clipboard.set(encoded)
    print("✓ Config exported to clipboard!")
    return true
end

simple_config.import = function()
    local clipboard_data = clipboard.get()
    if not clipboard_data then
        print("✗ No data in clipboard")
        return false
    end
    
    local success, decoded = pcall(function()
        return json.parse(base64.decode(clipboard_data))
    end)
    
    if success and decoded and decoded.settings then
        local success_count = 0
        
        local function safe_set(element, value)
            if element and value ~= nil then
                local set_success = pcall(function()
                    element:set(value)
                end)
                if set_success then
                    success_count = success_count + 1
            end
        end
    end
    
        -- Load settings to UI with safety checks
        safe_set(tab_selector, decoded.settings.tab_selector)
        safe_set(aa_tab, decoded.settings.aa_tab)
        safe_set(aa_pitch, decoded.settings.aa_pitch)
        safe_set(aa_yaw_base, decoded.settings.aa_yaw_base)
        safe_set(aa_fs_enable, decoded.settings.aa_fs_enable)
        safe_set(aa_fs_key, decoded.settings.aa_fs_key)
        safe_set(safe_head_enabled, decoded.settings.safe_head_enabled)
        safe_set(safe_head_states, decoded.settings.safe_head_states)
        safe_set(avoid_backstab_enabled, decoded.settings.avoid_backstab_enabled)
        safe_set(aa_condition, decoded.settings.aa_condition)
        safe_set(enable_fl, decoded.settings.enable_fl)
        safe_set(fl_limit, decoded.settings.fl_limit)
        safe_set(fl_variance, decoded.settings.fl_variance)
        safe_set(fl_type, decoded.settings.fl_type)
        safe_set(oth_sw, decoded.settings.oth_sw)
        safe_set(oth_sw_kb, decoded.settings.oth_sw_kb)
        safe_set(oth_lm, decoded.settings.oth_lm)
        safe_set(oth_osaa, decoded.settings.oth_osaa)
        safe_set(oth_osaa_kb, decoded.settings.oth_osaa_kb)
        safe_set(hitlogs_select, decoded.settings.hitlogs_select)
        safe_set(misslogs_select, decoded.settings.misslogs_select)
        safe_set(custom_scope_enabled, decoded.settings.custom_scope_enabled)
        safe_set(custom_scope_color, decoded.settings.custom_scope_color)
        safe_set(custom_scope_mode, decoded.settings.custom_scope_mode)
        safe_set(custom_scope_position, decoded.settings.custom_scope_position)
        safe_set(custom_scope_offset, decoded.settings.custom_scope_offset)
        safe_set(hitrate_enabled, decoded.settings.hitrate_enabled)
        safe_set(hitrate_color, decoded.settings.hitrate_color)
        safe_set(vis_desync_arrows_style, decoded.settings.vis_desync_arrows_style)
        safe_set(vis_desync_arrows_color, decoded.settings.vis_desync_arrows_color)
        safe_set(vis_desync_arrows_distance, decoded.settings.vis_desync_arrows_distance)
        safe_set(vis_dmg_indicator_enable, decoded.settings.vis_dmg_indicator_enable)
        safe_set(dmg_indicator_color, decoded.settings.dmg_indicator_color)
        safe_set(vis_watermark, decoded.settings.vis_watermark)
        safe_set(vis_watermark_color, decoded.settings.vis_watermark_color)
        safe_set(vis_watermark_mode, decoded.settings.vis_watermark_mode)
        safe_set(vis_watermark_position, decoded.settings.vis_watermark_position)
        safe_set(clantag_enable, decoded.settings.clantag_enable)
        safe_set(animation_breaker_enable, decoded.settings.animation_breaker_enable)
        safe_set(animation_breaker_condition, decoded.settings.animation_breaker_condition)
        
        -- Import anti-aim system settings
        if decoded.settings.aa_sys and aa_sys then
            for i = 1, 7 do
                if decoded.settings.aa_sys[i] and aa_sys[i] then
                    safe_set(aa_sys[i].enable, decoded.settings.aa_sys[i].enable)
                    safe_set(aa_sys[i].mod_type, decoded.settings.aa_sys[i].mod_type)
                    safe_set(aa_sys[i].mod_dm, decoded.settings.aa_sys[i].mod_dm)
                    safe_set(aa_sys[i].yaw_type, decoded.settings.aa_sys[i].yaw_type)
                    safe_set(aa_sys[i].yaw_delay, decoded.settings.aa_sys[i].yaw_delay)
                    safe_set(aa_sys[i].yaw_left, decoded.settings.aa_sys[i].yaw_left)
                    safe_set(aa_sys[i].yaw_right, decoded.settings.aa_sys[i].yaw_right)
                    safe_set(aa_sys[i].desync_mode, decoded.settings.aa_sys[i].desync_mode)
                end
            end
        end
        
        print("✓ Config imported from clipboard!")
        print("Successfully set " .. success_count .. " settings")
        return true
    else
        print("✗ Invalid config data in clipboard")
        return false
    end
end

simple_config.load_default = function()
    local success_count = 0
    
    local function safe_set(element, value)
        if element and value ~= nil then
            local success = pcall(function()
                element:set(value)
            end)
            if success then
                success_count = success_count + 1
            end
        end
    end
    
    safe_set(tab_selector, default_settings.tab_selector)
    safe_set(aa_tab, default_settings.aa_tab)
    safe_set(aa_pitch, default_settings.aa_pitch)
    safe_set(aa_yaw_base, default_settings.aa_yaw_base)
    safe_set(aa_fs_enable, default_settings.aa_fs_enable)
    safe_set(aa_fs_key, default_settings.aa_fs_key)
    safe_set(safe_head_enabled, default_settings.safe_head_enabled)
    safe_set(safe_head_states, default_settings.safe_head_states)
    safe_set(avoid_backstab_enabled, default_settings.avoid_backstab_enabled)
    safe_set(aa_condition, default_settings.aa_condition)
    safe_set(enable_fl, default_settings.enable_fl)
    safe_set(fl_limit, default_settings.fl_limit)
    safe_set(fl_variance, default_settings.fl_variance)
    safe_set(fl_type, default_settings.fl_type)
    safe_set(oth_sw, default_settings.oth_sw)
    safe_set(oth_sw_kb, default_settings.oth_sw_kb)
    safe_set(oth_lm, default_settings.oth_lm)
    safe_set(oth_osaa, default_settings.oth_osaa)
    safe_set(oth_osaa_kb, default_settings.oth_osaa_kb)
    safe_set(hitlogs_select, default_settings.hitlogs_select)
    safe_set(misslogs_select, default_settings.misslogs_select)
    safe_set(custom_scope_enabled, default_settings.custom_scope_enabled)
    safe_set(custom_scope_color, default_settings.custom_scope_color)
    safe_set(custom_scope_mode, default_settings.custom_scope_mode)
    safe_set(custom_scope_position, default_settings.custom_scope_position)
    safe_set(custom_scope_offset, default_settings.custom_scope_offset)
    safe_set(hitrate_enabled, default_settings.hitrate_enabled)
    safe_set(hitrate_color, default_settings.hitrate_color)
    safe_set(vis_desync_arrows_style, default_settings.vis_desync_arrows_style)
    safe_set(vis_desync_arrows_color, default_settings.vis_desync_arrows_color)
    safe_set(vis_desync_arrows_distance, default_settings.vis_desync_arrows_distance)
    safe_set(vis_dmg_indicator_enable, default_settings.vis_dmg_indicator_enable)
    safe_set(dmg_indicator_color, default_settings.dmg_indicator_color)
    safe_set(vis_watermark, default_settings.vis_watermark)
    safe_set(vis_watermark_color, default_settings.vis_watermark_color)
    safe_set(vis_watermark_mode, default_settings.vis_watermark_mode)
    safe_set(vis_watermark_position, default_settings.vis_watermark_position)
    safe_set(clantag_enable, default_settings.clantag_enable)
    safe_set(animation_breaker_enable, default_settings.animation_breaker_enable)
    safe_set(animation_breaker_condition, default_settings.animation_breaker_condition)
    
    if default_settings.aa_sys and aa_sys then
        for i = 1, 7 do
            if default_settings.aa_sys[i] and aa_sys[i] then
                safe_set(aa_sys[i].enable, default_settings.aa_sys[i].enable)
                safe_set(aa_sys[i].mod_type, default_settings.aa_sys[i].mod_type)
                safe_set(aa_sys[i].mod_dm, default_settings.aa_sys[i].mod_dm)
                safe_set(aa_sys[i].yaw_type, default_settings.aa_sys[i].yaw_type)
                safe_set(aa_sys[i].yaw_delay, default_settings.aa_sys[i].yaw_delay)
                safe_set(aa_sys[i].yaw_left, default_settings.aa_sys[i].yaw_left)
                safe_set(aa_sys[i].yaw_right, default_settings.aa_sys[i].yaw_right)
                safe_set(aa_sys[i].desync_mode, default_settings.aa_sys[i].desync_mode)
            end
        end
    end
    
    print("✓ Default config loaded!")
    print("Successfully set " .. success_count .. " settings")
    return true
end

if config_export_btn then
    config_export_btn:set_callback(function()
        simple_config.export()
    end)
end

if config_import_btn then
    config_import_btn:set_callback(function()
        simple_config.import()
    end)
end

if config_default_btn then
    config_default_btn:set_callback(function()
        simple_config.load_default()
        -- Apply anti-aim settings after loading default config
        client.delay_call(0.1, function()
            apply_your_settings()
        end)
    end)
end

-- Load default config automatically on startup
simple_config.load_default()

-- Apply anti-aim settings after UI elements are created
client.delay_call(0.1, function()
    apply_your_settings()
end)

-- Old config system functions removed (using simple config system now)

-- Old custom config loading removed (using simple config system now)

-- Function to enable anti-aim systems based on config
local function enable_aa_systems_from_config()
    -- Enable all anti-aim systems by default so the builder works
    if aa_sys then
        local enabled_count = 0
        for i = 1, 7 do
            if aa_sys[i] and aa_sys[i].enable then
                aa_sys[i].enable:set(true)
                enabled_count = enabled_count + 1
            end
        end
        print("✓ Anti-aim systems enabled for builder (" .. enabled_count .. "/7 systems)")
    else
        print("Warning: aa_sys not initialized yet")
    end
end

-- Function will be defined after aa_sys table is created

-- Old config functions removed (using simple config system now)

-- Old delete function removed

-- Old import function removed

-- Old export function removed

-- Old config buttons removed (using simple config system now)

-- Config buttons registered (no longer needed with simple config system)

-- Config system initialized silently






local aa_sys = {}
for i = 1, #antiaim_cond do
    aa_sys[i] = {
        label = aa_group:label('\f<antiaim_vinco>Editing \v'..antiaim_cond[i]),
        enable = aa_group:checkbox('\f<antiaim_vinco>Enable | \v'..antiaim_cond[i]),
        yaw_type = aa_group:combobox('\f<antiaim_vinco>Yaw Type', {"Default", "Delay"}),
        yaw_delay = aa_group:slider('\f<antiaim_vinco>Delay Ticks', 1, 10, 4, true, 't', 1),
        yaw_left = aa_group:slider('\f<antiaim_vinco>Yaw Left', -180, 180, 0, true, '', 1),
        yaw_right = aa_group:slider('\f<antiaim_vinco>Yaw Right', -180, 180, 0, true, ' ', 1),
        mod_type = aa_group:combobox('\f<antiaim_vinco>Jitter Type', {'Off', 'Offset', 'Center', 'Random', 'Skitter'}),
        mod_dm = aa_group:slider('\f<antiaim_vinco>Offset', -180, 180, 0, true, '', 1),
        desync_mode = aa_group:combobox("\f<antiaim_vinco>Desync Mode", {"Krim", "gamsense"}),
    }
    
    -- Anti-aim system elements created (no longer need registration)
end

for i=1, #antiaim_cond do
    local antiaimbot_tab = {tab_selector, "Anti~Aimbot"}
    local builder_tab = {aa_tab, "Builder"}
    local tab_cond = {aa_condition, antiaim_cond[i]}
    local cnd_en = aa_sys[i].enable
    local delay_selected = {aa_sys[i].yaw_type, "Delay"}
    local jitter_type = {aa_sys[i].mod_type, function() return aa_sys[i].mod_type:get() ~= "Off" end}
    aa_sys[i].label:depend(antiaimbot_tab, builder_tab, tab_cond)
    aa_sys[i].enable:depend(antiaimbot_tab, builder_tab, tab_cond)
    aa_sys[i].yaw_type:depend(cnd_en, antiaimbot_tab, builder_tab, tab_cond)
    aa_sys[i].yaw_delay:depend(cnd_en, delay_selected, antiaimbot_tab, builder_tab, tab_cond)
    aa_sys[i].yaw_left:depend(cnd_en, antiaimbot_tab, builder_tab, tab_cond)
    aa_sys[i].yaw_right:depend(cnd_en, antiaimbot_tab, builder_tab, tab_cond)
    aa_sys[i].mod_type:depend(cnd_en, antiaimbot_tab, builder_tab, tab_cond)
    aa_sys[i].mod_dm:depend(cnd_en, antiaimbot_tab, builder_tab, tab_cond, jitter_type)
    aa_sys[i].desync_mode:depend(cnd_en, antiaimbot_tab, builder_tab, tab_cond)
end

-- Enable anti-aim systems after they are created
enable_aa_systems_from_config()

-- Apply your settings directly
function apply_your_settings()
    print("=== APPLYING SETTINGS FUNCTION CALLED ===")
    print("Applying your complete configuration...")
    
    -- ANTI-AIM SETTINGS
    print("Debug: aa_sys exists: " .. tostring(aa_sys ~= nil))
    if aa_sys then
        print("Debug: aa_sys length: " .. #aa_sys)
        for i = 1, 7 do
            if aa_sys[i] then
                print("Debug: aa_sys[" .. i .. "] exists")
            else
                print("Debug: aa_sys[" .. i .. "] is nil!")
            end
        end
        -- System 1 (Default)
        if aa_sys[1] then
            aa_sys[1].enable:set(true)
            aa_sys[1].mod_type:set("Skitter")
            aa_sys[1].mod_dm:set(-10)
            aa_sys[1].yaw_type:set("Delay")
            aa_sys[1].yaw_delay:set(4)
            aa_sys[1].yaw_left:set(-27)
            aa_sys[1].yaw_right:set(21)
            aa_sys[1].desync_mode:set("Krim")
            print("Debug: System 1 set - enable: " .. tostring(aa_sys[1].enable:get()) .. ", mod_type: " .. aa_sys[1].mod_type:get())
        end
        
        -- System 2 (Standing)
        if aa_sys[2] then
            aa_sys[2].enable:set(true)
            aa_sys[2].mod_type:set("Skitter")
            aa_sys[2].mod_dm:set(7)
            aa_sys[2].yaw_type:set("Delay")
            aa_sys[2].yaw_delay:set(4)
            aa_sys[2].yaw_left:set(-16)
            aa_sys[2].yaw_right:set(23)
            aa_sys[2].desync_mode:set("Krim")
        end
        
        -- System 3 (Walking)
        if aa_sys[3] then
            aa_sys[3].enable:set(true)
            aa_sys[3].mod_type:set("Skitter")
            aa_sys[3].mod_dm:set(-14)
            aa_sys[3].yaw_type:set("Delay")
            aa_sys[3].yaw_delay:set(4)
            aa_sys[3].yaw_left:set(-18)
            aa_sys[3].yaw_right:set(14)
            aa_sys[3].desync_mode:set("Krim")
        end
        
        -- System 4 (Running)
        if aa_sys[4] then
            aa_sys[4].enable:set(true)
            aa_sys[4].mod_type:set("Skitter")
            aa_sys[4].mod_dm:set(-12)
            aa_sys[4].yaw_type:set("Delay")
            aa_sys[4].yaw_delay:set(4)
            aa_sys[4].yaw_left:set(-19)
            aa_sys[4].yaw_right:set(16)
            aa_sys[4].desync_mode:set("Krim")
        end
        
        -- System 5 (Air)
        if aa_sys[5] then
            aa_sys[5].enable:set(true)
            aa_sys[5].mod_type:set("Skitter")
            aa_sys[5].mod_dm:set(-16)
            aa_sys[5].yaw_type:set("Delay")
            aa_sys[5].yaw_delay:set(4)
            aa_sys[5].yaw_left:set(-10)
            aa_sys[5].yaw_right:set(16)
            aa_sys[5].desync_mode:set("Krim")
        end
        
        -- System 6 (Air-C)
        if aa_sys[6] then
            aa_sys[6].enable:set(true)
            aa_sys[6].mod_type:set("Skitter")
            aa_sys[6].mod_dm:set(10)
            aa_sys[6].yaw_type:set("Delay")
            aa_sys[6].yaw_delay:set(4)
            aa_sys[6].yaw_left:set(-12)
            aa_sys[6].yaw_right:set(12)
            aa_sys[6].desync_mode:set("Krim")
        end
        
        -- System 7 (Ducked)
        if aa_sys[7] then
            aa_sys[7].enable:set(true)
            aa_sys[7].mod_type:set("Skitter")
            aa_sys[7].mod_dm:set(-19)
            aa_sys[7].yaw_type:set("Delay")
            aa_sys[7].yaw_delay:set(4)
            aa_sys[7].yaw_left:set(-12)
            aa_sys[7].yaw_right:set(16)
            aa_sys[7].desync_mode:set("Krim")
        end
    end
    
    if aa_pitch then aa_pitch:set("Down") end
    if aa_yaw_base then aa_yaw_base:set("At Targets") end
    if aa_tab then aa_tab:set("Builder") end
    if safe_head_enabled then safe_head_enabled:set(true) end
    if avoid_backstab_enabled then avoid_backstab_enabled:set(true) end
    if aa_fs_enable then aa_fs_enable:set(true) end
    if aa_fs_key then aa_fs_key:set(false) end
    if enable_fl then enable_fl:set(false) end
    if fl_limit then fl_limit:set(1) end
    if fl_variance then fl_variance:set(0) end
    if fl_type then fl_type:set("Dynamic") end
    
    if vis_desync_arrows_color then vis_desync_arrows_color:set(255) end
    if vis_desync_arrows_distance then vis_desync_arrows_distance:set(60) end
    if vis_desync_arrows_style then vis_desync_arrows_style:set("Disabled") end
    if vis_watermark then vis_watermark:set(true) end
    if vis_watermark_mode then vis_watermark_mode:set("#1") end
    if vis_watermark_position then vis_watermark_position:set("Left") end
    if vis_watermark_color then vis_watermark_color:set(155) end
    if vis_watermark_color2 then vis_watermark_color2:set(0) end
    if vis_watermark_color_mode_2 then vis_watermark_color_mode_2:set(155) end
    if vis_dmg_indicator_enable then vis_dmg_indicator_enable:set(true) end
    if dmg_indicator_color then dmg_indicator_color:set(255) end
    if hitrate_enabled then hitrate_enabled:set(true) end
    if hitrate_color then hitrate_color:set(113) end
    
    if custom_scope_enabled then custom_scope_enabled:set(true) end
    if custom_scope_color then custom_scope_color:set(255) end
    if custom_scope_mode then custom_scope_mode:set("Default") end
    if custom_scope_position then custom_scope_position:set(50) end
    if custom_scope_offset then custom_scope_offset:set(10) end
    
    if trash_talk_enable then trash_talk_enable:set(false) end
    if clantag_enable then clantag_enable:set(true) end
    if animation_breaker then animation_breaker:set({"earthquake", "sliding slow motion", "sliding crouch", "on ground", "aerobic", "quick peek legs"}) end
    if on_ground_options then on_ground_options:set("swag") end
    if on_air_options then on_air_options:set("swag") end
    
    if oth_sw then oth_sw:set(false) end
    if oth_sw_kb then oth_sw_kb:set(false) end
    if oth_lm then oth_lm:set("Disabled") end
    if oth_osaa then oth_osaa:set(false) end
    if oth_osaa_kb then oth_osaa_kb:set(false) end
    
    if hitlogs_select then hitlogs_select:set({"On Screen", "On Console"}) end
    if misslogs_select then misslogs_select:set({"On Screen", "On Console"}) end
    
    if safe_head_states then safe_head_states:set({"Air Knife", "Air Zeus", "Standing", "Crouched", "Crouched Air"}) end
    
    print("✓ Complete configuration applied!")
    print("✓ Anti-aim: 7 systems with Skitter jitter")
    print("✓ Visuals: Watermark, desync arrows, hitrate")
    print("✓ Misc: Clantag, animation breaker, custom scope")
end


local function get_velocity(player)
    local x, y, z = entity.get_prop(player, "m_vecVelocity")
    if x == nil then
        return
    end
    return math.sqrt(x * x + y * y + z * z)
end


local function get_player_state()
    local me = entity.get_local_player()
    local m_fFlags = entity.get_prop(me, 'm_fFlags')
    local m_bDucked = entity.get_prop(me, 'm_flDuckAmount') > 0.7
    local speedvec = { entity.get_prop(me, 'm_vecVelocity') }
    local speed = math.sqrt(speedvec[1]^2+speedvec[2]^2)
    local slowwalk = ui.get(menu_ref.antiaim.slowwalk[1]) and ui.get(menu_ref.antiaim.slowwalk[2])
    local in_air = false
    local air_tick = 0
    local current_tickcount = 0
    --local frestanding = antiaim_tab.freestand:get()
    if bit.band(m_fFlags, bit.lshift(1, 0)) == 0 then
        in_air = true
        air_tick = globals.tickcount() + 3
    else
        in_air = (air_tick > globals.tickcount()) and true or false
    end

    if in_air and m_bDucked then
        return 'AIR-C'
    end

    if in_air then
        return 'AIR'
    end

    if m_bDucked then
        return 'DUCKED'
    end

    if slowwalk then
        return 'WALK'
    end

    if speed < 8 then
        return 'STAND'
    else
        return 'RUN'
    end
end

local id = 1
local current_tickcount = 0
local to_jitter = false
local last_player_state = ""
local last_aa_id = 0

local function setup_builder(cmd)
    ui.set(menu_ref.antiaim.enabled, true)
    ui.set(menu_ref.antiaim.yaw[1], "180")

    local lp = entity.get_local_player()
    if lp == nil then return end
    local desync_type = entity.get_prop(lp, 'm_flPoseParameter', 11) * 120 - 60
	desync_side = desync_type > 0 and 1 or -1

    local player_state = get_player_state()
    
    -- Check if any anti-aim systems are enabled, if not use default values
    local has_enabled_system = false
    for i = 1, 7 do
        if aa_sys[i] and aa_sys[i].enable and aa_sys[i].enable:get() then
            has_enabled_system = true
            break
        end
    end
    
    if has_enabled_system then
        if player_state == "DUCKED" and aa_sys[7] and aa_sys[7].enable:get() then id = 7
        elseif player_state == "AIR-C" and aa_sys[6] and aa_sys[6].enable:get() then id = 6
        elseif player_state == "AIR" and aa_sys[5] and aa_sys[5].enable:get() then id = 5
        elseif player_state == "RUN" and aa_sys[4] and aa_sys[4].enable:get() then id = 4
        elseif player_state == "WALK" and aa_sys[3] and aa_sys[3].enable:get() then id = 3
        elseif player_state == "STAND" and aa_sys[2] and aa_sys[2].enable:get() then id = 2
        else id = 1 end
    else
        -- Use default anti-aim settings from your config
        id = 1
    end
    
    -- Update state tracking without console spam
    if player_state ~= last_player_state or id ~= last_aa_id then
        last_player_state = player_state
        last_aa_id = id
    end

    ui.set(menu_ref.antiaim.fsbodyyaw, false)
    if aa_pitch:get() == "Disabled" then
        ui.set(menu_ref.antiaim.pitch[1], "Custom")
        ui.set(menu_ref.antiaim.pitch[2], 0)
    else
        ui.set(menu_ref.antiaim.pitch[1], "Custom")
        ui.set(menu_ref.antiaim.pitch[2], 89)
    end
    ui.set(menu_ref.antiaim.yawbase, aa_yaw_base:get())

    -- Use anti-aim system values if available, otherwise use default values from config
    local mod_type = "Off"
    local mod_dm = 0
    local yaw_type = "Default"
    local yaw_delay = 4
    local yaw_left = 0
    local yaw_right = 0
    
    if aa_sys[id] and aa_sys[id].mod_type then
        mod_type = aa_sys[id].mod_type:get()
        mod_dm = aa_sys[id].mod_dm:get()
        yaw_type = aa_sys[id].yaw_type:get()
        yaw_delay = aa_sys[id].yaw_delay:get()
        yaw_left = aa_sys[id].yaw_left:get()
        yaw_right = aa_sys[id].yaw_right:get()
    else
        -- Use default values from your config
        mod_type = "Skitter"
        mod_dm = -10
        yaw_type = "Delay"
        yaw_delay = 4
        yaw_left = -27
        yaw_right = 21
    end
    
    ui.set(menu_ref.antiaim.yaw_jitter[1], mod_type)
    ui.set(menu_ref.antiaim.yaw_jitter[2], mod_dm)
    
    if yaw_type == "Delay" then
        if globals.tickcount() > current_tickcount + yaw_delay then
            if cmd.chokedcommands == 0 then
                to_jitter = not to_jitter
                current_tickcount = globals.tickcount()
            end
        elseif globals.tickcount() <  current_tickcount then
            current_tickcount = globals.tickcount()
        end
        ui.set(menu_ref.antiaim.body_yaw[1], "Static")
        ui.set(menu_ref.antiaim.body_yaw[2], to_jitter and 1 or -1)
        if desync_side == 1 then
            ui.set(menu_ref.antiaim.yaw[2], yaw_left)
        elseif desync_side == -1 then
            ui.set(menu_ref.antiaim.yaw[2], yaw_right)
        end
    else
        if globals.tickcount() > current_tickcount + 1 then
            if cmd.chokedcommands == 0 then
                to_jitter = not to_jitter
                current_tickcount = globals.tickcount()
            end
        elseif globals.tickcount() <  current_tickcount then
            current_tickcount = globals.tickcount()
        end
        
        if yaw_left == 0 and yaw_right == 0 then
            ui.set(menu_ref.antiaim.body_yaw[1], "Static")
            ui.set(menu_ref.antiaim.body_yaw[2], -60)
        else
            ui.set(menu_ref.antiaim.body_yaw[1], "Static")
            ui.set(menu_ref.antiaim.body_yaw[2], to_jitter and 1 or -1)
        end

        if desync_side == 1 then
            ui.set(menu_ref.antiaim.yaw[2], yaw_left)
        elseif desync_side == -1 then
            ui.set(menu_ref.antiaim.yaw[2], yaw_right)
        end
    end
    ui.set(menu_ref.antiaim.freestand[1], aa_fs_enable:get())
    ui.set(menu_ref.antiaim.freestand[2], aa_fs_key:get() and 'Always on' or 'On hotkey')
end

local function setup_fakelag()
    ui.set(menu_ref.fakelag.enabled[1], enable_fl:get())
    ui.set(menu_ref.fakelag.enabled[2], 'Always on')
    ui.set(menu_ref.fakelag.variance, fl_variance:get())
    ui.set(menu_ref.fakelag.limit, fl_limit:get())
    ui.set(menu_ref.fakelag.amount, "Maximum")
end

local function setup_other_aa_tab()
    if oth_lm:get() == "Disabled" then
        ui.set(menu_ref.other.leg_movement, "Off")
    end
    if oth_lm:get() == "Always" then
        ui.set(menu_ref.other.leg_movement, "Always slide")
    end
    if oth_lm:get() == "Never" then
        ui.set(menu_ref.other.leg_movement, "Never slide")
    end

    ui.set(menu_ref.other.enabled_slw[1], oth_sw:get())
    ui.set(menu_ref.other.enabled_slw[2], oth_sw_kb:get() and 'Always on' or 'On hotkey')
    ui.set(menu_ref.other.osaa[1], oth_osaa:get())
    ui.set(menu_ref.other.osaa[2], oth_osaa_kb:get() and 'Always on' or 'On hotkey')
end


hide_original_menu = function(state)
    ui.set_visible(menu_ref.antiaim.enabled, state)
    ui.set_visible(menu_ref.antiaim.pitch[1], state)
    ui.set_visible(menu_ref.antiaim.pitch[2], state)
    ui.set_visible(menu_ref.antiaim.yawbase, state)
    ui.set_visible(menu_ref.antiaim.yaw[1], state)
    ui.set_visible(menu_ref.antiaim.yaw[2], state)
    ui.set_visible(menu_ref.antiaim.yaw_jitter[1], state)
    ui.set_visible(menu_ref.antiaim.roll, state)
    ui.set_visible(menu_ref.antiaim.yaw_jitter[2], state)
    ui.set_visible(menu_ref.antiaim.body_yaw[1], state)
    ui.set_visible(menu_ref.antiaim.body_yaw[2], state)
    ui.set_visible(menu_ref.antiaim.fsbodyyaw, state)
    ui.set_visible(menu_ref.antiaim.edgeyaw, state)
    ui.set_visible(menu_ref.antiaim.freestand[1], state)
    ui.set_visible(menu_ref.antiaim.freestand[2], state)
    ui.set_visible(menu_ref.other.enabled_slw[1], state)
    ui.set_visible(menu_ref.other.enabled_slw[2], state)
    ui.set_visible(menu_ref.other.osaa[1], state)
    ui.set_visible(menu_ref.other.osaa[2], state)
    ui.set_visible(menu_ref.other.leg_movement, state)
    ui.set_visible(menu_ref.other.fakepeek[1], state)
    ui.set_visible(menu_ref.other.fakepeek[2], state)
    ui.set_visible(menu_ref.fakelag.enabled[1], state)
    ui.set_visible(menu_ref.fakelag.enabled[2], state)
    ui.set_visible(menu_ref.fakelag.amount, state)
    ui.set_visible(menu_ref.fakelag.variance, state)
    ui.set_visible(menu_ref.fakelag.limit, state)
end

local function create_lua_name()
    vencolabelaa:set(fade_text(info_script.basecolor, "               ⌖ Krim ⌖"))
    vencolabelfl:set(fade_text(info_script.basecolor, "               ⌖ Krim ⌖"))
    vencolabeloth:set(fade_text(info_script.basecolor, "               ⌖ Krim ⌖"))
end


local function paint_ui()
    -- Watermark removed from down screen
end

-- Annesty Visual Functions

-- Annesty rounded rectangle functions
renderer.rounded_rectangle = function(x, y, w, h, r, g, b, a, radius)
    y = y + radius
    local data_circle = {
        {x + radius, y, 180},
        {x + w - radius, y, 90},
        {x + radius, y + h - radius * 2, 270},
        {x + w - radius, y + h - radius * 2, 0},
    }

    local data = {
        {x + radius, y, w - radius * 2, h - radius * 2},
        {x + radius, y - radius, w - radius * 2, radius},
        {x + radius, y + h - radius * 2, w - radius * 2, radius},
        {x, y, radius, h - radius * 2},
        {x + w - radius, y, radius, h - radius * 2},
    }

    for _, data in next, data_circle do
        renderer.circle(data[1], data[2], r, g, b, a, radius, data[3], 0.25)
    end

    for _, data in next, data do
        renderer.rectangle(data[1], data[2], data[3], data[4], r, g, b, a)
    end
end

renderer.rounded_outline = function(x, y, w, h, r, g, b, a, thickness, radius)
    renderer.rectangle(x + radius, y, w - radius * 2, thickness, r, g, b, a)
    renderer.rectangle(x + w - thickness, y + radius, thickness, h - radius * 2, r, g, b, a)
    renderer.rectangle(x, y + radius, thickness, h - radius * 2, r, g, b, a)
    renderer.rectangle(x + radius, y + h - thickness, w - radius * 2, thickness, r, g, b, a)
    renderer.circle_outline(x + radius, y + radius, r, g, b, a, radius, 180, 0.25, thickness)
    renderer.circle_outline(x - radius + w, y + radius, r, g, b, a, radius, 270, 0.25, thickness)
    renderer.circle_outline(x + radius, y - radius + h, r, g, b, a, radius, 90, 0.25, thickness)
    renderer.circle_outline(x - radius + w, y - radius + h, r, g, b, a, radius, 0, 0.25, thickness)
end


-- Animation lerp function from annesty
local anim = {
    lerp = function(tog, val, towhat, speed, if_not_tog)
        local wanted_frametime = 80
        local current_frametime = 1 / globals.frametime()
        local percent = wanted_frametime / current_frametime
        if tog then
            if towhat == 255 then
                if val > 235 then
                    val = 255
                else
                    if val < towhat then
                        val = val + globals.frametime() * speed * 1.5 * 64
                    end
                    if val > towhat then
                        val = val - globals.frametime() * speed * 1.5 * 64
                    end
                end
            else
                if math.floor(val / 10) == math.floor(towhat / 10) then
                    val = towhat
                else
                    if val < towhat then
                        val = val + globals.frametime() * speed * 2 * 64
                    end
                    if val > towhat then
                        val = val - globals.frametime() * speed * 2 * 64
                    end
                end
            end
        else
            if math.floor(val) <= math.floor(if_not_tog) then
                val = if_not_tog
            end
            if math.floor(val) > if_not_tog then
                val = val - speed * percent
            end
        end
        return math.floor(val)
    end
}

-- Motion interpolation function for smooth animations
local motion = {
    interp = function(from, to, speed)
        return from + (to - from) * speed
    end
}

-- Render solus function from annesty
local render = {
    solus = function(style, x, y, w, h, ac, alpha)
        if style == 1 then
            renderer.rectangle(x, y + 2, w, h, 0,0,0, ac[4] * alpha / 255)
            renderer.rectangle(x, y, w, 2, ac[1], ac[2], ac[3], alpha)
        elseif style == 2 then
            local round = 3
            renderer.rounded_rectangle(x + 1, y + 1, w - 1, h - 1, 0, 0, 0, ac[4] * alpha / 255, round)
            renderer.rectangle(x + round, y, w - round * 2, 1, ac[1], ac[2], ac[3], alpha)
            
            renderer.circle_outline(x + round, y + round, ac[1], ac[2], ac[3], alpha, round, 180, 0.25, 1)
            renderer.circle_outline(x - round + w, y + round, ac[1], ac[2], ac[3], alpha, round, 270, 0.25, 1)
            
            renderer.gradient(x, y + round, 1, h - round, ac[1], ac[2], ac[3], alpha, ac[1], ac[2], ac[3], 0, false)
            renderer.gradient(x + w - 1, y + round, 1, h - round, ac[1], ac[2], ac[3], alpha, ac[1], ac[2], ac[3], 0, false)
            
            renderer.rounded_outline(x + 1, y + 1, w - 2, h - 1, ac[1], ac[2], ac[3], ac[4] * alpha / 255^2 * 25, 1, round)
            renderer.rounded_outline(x, y, w, h, ac[1], ac[2], ac[3], ac[4] * alpha / 255^2 * 100, 1, round)
        end
    end,
    measure_text = function(flags, texting)
        return renderer.measure_text(flags, texting)
    end
}






local watermark_helpers = {
    framerate = 0,
    last_framerate = 0,
    animations = (function()
        local a = {data = {}}
        function a:clamp(b, c, d) return math.min(d, math.max(c, b)) end
        function a:animate(e, f, g)
            if not self.data[e] then self.data[e] = 0 end
            g = g or 4
            local b = globals.frametime() * g * (f and -1 or 1)
            self.data[e] = self:clamp(self.data[e] + b, 0, 1)
            return self.data[e]
        end
        return a
    end)(),
    rgba_to_hex = function(self, b, c, d, e)
        return string.format('%02x%02x%02x%02x', b, c, d, e)
    end,
    fade_handle = function(self, time, string, r, g, b, a)
        local color1, color2, color3, color4 = vis_watermark_color2:get()
        local t_out, t_out_iter = {}, 1
        local l = string:len() - 1
        local r_add = (color1 - r)
        local g_add = (color2 - g)
        local b_add = (color3 - b)
        for i = 1, #string do
            local iter = (i - 1) / (#string - 1) + time
            t_out[t_out_iter] = "\a" .. self:rgba_to_hex(r + r_add * math.abs(math.cos(iter)), g + g_add * math.abs(math.cos(iter)), b + b_add * math.abs(math.cos(iter)), a)
            t_out[t_out_iter + 1] = string:sub(i, i)
            t_out_iter = t_out_iter + 2
        end
        return t_out
    end
}

local function watermark_render()
    if not entity.get_local_player() then return end

    local x, y = client.screen_size()
    local r1, g1, b1, a1 = vis_watermark_color:get()
    local r, g, b, a = vis_watermark_color_mode_2:get()

    local global_alpha = watermark_helpers.animations:animate("alpha5", not vis_watermark:get(), 6)
    local left_alpha = watermark_helpers.animations:animate("alpha15", not (vis_watermark_position:get() == 'Left'), 6)
    local right_alpha = watermark_helpers.animations:animate("alpha65", not (vis_watermark_position:get() == 'Right'), 6)
    local style_1 = watermark_helpers.animations:animate("watermark_mode_1", not (vis_watermark_mode:get() == '#1'), 6)
    local style_2 = watermark_helpers.animations:animate("watermark_mode_2", not (vis_watermark_mode:get() == '#2'), 6)
    local icon = ""
    local left_water = watermark_helpers:fade_handle(globals.curtime() * 1.2, "K R I M [BETA]", r1, g1, b1, a1 * global_alpha * left_alpha * style_1)
    local right_water = watermark_helpers:fade_handle(-globals.curtime() * 1.2, "K R I M [BETA]", r1, g1, b1, a1 * global_alpha * right_alpha * style_1)

    local text = '\a' .. watermark_helpers:rgba_to_hex(r, g, b, a * global_alpha * style_2) .. 'Krim[BETA] ~' ..
             '\a' .. watermark_helpers:rgba_to_hex(200, 200, 200, 255 * global_alpha * style_2)

if vis_watermark_items:get('Username') then
    text = text .. ' | ' .. info_script.username()
end
if vis_watermark_items:get('Latency') then
    text = text .. ' | ' .. string.format('%dms', client.real_latency() * 1000)
end
if vis_watermark_items:get('Framerate') then
    watermark_helpers.framerate = 0.9 * watermark_helpers.framerate + (1.0 - 0.9) * globals.absoluteframetime()
    watermark_helpers.last_framerate = watermark_helpers.framerate > 0 and watermark_helpers.framerate or 1
    text = text .. ' | ' .. string.format('%d FPS', 1 / watermark_helpers.last_framerate)
end
if vis_watermark_items:get('Time') then
    text = text .. ' | ' .. string.format('%02d:%02d', client.system_time())
end

local text_size = renderer.measure_text(nil, text)
local padding = 12
local bg_width = text_size + (padding * 2)
local bg_x = x - bg_width - 20
local bg_y = 15

-- Background Box (Soft rounded corner with a modern feel)
renderer.rectangle(bg_x, bg_y, bg_width, 30, 15, 15, 15, 160 * global_alpha * style_2)

-- Watermark Text (Modern clean font with transparency effects)
renderer.text(bg_x + padding, bg_y + 8, 255, 255, 255, 255 * global_alpha * style_2, nil, nil, text)

-- Optional Text Effects (Sleek animations for dynamic effects)
renderer.text(x / 21 - 80, y / 2, 255, 255, 255, 255 * global_alpha * left_alpha * style_1, nil, nil, unpack(left_water))
renderer.text(x - 135, y / 2, 255, 255, 255, 255 * global_alpha * right_alpha * style_1, nil, nil, unpack(right_water))

-- Advanced UI Effects (Shadow effect to make the text stand out more)
renderer.rectangle(bg_x + padding, bg_y + 8, 0, 0, 0, 100 * global_alpha * style_2, nil, nil, text)
end

local function paint_damage_indicator(ctx)
    if not vis_dmg_indicator_enable:get() then return end
    
    local me = entity.get_local_player()
    if not entity.is_alive(me) then return end
    
    local sw, sh = client.screen_size()
    
    -- Show minimum damage override value when enabled, otherwise show regular minimum damage
    local damage_value
    if ui.get(menu_ref.rage.dmg_override[2]) then
        damage_value = ui.get(menu_ref.rage.dmg_override[3])
    else
        damage_value = ui.get(menu_ref.rage.dmg)
    end
    
    -- Custom color damage indicator
    local r, g, b = dmg_indicator_color:get()
    renderer.indicator(r, g, b, 255, damage_value)
    renderer.text(sw * 0.507, sh * 0.48, r, g, b, 255, "nil", 0, damage_value)
end

local function paint_desync_arrows()
    local style = vis_desync_arrows_style:get()
    if style == "Disabled" then return end
    
    local me = entity.get_local_player()
    if not me then return end
    
    local screen = vector(client.screen_size())
    local r, g, b, a = vis_desync_arrows_color:get()
    local distance = vis_desync_arrows_distance:get()
    
    local desync_type = entity.get_prop(me, 'm_flPoseParameter', 11) * 120 - 60
    local desync_side = desync_type > 0 and 1 or -1
    
    if style == "Default" then
        if desync_side == 1 then
            -- Right arrow
            renderer.text(screen.x / 2 + distance, screen.y / 2, r, g, b, a, "cdb", 0, "→")
        else
            -- Left arrow
            renderer.text(screen.x / 2 - distance, screen.y / 2, r, g, b, a, "cdb", 0, "←")
        end
    elseif style == "Lol kek 2018" then
        if desync_side == 1 then
            renderer.text(screen.x / 2 + distance, screen.y / 2, r, g, b, a, "cdb", 0, "RIGHT")
        else
            renderer.text(screen.x / 2 - distance, screen.y / 2, r, g, b, a, "cdb", 0, "LEFT")
        end
    end
end

local custom_scope_alpha = 0

local function paint_custom_scope_overlay()
    if not custom_scope_enabled:get() then
        return
    end

    ui.set(menu_ref.visuals.scope_overlay, false)

    local lp = entity.get_local_player()
    if lp == nil then
        return
    end

    local width, height = client.screen_size()
    local offset, position = custom_scope_offset:get() * height / 1080, custom_scope_position:get() * height / 1080

    local condition = entity.get_prop(lp, 'm_bIsScoped') == 1 and entity.get_prop(lp, 'm_bResumeZoom') == 0
    custom_scope_alpha = motion.interp(custom_scope_alpha, condition and 1 or 0, 0.045)
    if custom_scope_alpha < 0.001 then
        return
    end

    local r, g, b, a = custom_scope_color:get()
    local clr1 = { r, g, b, 0 }
    local clr2 = { r, g, b, a * custom_scope_alpha }
    local mode = custom_scope_mode:get()

    if mode ~= 'T' then
        renderer.gradient(
            width / 2, height / 2 - position + 2,
            1, position - offset,
            clr1[1], clr1[2], clr1[3], clr1[4],
            clr2[1], clr2[2], clr2[3], clr2[4],
            false
        )
    end

    renderer.gradient(
        width / 2, height / 2 + offset,
        1, position - offset,
        clr2[1], clr2[2], clr2[3], clr2[4],
        clr1[1], clr1[2], clr1[3], clr1[4],
        false
    )

    renderer.gradient(
        width / 2 - position + 2, height / 2,
        position - offset, 1,
        clr1[1], clr1[2], clr1[3], clr1[4],
        clr2[1], clr2[2], clr2[3], clr2[4],
        true
    )

    renderer.gradient(
        width / 2 + offset, height / 2,
        position - offset, 1,
        clr2[1], clr2[2], clr2[3], clr2[4],
        clr1[1], clr1[2], clr1[3], clr1[4],
        true
    )
end


-- Acid.lua style hitrate tracking system (exact copy from acid.lua architecture)
local hitrate = {
    total_shots = 0,
    total_hits = 0,
    hitrate_percentage = 0,
    last_reset_time = 0,
    reset_interval = 300000 -- 5 minutes in milliseconds
}

-- Acid.lua style motion interpolation (exact copy)
local motion = {
    interp = function(from, to, speed)
        if from == to then
            return to
        end
        
        local diff = to - from
        local move = diff * speed
        
        if math.abs(diff) < 0.01 then
            return to
        end
        
        return from + move
    end
}

-- Acid.lua Hitrate System (exact copy)
local shots = {
    total = 0,
    hits = 0
}

-- Safe Head System (from acid.lua)
local safe_head = {
    is_active = false,
    enabled = true  -- Always enabled, can be toggled by modifying this
}

local function get_statement(me)
    local flags = entity.get_prop(me, "m_fFlags")
    local is_airborne = bit.band(flags, 1) == 0
    if is_airborne then
        local wpn = entity.get_player_weapon(me)
        if wpn == nil then return end

        local classname = entity.get_classname(wpn)

        if classname == "CKnife" then
            return "Air Knife"
        end

        if classname == "CWeaponTaser" then
            return "Air Zeus"
        end

        if entity.get_prop(me, "m_flDuckAmount") == 1.0 then
            return "Crouched Air"
        end

        return nil
    end

    if entity.get_prop(me, "m_flDuckAmount") > 0.1 then
        return "Crouched"
    end

    local velocity = vector(entity.get_prop(me, "m_vecVelocity"))
    local speed = math.sqrt(velocity.x^2 + velocity.y^2)
    if speed < 8 then
        return "Standing"
    end

    return nil
end

local function extrapolate_entity(ent, pos)
    local tick_interval = globals.tickinterval()
    local velocity = vector(entity.get_prop(ent, "m_vecVelocity"))
    local new_pos = pos:clone()

    local ticks = 25
    if velocity:length() < 32 then
        ticks = 40
    end

    new_pos.x = new_pos.x + velocity.x * tick_interval * ticks
    new_pos.y = new_pos.y + velocity.y * tick_interval * ticks

    if entity.get_prop(ent, "m_hGroundEntity") == nil then
        local sv_gravity = cvar.sv_gravity:get_float()
        new_pos.z = new_pos.z + velocity.z * tick_interval * ticks - sv_gravity * tick_interval * tick_interval
    end

    return new_pos
end

function safe_head.update(e, ctx)
    safe_head.is_active = false

    if not safe_head_enabled:get() then
        return
    end

    local me = entity.get_local_player()
    if me == nil then return end

    local team = entity.get_prop(me, "m_iTeamNum")
    if team == nil then return end

    local wpn = entity.get_player_weapon(me)
    if wpn == nil then return end

    local threat = client.current_threat()
    if threat == nil then return end

    local statement = get_statement(me)
    if statement == nil then return end

    -- Check if the statement is enabled in safe head states
    if not safe_head_states:get(statement) then
        return
    end

    local should_continue = false
    if statement == "Air Zeus" or statement == "Air Knife" then
        should_continue = true
    else
        local eye_pos = extrapolate_entity(threat, vector(entity.hitbox_position(threat, 0)))
        local head_pos = vector(entity.hitbox_position(me, 0))

        eye_pos.z = eye_pos.z + 5

        if head_pos.z > eye_pos.z then
            should_continue = true
        end
    end

    if not should_continue then
        return
    end

    local presets = {
        ["Standing"] = {
            [2] = function(e, ctx, me)
                ctx.yaw_offset = -6
                ctx.body_yaw = "Static"
                ctx.body_yaw_offset = 0
            end,
            [3] = function(e, ctx, me)
                ctx.yaw_offset = 8
                ctx.body_yaw = "Static"
                ctx.body_yaw_offset = 0
            end
        },
        ["Crouched"] = {
            [2] = function(e, ctx, me)
                ctx.yaw_offset = 0
                ctx.body_yaw = "Static"
                ctx.body_yaw_offset = 0
            end,
            [3] = function(e, ctx, me)
                ctx.yaw_offset = 40
                ctx.body_yaw = "Static"
                ctx.body_yaw_offset = 180
            end
        },
        ["Crouched Air"] = {
            [2] = function(e, ctx, me)
                ctx.yaw_offset = 0
                ctx.body_yaw = "Static"
                ctx.body_yaw_offset = -120
            end,
            [3] = function(e, ctx, me)
                ctx.yaw_offset = 0
                ctx.body_yaw = "Static"
                ctx.body_yaw_offset = 120
            end
        },
        ["Air Knife"] = {
            [2] = function(e, ctx, me)
                ctx.yaw_offset = 45
                ctx.body_yaw = "Static"
                ctx.body_yaw_offset = 180
            end,
            [3] = function(e, ctx, me)
                ctx.yaw_offset = 35
                ctx.body_yaw = "Static"
                ctx.body_yaw_offset = 180
            end
        },
        ["Air Zeus"] = {
            [2] = function(e, ctx, me)
                ctx.yaw_offset = 23
                ctx.body_yaw = "Static"
                ctx.body_yaw_offset = 0
            end,
            [3] = function(e, ctx, me)
                ctx.yaw_offset = 10
                ctx.body_yaw = "Static"
                ctx.body_yaw_offset = 0
            end
        }
    }

    local preset = presets[statement]
    if preset == nil then return end

    local fn = preset[team]
    if fn == nil then return end

    ctx.pitch = "Default"
    ctx.yaw_base = "At targets"
    ctx.yaw = "180"
    ctx.yaw_offset = 22
    ctx.yaw_jitter = "Off"
    ctx.body_yaw = "Static"
    ctx.body_yaw_offset = 120
    ctx.freestanding_body_yaw = false

    fn(e, ctx, me)

    safe_head.is_active = true
end

-- LITERAL EMBERLASH ANTI-AIM SYSTEM (EXACT COPY)

-- Add missing math.clamp function
math.clamp = function(value, minimum, maximum)
    if minimum > maximum then 
        minimum, maximum = maximum, minimum 
    end
    return math.max(minimum, math.min(maximum, value))
end

local util = {
    contains = function(self, tbl, val)
        for i = 1, #tbl do
            if tbl[i] == val then
                return true
            end
        end
        return false
    end,
    get_me = function(self)
        return entity.get_local_player()
    end,
    not_me = function(self)
        local me = self.get_me()
        return me == nil or not entity.is_alive(me)
    end,
    in_air = function(self, ent)
        local flags = entity.get_prop(ent, "m_fFlags")
        return bit.band(flags, 1) == 0
    end,
    in_duck = function(self, ent)
        local flags = entity.get_prop(ent, "m_fFlags")
        return bit.band(flags, 4) == 4
    end,
    get_velocity = function(self, ent)
        local wam = entity.get_prop(ent, "m_vecVelocity")
        return vector(wam):length2d()
    end,
    manual = function(self)
        if self:not_me() then
            return
        end
        return 0 -- Simplified for now
    end,
    state = function(self)
        local me = self:get_me()
        local vel = self:get_velocity(me)
        local iair = self:in_air(me)
        local ducking = self:in_duck(me)
        
        if iair then
            return "air"
        elseif vel > 1.5 then
            return "running"
        elseif ducking then
            return "crouch"
        else
            return "stand"
        end
    end,
    normalize_yaw = function(self, yaw)
        yaw = yaw % 360 
        yaw = (yaw + 360) % 360
        if (yaw > 180)  then
            yaw = yaw - 360
        end
        return yaw
    end
}

local antiaim = {
    me = nil,
    manual_side = 0,
    yaw_last = 0,

    get_defensive = function(self, data)
        local trigs = data.trigger or {"Always"}
        local condition = false
        local check_charge = false -- Simplified
        local tick = (data.duration or 1) * 2

        if util:contains(trigs, "Always") then 
            condition = true
        end

        if util:contains(trigs, "On weapon switch") then 
            local nextattack = math.max(entity.get_prop(self.me, 'm_flNextAttack') - globals.curtime(), 0)
            if nextattack / globals.tickinterval() > 2 then
                condition = true
            end
        end

        if globals.tickcount() % 32 <= tick and check_charge then 
            return condition
        end
        
        return condition
    end,

    get_safehead = function(self, taser)
        local target = client.current_threat()

        if target then
            local taser = util:contains({"Taser"}, "Taser") -- Simplified
            local knife = util:contains({"Knife"}, "Knife") -- Simplified
            local weapon = entity.get_player_weapon(self.me)
            if util:in_air(self.me) and weapon and (knife and entity.get_classname(weapon):find('Knife') or (taser and entity.get_classname(weapon):find('Taser'))) then 
                return true
            end
        end
        
        return false
    end,

    get_backstab = function(self)
        local target = client.current_threat()

        if util:not_me() or not target then 
            return false 
        end

        local weapon_ent = entity.get_player_weapon(target)
        if not weapon_ent then return false end
        local weapon_name = entity.get_classname(weapon_ent)
        if not weapon_name:find('Knife') then return false end
        local origin = {vector(entity.get_origin(self.me)), vector(entity.get_origin(target))}

        return origin[2]:dist2d(origin[1]) < 230 -- #дистанция #2метра #коронавирус
    end,

    side = 0,
    cycle = 0,
    ways = {
        curr = 0,
        deg = 0,
    },
    yaw = { 
        freeze = 0,
        random = 0,
        skit = 0,
    }, 
    def = {
        yaw = {spin=0,side=0,sway=0},
        pitch = {spin=0,side=0,sway=0}
    },

    modifier = function(self, data, type, is_delayed, general_yaw)
        local to_return = 0
        local current_side = self.side

        if type == "Offset" then
            if current_side == 1 then
                to_return = general_yaw
            end
        elseif type == "Center" then
            to_return = (current_side == 1 and -general_yaw or general_yaw)
        elseif type == "Ground-Based" then
            local sequence = {0, 2, 1}

            local next_side

            if self.yaw.skit == #sequence then
                self.yaw.skit = 1
            elseif not is_delayed then
                self.yaw.skit = self.yaw.skit + 1
            end
            
            next_side = sequence[self.yaw.skit]

            if next_side == 0 then
                to_return = to_return - math.abs(general_yaw)
            elseif next_side == 1 then
                to_return = to_return + math.abs(general_yaw)
            end
        elseif type == "Random" then 
            local rand = (math.random(0, general_yaw*2) - general_yaw)
            if not is_delayed then
                to_return = to_return + rand

                self.yaw.random = rand
            else
                to_return = to_return + self.yaw.random
            end
        elseif type == "X-way" then
            if not is_delayed then 
                self.ways.curr = self.ways.curr + 1 
                if self.ways.curr > (data.way_value or 3) then
                    self.ways.curr = 1 
                end 
            else
                to_return = to_return + self.ways.deg
            end

            self.ways.deg = data["way_"..self.ways.curr] or 0
            to_return = self.ways.deg
        end
        
        return to_return
    end,

    set = function(self, cmd, data, data_defs) 
        local safe_head = false
        local manual = util:manual()
        local current_side = self.side

        local freeze_value = data.delay_value_freze or 0
        local freeze_delay = (data.freeze_ms or 100) / 10

        if ((globals.tickcount() % (freeze_delay*2))+1 <= freeze_delay and -1 or 1) == 1 then 
            self.yaw.freeze = math.random(0, (data.freeze_random or 100)/10)
        end

        local freeze = freeze_value + self.yaw.freeze/2

        local yaw_delay = math.clamp((data.delay_adds == "Randomize Delay Ticks" and data.delay_value + math.random(-(data.delay_random or 0), data.delay_random or 0)) or freeze, 0, 32)
        local is_delayed = true

        if data.delay_adds == "-" then
            yaw_delay = data.delay_value_freze or 0
        end

        if globals.chokedcommands() == 0 and self.cycle == yaw_delay then
            current_side = current_side == 1 and 0 or 1
            is_delayed = false
        end

        local pitch = 90
        local yaw_offset = 0
        local general_yaw = (data.lryaw and data.yaw_value or data.lyaw or 58) + math.random(-(data.yaw_random or 0), data.yaw_random or 0)
        local body_yaw = data.body_yaw or "Static"
        local bodyy

        if body_yaw == "Off" then
            bodyy = "Off"
        elseif body_yaw == "Opposite" then
            bodyy = "Opposite"
        else
            if body_yaw ~= "Jitter" then 
                if data.body_yaw_static == "Left" then 
                    current_side = 1
                else
                    current_side = 0
                end
            end
            bodyy = "Static"
        end

        yaw_offset = self:modifier(data, data.yaw or "Offset", is_delayed, general_yaw)

        local defensive_value = 0
        if self:get_defensive(data_defs or {}) then 
            cmd.force_defensive = true
            defensive_value = 1
        end

        local add_left = (data.lyaw or 58) + (math.random(-(data.lyaw_random or 0), data.lyaw_random or 0))
        local add_right = (data.ryaw or 58) + (math.random(-(data.ryaw_random or 0), data.ryaw_random or 0))

        yaw_offset = yaw_offset + (data.lryaw and (current_side == 0 and add_right or (current_side == 1 and add_left or 0)) or 0)

        local body_yaw_angle = (current_side == 2) and 0 or (current_side == 1 and -(data.body_value or 0) or (data.body_value or 0))

        -- EMBERLASH ANTI BACKSTAB
        if avoid_backstab_enabled:get() and self:get_backstab() then 
            yaw_offset = yaw_offset + 180
        end

        -- EMBERLASH SAFE HEAD
        if safe_head_enabled:get() and self:get_safehead() then
            safe_head = true
            yaw_offset = 0
            pitch = 90
            body_yaw_angle = 0
            current_side = 2
        end

        if manual and manual ~= 0 then
            yaw_offset = yaw_offset + manual
        end

        -- Apply anti-aim
        cmd.pitch = math.clamp(type(pitch) == "number" and pitch or 0, -89, 89)
        cmd.yaw = util:normalize_yaw(yaw_offset)
        self.yaw_last = util:normalize_yaw(yaw_offset)

        if globals.chokedcommands() == 0 then
            if self.cycle >= yaw_delay then
                self.cycle = 1
            else
                self.cycle = self.cycle + 1
            end
        end
        self.side = current_side
    end,

    complete = function(self, cmd, state)
        local data = {
            delay_value_freze = 0,
            freeze_ms = 100,
            freeze_random = 100,
            delay_adds = "-",
            delay_value = 0,
            delay_random = 0,
            lryaw = false,
            yaw_value = 58,
            lyaw = 58,
            ryaw = 58,
            yaw_random = 0,
            lyaw_random = 0,
            ryaw_random = 0,
            body_yaw = "Static",
            body_yaw_static = "Left",
            body_value = 0,
            yaw = "Offset",
            way_value = 3
        }
        
        local data_defs = {
            active = false
        }

        self:set(cmd, data, data_defs)
    end,

    run = function(self, cmd)
        self.me = util.get_me()

        if util:not_me() then
            return 
        end

        local state = util:state()

        self:complete(cmd, state)
    end
}

-- EMBERLASH BACKSTAB TRANSFERRED TO MESSAGE11.LUA
local avoid_backstab = {
    is_active = false,
    me = nil
}

function avoid_backstab.get_backstab()
    local target = client.current_threat()

    if util:not_me() or not target then 
        return false 
    end

    local weapon_ent = entity.get_player_weapon(target)
    if not weapon_ent then return false end
    local weapon_name = entity.get_classname(weapon_ent)
    if not weapon_name or not weapon_name:find('Knife') then return false end
    local origin = {vector(entity.get_origin(avoid_backstab.me)), vector(entity.get_origin(target))}

    return origin[2]:dist2d(origin[1]) < 230 -- #дистанция #2метра #коронавирус
end

function avoid_backstab.update(ctx)
    avoid_backstab.is_active = false
    
    if not avoid_backstab_enabled:get() then
        return
    end
    
    avoid_backstab.me = entity.get_local_player()
    
    if avoid_backstab.get_backstab() then
        -- EmBeRlaS exact implementation: yaw_offset = yaw_offset + 180
        if ctx.yaw_offset == nil then
            ctx.yaw_offset = 0
        end
        ctx.yaw_offset = ctx.yaw_offset + 180
        avoid_backstab.is_active = true
    end
end

-- Acid.lua hitrate tracking (exact copy)
client.set_event_callback('aim_fire', function (shot)
    shots.total = shots.total + 1
end)

client.set_event_callback('aim_hit', function (shot)
    shots.hits = shots.hits + 1
end)

client.set_event_callback('player_connect_full', function (e)
    if client.userid_to_entindex(e['userid']) ~= entity.get_local_player() then
        return
    end
    
    shots.hits = 0
    shots.total = 0
end)

function hitrate.frame()
    if not hitrate_enabled:get() then
        return
    end

    local lp = entity.get_local_player()
    if lp == nil then
        return
    end

    local hit_rate = shots.total ~= 0 and (shots.hits / shots.total * 100) or 100
    local r, g, b = hitrate_color:get()
    
    -- Clean hitrate display without symbol
    renderer.indicator(r, g, b, 255, string.format('%d%%', hit_rate))
end


-- hitlogs
local hitgroup_names = {"generic", "head", "chest", "stomach", "left arm", "right arm", "left leg", "right leg", "neck", "?", "gear"}
local hitlog = {}
local id = 1

local function aim_hit(e)
    local group = hitgroup_names[e.hitgroup + 1] or "?"


    if hitlogs_select:get("On Console") then
        print(string.format(
            "Hit %s in the %s for %d damage (%d health remaining)",
            entity.get_player_name(e.target), group, e.damage,
            entity.get_prop(e.target, "m_iHealth")
        ))
    end

    if hitlogs_select:get("On Screen") then
        hitlog[#hitlog+1] = {("Hit \aADD8E6FF@"..entity.get_player_name(e.target).."\aFFFFFFFF to \aADD8E6FF"..group.."\aFFFFFFFF for \aADD8E6FF"..e.damage.."\aFFFFFFFF damage (\aADD8E6FF"..entity.get_prop(e.target, "m_iHealth").."\aFFFFFFFF health remaining)"), globals.tickcount() + 250, 0}
    end
end

local function aim_miss(e)
    local group = hitgroup_names[e.hitgroup + 1] or "?"

    -- Safe Head integration
    safe_head.update(e, e)

    if misslogs_select:get("On Console") then
        print(string.format(
            "Missed %s (%s) due to %s",
            entity.get_player_name(e.target), group, e.reason
        ))
    end

    if misslogs_select:get("On Screen") then
        hitlog[#hitlog+1] = {("Missed shot \aADD8E6FF@"..entity.get_player_name(e.target).."\aFFFFFFFF to \aADD8E6FF"..group.."\aFFFFFFFF because \aADD8E6FF"..e.reason), globals.tickcount() + 250, 0}
    end

end

local function paint_hitlog()
    local screen = vector(client.screen_size())
    if #hitlog > 0 then
        if globals.tickcount() >= hitlog[1][2] then
            if hitlog[1][3] > 0 then
                hitlog[1][3] = hitlog[1][3] - 20
            elseif hitlog[1][3] <= 0 then
                table.remove(hitlog, 1)
            end
        end
        if #hitlog > 6 then
            table.remove(hitlog, 1)
        end
        if globals.is_connected == false then
            table.remove(hitlog, #hitlog)
        end
        for i = 1, #hitlog do
            text_size = renderer.measure_text("b", hitlog[i][1])
           if hitlog[i][3] < 255 then 
                hitlog[i][3] = hitlog[i][3] + 10 
            end
            renderer.text(screen.x/2 - text_size/2 + (hitlog[i][3]/35), screen.y/1.3 + 13 * i, 255, 255, 255, 230, "", 0, hitlog[i][1])
		end
    end
end

-- Old animation breaker system removed - replaced with Emberlash V2 implementation

local tt_sel = {
    sound_cloud = {
        "This 1 tap is sponsored by Krim, dont cry",
        "You just got deleted, thank Krim for that.",
        "One shot, one tap, one Krim moment.",
        "Dont hate me, hate Krim for making it look easy",
        "Stay mad, its just Krim making me better.",
        "This 1 tap is sponsored by Krim, dont cry",
        "You just got deleted, thank Krim for that"
    },
    default = {
        "One shot, one tap, one Krim moment",
        "Dont hate me, hate Krim for making it look easy",
        "Stay mad, its just Krim making me better",
        "This 1 tap is sponsored by Krim, dont cry",
        "You just got deleted, thank Krim for that",
        "by krim"
    }
}

local userid_to_entindex, get_local_player, is_enemy, console_cmd = client.userid_to_entindex, entity.get_local_player, entity.is_enemy, client.exec

local function on_trashtalk(e)
    if not trash_talk_enable:get() then return end
    local victim_userid, attacker_userid = e.userid, e.attacker
    if victim_userid == nil or attacker_userid == nil then
        return
    end
    local victim_entindex = userid_to_entindex(victim_userid)
    local attacker_entindex = userid_to_entindex(attacker_userid)
    if attacker_entindex == get_local_player() and is_enemy(victim_entindex) then
        client.delay_call(0.2, function() console_cmd("say ", tt_sel.sound_cloud[math.random(1, #tt_sel.sound_cloud)]) end)
    end
end

-- confg
local config_items = {aa_sys}

local package, data, encrypted, decrypted = pui.setup(config_items), "", "", ""
config.export = function()
    data = package:save()
    encrypted = json.stringify(data)
    clipboard.set(encrypted)
    print("\aADD8E6FFExported")
end
config.import = function(input)
    decrypted = json.parse(input ~= nil and input or clipboard.get())
    package:load(decrypted)
    print("\aADD8E6FFImported")
end


-- ACID.LUA CONFIG SYSTEM
local acid_config_system = {}

local function resolve_item_export(item)
    if not item.saveable then
        return
    end

    if ui.type(item.ref) == "label" or ui.type(item.ref) == "hotkey" then
        return
    end

    return item.value
end

local function resolve_item_import(item, data)
    if ui.type(item.ref) == "label" or ui.type(item.ref) == "hotkey" then
        return true
    end

    if not item.saveable then
        return true
    end

    if data == nil then
        return false
    end

    item:set(unpack(data))
    return true
end

function acid_config_system.export_to_str()
    local config_result = {}

    for _, item in ipairs(ui.get_items()) do
        config_result[item.name] = resolve_item_export(item)
    end

    return base64.encode(json.stringify(config_result)) .. '_acid'
end

function acid_config_system.import_from_str(str)
    str = str:gsub('_acid', '')
    local status, config = pcall(base64.decode, str)
    if not status then
        print("Failed to decode config")
        return
    end

    status, config = pcall(json.parse, config)
    if not status then
        print("Failed to parse config")
        return
    end

    for _, item in ipairs(ui.get_items()) do
        local imported = resolve_item_import(item, config[item.name])
        if not imported then
            -- Item not found or failed to import
        end
    end
end

-- Config system initialized

client.set_event_callback("setup_command", function(cmd)
    -- RESTORE ANTI-AIM BUILDER
    setup_builder(cmd)
    
    -- Apply avoid backstab if enabled (only if safe head is not active)
    if not safe_head.is_active and avoid_backstab_enabled:get() then
        local me = entity.get_local_player()
        if me and entity.is_alive(me) then
            local target = client.current_threat()
            if target then
                local weapon_ent = entity.get_player_weapon(target)
                if weapon_ent then
                    local weapon_name = entity.get_classname(weapon_ent)
                    if weapon_name:find('Knife') then
                        local my_origin = vector(entity.get_origin(me))
                        local target_origin = vector(entity.get_origin(target))
                        local distance = my_origin:dist2d(target_origin)
                        
                        if distance < 230 then
                            -- Calculate angle to face the target
                            local dx = target_origin.x - my_origin.x
                            local dy = target_origin.y - my_origin.y
                            local angle_to_target = math.deg(math.atan2(dy, dx))
                            
                            -- Set yaw to face the target
                            cmd.yaw = angle_to_target
                            ui.set(menu_ref.antiaim.yaw[2], 0)    -- No offset when facing target
                        end
                    end
                end
            end
        end
    end
end)

client.set_event_callback('paint_ui', function()
    hide_original_menu(false)
    create_lua_name()
    -- Enable scope overlay removal when custom scope is enabled
    if custom_scope_enabled:get() then
        ui.set(menu_ref.visuals.scope_overlay, true)
    end
end)

client.set_event_callback('paint', function(ctx)
    paint_ui()
    paint_hitlog()
    watermark_render()
    paint_desync_arrows()
    paint_damage_indicator(ctx)
    paint_custom_scope_overlay()
    hitrate.frame()
    if clantag_enable:get() then krim_clantag.handle() end
    
end)

-- Old animation breaker event callbacks removed - replaced with Emberlash V2 implementation

client.set_event_callback('shutdown', function()
    hide_original_menu(true)
    krim_clantag.set("")
    -- Reset scope overlay to default state
    ui.set_visible(menu_ref.visuals.scope_overlay, true)
end)

client.set_event_callback("aim_hit", aim_hit)
client.set_event_callback("aim_miss", aim_miss)
client.set_event_callback("player_death", on_trashtalk)

-- Safe Head functionality from acid.lua
local safe_head = {
    is_active = false
}

-- Safe Head presets from acid.lua
local safe_head_presets = {
    ["Standing"] = {
        [2] = function(e, ctx, me) -- CT
            ctx.yaw_offset = -6
            ctx.body_yaw = "Static"
            ctx.body_yaw_offset = 0
        end,
        [3] = function(e, ctx, me) -- T
            ctx.yaw_offset = 8
            ctx.body_yaw = "Static"
            ctx.body_yaw_offset = 0
        end
    },
    ["Crouched"] = {
        [2] = function(e, ctx, me) -- CT
            ctx.yaw_offset = 0
            ctx.body_yaw = "Static"
            ctx.body_yaw_offset = 0
        end,
        [3] = function(e, ctx, me) -- T
            ctx.yaw_offset = 40
            ctx.body_yaw = "Static"
            ctx.body_yaw_offset = 180
        end
    },
    ["Crouched Air"] = {
        [2] = function(e, ctx, me) -- CT
            ctx.yaw_offset = 0
            ctx.body_yaw = "Static"
            ctx.body_yaw_offset = -120
        end,
        [3] = function(e, ctx, me) -- T
            ctx.yaw_offset = 0
            ctx.body_yaw = "Static"
            ctx.body_yaw_offset = 120
        end
    },
    ["Air Knife"] = {
        [2] = function(e, ctx, me) -- CT
            ctx.yaw_offset = 45
            ctx.body_yaw = "Static"
            ctx.body_yaw_offset = 180
        end,
        [3] = function(e, ctx, me) -- T
            ctx.yaw_offset = 35
            ctx.body_yaw = "Static"
            ctx.body_yaw_offset = 180
        end
    },
    ["Air Zeus"] = {
        [2] = function(e, ctx, me) -- CT
            ctx.yaw_offset = 23
            ctx.body_yaw = "Static"
            ctx.body_yaw_offset = 0
        end,
        [3] = function(e, ctx, me) -- T
            ctx.yaw_offset = 10
            ctx.body_yaw = "Static"
            ctx.body_yaw_offset = 0
        end
    }
}

-- Get player state function from acid.lua
local function get_statement(me)
    if entity.is_airborne(me) then
    local wpn = entity.get_player_weapon(me)
    if wpn == nil then return nil end

    local classname = entity.get_classname(wpn)
    if classname == nil then return nil end

    if classname == "CKnife" then
        return "Air Knife"
    end

    if classname == "CWeaponTaser" then
        return "Air Zeus"
    end

        if entity.get_prop(me, "m_flDuckAmount") == 1.0 then
            return "Crouched Air"
        end

        return nil
    end

    if entity.is_crouched(me) then
        return "Crouched"
    end

    local velocity = entity.get_prop(me, "m_vecVelocity")
    local speed = math.sqrt(velocity.x^2 + velocity.y^2)
    
    if speed < 5 then
        return "Standing"
    end

    return nil
end

-- Extrapolate entity function from acid.lua
local function extrapolate_entity(ent, pos)
    local tick_interval = globals.tickinterval()
    local velocity = vector(entity.get_prop(ent, "m_vecVelocity"))
    local new_pos = pos:clone()

    local ticks = 25
    if #velocity < 32 then
        ticks = 40
    end

    new_pos.x = new_pos.x + velocity.x * tick_interval * ticks
    new_pos.y = new_pos.y + velocity.y * tick_interval * ticks

    if entity.get_prop(ent, "m_hGroundEntity") == nil then
        new_pos.z = new_pos.z + velocity.z * tick_interval * ticks - 800 * tick_interval -- sv_gravity
    end

    return new_pos
end

-- Safe Head update function from acid.lua
function safe_head.update(e, ctx)
    safe_head.is_active = false

    if not safe_head_enabled:get() then
        return
    end

    local me = entity.get_local_player()
    if not me then return end

    local team = entity.get_prop(me, "m_iTeamNum")
    if team == nil then return end

    local wpn = entity.get_player_weapon(me)
    if wpn == nil then return end

    local threat = client.current_threat()
    if threat == nil then return end

    local statement = get_statement(me)
    if statement == nil then return end

    -- Check if this state is enabled in the multiselect
    local enabled_states = safe_head_states:get()
    local state_enabled = false
    for i, state in ipairs(enabled_states) do
        if state == statement then
            state_enabled = true
            break
        end
    end

    if not state_enabled then return end

    local should_continue = false
    if statement == "Air Zeus" or statement == "Air Knife" then
        should_continue = true
    else
        local eye_pos = extrapolate_entity(threat, vector(entity.hitbox_position(threat, 0)))
        local head_pos = vector(entity.hitbox_position(me, 0))

        eye_pos.z = eye_pos.z + 5

        if head_pos.z > eye_pos.z then
            local entindex, damage = client.trace_bullet(threat, eye_pos.x, eye_pos.y, eye_pos.z, head_pos.x, head_pos.y, head_pos.z + 6, threat)
            should_continue = damage > 0
        end
    end

    if not should_continue then return end

    local preset = safe_head_presets[statement]
    if preset == nil then return end

    local fn = preset[team]
    if fn == nil then return end

    ctx.pitch = "Default"
    ctx.yaw_base = "At targets"
    ctx.yaw = "180"
    ctx.yaw_offset = 22
    ctx.yaw_jitter = "Off"
    ctx.body_yaw = "Static"
    ctx.body_yaw_offset = 120
    ctx.freestanding_body_yaw = false

    fn(e, ctx, me)
    safe_head.is_active = true
end

-- Anti-aimbot angles callback for avoid backstab and safe head
client.set_event_callback("antiaim_angles", function(ctx)
    -- Apply safe head first (higher priority)
    safe_head.update(e, ctx)
    
    -- Apply avoid backstab if safe head is not active
    if not safe_head.is_active and avoid_backstab_enabled:get() then
        local target = client.current_threat()
        if target then
            local weapon_ent = entity.get_player_weapon(target)
            if weapon_ent then
                local weapon_name = entity.get_classname(weapon_ent)
                if weapon_name:find('Knife') then
                    local me = entity.get_local_player()
                    if me then
                        local my_origin = vector(entity.get_origin(me))
                        local target_origin = vector(entity.get_origin(target))
                        local distance = my_origin:dist2d(target_origin)
                        
                        if distance < 230 then
                            if ctx.yaw_offset == nil then
                                ctx.yaw_offset = 0
                            end
                            ctx.yaw_offset = ctx.yaw_offset + 180
                        end
                    end
                end
            end
        end
    end
end)

-- Ragebot Prediction System (from invictus.lua)
local ragebot_active = false
local prediction_records = {}

-- Defensive Anti-Aim System (from zov.lua)
local defensive_aa_active = false
local checked_ticks = 0

-- Defensive anti-aim detection function
local function is_defensive(player_index)
    checked_ticks = math.max(entity.get_prop(player_index, 'm_nTickBase'), checked_ticks or 0)
    return math.abs(entity.get_prop(player_index, 'm_nTickBase') - checked_ticks) > 2 and 
           math.abs(entity.get_prop(player_index, 'm_nTickBase') - checked_ticks) < 14
end

-- Helper functions for prediction system
local function to_ticks(time) 
    return math.floor(time / globals.tickinterval() + 0.5) 
end

local function get_velocity(player)
    local velocity = vector(entity.get_prop(player, "m_vecVelocity"))
    return math.sqrt(velocity.x^2 + velocity.y^2)
end

-- Advanced Prediction Fix (Enhanced from invictus.lua)
local function prediction_fix()
    if not prediction_enabled:get() or not ragebot_active then return end

    local local_player = entity.get_local_player()
    if not local_player or not entity.is_alive(local_player) then return end

    local target = client.current_threat()
    if not target or not entity.is_alive(target) or entity.is_dormant(target) then return end

    local x, y, z = entity.get_prop(target, "m_vecOrigin")
    if not x or not y or not z then return end
    
    local velocity = get_velocity(target)
    if velocity < prediction_min_velocity:get() then return end

    local velocity_vec = vector(entity.get_prop(target, "m_vecVelocity"))
    
    -- Enhanced prediction with multiple tick prediction
    local prediction_ticks_count = prediction_ticks:get() -- Use UI setting
    local tick_interval = globals.tickinterval()
    
    -- Calculate predicted position with acceleration
    local predicted_x = x
    local predicted_y = y
    local predicted_z = z
    
    -- Store previous velocity for acceleration calculation
    local prev_velocity = prediction_records[target] and prediction_records[target].velocity
    local acceleration = vector(0, 0, 0)
    
    if prev_velocity and prediction_acceleration:get() then
        acceleration.x = (velocity_vec.x - prev_velocity.x) / tick_interval
        acceleration.y = (velocity_vec.y - prev_velocity.y) / tick_interval
        acceleration.z = (velocity_vec.z - prev_velocity.z) / tick_interval
    end
    
    -- Predict position with acceleration
    for i = 1, prediction_ticks_count do
        local time = i * tick_interval
        if prediction_acceleration:get() then
            predicted_x = predicted_x + velocity_vec.x * tick_interval + 0.5 * acceleration.x * time^2
            predicted_y = predicted_y + velocity_vec.y * tick_interval + 0.5 * acceleration.y * time^2
            predicted_z = predicted_z + velocity_vec.z * tick_interval + 0.5 * acceleration.z * time^2
        else
            predicted_x = predicted_x + velocity_vec.x * tick_interval
            predicted_y = predicted_y + velocity_vec.y * tick_interval
            predicted_z = predicted_z + velocity_vec.z * tick_interval
        end
    end
    
    -- Apply smoothing
    local frame_count = globals.framecount()
    local smoothing_factor = prediction_smoothing:get() / 100
    local smoothing = smoothing_factor / frame_count

    local smoothed_position = vector(x, y, z)
    smoothed_position.x = smoothed_position.x + (predicted_x - smoothed_position.x) * smoothing
    smoothed_position.y = smoothed_position.y + (predicted_y - smoothed_position.y) * smoothing
    smoothed_position.z = smoothed_position.z + (predicted_z - smoothed_position.z) * smoothing

    -- Store current velocity for next frame
    if not prediction_records[target] then
        prediction_records[target] = {}
    end
    prediction_records[target].velocity = velocity_vec

    if prediction_visualize:get() then
        local r, g, b, a = 255, 0, 0, 200
        local screen_x, screen_y = renderer.world_to_screen(x, y, z)
        local target_x, target_y = renderer.world_to_screen(smoothed_position.x, smoothed_position.y, smoothed_position.z)

        if screen_x and screen_y and target_x and target_y then
            -- Draw prediction line
            renderer.line(screen_x, screen_y, target_x, target_y, r, g, b, a)
            
            -- Draw prediction circle
            renderer.circle_outline(target_x, target_y, r, g, b, a, 8, 0, 1, 2)
            
            -- Draw velocity indicator
            local vel_screen_x, vel_screen_y = renderer.world_to_screen(x + velocity_vec.x * 0.1, y + velocity_vec.y * 0.1, z)
            if vel_screen_x and vel_screen_y then
                renderer.line(screen_x, screen_y, vel_screen_x, vel_screen_y, 0, 255, 0, 150)
            end
        end
    end
end

-- Advanced Anti-Aim Functions (Enhanced from invictus.lua)
local antiaim_funcs = {}

-- Get animation state for player
function antiaim_funcs.get_animstate(player)
    if not player or not entity.is_alive(player) then return nil end
    local animstate_ptr = entity.get_prop(player, "m_flAnimTime")
    if not animstate_ptr then return nil end
    
    -- Return a mock animstate structure for desync calculation
    return {
        eye_angles_y = select(2, entity.get_prop(player, "m_angEyeAngles")),
        eye_angles_x = select(1, entity.get_prop(player, "m_angEyeAngles")),
        goal_feet_yaw = entity.get_prop(player, "m_flLowerBodyYawTarget"),
        current_feet_yaw = entity.get_prop(player, "m_flLowerBodyYawTarget"),
        torso_yaw = entity.get_prop(player, "m_flLowerBodyYawTarget"),
        lean_amount = 0,
        duck_amount = entity.get_prop(player, "m_flDuckAmount") or 0,
        on_ground = bit.band(entity.get_prop(player, "m_fFlags"), 1) == 1,
        velocity_x = select(1, entity.get_prop(player, "m_vecVelocity")),
        velocity_y = select(2, entity.get_prop(player, "m_vecVelocity"))
    }
end

-- Calculate maximum desync for player
function antiaim_funcs.get_max_desync(animstate)
    if not animstate then return 58 end -- Default desync
    
    local max_desync = 58 -- Base desync
    
    -- Adjust desync based on player state
    if animstate.duck_amount and animstate.duck_amount > 0.1 then
        max_desync = max_desync * 0.8 -- Reduce desync when ducking
    end
    
    if animstate.on_ground then
        local velocity = math.sqrt(animstate.velocity_x^2 + animstate.velocity_y^2)
        if velocity > 100 then
            max_desync = max_desync * 1.2 -- Increase desync when moving fast
        end
    else
        max_desync = max_desync * 0.6 -- Reduce desync in air
    end
    
    return math.min(max_desync, 60) -- Cap at 60 degrees
end

-- Advanced Resolver (Enhanced from invictus.lua)
local function resolver()
    if not resolver_enabled:get() or not ragebot_active then return end
    if not entity.is_alive(entity.get_local_player()) then return end

    client.update_player_list()
    for _, player in pairs(entity.get_players(true)) do
        local simtime, old_simtime = entity.get_prop(player, "m_flSimulationTime"), entity.get_prop(player, "m_flOldSimulationTime")
        if not simtime or not old_simtime then return end
        
        simtime, old_simtime = to_ticks(simtime), to_ticks(old_simtime)
        prediction_records[player] = prediction_records[player] or {}
        
        -- Get enhanced player data
        local animstate = antiaim_funcs.get_animstate(player)
        local max_desync = antiaim_funcs.get_max_desync(animstate)
        
        prediction_records[player][simtime] = {
            eye = select(2, entity.get_prop(player, "m_angEyeAngles")),
            lby = entity.get_prop(player, "m_flLowerBodyYawTarget"),
            desync = max_desync,
            animstate = animstate,
            velocity = vector(entity.get_prop(player, "m_vecVelocity")),
            origin = vector(entity.get_prop(player, "m_vecOrigin"))
        }
        
        if prediction_records[player][old_simtime] and prediction_records[player][simtime] then
            local current_record = prediction_records[player][simtime]
            local old_record = prediction_records[player][old_simtime]
            
            local max_desync = current_record.desync
            local eye_yaw = current_record.eye

            -- Advanced Fake Yaw Prediction
            local fake_yaw = eye_yaw + max_desync
            
            -- Check for desync side changes
            if math.abs(fake_yaw - old_record.eye) > max_desync then
                fake_yaw = eye_yaw - max_desync
            end
            
            -- Velocity-based desync prediction
            if current_record.velocity and old_record.velocity then
                local velocity_diff = current_record.velocity:dist2d(old_record.velocity)
                if velocity_diff > 50 then -- Significant velocity change
                    -- Adjust fake yaw based on movement direction
                    local movement_angle = math.atan2(current_record.velocity.y, current_record.velocity.x)
                    fake_yaw = fake_yaw + (movement_angle * 0.1) -- Small adjustment
                end
            end
            
            -- Apply resolver settings (using plist.set like original invictus.lua)
            if resolver_force_body_yaw:get() then
                -- Try to use plist.set if available
                local success = pcall(function()
                    plist.set(player, "Force body yaw", fake_yaw)
                    plist.set(player, "Force body yaw value", fake_yaw)
                end)
                
                -- Silent operation - no debug output
            end
            
            if resolver_correction_active:get() then
                local success = pcall(function()
                    plist.set(player, "Correction active", true)
                end)
                
                -- Silent operation - no debug output
            end
        end
    end
end

-- Event callbacks for ragebot system
client.set_event_callback("net_update_end", function()
    if resolver_enabled:get() and ragebot_active then
        resolver()
    end
    
    -- Update defensive anti-aim state
    local me = entity.get_local_player()
    if me and entity.is_alive(me) then
        defensive_aa_active = is_defensive(me)
    end
end)

client.set_event_callback("paint", function()
    if prediction_enabled:get() and ragebot_active then
        prediction_fix()
    end
end)

-- Ragebot activation system
client.set_event_callback("setup_command", function(cmd)
    if ragebot_activation_key:get() then
        ragebot_active = true
    else
        ragebot_active = false
    end
    
    local me = entity.get_local_player()
    if me and entity.is_alive(me) then
        defensive_aa_active = is_defensive(me)
        
        -- Determine actual player state for defensive AA
        local state_id = 1 -- Default to Global
        
        -- Check actual player state
        local velocity = vector(entity.get_prop(me, "m_vecVelocity"))
        local speed = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
        local flags = entity.get_prop(me, "m_fFlags")
        local duck_amount = entity.get_prop(me, "m_flDuckAmount")
        
        if bit.band(flags, 1) == 0 then -- In air
            if duck_amount > 0.1 then
                state_id = 6 -- Air+
            else
                state_id = 5 -- Air
            end
        elseif duck_amount > 0.1 then -- Ducking
            if speed > 5 then
                state_id = 7 -- Duck
            else
                state_id = 7 -- Duck
            end
        elseif speed < 5 then -- Standing
            state_id = 2 -- Stand
        elseif speed < 100 then -- Walking
            state_id = 3 -- Walking
        else -- Running
            state_id = 4 -- Running
        end
        
        -- Apply defensive anti-aim for the actual player state
        if ui.get(defensive_aa_settings[state_id].defensive_anti_aimbot) then
            
            -- Defensive Pitch
            if ui.get(defensive_aa_settings[state_id].defensive_pitch) then
                ui.set(menu_ref.antiaim.pitch[1], ui.get(defensive_aa_settings[state_id].defensive_pitch1))
                
                if ui.get(defensive_aa_settings[state_id].defensive_pitch1) == 'Random' then
                    ui.set(menu_ref.antiaim.pitch[1], 'Custom')
                    ui.set(menu_ref.antiaim.pitch[2], math.random(ui.get(defensive_aa_settings[state_id].defensive_pitch2), ui.get(defensive_aa_settings[state_id].defensive_pitch3)))
                else
                    ui.set(menu_ref.antiaim.pitch[2], ui.get(defensive_aa_settings[state_id].defensive_pitch2))
                end
            end
            
            -- Defensive Yaw
            if ui.get(defensive_aa_settings[state_id].defensive_yaw) then
                ui.set(menu_ref.antiaim.yaw_jitter[1], 'Off')
                ui.set(menu_ref.antiaim.body_yaw[1], 'Opposite')
                
                if ui.get(defensive_aa_settings[state_id].defensive_yaw1) == '180' then
                    ui.set(menu_ref.antiaim.yaw[1], '180')
                    ui.set(menu_ref.antiaim.yaw[2], ui.get(defensive_aa_settings[state_id].defensive_yaw2))
                elseif ui.get(defensive_aa_settings[state_id].defensive_yaw1) == 'Spin' then
                    ui.set(menu_ref.antiaim.yaw[1], 'Spin')
                    ui.set(menu_ref.antiaim.yaw[2], ui.get(defensive_aa_settings[state_id].defensive_yaw2))
                elseif ui.get(defensive_aa_settings[state_id].defensive_yaw1) == '180 Z' then
                    ui.set(menu_ref.antiaim.yaw[1], '180 Z')
                    ui.set(menu_ref.antiaim.yaw[2], ui.get(defensive_aa_settings[state_id].defensive_yaw2))
                elseif ui.get(defensive_aa_settings[state_id].defensive_yaw1) == 'Sideways' then
                    ui.set(menu_ref.antiaim.yaw[1], '180')
                    if cmd.command_number % 4 >= 2 then
                        ui.set(menu_ref.antiaim.yaw[2], math.random(85, 100))
                    else
                        ui.set(menu_ref.antiaim.yaw[2], math.random(-100, -85))
                    end
                elseif ui.get(defensive_aa_settings[state_id].defensive_yaw1) == 'Random' then
                    ui.set(menu_ref.antiaim.yaw[1], '180')
                    ui.set(menu_ref.antiaim.yaw[2], math.random(-180, 180))
                end
            end
        end
    end
end)


-- Emberlash V2 Animation Breaker Implementation
local animations do
    local native_GetClientEntity = vtable_bind('client.dll', 'VClientEntityList003', 3, 'void*(__thiscall*)(void*, int)')
    local char_ptr = ffi.typeof('char*')
    local nullptr = ffi.new('void*')
    local class_ptr = ffi.typeof('void***')
    local animation_layer_t = ffi.typeof([[struct { char pad0[0x18]; uint32_t sequence; float prev_cycle, weight, weight_delta_rate, playback_rate, cycle; void *entity; char pad1[0x4]; } **]])

    local command_number = 0
    local function on_run_command (e)
        command_number = e.command_number
    end

    client.set_event_callback('run_command', on_run_command)

    local function on_pre_render ()
        if not animation_breaker_enable:get() then
            return
        end
        
        local me = entity.get_local_player()
        if not me or not entity.is_alive(me) then 
            return 
        end
    
        local player_ptr = ffi.cast(class_ptr, native_GetClientEntity(me))
        if player_ptr == nullptr then 
            return 
        end
    
        local first_velocity, second_velocity = entity.get_prop(me, 'm_vecVelocity')
        local speed = math.floor(math.sqrt(first_velocity^2 + second_velocity^2))
        local flags = entity.get_prop(me, 'm_fFlags')
        local ground_tick = bit.band(flags, 1) == 1
    
        local anim_layers = ffi.cast(animation_layer_t, ffi.cast(char_ptr, player_ptr) + 0x2990)[0]
        local anim_type, anim_extra_type, anim_jitter_min, anim_jitter_max, body_lean_value = false, false, false, false, 0
        
        if ground_tick and speed > 5 then
            anim_type = animation_breaker_running_type:get()
            anim_jitter_min = animation_breaker_running_min_jitter:get() * 0.01
            anim_jitter_max = animation_breaker_running_max_jitter:get() * 0.01
            body_lean_value = animation_breaker_running_bodylean:get()
            anim_extra_type = animation_breaker_running_extra:get('Body lean')
        elseif not ground_tick then
            anim_type = animation_breaker_air_type:get()
            anim_jitter_min = animation_breaker_air_min_jitter:get() * 0.01
            anim_jitter_max = animation_breaker_air_max_jitter:get() * 0.01
            body_lean_value = animation_breaker_air_bodylean:get()
            anim_extra_type = animation_breaker_air_extra:get('Body lean')
        end
        local is_lagging = globals.realtime() / 2 % 1
    
        if anim_type == 'Allah' then
            entity.set_prop(me, 'm_flPoseParameter', 1, ground_tick and speed > 5 and 7 or 6)
            if not ground_tick then anim_layers[6].weight, anim_layers[6].cycle = 1, is_lagging end
            ui.set(menu_ref.other.leg_movement, 'off')
        elseif anim_type == 'Static' then
            entity.set_prop(me, 'm_flPoseParameter', 1, ground_tick and speed > 5 and 0 or 6)
            ui.set(menu_ref.other.leg_movement, 'always slide')
        elseif anim_type == 'Jitter' then
            entity.set_prop(me, 'm_flPoseParameter', client.random_float(anim_jitter_min, anim_jitter_max), ground_tick and speed > 5 and 7 or 6)
            ui.set(menu_ref.other.leg_movement, 'never slide')
        elseif animation_breaker_running_type:get() == 'Alternative jitter' then
            ui.set(menu_ref.other.leg_movement, command_number % 3 == 0 and 'off' or 'always slide')
            entity.set_prop(me, 'm_flPoseParameter', 1, globals.tickcount() % 4 > 1 and 0.5 or 1)
            if ground_tick and speed < 0 then
                entity.set_prop(me, 'm_flPoseParameter', client.random_float(0.4, 0.8), 7)
            end
        else
            ui.set(menu_ref.other.leg_movement, 'off')
        end
    
        if anim_extra_type then
            anim_layers[12].weight = body_lean_value / 100
        end
    
        if animation_breaker_air_extra:get('Zero pitch on landing') then
            -- Proper landing detection using animstate
            local animstate = memory.animstate:get(me)
            if animstate and animstate.hit_in_ground_animation and ground_tick then
                entity.set_prop(me, 'm_flPoseParameter', 0.5, 12)
            end
        end
    end

    client.set_event_callback('pre_render', on_pre_render)
end

-- Fast Ladder Implementation (1:1 from Emberlash V2)
local function fast_ladder_setup_command(e)
    if not fast_ladder_enable:get() then
        return
    end
    
    local me = entity.get_local_player()
    if not me or not entity.is_alive(me) then
        return
    end
    
    local pitch, yaw = client.camera_angles()
    local move_type = entity.get_prop(me, 'm_MoveType')
    local weapon = entity.get_player_weapon(me)
    local throw = entity.get_prop(weapon, 'm_fThrowTime')

    if move_type ~= 9 then
        return
    end

    if weapon == nil then
        return
    end

    if throw ~= nil and throw ~= 0 then
        return
    end	

    if e.forwardmove > 0 then
        if e.pitch < 45 then
            e.pitch = 89
            e.in_moveright = 1
            e.in_moveleft = 0
            e.in_forward = 0
            e.in_back = 1
    
            if e.sidemove == 0 then
                e.yaw = e.yaw + 90
            end
    
            e.sidemove = 250
        end
    end
end

client.set_event_callback("setup_command", fast_ladder_setup_command)
