# LUA Induction GUI

A ComputerCraft (CC:Tweaked) program that shows a live GUI for a **Mekanism
Induction Matrix**: a colored progress bar plus stored energy, total capacity,
charge %, input/output rates, and a time-to-full / time-to-empty estimate.

* Units auto-scale as your storage grows: `FE`, `kFE`, `MFE`, `GFE`, `TFE`, `PFE`…
* Capacity is re-read every refresh, so **adding more Induction Cells or
  Providers updates the display instantly** — no restart needed.
* Draws on the computer's own terminal **and** every attached monitor at the
  same time, picking the biggest text scale that fits each monitor.
* Handles the matrix being broken/unformed, the port disconnecting, and
  chunk reloads by re-scanning automatically.
* Works on basic (grayscale) and advanced (color) computers/monitors.

```
                Induction Matrix
 ─────────────────────────────────────────────
  Stored                             493.6 MFE
  Capacity                            1.02 GFE

  ████████████████ 48.2% ░░░░░░░░░░░░░░░░░░░░

  Input                             4.80 kFE/t
  Output                            1.60 kFE/t
  Net                              +3.20 kFE/t
  Full in                               2h 18m

            Cells: 256   Providers: 4
```

## Requirements

* Minecraft 1.16.5+ with **Mekanism v10.1 or newer** (built-in computer
  integration) and **CC:Tweaked**.
* A formed Induction Matrix with at least one **Induction Port**.

## Setup

1. Place a computer directly against one of the matrix's Induction Ports,
   **or** connect the two with wired modems + network cable (right-click each
   modem so it turns red/active).
2. (Optional) Attach a monitor — any size works, advanced monitors get colors.
3. Install the program on the computer:

   ```
   wget https://raw.githubusercontent.com/AidanPotter15/LUAInductionGUI/main/induction.lua induction.lua
   ```

4. Run it:

   ```
   induction
   ```

   To use one specific monitor instead of all of them:

   ```
   induction monitor_0
   ```

   Press `Q` (or hold `Ctrl+T`) to quit.

### Run automatically on boot

```
edit startup.lua
```

and put this in it:

```lua
shell.run("induction")
```

## Configuration

All options are at the top of `induction.lua`:

| Option          | Default  | Meaning                                              |
| --------------- | -------- | ---------------------------------------------------- |
| `REFRESH`       | `1`      | Seconds between screen updates                       |
| `UNIT`          | `"FE"`   | `"FE"` (Forge Energy) or `"J"` (raw Mekanism Joules) |
| `JOULES_PER_FE` | `2.5`    | Mekanism's `energyConversionRate` config value       |
| `MONITOR_NAME`  | `nil`    | Lock to one monitor, e.g. `"monitor_0"`; `nil` = all |
| `TITLE`         | …        | Heading shown at the top                             |

## About the units

Mekanism always reports energy to computers in **Joules**, regardless of the
display unit chosen in Mekanism's own config/GUI. This program converts to FE
using Mekanism's default rate of **2.5 J per 1 FE**. If your modpack changes
`energyConversionRate` in `config/mekanism/general.toml`, set `JOULES_PER_FE`
to the same value so the numbers match other mods' machines.

## Troubleshooting

* **"No Induction Port found"** — the computer isn't touching an Induction
  Port and no port is reachable over wired modems. If you're using modems,
  right-click both modems so they show a red band and a name like
  `inductionPort_0` appears in chat.
* **"Matrix is not formed!"** — the multiblock is incomplete; finish it and
  the display resumes by itself.
* **Numbers look ~2.5× too big** — you're comparing FE against Joules
  somewhere; check `UNIT` / `JOULES_PER_FE` (see "About the units" above).
* **Nothing on the monitor** — make sure the monitor is attached to the
  computer (or its wired network), then the program will pick it up within a
  second; no restart needed.
