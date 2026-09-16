# Uninstalling IconDock

Because IconDock never modifies protected system files or injects kernel extensions, uninstallation is straightforward and clean.

---

## 📋 Step 1: Restore Standard Dock Appearance

Before deleting the application, restore standard macOS Dock settings:
1. Click the **IconDock** icon in the menu bar.
2. Select **Restore Default Dock**.
3. Confirm the restoration.

*(Alternatively, run `defaults write com.apple.dock eyecandy-show-borders -bool true && killall Dock` in Terminal).*

---

## 🗑️ Step 2: Quit and Delete the Application

1. Click the IconDock menu bar icon and select **Quit IconDock** (or press `Cmd + Q`).
2. Remove `IconDock.app` from `/Applications` or your build directory:
   ```bash
   rm -rf /Applications/IconDock.app
   ```

---

## 🧹 Step 3: Remove Application Support Snapshots (Optional)

IconDock keeps configuration backup snapshots in your user Library. To completely clean these up:

```bash
rm -rf ~/Library/Application\ Support/IconDock
```

---

## ✅ Complete Clean Removal Command

Run this single command in Terminal to perform all cleanup steps at once:

```bash
# 1. Kill IconDock if running
killall IconDock 2>/dev/null || true

# 2. Restore standard Dock preferences
defaults write com.apple.dock eyecandy-show-borders -bool true
defaults write com.apple.dock reduce-desktop-tinting -bool false
killall Dock

# 3. Clean up support files
rm -rf ~/Library/Application\ Support/IconDock
rm -rf /Applications/IconDock.app
```
