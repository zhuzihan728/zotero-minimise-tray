# zotero-minimise-tray

A Windows plugin for Zotero 7 to 10. Closing the main window sends Zotero to the system tray so that syncing and the Zotero Connector can continue running.

## Installation

1. Download `zotero-mini-tray-0.2.0.xpi` from the [latest release](https://github.com/zhuzihan728/zotero-minimise-tray/releases/latest).
2. In Zotero, open **Tools → Plugins**.
3. Select the gear menu, choose **Install Add-on From File**, and open the XPI file.

## Usage

- Close the main window or press Alt+F4 to hide Zotero in the system tray.
- Click the tray icon to restore Zotero.
- Right-click the tray icon and select **Exit Zotero** to quit.

## Development

Build the XPI:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/build.ps1
```

Run the integration test with an isolated Zotero profile:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/test-integration.ps1
```

The plugin supports Windows only. Version 0.2.0 was tested with Zotero 10.0.6.
