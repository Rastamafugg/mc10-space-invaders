-- MAME 0.289 regression harness for the MC-10 IRQ1 sanity test.
--
-- The cassette image is mounted before this script starts. The harness uses
-- the emulated keyboard and cassette controls, waits for the complete
-- transfer, enters EXEC, and reads the diagnostic's RAM proof points. The
-- test is successful only when the IRQ1 handler count is zero after CLI has
-- been active for the observation window.
--
-- Run with:
--   mame.exe mc10 -noreadconfig -ramsize 20K \
--     -rompath <rom-path> -cass build/irq1-sanity.c10 \
--     -autoboot_delay 2 \
--     -autoboot_script scripts/mame-irq1-regression.lua \
--     -seconds_to_run 120 -window -nothrottle

local machine = manager.machine
local cassette = machine.cassettes[":cassette"]
local screen = machine.screens[":screen"]
local keyboard = machine.natkeyboard
local cpu = machine.devices[":maincpu"]
local program_space = cpu and cpu.spaces["program"]

local IRQ1_COUNT = 0x00E0
local IRQ1_DONE = 0x00E1
local IRQ1_STATUS = 0x00E2

local PLAY_FRAME = 240
local EXEC_MIN_FRAME = 1800
local EXEC_TIMEOUT_FRAME = 7200
local TAPE_SETTLE_FRAMES = 30
local RESULT_STABLE_FRAMES = 10
local TEST_TIMEOUT_FRAME = 12000

assert(cassette, "MC-10 cassette device not found")
assert(screen, "MC-10 screen device not found")
assert(keyboard and keyboard.can_post, "MC-10 natural keyboard input is unavailable")
assert(program_space, "MC-10 CPU program address space not found")

keyboard.in_use = true
keyboard:post_coded("CLOADM{ENTER}")
print("MC-10 IRQ1 keyboard: CLOADM{ENTER}")

local frame = 0
local started = false
local exec_sent = false
local tape_end_frame = nil
local result_frame = nil
local failed = false

local function read_byte(address)
    return program_space:read_u8(address)
end

local function fail(message)
    if failed then
        return
    end
    failed = true
    print("MC-10 IRQ1 sanity: FAIL: " .. message)
    machine:exit()
    error("MC-10 IRQ1 sanity: " .. message)
end

local function trace_state(label)
    local pc_entry = cpu.state["PC"] or cpu.state["CURPC"] or cpu.state["rPC"]
    local pc = pc_entry and pc_entry.value or -1
    print(string.format(
        "MC-10 IRQ1 trace: %s pc=%04X count=%02X done=%02X status=%02X tape=%.2f/%.2f playing=%s",
        label,
        pc,
        read_byte(IRQ1_COUNT),
        read_byte(IRQ1_DONE),
        read_byte(IRQ1_STATUS),
        cassette.position,
        cassette.length,
        tostring(cassette.is_playing)))
end

local function save_snapshot(name)
    local error_message = screen:snapshot(name)
    if error_message then
        fail("snapshot failed: " .. tostring(error_message))
    end
end

frame_subscription = emu.add_machine_frame_notifier(function()
    frame = frame + 1

    if not started and frame >= PLAY_FRAME then
        cassette:play()
        started = true
        print(string.format("MC-10 IRQ1 cassette: PLAY at frame %d", frame))
    end

    local tape_at_end = cassette.length > 0 and cassette.position >= cassette.length - 0.25
    if started and not exec_sent and tape_at_end and not tape_end_frame then
        tape_end_frame = frame
        print(string.format("MC-10 IRQ1 cassette: end detected at frame %d", frame))
    end

    local end_settled = tape_end_frame and frame >= tape_end_frame + TAPE_SETTLE_FRAMES
    if started and not exec_sent and frame >= EXEC_MIN_FRAME
        and (end_settled or frame >= EXEC_TIMEOUT_FRAME) then
        trace_state("before-exec")
        cassette:stop()
        keyboard:post_coded("EXEC{ENTER}")
        exec_sent = true
        print(string.format("MC-10 IRQ1 keyboard: EXEC{ENTER} at frame %d", frame))
    end

    if exec_sent and not result_frame and read_byte(IRQ1_DONE) == 1 then
        result_frame = frame + RESULT_STABLE_FRAMES
        print(string.format("MC-10 IRQ1: diagnostic completed at frame %d", frame))
    end

    if result_frame and frame >= result_frame then
        local count = read_byte(IRQ1_COUNT)
        local done = read_byte(IRQ1_DONE)
        local status = read_byte(IRQ1_STATUS)
        trace_state("result")
        save_snapshot("mame-irq1-sanity.png")
        if count ~= 0 or done ~= 1 or status ~= 1 then
            fail(string.format(
                "unexpected result count=%02X done=%02X status=%02X",
                count, done, status))
        end
        print(string.format(
            "MC-10 IRQ1 sanity: PASS (count=%02X status=%02X done=%02X)",
            count, status, done))
        print("MC-10 IRQ1 proof: IRQ1: INACTIVE, handler count remained zero")
        machine:exit()
        return
    end

    if frame >= TEST_TIMEOUT_FRAME then
        trace_state("timeout")
        fail("cassette transfer or diagnostic result timed out")
    end
end)
