# My Mac X

My Mac X describes window placement as user intent independent of whether it came from a pointer, hotkey, menu or Super Mode. This glossary keeps product copy, design and code aligned.

## Windows and screens

**Eligible Window**:
A user-facing application window that can participate in at least one Window Action.
_Avoid_: Adjustable Window, manageable window

**Focused Window**:
The Eligible Window selected by macOS when a direct Window Action begins.
_Avoid_: Active app, current app

**Captured Window**:
The Eligible Window identity bound to an in-progress interaction or action, even if focus later changes.
_Avoid_: Current window, target app

**Display**:
A physical screen available to macOS.
_Avoid_: Desktop, monitor space

**Space**:
A macOS virtual workspace managed through Mission Control.
_Avoid_: Display, screen, Desktop when referring to hardware

## Placement

**Window Action**:
A named user intent that previews, places, restores or changes the display of one Captured Window.
_Avoid_: Command, operation, shortcut action

**Layout**:
A named arrangement containing one or more normalized regions within a Display's usable area.
_Avoid_: Preset, grid template

**Layout Region**:
One selectable normalized area inside a Layout.
_Avoid_: Cell, slot, tile

**Snap**:
Placing a Captured Window into a Layout Region after a user confirms a pointer or keyboard interaction.
_Avoid_: Tile, resize

**Maximize**:
Placing a window across the Display's usable area while keeping it in the current Space.
_Avoid_: Full screen

**Native Full Screen**:
The macOS window state that may create or enter a dedicated Space.
_Avoid_: Maximize

**Cycle Group**:
An ordered set of Window Actions traversed by repeating the same input binding.
_Avoid_: Rotation, alternate sizes

**Window Snapshot**:
The remembered placement of one Captured Window before a committed Window Action.
_Avoid_: Backup, saved frame

**Undo**:
Restoring the Window Snapshot created by the latest applicable committed action.
_Avoid_: Reset

**Restore**:
Returning a Captured Window to its remembered non-layout placement.
_Avoid_: Undo when referring to action history

## Pointer interaction

**Notch Trigger**:
The top-edge activation region that opens the Layout Chooser; it falls back to top-center on a Display without a notch.
_Avoid_: Drop zone, hotspot

**Layout Chooser**:
The transient surface for selecting a Layout Region during a Snap interaction.
_Avoid_: Popup grid, snap menu

**Placement Preview**:
A non-mutating representation of the frame a Window Action would produce.
_Avoid_: Ghost window, fake window

## Keyboard interaction

**Super Mode**:
A temporary keyboard mode entered through a Prefix and completed by a registered key sequence.
_Avoid_: Leader mode, command mode

**Prefix**:
The configurable key combination that arms Super Mode for a bounded time.
_Avoid_: Super key, leader key

