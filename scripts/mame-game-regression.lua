-- MAME 0.289 regression harness for the MC-10 Space Invaders target.
--
-- The cassette image is mounted by MAME before this script starts. The script
-- enters the MC-10 machine-code loader, waits for the complete Space Invaders
-- image, executes it, verifies the first rendered game screen, exercises
-- keyboard movement, firing, and an alien collision, and checks the alien-shot
-- player-hit, life-loss, formation-descent, shield-clearing, visible game-over,
-- and Space-restart paths.
--
-- Run with:
--   mame.exe mc10 -ramsize 20K -cass build/space-invaders.c10 \
--     -autoboot_delay 2 \
--     -autoboot_script scripts/mame-game-regression.lua \
--     -snapshot_directory build/mame-snapshots -seconds_to_run 150

local machine = manager.machine
local cassette = machine.cassettes[":cassette"]
local screen = machine.screens[":screen"]
local keyboard = machine.natkeyboard
local cpu = machine.devices[":maincpu"]
local program_space = cpu and cpu.spaces["program"]

local GAME_FRAME = 0x00E1
local GAME_SCORE_0 = 0x00E2
local GAME_SCORE_1 = 0x00E3
local GAME_SCORE_2 = 0x00E4
local GAME_SCORE_3 = 0x00E5
local GAME_LIVES = 0x00E6
local GAME_OVER = 0x00E7
local GAME_PLAYER_X = 0x00E8
local GAME_BULLET_X = 0x00E9
local GAME_BULLET_Y = 0x00EA
local GAME_BULLET_ACTIVE = 0x00EB
local GAME_ALIEN_SHOT_X = 0x00EC
local GAME_ALIEN_SHOT_Y = 0x00ED
local GAME_ALIEN_SHOT_ACTIVE = 0x00EE
local GAME_ALIEN_SHOT_TICK = 0x00EF
local GAME_INVADER_X = 0x00F0
local GAME_INVADER_Y = 0x00F1
local GAME_INVADER_DIR = 0x00F2
local GAME_INVADER_TICK = 0x00F3
local GAME_BONUS_ACTIVE = 0x00F6
local GAME_SHIELDS_ACTIVE = 0x00FB
local ALIEN_LIVE = 0x4C00
local WORK_TEMP = 0x4C49
local FORMATION_BUSY = 0x4C53

local EXEC_MIN_FRAME = 2400
local EXEC_TIMEOUT_FRAME = 7200
local GAME_TIMEOUT_FRAMES = 600
local GAME_OVER_STABLE_FRAMES = 120
local ACTIVE_WIDTH = 256
local ACTIVE_HEIGHT = 192
local ACTIVE_PIXELS = ACTIVE_WIDTH * ACTIVE_HEIGHT
local SHIELD_LEFT = 2 * 16
local SHIELD_TOP = 2 * 70
local SHIELD_RIGHT = 2 * 28
local SHIELD_BOTTOM = 2 * 77
local ALL_SHIELDS_TOP = 2 * 68
local ALL_SHIELDS_BOTTOM = 2 * 80

assert(cassette, "MC-10 cassette device not found")
assert(screen, "MC-10 screen device not found")
assert(keyboard and keyboard.can_post, "MC-10 natural keyboard input is unavailable")
assert(program_space, "MC-10 CPU program address space not found")

keyboard.in_use = true
keyboard:post_coded("CLOADM{ENTER}")
print("MC-10 keyboard: CLOADM{ENTER}")

local frame = 0
local started = false
local exec_sent = false
local deadline = GAME_TIMEOUT_FRAMES
local failed = false
local last_message = nil
local phase = "waiting for initial game screen"
local phase_deadline = GAME_TIMEOUT_FRAMES
local initial_player_x = nil
local left_player_x = nil
local right_player_x = nil
local live_aliens_at_start = 55
local shield_yellow_before = nil
local shields_before_descent = nil
local player_lives_before = nil
local formation_collision_lives_before = nil
local game_over_frame = nil

local function post_game_key(code, description, next_phase)
    keyboard:post_coded(code)
    phase = next_phase
    phase_deadline = frame + GAME_TIMEOUT_FRAMES
    print(string.format("MC-10 keyboard: %s at frame %d", description, frame))
end

local function fail(message)
    if failed then
        return
    end
    failed = true
    print("MC-10 game regression: FAIL: " .. message)
    machine:exit()
    error("MC-10 game regression: " .. message)
end

local function read_byte(address)
    return program_space:read_u8(address)
end

local function write_byte(address, value)
    program_space:write_u8(address, value)
end

local function trace_state(label)
    local pc_entry = cpu.state["PC"] or cpu.state["CURPC"] or cpu.state["rPC"]
    local pc = pc_entry and pc_entry.value or -1
    local b_entry = cpu.state["B"]
    local b = b_entry and b_entry.value or -1
    print(string.format(
        "MC-10 game trace: %s frame=%d pc=%04X b=%02X temp=%02X state=%02X/%02X/%02X/%02X/%02X/%02X/%02X/%02X/%02X/%02X/%02X/%02X",
        label,
        frame,
        pc,
        b,
        read_byte(WORK_TEMP),
        read_byte(GAME_FRAME),
        read_byte(GAME_SCORE_0),
        read_byte(GAME_SCORE_1),
        read_byte(GAME_SCORE_2),
        read_byte(GAME_SCORE_3),
        read_byte(GAME_LIVES),
        read_byte(GAME_PLAYER_X),
        read_byte(GAME_BULLET_ACTIVE),
        read_byte(GAME_ALIEN_SHOT_ACTIVE),
        read_byte(GAME_INVADER_X),
        read_byte(GAME_INVADER_Y),
        read_byte(GAME_SHIELDS_ACTIVE)))
end

local function cpu_pc()
    local pc_entry = cpu.state["PC"] or cpu.state["CURPC"] or cpu.state["rPC"]
    return pc_entry and pc_entry.value or -1
end

local function game_main_loop_active()
    local pc = cpu_pc()
    return pc >= 0x502C and pc <= 0x503B
end

local function rgb_from_pixel(value)
    if value <= 0xFF and screen.palette then
        value = screen.palette:pen_color(value)
    end
    local red = math.floor(value / 0x10000) % 0x100
    local green = math.floor(value / 0x100) % 0x100
    local blue = value % 0x100
    return red, green, blue
end

local function color_class(value)
    local red, green, blue = rgb_from_pixel(value)
    if blue >= red + 30 and blue >= green + 30 then
        return "blue"
    end
    if red >= 60 and green >= 60 and red >= blue + 30 and green >= blue + 30 then
        return "yellow"
    end
    if green >= red + 20 and green >= blue + 20 then
        return "green"
    end
    if red >= green + 20 and red >= blue + 20 then
        return "red"
    end
    return "other"
end

local function analyze_pixels()
    local pixels, width, height = screen:pixels()
    assert(type(pixels) == "string", "screen:pixels() did not return a pixel buffer")
    assert(width and height and width > 0 and height > 0, "screen dimensions are invalid")

    local counts = { blue = 0, green = 0, red = 0, yellow = 0, other = 0 }
    local boxes = { blue = nil, green = nil, red = nil, yellow = nil }

    for y = 0, height - 1 do
        for x = 0, width - 1 do
            local kind = color_class(screen:pixel(x, y))
            counts[kind] = counts[kind] + 1
            if boxes[kind] then
                local box = boxes[kind]
                if x < box.left then box.left = x end
                if y < box.top then box.top = y end
                if x + 1 > box.right then box.right = x + 1 end
                if y + 1 > box.bottom then box.bottom = y + 1 end
            elseif kind ~= "other" then
                boxes[kind] = { left = x, top = y, right = x + 1, bottom = y + 1 }
            end
        end
    end

    return {
        pixels = pixels,
        width = width,
        height = height,
        total = width * height,
        counts = counts,
        boxes = boxes,
    }
end

local function format_bbox(box)
    if not box then
        return "none"
    end
    return string.format("%d,%d-%d,%d", box.left, box.top, box.right, box.bottom)
end

local function count_region(metrics, kind, left, top, right, bottom)
    local box = metrics.boxes.blue
    local count = 0
    for y = math.max(0, top), math.min(ACTIVE_HEIGHT, bottom) - 1 do
        for x = math.max(0, left), math.min(ACTIVE_WIDTH, right) - 1 do
            local actual = color_class(screen:pixel(box.left + x, box.top + y))
            if actual == kind then
                count = count + 1
            end
        end
    end
    return count
end

local function print_metrics(metrics, rows, shields, player, score, lives, hud)
    print(string.format(
        "MC-10 game pixels: size=%dx%d blue=%d green=%d red=%d yellow=%d other=%d blue-box=%s green-box=%s red-box=%s yellow-box=%s",
        metrics.width,
        metrics.height,
        metrics.counts.blue,
        metrics.counts.green,
        metrics.counts.red,
        metrics.counts.yellow,
        metrics.counts.other,
        format_bbox(metrics.boxes.blue),
        format_bbox(metrics.boxes.green),
        format_bbox(metrics.boxes.red),
        format_bbox(metrics.boxes.yellow)))
    print(string.format(
        "MC-10 game regions: alien-rows=%d/%d/%d/%d/%d shields=%d player=%d score=%d lives=%d hud=%d",
        rows[1], rows[2], rows[3], rows[4], rows[5], shields, player, score, lives, hud))
end

local function game_state_ready()
    local state = {
        frame = read_byte(GAME_FRAME),
        score0 = read_byte(GAME_SCORE_0),
        score1 = read_byte(GAME_SCORE_1),
        score2 = read_byte(GAME_SCORE_2),
        score3 = read_byte(GAME_SCORE_3),
        lives = read_byte(GAME_LIVES),
        player_x = read_byte(GAME_PLAYER_X),
        bullet_active = read_byte(GAME_BULLET_ACTIVE),
        alien_shot_active = read_byte(GAME_ALIEN_SHOT_ACTIVE),
        invader_x = read_byte(GAME_INVADER_X),
        invader_y = read_byte(GAME_INVADER_Y),
        bonus_active = read_byte(GAME_BONUS_ACTIVE),
        shields_active = read_byte(GAME_SHIELDS_ACTIVE),
    }

    if state.score0 ~= 0 or state.score1 ~= 0 or state.score2 ~= 0 or state.score3 ~= 0 then
        return nil, string.format(
            "initial score is not zero: %02X%02X%02X%02X",
            state.score0,
            state.score1,
            state.score2,
            state.score3)
    end
    if state.lives ~= 3 then
        return nil, string.format("initial lives expected 3, got %d", state.lives)
    end
    if state.player_x ~= 0x0F then
        return nil, string.format("initial player X expected 0F, got %02X", state.player_x)
    end
    if state.invader_x < 0x08 or state.invader_x > 0x20 or state.invader_y ~= 0x04 then
        return nil, string.format(
            "initial formation position is outside the opening band: got %02X/%02X",
            state.invader_x,
            state.invader_y)
    end
    if state.bonus_active ~= 0 or state.shields_active ~= 1 then
        return nil, "initial bonus or shield state is incorrect"
    end

    for offset = 0, 54 do
        if read_byte(ALIEN_LIVE + offset) ~= 1 then
            return nil, string.format("alien live table entry %d is not initialized", offset)
        end
    end
    return state
end

local function count_live_aliens()
    local count = 0
    for offset = 0, 54 do
        if read_byte(ALIEN_LIVE + offset) ~= 0 then
            count = count + 1
        end
    end
    return count
end

local function score_is_nonzero()
    return read_byte(GAME_SCORE_0) ~= 0
        or read_byte(GAME_SCORE_1) ~= 0
        or read_byte(GAME_SCORE_2) ~= 0
        or read_byte(GAME_SCORE_3) ~= 0
end

local function shield_yellow_count(metrics)
    return count_region(
        metrics,
        "yellow",
        SHIELD_LEFT,
        SHIELD_TOP,
        SHIELD_RIGHT,
        SHIELD_BOTTOM)
end

local function all_shield_yellow_count(metrics)
    return count_region(
        metrics,
        "yellow",
        0,
        ALL_SHIELDS_TOP,
        ACTIVE_WIDTH,
        ALL_SHIELDS_BOTTOM)
end

local function verify_initial_screen()
    local state, state_error = game_state_ready()
    if not state then
        return nil, state_error
    end

    local metrics = analyze_pixels()
    local blue_box = metrics.boxes.blue
    if not blue_box then
        return nil, "no blue CG3 background was rendered"
    end
    if blue_box.right - blue_box.left ~= ACTIVE_WIDTH
        or blue_box.bottom - blue_box.top ~= ACTIVE_HEIGHT then
        return nil, string.format(
            "blue CG3 surface has unexpected size %dx%d",
            blue_box.right - blue_box.left,
            blue_box.bottom - blue_box.top)
    end
    -- The opening formation, shields, player, and HUD occupy roughly 17% of
    -- the active surface, so the blue background threshold leaves room for
    -- the intended playfield contents.
    if metrics.counts.blue < ACTIVE_PIXELS * 0.70 then
        return nil, string.format("blue CG3 background is too small: %d pixels", metrics.counts.blue)
    end

    -- Source coordinates are doubled in the 256x192 MAME capture. The five
    -- formation rows start at logical Y=4 and are seven logical pixels apart.
    local expected = { "red", "green", "green", "yellow", "yellow" }
    local rows = {}
    for index = 1, 5 do
        local top = 2 * (4 + (index - 1) * 7)
        rows[index] = count_region(metrics, expected[index], 0, top, ACTIVE_WIDTH, top + 14)
        if rows[index] < 40 then
            return nil, string.format(
                "formation row %d lacks %s pixels: %d",
                index,
                expected[index],
                rows[index])
        end
    end

    local shields = count_region(metrics, "yellow", 0, 2 * 68, ACTIVE_WIDTH, 2 * 80)
    if shields < 80 then
        return nil, string.format("shield structures are missing: %d yellow pixels", shields)
    end

    local player = count_region(metrics, "red", 0, 2 * 80, ACTIVE_WIDTH, 2 * 89)
    if player < 30 then
        return nil, string.format("player ship is missing: %d red pixels", player)
    end

    local score = count_region(metrics, "yellow", 0, 2 * 89, 2 * 40, ACTIVE_HEIGHT)
    if score < 10 then
        return nil, string.format("score is missing from the lower-left HUD: %d yellow pixels", score)
    end

    local lives = count_region(metrics, "yellow", 2 * 80, 2 * 89, ACTIVE_WIDTH, ACTIVE_HEIGHT)
    if lives < 10 then
        return nil, string.format("life icons are missing from the lower-right HUD: %d yellow pixels", lives)
    end

    local hud = score + lives
    if hud < 30 then
        return nil, string.format("score/lives HUD is missing: %d yellow pixels", hud)
    end

    print_metrics(metrics, rows, shields, player, score, lives, hud)
    local error_message = screen:snapshot("mame-game-initial.png")
    if error_message then
        fail("game snapshot failed: " .. tostring(error_message))
    end
    print(string.format(
        "MC-10 game state: frame=%02X score=0000 lives=%d player-x=%02X formation=%02X/%02X",
        state.frame,
        state.lives,
        state.player_x,
        state.invader_x,
        state.invader_y))
    print("MC-10 game initial screen: PASS")
    return true
end

local function verify_game_input()
    local player_x = read_byte(GAME_PLAYER_X)

    if phase == "waiting for initial game screen" then
        local ok, message = verify_initial_screen()
        if not ok then
            return nil, message
        end
        initial_player_x = player_x
        post_game_key("A", "A (move left)", "waiting for left movement")
        return true
    end

    if phase == "waiting for left movement" then
        if player_x < initial_player_x then
            left_player_x = player_x
            print(string.format(
                "MC-10 game input: LEFT PASS player-x=%02X->%02X",
                initial_player_x,
                player_x))
            post_game_key("D", "D (move right)", "waiting for first right movement")
            return true
        end
        return nil, string.format("A did not move the player left from %02X", initial_player_x)
    end

    if phase == "waiting for first right movement" then
        if player_x > left_player_x then
            right_player_x = player_x
            print(string.format(
                "MC-10 game input: RIGHT PASS player-x=%02X->%02X",
                left_player_x,
                player_x))
            post_game_key("D", "D (position for collision)", "waiting for collision alignment")
            return true
        end
        return nil, string.format("D did not move the player right from %02X: got %02X", left_player_x, player_x)
    end

    if phase == "waiting for collision alignment" then
        if player_x > right_player_x then
            print(string.format(
                "MC-10 game input: COLLISION ALIGN PASS player-x=%02X",
                player_x))
            live_aliens_at_start = count_live_aliens()
            post_game_key("{SPACE}", "SPACE (fire)", "waiting for bullet launch")
            return true
        end
        return nil, string.format(
            "second D did not advance the collision position beyond %02X: got %02X",
            right_player_x,
            player_x)
    end

    if phase == "waiting for bullet launch" then
        if read_byte(GAME_BULLET_ACTIVE) ~= 0 then
            local bullet_x = read_byte(GAME_BULLET_X)
            local bullet_y = read_byte(GAME_BULLET_Y)
            if bullet_x ~= player_x + 1 then
                return nil, string.format(
                    "Space launched a bullet at unexpected X: player=%02X bullet=%02X",
                    player_x,
                    bullet_x)
            end
            if bullet_y == 0 or bullet_y > 0x4E then
                return nil, string.format("Space launched a bullet at unexpected Y: %02X", bullet_y)
            end
            local error_message = screen:snapshot("mame-game-fired.png")
            if error_message then
                fail("firing snapshot failed: " .. tostring(error_message))
            end
            print(string.format(
                "MC-10 game input: FIRE PASS bullet=%02X/%02X",
                bullet_x,
                bullet_y))
            phase = "waiting for alien collision"
            phase_deadline = frame + GAME_TIMEOUT_FRAMES
            return true
        end
        return nil, "Space did not launch an active bullet"
    end

    if phase == "waiting for alien collision" then
        local live_aliens = count_live_aliens()
        if live_aliens < live_aliens_at_start and score_is_nonzero() then
            local metrics = analyze_pixels()
            local error_message = screen:snapshot("mame-game-collision.png")
            if error_message then
                fail("collision snapshot failed: " .. tostring(error_message))
            end
            print(string.format(
                "MC-10 game collision: PASS live-aliens=%d->%d bullet-active=%d score=%02X%02X%02X%02X",
                live_aliens_at_start,
                live_aliens,
                read_byte(GAME_BULLET_ACTIVE),
                read_byte(GAME_SCORE_0),
                read_byte(GAME_SCORE_1),
                read_byte(GAME_SCORE_2),
                read_byte(GAME_SCORE_3)))
            print(string.format(
                "MC-10 game collision pixels: size=%dx%d blue=%d green=%d red=%d yellow=%d other=%d",
                metrics.width,
                metrics.height,
                metrics.counts.blue,
                metrics.counts.green,
                metrics.counts.red,
                metrics.counts.yellow,
                metrics.counts.other))
            phase = "waiting for natural alien shot"
            phase_deadline = frame + GAME_TIMEOUT_FRAMES
            return true
        end
        return nil, string.format(
            "keyboard-fired bullet did not collide with an alien: live=%d/%d score=%02X%02X%02X%02X",
            live_aliens,
            live_aliens_at_start,
            read_byte(GAME_SCORE_0),
            read_byte(GAME_SCORE_1),
            read_byte(GAME_SCORE_2),
            read_byte(GAME_SCORE_3))
    end

    if phase == "waiting for natural alien shot" then
        if read_byte(GAME_ALIEN_SHOT_ACTIVE) ~= 0 then
            local shot_x = read_byte(GAME_ALIEN_SHOT_X)
            local shot_y = read_byte(GAME_ALIEN_SHOT_Y)
            if shot_x > 0x1F then
                return nil, string.format("alien shot X is outside the playfield: %02X", shot_x)
            end
            if shot_y < 0x20 or shot_y > 0x5E then
                return nil, string.format("alien shot Y is outside the descent path: %02X", shot_y)
            end
            local error_message = screen:snapshot("mame-game-alien-shot.png")
            if error_message then
                fail("alien-shot snapshot failed: " .. tostring(error_message))
            end
            print(string.format(
                "MC-10 game input: ALIEN SHOT PASS shot=%02X/%02X tick=%02X",
                shot_x,
                shot_y,
                read_byte(GAME_ALIEN_SHOT_TICK)))

            local metrics = analyze_pixels()
            shield_yellow_before = shield_yellow_count(metrics)
            if read_byte(GAME_SHIELDS_ACTIVE) == 0 then
                return nil, "shields became inactive before the shield-damage fixture"
            end
            if shield_yellow_before < 20 then
                return nil, string.format(
                    "first shield has insufficient yellow pixels before damage: %d",
                    shield_yellow_before)
            end

            -- Keep the natural activation check above, then place the active
            -- projectile one update above a known lit pixel in the first
            -- shield. This makes shield damage deterministic while the normal
            -- game_alien_shot_update routine performs the collision.
            program_space:write_u8(GAME_ALIEN_SHOT_X, 0x04)
            program_space:write_u8(GAME_ALIEN_SHOT_Y, 0x45)
            program_space:write_u8(GAME_ALIEN_SHOT_TICK, 0x01)
            program_space:write_u8(GAME_ALIEN_SHOT_ACTIVE, 0x01)
            print("MC-10 game fixture: alien shot seeded at shield X=04 Y=45 TICK=01")
            phase = "waiting for shield damage"
            phase_deadline = frame + GAME_TIMEOUT_FRAMES
            return true
        end
        return nil, "alien shot did not become active"
    end

    if phase == "waiting for shield damage" then
        if read_byte(GAME_ALIEN_SHOT_ACTIVE) == 0 then
            local metrics = analyze_pixels()
            local shield_yellow_after = shield_yellow_count(metrics)
            if shield_yellow_after >= shield_yellow_before then
                return nil, string.format(
                    "alien shot ended without reducing first-shield yellow pixels: %d->%d",
                    shield_yellow_before,
                    shield_yellow_after)
            end
            local error_message = screen:snapshot("mame-game-shield-damage.png")
            if error_message then
                fail("shield-damage snapshot failed: " .. tostring(error_message))
            end
            print(string.format(
                "MC-10 game shield damage: PASS yellow=%d->%d shot-active=%d",
                shield_yellow_before,
                shield_yellow_after,
                read_byte(GAME_ALIEN_SHOT_ACTIVE)))
            -- Seed the normal alien-shot collision one pixel-coordinate step
            -- above the player. The next game update must spend one life and
            -- reset the active formation and player state.
            player_lives_before = read_byte(GAME_LIVES)
            write_byte(GAME_ALIEN_SHOT_X, 0x10)
            write_byte(GAME_ALIEN_SHOT_Y, 0x51)
            write_byte(GAME_ALIEN_SHOT_TICK, 0x01)
            write_byte(GAME_ALIEN_SHOT_ACTIVE, 0x01)
            print("MC-10 game fixture: alien shot seeded at player X=10 Y=51 TICK=01")
            phase = "waiting for player damage"
            phase_deadline = frame + GAME_TIMEOUT_FRAMES
            return true
        end
        return nil, string.format(
            "seeded alien shot has not reached the shield: y=%02X active=%d",
            read_byte(GAME_ALIEN_SHOT_Y),
            read_byte(GAME_ALIEN_SHOT_ACTIVE))
    end

    if phase == "waiting for player damage" then
        if player_lives_before == 3
            and read_byte(GAME_LIVES) == player_lives_before - 1
            and read_byte(GAME_ALIEN_SHOT_ACTIVE) == 0
            and read_byte(GAME_PLAYER_X) == 0x0F
            and read_byte(GAME_INVADER_X) == 0x08
            and read_byte(GAME_INVADER_Y) == 0x04 then
            local error_message = screen:snapshot("mame-game-player-hit.png")
            if error_message then
                fail("player-hit snapshot failed: " .. tostring(error_message))
            end
            print("MC-10 game player damage: PASS lives=3->2 player/formation reset")
            local metrics = analyze_pixels()
            shields_before_descent = all_shield_yellow_count(metrics)
            if read_byte(GAME_SHIELDS_ACTIVE) == 0 or shields_before_descent < 20 then
                return nil, string.format(
                    "shields are not available before descent: active=%d yellow=%d",
                    read_byte(GAME_SHIELDS_ACTIVE),
                    shields_before_descent)
            end

            -- Force the right-edge branch on the next normal game update.
            -- Y=19 plus the seven-pixel descent reaches Y=20, which is the
            -- game rule that clears the persistent shield region.
            write_byte(GAME_INVADER_X, 0x14)
            write_byte(GAME_INVADER_Y, 0x19)
            write_byte(GAME_INVADER_DIR, 0x01)
            write_byte(GAME_INVADER_TICK, 0x0F)
            write_byte(FORMATION_BUSY, 0x00)
            print("MC-10 game fixture: formation seeded at X=14 Y=19 DIR=01 TICK=0F")
            phase = "waiting for formation descent"
            phase_deadline = frame + GAME_TIMEOUT_FRAMES
            return true
        end
        return nil, string.format(
            "alien shot did not damage the player: lives=%d shot-active=%d player=%02X formation=%02X/%02X",
            read_byte(GAME_LIVES),
            read_byte(GAME_ALIEN_SHOT_ACTIVE),
            read_byte(GAME_PLAYER_X),
            read_byte(GAME_INVADER_X),
            read_byte(GAME_INVADER_Y))
    end

    if phase == "waiting for formation descent" then
        if read_byte(GAME_INVADER_Y) == 0x20
            and read_byte(GAME_INVADER_DIR) == 0
            and read_byte(GAME_SHIELDS_ACTIVE) == 0 then
            local metrics = analyze_pixels()
            local shields_after = all_shield_yellow_count(metrics)
            if shields_after >= shields_before_descent then
                return nil, string.format(
                    "formation descended but shield pixels did not clear: %d->%d",
                    shields_before_descent,
                    shields_after)
            end
            if shields_after > 0 then
                return nil, string.format(
                    "formation descent left shield pixels visible: %d",
                    shields_after)
            end
            local error_message = screen:snapshot("mame-game-descent-shield-clear.png")
            if error_message then
                fail("descent snapshot failed: " .. tostring(error_message))
            end
            print("MC-10 game formation descent: PASS y=19->20 dir=01->00")
            print(string.format(
                "MC-10 game shield clear: PASS yellow=%d->%d shields-active=1->0",
                shields_before_descent,
                shields_after))
            -- Force the next left-edge descent to reach the player level.
            -- Y=31 plus seven pixels becomes Y=38, which is the
            -- formation/player collision threshold.
            formation_collision_lives_before = read_byte(GAME_LIVES)
            write_byte(GAME_INVADER_X, 0x08)
            write_byte(GAME_INVADER_Y, 0x31)
            write_byte(GAME_INVADER_DIR, 0x00)
            write_byte(GAME_INVADER_TICK, 0x0F)
            write_byte(FORMATION_BUSY, 0x00)
            print("MC-10 game fixture: formation seeded at X=08 Y=31 DIR=00 TICK=0F")
            phase = "waiting for formation player collision"
            phase_deadline = frame + GAME_TIMEOUT_FRAMES
            return true
        end
        return nil, string.format(
            "formation did not descend and clear shields: x=%02X y=%02X dir=%02X tick=%02X active=%d",
            read_byte(GAME_INVADER_X),
            read_byte(GAME_INVADER_Y),
            read_byte(GAME_INVADER_DIR),
            read_byte(GAME_INVADER_TICK),
            read_byte(GAME_SHIELDS_ACTIVE))
    end

    if phase == "waiting for formation player collision" then
        if formation_collision_lives_before == 2
            and read_byte(GAME_LIVES) == formation_collision_lives_before - 1
            and read_byte(GAME_OVER) == 0
            and read_byte(GAME_PLAYER_X) == 0x0F
            and read_byte(GAME_INVADER_Y) == 0x04 then
            local error_message = screen:snapshot("mame-game-formation-player-collision.png")
            if error_message then
                fail("formation-player-collision snapshot failed: " .. tostring(error_message))
            end
            print(string.format(
                "MC-10 game formation/player collision: PASS lives=2->1 after descent formation-x=%02X",
                read_byte(GAME_INVADER_X)))

            -- Repeat the same collision with the final remaining life. The
            -- normal game_set_game_over path must latch GAME_OVER and stop
            -- simulation updates.
            write_byte(GAME_INVADER_X, 0x08)
            write_byte(GAME_INVADER_Y, 0x31)
            write_byte(GAME_INVADER_DIR, 0x00)
            write_byte(GAME_INVADER_TICK, 0x0F)
            write_byte(FORMATION_BUSY, 0x00)
            print("MC-10 game fixture: final formation collision seeded at X=08 Y=31")
            phase = "waiting for final life loss"
            phase_deadline = frame + GAME_TIMEOUT_FRAMES
            return true
        end
        return nil, string.format(
            "formation/player collision did not spend one life: lives=%d gameover=%d player=%02X formation=%02X/%02X",
            read_byte(GAME_LIVES),
            read_byte(GAME_OVER),
            read_byte(GAME_PLAYER_X),
            read_byte(GAME_INVADER_X),
            read_byte(GAME_INVADER_Y))
    end

    if phase == "waiting for final life loss" then
        if read_byte(GAME_LIVES) == 0
            and read_byte(GAME_OVER) == 1
            and read_byte(GAME_INVADER_X) == 0x08
            and read_byte(GAME_INVADER_Y) == 0x38
            and read_byte(GAME_INVADER_DIR) == 0x01 then
            game_over_frame = read_byte(GAME_FRAME)
            print(string.format(
                "MC-10 game final-life: PASS lives=1->0 game-over=1 frame=%02X",
                game_over_frame))
            phase = "checking game-over stability"
            phase_deadline = frame + GAME_OVER_STABLE_FRAMES
            return true
        end
        return nil, string.format(
            "final formation/player collision did not enter game over: lives=%d gameover=%d formation=%02X/%02X dir=%02X",
            read_byte(GAME_LIVES),
            read_byte(GAME_OVER),
            read_byte(GAME_INVADER_X),
            read_byte(GAME_INVADER_Y),
            read_byte(GAME_INVADER_DIR))
    end

    if phase == "checking game-over stability" then
        if read_byte(GAME_LIVES) ~= 0
            or read_byte(GAME_OVER) ~= 1
            or read_byte(GAME_FRAME) ~= game_over_frame then
            return nil, string.format(
                "game-over state changed after final life: lives=%d gameover=%d frame=%02X expected=%02X",
                read_byte(GAME_LIVES),
                read_byte(GAME_OVER),
                read_byte(GAME_FRAME),
                game_over_frame)
        end
        if frame >= phase_deadline then
            local metrics = analyze_pixels()
            local title = count_region(metrics, "red", 2 * 18, 2 * 23, 2 * 110, 2 * 35)
            local instruction = count_region(metrics, "yellow", 2 * 8, 2 * 49, 2 * 120, 2 * 57)
            if title < 50 then
                return nil, string.format("visible GAME OVER title is missing: %d red pixels", title)
            end
            if instruction < 20 then
                return nil, string.format(
                    "restart instruction is missing: %d yellow pixels",
                    instruction)
            end
            local error_message = screen:snapshot("mame-game-over.png")
            if error_message then
                fail("game-over snapshot failed: " .. tostring(error_message))
            end
            print(string.format(
                "MC-10 game over screen: PASS title-red=%d instruction-yellow=%d",
                title,
                instruction))
            post_game_key("{SPACE}", "SPACE (restart after game over)", "waiting for restart")
            return true
        end
        return true
    end

    if phase == "waiting for restart" then
        local state, state_error = game_state_ready()
        if state and read_byte(GAME_OVER) == 0 then
            if state.bullet_active ~= 0 or state.alien_shot_active ~= 0 then
                return nil, "restart restored the game with an active projectile"
            end
            local metrics = analyze_pixels()
            local blue_box = metrics.boxes.blue
            local player = count_region(metrics, "red", 0, 2 * 80, ACTIVE_WIDTH, 2 * 89)
            local shields = count_region(metrics, "yellow", 0, 2 * 68, ACTIVE_WIDTH, 2 * 80)
            if not blue_box or metrics.counts.blue < ACTIVE_PIXELS * 0.70 then
                return nil, "restart did not restore the blue CG3 playfield"
            end
            if player < 30 or shields < 80 then
                return nil, string.format(
                    "restart did not restore player/shields: player=%d shields=%d",
                    player,
                    shields)
            end
            local error_message = screen:snapshot("mame-game-restart.png")
            if error_message then
                fail("restart snapshot failed: " .. tostring(error_message))
            end
            print(string.format(
                "MC-10 game restart: PASS lives=%d score=%02X%02X%02X%02X player-x=%02X",
                state.lives,
                state.score0,
                state.score1,
                state.score2,
                state.score3,
                state.player_x))
            print("MC-10 game regression: PASS")
            phase = "complete"
            machine:exit()
            return true
        end
        return nil, state_error or "restart did not restore the opening game state"
    end

    return nil, "unknown game input phase: " .. phase
end

frame_subscription = emu.add_machine_frame_notifier(function()
    frame = frame + 1

    if not started and frame >= 240 then
        cassette:play()
        started = true
        print(string.format("MC-10 cassette: PLAY at frame %d", frame))
    end

    local tape_at_end = cassette.length > 0 and cassette.position >= cassette.length - 0.25
    if started and not exec_sent and frame >= EXEC_MIN_FRAME
        and (tape_at_end or frame >= EXEC_TIMEOUT_FRAME) then
        trace_state("before-exec")
        cassette:stop()
        keyboard:post_coded("EXEC{ENTER}")
        exec_sent = true
        deadline = frame + GAME_TIMEOUT_FRAMES
        phase = "waiting for initial game screen"
        phase_deadline = deadline
        print(string.format("MC-10 keyboard: EXEC{ENTER} at frame %d", frame))
    end

    if exec_sent and frame % 120 == 0 then
        trace_state("waiting")
    end

    if exec_sent and phase ~= "complete" and frame <= phase_deadline and game_main_loop_active() then
        local ok, message = verify_game_input()
        if ok then
            return
        end
        last_message = message
        if frame == phase_deadline then
            fail(message or "initial game screen did not render")
        end
    elseif exec_sent and phase ~= "complete" and frame > phase_deadline then
        fail(last_message or (phase .. " timed out"))
    end
end)
