# ExcelMacHelper

A native macOS menu bar app that brings Windows-style Excel productivity to Mac. Two core features make the transition from Windows Excel seamless:

1. **Per-App Function Key Toggle** - F1-F12 behave as standard function keys when Excel is active, media keys everywhere else
2. **Full Windows Alt-Key Ribbon Shortcuts** - 247 Windows Excel Alt+Key shortcuts mapped to their Mac equivalents with a visual HUD overlay

## Requirements

- macOS 14.0 (Sonoma) or later
- Apple Silicon (arm64) native
- Microsoft Excel for Mac
- Accessibility permissions (required for keyboard interception)

## Building

### With Xcode

1. Open `ExcelMacHelper.xcodeproj` in Xcode
2. Select the `ExcelMacHelper` scheme
3. Press **Cmd+R** to build and run

### With xcodebuild (Command Line)

```bash
xcodebuild -project ExcelMacHelper.xcodeproj -scheme ExcelMacHelper -configuration Release build
```

The built app will be in `build/Release/ExcelMacHelper.app`.

## Setup

### 1. Grant Accessibility Permissions

ExcelMacHelper requires Accessibility access to intercept keyboard events. On first launch:

1. The app will prompt you to grant Accessibility access
2. Click **Open System Settings** (or go to System Settings > Privacy & Security > Accessibility)
3. Find **ExcelMacHelper** in the list
4. Toggle the switch to enable access
5. If prompted, enter your administrator password
6. The app will automatically detect the permission change and start working

### 2. Menu Bar Icon

Once running, ExcelMacHelper appears as a keyboard icon in your menu bar:

- **Green keyboard** = Active and monitoring
- **Gray keyboard** = Inactive (permissions not granted or features disabled)

Click the icon to access the menu with quick toggles, preferences, and status information.

### 3. Launch at Login (Optional)

Open Preferences (click menu bar icon > Preferences) and enable "Launch at Login" to start ExcelMacHelper automatically.

## Feature 1: Per-App Function Key Toggle

When Microsoft Excel (or any configured app) is the frontmost application, F1-F12 keys behave as standard function keys. When you switch to any other app, they revert to media keys (brightness, volume, etc.).

This works with built-in and external keyboards, including NuPhy keyboards via USB or Bluetooth.

### Adding Apps

By default, only Microsoft Excel is monitored. To add more apps:

1. Open Preferences > Apps tab
2. Type the application name (e.g., "Google Sheets")
3. Click **Add**

## Feature 2: Windows Alt-Key Ribbon Shortcuts

### How It Works

1. With Excel as the frontmost app, press and release the **Option (Alt)** key
2. A translucent HUD overlay appears showing available ribbon tab keys (H, N, P, M, A, R, W, L, F)
3. Press a key (e.g., **H** for Home tab) - the HUD updates to show available sub-options
4. Continue pressing keys to drill down the shortcut tree
5. After the 2nd level, ExcelMacHelper intercepts and executes the Mac-equivalent action

### Example: AutoFit Column Width

On Windows: `Alt, H, O, I` (press and release each key sequentially)

With ExcelMacHelper on Mac:
1. Press and release **Option** - HUD shows ribbon tabs
2. Press **H** - HUD shows Home tab options
3. Press **O** - Mac Excel handles up to here natively; HUD shows Format sub-options
4. Press **I** - ExcelMacHelper intercepts and executes "Format > Column > AutoFit Selection"

### Key Tips HUD

The HUD overlay shows:
- Current key sequence (e.g., `Alt > H > O`)
- Available next keys with labels
- Automatically hides after 3 seconds of inactivity or when Escape is pressed

The HUD can be disabled in Preferences while keeping shortcuts functional.

### Action Types

Shortcuts execute via three mechanisms:

| Type | Description | Example |
|------|-------------|---------|
| `keystroke` | Simulates a Mac keyboard shortcut | Cmd+B for Bold |
| `menu` | Navigates Mac Excel menus via AppleScript | Format > Column > AutoFit |
| `applescript` | Runs custom AppleScript commands | Custom automation |

## Customizing Shortcuts

### Shortcuts File Location

On first launch, the bundled shortcuts JSON is copied to:

```
~/Library/Application Support/ExcelMacHelper/shortcuts.json
```

### Editing Shortcuts

1. Open the file in any text editor
2. Add or modify entries following the existing format:

```json
{
  "keys": "Alt+H+V+V",
  "action": "Paste Values",
  "mac_action_type": "keystroke",
  "mac_equivalent": "Cmd+Shift+V"
}
```

3. Click **Reload Shortcuts** in the menu bar, or use the Reload button in Preferences

### Shortcut Entry Format

| Field | Description |
|-------|-------------|
| `keys` | Windows Alt-key sequence, `+` separated (e.g., `Alt+H+O+I`) |
| `action` | Human-readable description |
| `mac_action_type` | One of: `keystroke`, `menu`, `applescript` |
| `mac_equivalent` | Mac action to execute |

### Mac Equivalent Formats

**For `keystroke` type:**
- Key combos: `Cmd+V`, `Cmd+Shift+X`, `Ctrl+Shift+=`
- Sequential: `Cmd+Shift+C then Cmd+Shift+V`
- Alternatives: `Cmd+Shift+F2 or Cmd+Option+A` (first one is used)

**For `menu` type:**
- Menu path: `Format > Column > AutoFit Selection`
- Navigates the actual Mac Excel menu hierarchy

**For `applescript` type:**
- Any valid AppleScript code

### Using a Custom File

You can point to a different JSON file in Preferences > Shortcuts > Custom Path.

## Included Shortcuts (247 Total)

### Home Tab (H)
- **Clipboard**: Paste Values, Paste Special, Paste Formulas, Paste Formatting, Format Painter, Copy, Cut
- **Font**: Bold, Italic, Underline, Strikethrough, Font Color, Fill Color, Font Size
- **Borders**: Bottom, Top, Left, Right, All, No Border, Thick, Double, Outside
- **Alignment**: Top, Middle, Bottom, Left, Center, Right, Wrap Text, Indent
- **Merge**: Merge & Center, Merge Cells, Merge Across, Unmerge
- **Number Format**: Percentage, Currency, Increase/Decrease Decimal
- **Conditional Formatting**: Highlight Rules, Top/Bottom, Data Bars, Color Scales, Icon Sets
- **Cells**: Insert/Delete Rows, Columns, Cells, Sheets
- **Format**: AutoFit Column/Row, Set Width/Height, Hide/Unhide, Rename Sheet
- **Clear**: All, Formats, Contents, Comments, Hyperlinks
- **Sort & Filter**: Custom Sort, Ascending, Descending, Filter Toggle
- **Find**: Find, Replace, Go To, Go To Special

### Insert Tab (N)
- PivotTable, Table, Picture, Shape, Charts (Column, Bar, Pie, Line), Sparklines
- Hyperlink, Text Box, Header & Footer, Symbol, Equation, Function

### Page Layout Tab (P)
- Margins, Orientation, Paper Size, Print Area, Page Breaks, Print Titles, Scale, Gridlines, Headings

### Formulas Tab (M)
- Insert Function, AutoSum (SUM, Average, Count, Max, Min)
- Financial, Logical, Text, Date & Time, Lookup & Reference, Math & Trig
- Name Manager, Define Name, Trace Dependents/Precedents
- Show Formulas, Error Checking, Evaluate Formula, Watch Window

### Data Tab (A)
- Get External Data, Refresh All, Sort (A-Z, Z-A, Custom), Filter, Advanced Filter
- Data Validation, Text to Columns, Flash Fill, Remove Duplicates
- What-If Analysis (Goal Seek, Data Table, Scenario Manager)
- Group/Ungroup, Subtotal

### Review Tab (R)
- Spell Check, Thesaurus, Comments (New, Delete, Navigate)
- Protect Sheet, Protect Workbook, Track Changes

### View Tab (W)
- Normal, Page Break Preview, Page Layout, Gridlines, Headings
- Freeze Panes (All, Top Row, First Column), Split, Window management
- Zoom, Macros (Record, View, Relative References)

### Developer Tab (L)
- Visual Basic Editor, Macros, Record Macro, Macro Security
- Insert Form Control, Design Mode, Properties, View Code

### File Tab (F)
- New, Open, Save, Save As, Print, Close, Preferences, Export/PDF

### Legacy Shortcuts (pre-2007)
- Alt+E (Edit), Alt+O (Format), Alt+D (Data), Alt+I (Insert), Alt+T (Tools)

## Troubleshooting

### App doesn't intercept keystrokes
- Ensure Accessibility access is granted in System Settings > Privacy & Security > Accessibility
- Try removing and re-adding ExcelMacHelper in the Accessibility list
- Restart the app after granting permissions

### HUD overlay doesn't appear
- Check that "Show HUD Overlay" is enabled in Preferences
- Check that "Alt-Key Shortcuts" is enabled
- Ensure Excel is the frontmost application

### Function keys still act as media keys
- Check that "Function Key Toggle" is enabled in Preferences
- Verify "Microsoft Excel" is in the monitored apps list
- Ensure Excel is actually the frontmost (active) application

### Shortcuts execute the wrong action
- Check the shortcuts JSON for correct `mac_equivalent` values
- Menu paths must match the actual Mac Excel menu hierarchy
- Try reloading shortcuts after edits

## Architecture

```
ExcelMacHelper/
├── ExcelMacHelperApp.swift      # SwiftUI app entry point
├── AppDelegate.swift            # Menu bar setup, HUD management
├── Info.plist                   # App configuration (LSUIElement for menu bar)
├── ExcelMacHelper.entitlements  # Apple Events entitlement
├── Assets.xcassets/             # App icon and accent color
├── Models/
│   ├── ShortcutModels.swift     # JSON parsing models, ParsedShortcut
│   ├── ShortcutTree.swift       # Tree structure for efficient lookup
│   └── AppState.swift           # Central state coordination
├── Services/
│   ├── AccessibilityManager.swift  # Permission checking and prompting
│   ├── ActiveAppMonitor.swift      # NSWorkspace frontmost app detection
│   ├── ShortcutManager.swift       # JSON file loading and management
│   ├── EventTapManager.swift       # CGEventTap keyboard interception
│   ├── KeyTipsManager.swift        # Key Tips mode state machine
│   └── ActionExecutor.swift        # Keystroke/menu/AppleScript execution
├── Views/
│   ├── HUDOverlayWindow.swift   # Translucent Key Tips overlay
│   └── PreferencesView.swift    # Settings window (SwiftUI)
├── Utilities/
│   ├── Constants.swift          # App-wide constants
│   └── Logger.swift             # Centralized logging
└── Resources/
    └── excel_alt_shortcuts.json # Bundled shortcuts (247 entries)
```

## License

MIT License
