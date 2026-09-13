-- MAME 0.289 manual-play launcher for the MC-10 Space Invaders target.
--
-- MAME starts the MC-10 cassette motor stopped.  This script enters CLOADM,
-- starts the cassette, waits for the complete image plus a short BASIC settle
-- interval, enters EXEC, and leaves the game running for manual input.
-- The launcher supplies a temporary accelerated speed through -speed.  Once
-- the loaded program reaches its game loop, this script restores normal speed.

local machine = manager.machine
local cassette = machine.cassettes[":cassette"]
local keyboard = machine.natkeyboard
local cpu = machine.devices[":maincpu"]
local program_space = cpu and cpu.spaces["program"]
local video = machine.video
local ui = manager.ui

local frame = 0
local cassette_started = false
local tape_end_frame = nil
local exec_sent = false
local game_started = false
local load_timeout_reported = false

local CASSETTE_START_FRAME = 240
local EXEC_MIN_FRAME = 2400
local TAPE_SETTLE_FRAMES = 30
local LOAD_TIMEOUT_FRAME = 7200
local GAME_LOOP_FIRST = 0x502C
local GAME_LOOP_LAST = 0x503B

assert(cassette, "MC-10 cassette device not found")
assert(keyboard and keyboard.can_post, "MC-10 natural keyboard input is unavailable")
assert(cpu and program_space, "MC-10 CPU program address space not found")
assert(video, "MAME video manager is unavailable")
assert(ui, "MAME UI manager is unavailable")

keyboard.in_use = true
ui.show_fps = true
video.throttled = true
keyboard:post_coded("CLOADM{ENTER}")
machine:popmessage("MC-10 loading Space Invaders")
print("MC-10 manual play: CLOADM{ENTER}")

local function cpu_pc()
    local pc_entry = cpu.state["PC"] or cpu.state["CURPC"] or cpu.state["rPC"]
    return pc_entry and pc_entry.value or -1
end

local function game_main_loop_active()
    local pc = cpu_pc()
    return pc >= GAME_LOOP_FIRST and pc <= GAME_LOOP_LAST
end

local function restore_normal_speed()
    local speed_factor = video.speed_factor
    local normal_rate = 1.0
    if speed_factor and speed_factor > 0 then
        -- throttle_rate is relative to MAME's configured -speed factor.
        normal_rate = 1000.0 / speed_factor
    end
    video.throttle_rate = normal_rate
    video.throttled = true
    print(string.format(
        "MC-10 manual play: game loop reached at frame %d, normal speed restored (factor=%d rate=%.3f)",
        frame,
        speed_factor or 1000,
        normal_rate))
    machine:popmessage("SPACE INVADERS READY: A/D move, SPACE fire")
end

frame_subscription = emu.add_machine_frame_notifier(function()
    frame = frame + 1

    if not cassette_started and frame >= CASSETTE_START_FRAME then
        cassette:play()
        cassette_started = true
        print(string.format("MC-10 manual play: cassette PLAY at frame %d", frame))
    end

    local tape_at_end = cassette.length > 0
        and cassette.position >= cassette.length - 0.25
    if cassette_started and not exec_sent then
        if tape_at_end and not tape_end_frame then
            tape_end_frame = frame
            print(string.format(
                "MC-10 manual play: cassette end detected at frame %d (%.2f/%.2f)",
                frame,
                cassette.position,
                cassette.length))
        end

        local end_settled = tape_end_frame
            and frame >= tape_end_frame + TAPE_SETTLE_FRAMES
        if frame >= EXEC_MIN_FRAME and end_settled then
            cassette:stop()
            keyboard:post_coded("EXEC{ENTER}")
            exec_sent = true
            print(string.format("MC-10 manual play: EXEC{ENTER} at frame %d", frame))
        elseif frame >= LOAD_TIMEOUT_FRAME and not load_timeout_reported then
            load_timeout_reported = true
            cassette:stop()
            machine:popmessage("MC-10 cassette load timeout")
            print("MC-10 manual play: ERROR cassette end was not detected")
        end
    end

    if exec_sent and not game_started and game_main_loop_active() then
        game_started = true
        restore_normal_speed()
    end
end)
