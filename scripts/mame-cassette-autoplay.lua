-- MAME 0.289 regression helper for MC-10 cassette images.
--
-- MAME starts the MC-10 cassette motor stopped.  This script starts playback
-- after the machine has reached its command prompt, then requests a snapshot
-- late enough to include the cassette-loaded program's output.

local machine = manager.machine
local cassette = machine.cassettes[":cassette"]
local screen = machine.screens[":screen"]
local keyboard = machine.natkeyboard
local frame = 0
local started = false
local exec_sent = false
local captured = false

assert(cassette, "MC-10 cassette device not found")
assert(screen, "MC-10 screen device not found")
assert(keyboard and keyboard.can_post, "MC-10 natural keyboard input is unavailable")

-- Use MAME's emulated keyboard path so the test does not depend on host
-- focus or on command-line newline escaping.
keyboard.in_use = true
keyboard:post_coded("CLOADM{ENTER}")
print("MC-10 keyboard: CLOADM{ENTER}")

frame_subscription = emu.add_machine_frame_notifier(function()
    frame = frame + 1

    -- Leave enough time for -autoboot_command to enter CLOADM before the
    -- cassette begins moving.  The MC-10 loader then displays its search state.
    if not started and frame >= 240 then
        cassette:play()
        started = true
        print(string.format("MC-10 cassette: PLAY at frame %d", frame))
    end

    -- The cassette image contains a machine-language load.  CLOADM returns
    -- to BASIC after the transfer; EXEC is required to enter the image.
    if started and not exec_sent and frame >= 2400 then
        keyboard:post_coded("EXEC{ENTER}")
        exec_sent = true
        print(string.format("MC-10 keyboard: EXEC{ENTER} at frame %d", frame))
    end

    if started and not captured and frame >= 3600 then
        local error_message = screen:snapshot("timer-mame289.png")
        captured = true
        print(string.format("MC-10 cassette: SNAPSHOT at frame %d (%s)", frame, tostring(error_message)))
    end
end)
