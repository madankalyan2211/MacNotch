# Restoring the Default macOS Dock

IconDock is built with safety as its primary directive. Returning your Dock to its factory macOS appearance can be done at any time.

---

## 🔘 Method 1: One-Click Restore from the App (Recommended)

1. Open **IconDock Settings** (from the menu bar icon or by launching the app).
2. Scroll to the **Safety & Integration** section.
3. Click the red **Restore Defaults** button.
4. Confirm by clicking **Restore Factory Dock** in the prompt.
5. IconDock will instantaneously:
   * Reset `eyecandy-show-borders` to standard.
   * Reset `reduce-desktop-tinting`.
   * Reset tile sizes and magnification to standard macOS defaults.
   * Synchronize `com.apple.dock` preferences.
   * Gracefully reload the Dock via `killall Dock`.

---

## ⏪ Method 2: Rolling Back to a Specific Snapshot

IconDock automatically saves a snapshot before every single modification:
1. Open **IconDock Settings**.
2. Click **Snapshots (...)** next to "Automatic Snapshots".
3. Browse the timestamped snapshots history list.
4. Click **Restore** next to any previous snapshot (including the initial clean snapshot created when IconDock was first launched).

---

## 💻 Method 3: Manual Terminal Restore (No App Required)

If you ever uninstall IconDock without clicking Restore Defaults, you can reset macOS Dock preferences via Terminal in seconds:

```bash
# Revert border suppression
defaults write com.apple.dock eyecandy-show-borders -bool true

# Revert desktop tinting
defaults write com.apple.dock reduce-desktop-tinting -bool false

# Reset icon size to default
defaults write com.apple.dock tilesize -int 54

# Reset orientation to bottom
defaults write com.apple.dock orientation -string "bottom"

# Restart the Dock to apply changes
killall Dock
```

### Complete Factory Reset (Alternative)
To completely reset all Dock preferences to fresh Apple factory out-of-the-box defaults:
```bash
defaults delete com.apple.dock
killall Dock
```
