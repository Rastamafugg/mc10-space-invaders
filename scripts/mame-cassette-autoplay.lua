-- MAME 0.289 regression helper for MC-10 cassette images.
--
-- MAME starts the MC-10 cassette motor stopped.  This script starts playback
-- after the machine has reached its command prompt, then requests a snapshot
-- late enough to include the cassette-loaded program's output.

local machine = manager.machine
local cassette = machine.cassettes[":cassette"]
local screen = machine.screens[":screen"]
local keyboard = machine.natkeyboard
local cpu = machine.devices[":maincpu"]
local program_space = cpu and cpu.spaces["program"]
local frame = 0
local started = false
local exec_sent = false
local captured = false

local EXEC_MIN_FRAME = 2400
local EXEC_TIMEOUT_FRAME = 4200
local SNAPSHOT_FRAME = 4800

assert(cassette, "MC-10 cassette device not found")
assert(screen, "MC-10 screen device not found")
assert(keyboard and keyboard.can_post, "MC-10 natural keyboard input is unavailable")
assert(program_space, "MC-10 CPU program address space not found")

-- Use MAME's emulated keyboard path so the test does not depend on host
-- focus or on command-line newline escaping.
keyboard.in_use = true
keyboard:post_coded("CLOADM{ENTER}")
print("MC-10 keyboard: CLOADM{ENTER}")

local function trace_state(label)
    local pc_entry = cpu.state["PC"] or cpu.state["CURPC"] or cpu.state["rPC"]
    local pc = pc_entry and pc_entry.value or -1
    print(string.format(
        "MC-10 trace: %s pc=%04X mem5000=%02X mem5001=%02X tape=%.2f/%.2f playing=%s posting=%s empty=%s",
        label,
        pc,
        program_space:read_u8(0x5000),
        program_space:read_u8(0x5001),
        cassette.position,
        cassette.length,
        tostring(cassette.is_playing),
        tostring(keyboard.is_posting),
        tostring(keyboard.empty)))
end

frame_subscription = emu.add_machine_frame_notifier(function()
    frame = frame + 1

    -- Leave enough time for -autoboot_command to enter CLOADM before the
    -- cassette begins moving.  The MC-10 loader then displays its search state.
    if not started and frame >= 240 then
        cassette:play()
        started = true
        print(string.format("MC-10 cassette: PLAY at frame %d", frame))
    end

    if frame == 1200 then
        trace_state("pre-transfer-check")
    end

    -- The cassette image contains a machine-language load.  CLOADM returns
    -- to BASIC after the transfer; EXEC is required to enter the image.  The
    -- image contains a long leader and trailer, so a fixed early delay can
    -- post EXEC while the loader is still active.
    local tape_at_end = cassette.length > 0 and cassette.position >= cassette.length - 0.25
    local exec_timeout = frame >= EXEC_TIMEOUT_FRAME
    if started and not exec_sent and frame >= EXEC_MIN_FRAME and (tape_at_end or exec_timeout) then
        trace_state("before-exec")
        cassette:stop()
        keyboard:post_coded("EXEC{ENTER}")
        exec_sent = true
        print(string.format("MC-10 keyboard: EXEC{ENTER} at frame %d", frame))
    end

    if exec_sent and frame == 3600 then
        trace_state("after-exec")
    end

    if exec_sent and not captured and frame >= SNAPSHOT_FRAME then
        local error_message = screen:snapshot("timer-mame289.png")
        captured = true
        print(string.format("MC-10 cassette: SNAPSHOT at frame %d (%s)", frame, tostring(error_message)))
    end
end)
