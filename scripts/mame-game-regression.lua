-- MAME 0.289 regression harness for the MC-10 Space Invaders target.
--
-- The cassette image is mounted by MAME before this script starts. The script
-- enters the MC-10 machine-code loader, waits for the complete Space Invaders
-- image, executes it, and verifies the first rendered game screen.
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
local GAME_PLAYER_X = 0x00E8
local GAME_BULLET_ACTIVE = 0x00EB
local GAME_ALIEN_SHOT_ACTIVE = 0x00EE
local GAME_INVADER_X = 0x00F0
local GAME_INVADER_Y = 0x00F1
local GAME_BONUS_ACTIVE = 0x00F6
local GAME_SHIELDS_ACTIVE = 0x00FB
local ALIEN_LIVE = 0x4C00
local WORK_TEMP = 0x4C49

local EXEC_MIN_FRAME = 2400
local EXEC_TIMEOUT_FRAME = 7200
local GAME_TIMEOUT_FRAMES = 600
local ACTIVE_WIDTH = 256
local ACTIVE_HEIGHT = 192
local ACTIVE_PIXELS = ACTIVE_WIDTH * ACTIVE_HEIGHT

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
    print("MC-10 game regression: PASS")
    machine:exit()
    return true
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
        print(string.format("MC-10 keyboard: EXEC{ENTER} at frame %d", frame))
    end

    if exec_sent and frame % 120 == 0 then
        trace_state("waiting")
    end

    if exec_sent and frame <= deadline and game_main_loop_active() then
        local ok, message = verify_initial_screen()
        if ok then
            return
        end
        last_message = message
        if frame == deadline then
            fail(message or "initial game screen did not render")
        end
    elseif exec_sent and frame > deadline then
        fail(last_message or "initial game screen did not render before timeout")
    end
end)
