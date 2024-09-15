-- Import menu elements
local menu = require("menu")
local menu_renderer = require("graphics.menu_renderer")
local revive = require("data.revive")
local explorer = require("data.explorer")
local automindcage = require("data.automindcage")
local actors = require("data.actors")
local waypoint_loader = require("functions.waypoint_loader")
local interactive_patterns = require("enums.interactive_patterns")
local teleport = require("data.teleport")
local movement = require("functions.movement")

-- Inicializa as variáveis
local waypoints = {}
local plugin_enabled = false
local initialMessageDisplayed = false
local doorsEnabled = false
local loopEnabled = false
local interactedObjects = {}
local is_interacting = false
local interaction_end_time = 0
local ni = 1
local start_time = 0
local check_interval = 120
local current_city_index = 1
local is_moving = false
local loading_start_time = nil
local returning_to_failed = false
local previous_cinders_count = 0
local moving_backwards = false
local graphics_enabled = false
local stuck_check_time = 0
local stuck_threshold = 10
local explorer_active = false
local moveThreshold = 12
local last_movement_time = 0
local force_move_cooldown = 0
local previous_player_pos = nil
local expiration_time = 10 -- Tempo q ele para quando interage com um bau

local function clear_interacted_objects()
    interactedObjects = {}
    console.print("Cleared interacted objects list")
end

local function update_explorer_target()
    if explorer and current_waypoint then
        explorer.set_target(current_waypoint)
    end
end

-- Add the cleanup_after_helltide function
local function cleanup_after_helltide()
    console.print("Performing general cleanup after Helltide...")

    -- Reset movement variables
    is_moving = false
    explorer_active = false
    moving_backwards = false

    -- Clear waypoints and related variables
    waypoints = {}
    ni = 1

    -- Reset interaction variables
    is_interacting = false
    interaction_end_time = 0
    interactedObjects = {}

    -- Reset timers
    start_time = 0
    loading_start_time = nil
    stuck_check_time = os.clock()
    last_movement_time = 0
    force_move_cooldown = 0

    -- Reset player position tracking
    previous_player_pos = nil

    -- Reset explorer module
    if explorer and explorer.disable then
        explorer.disable()
    end

    -- Reset teleport module
    teleport.reset()

    -- Force garbage collection
    collectgarbage("collect")

    console.print("Cleanup completed.")
end

local function initialize_plugin()
    console.print("Initializing Movement Plugin...")
    waypoints, current_city_index = waypoint_loader.check_and_load_waypoints()
    stuck_check_time = os.clock()
    movement.set_moving(true)
    -- Adicione aqui outras inicializações necessárias
end

local function randomize_waypoint(waypoint, max_offset)
    return waypoint_loader.randomize_waypoint(waypoint, max_offset)
end

-- Função para mover o jogador até o objeto e interagir com ele
local function moveToAndInteract(obj)
    local player_pos = get_player_position()
    local obj_pos = obj:get_position()
    local distanceThreshold = 2.0 -- Distancia para interagir com o objeto

    -- Verifica se o slider está disponível e obtém o valor
    if menu.move_threshold_slider then
        moveThreshold = menu.move_threshold_slider:get()
    else
        console.print("Warning: move_threshold_slider is not initialized. Using default value.")
    end

    local distance = obj_pos:dist_to(player_pos)
    
    if distance < distanceThreshold then
        is_interacting = true
        local obj_name = obj:get_skin_name()
        interactedObjects[obj_name] = os.clock() + expiration_time
        interact_object(obj)
        console.print("Interacting with " .. obj_name)
        interaction_end_time = os.clock() + 5
        previous_cinders_count = get_helltide_coin_cinders()
        return true
    elseif distance < moveThreshold then
        pathfinder.request_move(obj_pos)
        return false
    end
end

-- Função para interagir com objetos
local function interactWithObjects()
    local local_player = get_local_player()
    if not local_player then
        return
    end

    local objects = actors_manager.get_ally_actors()
    if not objects then
        return
    end

    for _, obj in ipairs(objects) do
        if obj then
            local obj_name = obj:get_skin_name()
            if obj_name and interactive_patterns[obj_name] then
                if doorsEnabled and (not interactedObjects[obj_name] or os.clock() > interactedObjects[obj_name]) then
                    if moveToAndInteract(obj) then
                        return
                    end
                end
            end
        end
    end
end

-- Função para verificar se o jogador ainda está interagindo e retomar o movimento se necessário
local function checkInteraction()
    if is_interacting and os.clock() > interaction_end_time then
        is_interacting = false
        local new_cinders_count = get_helltide_coin_cinders()
        local obj_name = nil

        -- Encontra o nome do objeto que está sendo interagido
        for key, expiration in pairs(interactedObjects) do
            if os.clock() < expiration then
                obj_name = key
                break
            end
        end
    end
end

-- Função de movimento principal modificada
-- Substitua a função pulse() existente por:
local function update_movement()
    if plugin_enabled then
        movement.pulse(plugin_enabled, loopEnabled)
    end
end

-- Função para verificar se o jogo está na tela de carregamento
local function is_loading_screen()
    local world_instance = world.get_current_world()
    if world_instance then
        local zone_name = world_instance:get_current_zone_name()
        return zone_name == nil or zone_name == ""
    end
    return true
end

-- Função para verificar se está na Helltide
local was_in_helltide = false

local function is_in_helltide(local_player)
    if not local_player then
        return false
    end

    local buffs = local_player:get_buffs()
    if not buffs then
        return false
    end

    for _, buff in ipairs(buffs) do
        if buff and buff.name_hash == 1066539 then
            was_in_helltide = true
            return true
        end
    end
    return false
end

-- Função para iniciar a contagem de cinders e teletransporte

local function update_menu_states()
    local new_plugin_enabled = menu.plugin_enabled:get()
    if new_plugin_enabled ~= plugin_enabled then
        plugin_enabled = new_plugin_enabled
        console.print("Movement Plugin " .. (plugin_enabled and "enabled" or "disabled"))
        if plugin_enabled then
            initialize_plugin()
        end
    end

    local new_doors_enabled = menu.main_openDoors_enabled:get()
    if new_doors_enabled ~= doorsEnabled then
        doorsEnabled = new_doors_enabled
        console.print("Open Chests " .. (doorsEnabled and "enabled" or "disabled"))
    end

    local new_loop_enabled = menu.loop_enabled:get()
    if new_loop_enabled ~= loopEnabled then
        loopEnabled = new_loop_enabled
        console.print("Loop " .. (loopEnabled and "enabled" or "disabled"))
    end

    local new_revive_enabled = menu.revive_enabled:get()
    if new_revive_enabled ~= revive_enabled then
        revive_enabled = new_revive_enabled
        console.print("Revive Module " .. (revive_enabled and "enabled" or "disabled"))
    end

    local new_profane_mindcage_enabled = menu.profane_mindcage_toggle:get()
    if new_profane_mindcage_enabled ~= profane_mindcage_enabled then
        profane_mindcage_enabled = new_profane_mindcage_enabled
        console.print("Profane Mindcage Auto Use " .. (profane_mindcage_enabled and "enabled" or "disabled"))
    end

    local new_profane_mindcage_count = menu.profane_mindcage_slider:get()
    if new_profane_mindcage_count ~= profane_mindcage_count then
        profane_mindcage_count = new_profane_mindcage_count
        console.print("Profane Mindcage Count set to " .. profane_mindcage_count)
    end

    local new_move_threshold = menu.move_threshold_slider:get()
    if new_move_threshold ~= moveThreshold then
        moveThreshold = new_move_threshold
        console.print("Move Threshold set to " .. moveThreshold)
    end
end

-- Função chamada periodicamente para interagir com objetos
on_update(function()
    update_menu_states()

    if plugin_enabled then
        local local_player = get_local_player()
        if not local_player then
            return
        end

        local world_instance = world.get_current_world()
        if not world_instance then
            return
        end

        local teleport_state = teleport.get_teleport_state()

        if teleport_state ~= "idle" then
            if teleport.tp_to_next() then
                console.print("Teleport completed. Loading new waypoints...")
                waypoints, current_city_index = waypoint_loader.check_and_load_waypoints()
                movement.set_waypoints(waypoints)
            end
        else
            local current_in_helltide = is_in_helltide(local_player)
            
            if was_in_helltide and not current_in_helltide then
                console.print("Helltide ended. Performing cleanup.")
                cleanup_after_helltide()
                was_in_helltide = false
            end

            if current_in_helltide then
                was_in_helltide = true
                if movement.is_explorer_active() then
                    if not _G.explorer_active then
                        movement.reset_explorer()
                        console.print("Explorer module finished, resuming normal movement")
                    end
                else
                    if menu.profane_mindcage_toggle:get() then
                        automindcage.update()
                    end
                    checkInteraction()
                    interactWithObjects()
                    movement.pulse(plugin_enabled, loopEnabled)
                    if menu.revive_enabled:get() then
                        revive.check_and_revive()
                    end
                    actors.update()
                end
            else
                console.print("Not in the Helltide zone. Attempting to teleport...")
                if teleport.tp_to_next() then
                    console.print("Teleported successfully. Loading new waypoints...")
                    waypoints, current_city_index = waypoint_loader.check_and_load_waypoints()
                    movement.set_waypoints(waypoints)
                else
                    local state = teleport.get_teleport_state()
                    console.print("Teleport in progress. Current state: " .. state)
                end
            end
        end
    end
end)

-- Função para renderizar o menu
on_render_menu(function()
    menu_renderer.render_menu(plugin_enabled, doorsEnabled, loopEnabled, revive_enabled, profane_mindcage_enabled, profane_mindcage_count, moveThreshold)
end)

-- Mantenha a função initialize_plugin() no main.lua:
local function initialize_plugin()
    console.print("Initializing Movement Plugin...")
    waypoints, current_city_index = waypoint_loader.check_and_load_waypoints()
    stuck_check_time = os.clock()
    -- Adicione aqui outras inicializações necessárias
end