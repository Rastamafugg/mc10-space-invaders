-- MAME 0.289 regression harness for the MC-10 timing calibrator.
--
-- The cassette image is mounted by MAME before this script starts.  The
-- script controls only the emulated machine after startup: it enters CLOADM,
-- starts the cassette, waits for the complete image, enters EXEC, cycles the
-- three calibrator modes, and analyzes the rendered screen pixels.
--
-- Run with:
--   mame.exe mc10 -ramsize 20K -cass build/timing-calibrator.c10 \
--     -autoboot_delay 2 \
--     -autoboot_script scripts/mame-calibrator-regression.lua \
--     -snapshot_directory build/mame-snapshots -seconds_to_run 120

local machine = manager.machine
local cassette = machine.cassettes[":cassette"]
local screen = machine.screens[":screen"]
local keyboard = machine.natkeyboard
local cpu = machine.devices[":maincpu"]
local program_space = cpu and cpu.spaces["program"]

local CAL_MODE = 0x00F1
local CAL_SWEEP_ACTIVE = 0x00F7
local CAL_PERIOD_H = 0x00E0
local CAL_PERIOD_L = 0x00E1
local CAL_PHASE_H = 0x00E2
local CAL_PHASE_L = 0x00E3
local CAL_EVENTS_H = 0x00E4
local CAL_EVENTS_L = 0x00E5

local EXEC_MIN_FRAME = 2400
local EXEC_TIMEOUT_FRAME = 4200
local ALPHA_FRAME = 4800
local KEY_TIMEOUT_FRAMES = 240
local SAMPLE_GAP_FRAMES = 120
local ACTIVE_WIDTH = 256
local ACTIVE_HEIGHT = 192
local ACTIVE_PIXELS = ACTIVE_WIDTH * ACTIVE_HEIGHT

local PHASE_WAIT_ALPHA = 1
local PHASE_WAIT_DRIFT = 2
local PHASE_DRIFT_GAP = 3
local PHASE_WAIT_SWEEP = 4
local PHASE_SWEEP_GAP = 5
local PHASE_WAIT_PAUSE = 6
local PHASE_PAUSED_GAP = 7
local PHASE_WAIT_RESUME = 8
local PHASE_WAIT_RETURN_ALPHA = 9
local PHASE_DONE = 10

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
local phase = PHASE_WAIT_ALPHA
local deadline = ALPHA_FRAME + KEY_TIMEOUT_FRAMES
local drift_first = nil
local sweep_first = nil
local paused_first = nil
local failed = false

local function fail(message)
    if failed then
        return
    end
    failed = true
    phase = PHASE_DONE
    print("MC-10 calibrator regression: FAIL: " .. message)
    machine:exit()
    error("MC-10 calibrator regression: " .. message)
end

local function read_byte(address)
    return program_space:read_u8(address)
end

local function read_word(address)
    return read_byte(address) * 0x100 + read_byte(address + 1)
end

local function format_bbox(box)
    if not box then
        return "none"
    end
    return string.format("%d,%d-%d,%d", box.left, box.top, box.right, box.bottom)
end

local function rgb_from_pixel(value)
    -- screen:pixel() returns either a palette index or a packed RGB value.
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
    if green >= red + 20 and green >= blue + 20 then
        return "green"
    end
    if red >= green + 40 and red >= blue + 40 then
        return "red"
    end
    if blue >= red + 30 and blue >= green + 30 then
        return "blue"
    end
    return "other"
end

local function analyze_pixels()
    local pixels, width, height = screen:pixels()
    assert(type(pixels) == "string", "screen:pixels() did not return a pixel buffer")
    assert(width and height and width > 0 and height > 0, "screen dimensions are invalid")

    local counts = { blue = 0, green = 0, red = 0, other = 0 }
    local boxes = {
        blue = nil,
        green = nil,
        red = nil,
    }

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

local function changed_pixels(first, second)
    if first.width ~= second.width or first.height ~= second.height then
        return first.total
    end

    -- MAME returns a 32-bit value for each visible pixel.  Comparing four
    -- bytes per pixel avoids depending on host endianness or pixel format.
    local changed = 0
    local length = math.min(#first.pixels, #second.pixels)
    for offset = 1, length, 4 do
        if string.byte(first.pixels, offset) ~= string.byte(second.pixels, offset)
            or string.byte(first.pixels, offset + 1) ~= string.byte(second.pixels, offset + 1)
            or string.byte(first.pixels, offset + 2) ~= string.byte(second.pixels, offset + 2)
            or string.byte(first.pixels, offset + 3) ~= string.byte(second.pixels, offset + 3) then
            changed = changed + 1
        end
    end
    return changed
end

local function print_metrics(label, metrics, delta)
    local suffix = delta and string.format(" changed=%d", delta) or ""
    print(string.format(
        "MC-10 pixels: %s size=%dx%d blue=%d green=%d red=%d other=%d green-box=%s red-box=%s%s",
        label,
        metrics.width,
        metrics.height,
        metrics.counts.blue,
        metrics.counts.green,
        metrics.counts.red,
        metrics.counts.other,
        format_bbox(metrics.boxes.green),
        format_bbox(metrics.boxes.red),
        suffix))
end

local function save_snapshot(name)
    local error_message = screen:snapshot(name .. ".png")
    if error_message then
        fail(string.format("snapshot %s failed: %s", name, tostring(error_message)))
    end
end

local function require_mode(expected, label)
    local actual = read_byte(CAL_MODE)
    if actual ~= expected then
        fail(string.format("%s expected CAL_MODE=%d, got %d", label, expected, actual))
    end
end

local function alpha_ready(metrics)
    local green = metrics.counts.green
    return green >= ACTIVE_PIXELS * 0.90
        and metrics.counts.blue == 0
        and metrics.counts.red == 0
end

local function sample_alpha(label)
    if read_byte(CAL_MODE) ~= 0 then
        return nil
    end
    local metrics = analyze_pixels()
    if not alpha_ready(metrics) then
        return nil
    end
    print_metrics(label, metrics)
    save_snapshot("mame-calibrator-" .. label)
    return metrics
end

local function cg3_ready(metrics, expected_color)
    return metrics.counts.blue >= ACTIVE_PIXELS * 0.90
        and metrics.counts[expected_color] >= 256
end

local function sample_cg3(label, expected_color)
    local metrics = analyze_pixels()
    if not cg3_ready(metrics, expected_color) then
        return nil
    end
    print_metrics(label, metrics)
    save_snapshot("mame-calibrator-" .. label)
    return metrics
end

local function post_key(code, description, next_phase, next_deadline)
    keyboard:post_coded(code)
    phase = next_phase
    deadline = next_deadline or (frame + KEY_TIMEOUT_FRAMES)
    print(string.format("MC-10 keyboard: %s at frame %d", description, frame))
end

local function trace_state(label)
    local pc_entry = cpu.state["PC"] or cpu.state["CURPC"] or cpu.state["rPC"]
    local pc = pc_entry and pc_entry.value or -1
    print(string.format(
        "MC-10 trace: %s pc=%04X mode=%02X active=%02X period=%04X phase=%04X events=%04X tape=%.2f/%.2f playing=%s posting=%s empty=%s",
        label,
        pc,
        read_byte(CAL_MODE),
        read_byte(CAL_SWEEP_ACTIVE),
        read_word(CAL_PERIOD_H),
        read_word(CAL_PHASE_H),
        read_word(CAL_EVENTS_H),
        cassette.position,
        cassette.length,
        tostring(cassette.is_playing),
        tostring(keyboard.is_posting),
        tostring(keyboard.empty)))
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
        deadline = ALPHA_FRAME + KEY_TIMEOUT_FRAMES
        print(string.format("MC-10 keyboard: EXEC{ENTER} at frame %d", frame))
    end

    if not exec_sent or phase == PHASE_DONE then
        return
    end

    if phase == PHASE_WAIT_ALPHA then
        if frame >= ALPHA_FRAME then
            local alpha = sample_alpha("alpha")
            if alpha then
                post_key("M", "M to raster drift", PHASE_WAIT_DRIFT)
            elseif frame > deadline then
                fail("initial alpha render was not visible")
            end
        end
    elseif phase == PHASE_WAIT_DRIFT then
        if read_byte(CAL_MODE) == 1 then
            drift_first = sample_cg3("drift-first", "green")
            if drift_first then
                phase = PHASE_DRIFT_GAP
                deadline = frame + SAMPLE_GAP_FRAMES
            elseif frame > deadline then
                fail("raster-drift mode did not render a blue CG3 surface")
            end
        elseif frame > deadline then
            fail("M did not select raster-drift mode")
        end
    elseif phase == PHASE_DRIFT_GAP then
        if frame >= deadline then
            local drift_second = sample_cg3("drift-second", "green")
            if not drift_second then
                fail("raster-drift render disappeared before the second sample")
            end
            local delta = changed_pixels(drift_first, drift_second)
            if delta < 64 then
                fail(string.format("raster-drift witness did not move enough: changed=%d", delta))
            end
            print(string.format("MC-10 pixels: raster-drift motion pass changed=%d", delta))
            post_key("M", "M to phase sweep", PHASE_WAIT_SWEEP)
        end
    elseif phase == PHASE_WAIT_SWEEP then
        if read_byte(CAL_MODE) == 2 then
            sweep_first = sample_cg3("sweep-first", "red")
            if sweep_first then
                phase = PHASE_SWEEP_GAP
                deadline = frame + SAMPLE_GAP_FRAMES
            elseif frame > deadline then
                fail("phase-sweep mode did not render a blue CG3 surface")
            end
        elseif frame > deadline then
            fail("M did not select phase-sweep mode")
        end
    elseif phase == PHASE_SWEEP_GAP then
        if frame >= deadline then
            local sweep_second = sample_cg3("sweep-second", "red")
            if not sweep_second then
                fail("phase-sweep render disappeared before the second sample")
            end
            local delta = changed_pixels(sweep_first, sweep_second)
            if delta < 64 then
                fail(string.format("phase-sweep witness did not move enough: changed=%d", delta))
            end
            print(string.format("MC-10 pixels: phase-sweep motion pass changed=%d", delta))
            post_key("{P}", "P pause sweep", PHASE_WAIT_PAUSE)
        end
    elseif phase == PHASE_WAIT_PAUSE then
        if read_byte(CAL_SWEEP_ACTIVE) == 0 then
            paused_first = sample_cg3("paused-first", "red")
            if paused_first then
                phase = PHASE_PAUSED_GAP
                deadline = frame + SAMPLE_GAP_FRAMES
            elseif frame > deadline then
                fail("paused phase-sweep render was not visible")
            end
        elseif frame > deadline then
            fail("P did not pause phase sweep")
        end
    elseif phase == PHASE_PAUSED_GAP then
        if frame >= deadline then
            local paused_second = sample_cg3("paused-second", "red")
            if not paused_second then
                fail("paused phase-sweep render disappeared before the second sample")
            end
            local delta = changed_pixels(paused_first, paused_second)
            if delta ~= 0 then
                fail(string.format("paused sweep changed rendered pixels: changed=%d", delta))
            end
            print("MC-10 pixels: paused-sweep stability pass changed=0")
            post_key("{P}", "P resume sweep", PHASE_WAIT_RESUME)
        end
    elseif phase == PHASE_WAIT_RESUME then
        if read_byte(CAL_SWEEP_ACTIVE) == 1 then
            post_key("M", "M return to alpha", PHASE_WAIT_RETURN_ALPHA)
        elseif frame > deadline then
            fail("P did not resume phase sweep")
        end
    elseif phase == PHASE_WAIT_RETURN_ALPHA then
        if read_byte(CAL_MODE) == 0 then
            local alpha = sample_alpha("return-alpha")
            if alpha then
                trace_state("complete")
                print("MC-10 calibrator regression: PASS")
                phase = PHASE_DONE
                machine:exit()
            elseif frame > deadline then
                fail("return to alpha changed the mode byte but not the rendered pixels")
            end
        elseif frame > deadline then
            fail("M did not cycle from phase sweep back to alpha mode")
        end
    end
end)
