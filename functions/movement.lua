-- functions/movement.lua

local movement = {}

-- Importar módulos necessários
local waypoint_loader = require("functions.waypoint_loader")
local explorer = require("data.explorer")
local teleport = require("data.teleport")

-- Variáveis locais
local waypoints = {}
local ni = 1
local is_moving = false
local is_interacting = false
local current_waypoint = nil
local moving_backwards = false
local explorer_active = false
local stuck_threshold = 10
local stuck_check_time = 0
local last_movement_time = 0
local force_move_cooldown = 0
local previous_player_pos = nil
local start_time = 0
local check_interval = 120

-- Função para obter a distância entre o jogador e um ponto
local function get_distance(point)
    return get_player_position():dist_to(point)
end

-- Função principal de movimento
function movement.pulse(plugin_enabled, loopEnabled)
    if not plugin_enabled or is_interacting or not is_moving then
        return
    end

    if #waypoints == 0 or ni > #waypoints or ni < 1 then
        if loopEnabled then
            ni = 1
        else
            return
        end
    end

    current_waypoint = waypoints[ni]
    if current_waypoint then
        local current_time = os.clock()
        local player_pos = get_player_position()
        local distance = get_distance(current_waypoint)
        
        if distance < 2 then
            if moving_backwards then
                ni = ni - 1
            else
                ni = ni + 1
            end
            last_movement_time = current_time
            force_move_cooldown = 0
            previous_player_pos = player_pos
            stuck_check_time = current_time
        else
            movement.handle_movement(current_time, player_pos, current_waypoint)
        end
    end
end

function movement.handle_movement(current_time, player_pos, current_waypoint)
    if not explorer_active then
        if current_time - stuck_check_time > stuck_threshold and teleport.get_teleport_state() == "idle" then
            console.print("Player stuck for " .. stuck_threshold .. " seconds, calling explorer module")
            if current_waypoint then
                explorer.set_target(current_waypoint)
                explorer.enable()
                explorer_active = true
                console.print("Explorer activated")
            else
                console.print("Error: No current waypoint set")
            end
            return
        end
    end
    
    if previous_player_pos and player_pos:dist_to(previous_player_pos) < 3 then
        if current_time - last_movement_time > 5 then
            console.print("Player stuck, using force_move_raw")
            local randomized_waypoint = waypoint_loader.randomize_waypoint(current_waypoint)
            pathfinder.force_move_raw(randomized_waypoint)
            last_movement_time = current_time
        end
    else
        previous_player_pos = player_pos
        last_movement_time = current_time
        stuck_check_time = current_time -- Reset stuck_check_time when moving
    end

    if current_time > force_move_cooldown then
        local randomized_waypoint = waypoint_loader.randomize_waypoint(current_waypoint)
        pathfinder.request_move(randomized_waypoint)
    end
end

-- Nova função start_movement_and_check_cinders
function movement.start_movement_and_check_cinders(plugin_enabled, loopEnabled)
    if not is_moving then
        start_time = os.clock()
        is_moving = true
    end

    if os.clock() - start_time > check_interval then
        is_moving = false
        local cinders_count = get_helltide_coin_cinders()

        if cinders_count == 0 then
            console.print("No cinders found. Stopping movement to teleport.")
            local player_pos = get_player_position()
            pathfinder.request_move(player_pos)
        else
            console.print("Cinders found. Continuing movement.")
        end
    end

    movement.pulse(plugin_enabled, loopEnabled)
end

-- Funções para configurar e obter o estado do movimento
function movement.set_waypoints(new_waypoints)
    waypoints = new_waypoints
    ni = 1
end

function movement.set_moving(moving)
    is_moving = moving
end

function movement.set_interacting(interacting)
    is_interacting = interacting
end

function movement.is_explorer_active()
    return explorer_active
end

function movement.reset_explorer()
    explorer_active = false
end

return movement