param([string]$ZoteroPath = 'C:\Program Files\Zotero\zotero.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$testRoot = Join-Path $projectRoot ('.test\run-' + [Guid]::NewGuid().ToString('N'))
$profile = Join-Path $testRoot 'profile'
$addon = Join-Path $testRoot 'addon-source'
[void][IO.Directory]::CreateDirectory((Join-Path $addon 'helper'))
[void][IO.Directory]::CreateDirectory((Join-Path $profile 'extensions'))
[void][IO.Directory]::CreateDirectory((Join-Path $testRoot 'data'))
& (Join-Path $projectRoot 'scripts\build.ps1') | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot 'manifest.json') -Destination $addon
Copy-Item -LiteralPath (Join-Path $projectRoot 'helper\tray-helper.exe') -Destination (Join-Path $addon 'helper')
Copy-Item -LiteralPath (Join-Path $projectRoot 'helper\TrayHelper.cs') -Destination (Join-Path $addon 'helper')
$dataPath = (Join-Path $testRoot 'data') | ConvertTo-Json -Compress
$preferences = @"
user_pref("extensions.autoDisableScopes", 0);
user_pref("extensions.enabledScopes", 15);
user_pref("extensions.logging.enabled", true);
user_pref("xpinstall.signatures.required", false);
user_pref("extensions.zoteroWinWordIntegration.skipInstallation", true);
user_pref("extensions.zoteroOpenOfficeIntegration.skipInstallation", true);
user_pref("extensions.zotero.useDataDir", true);
user_pref("extensions.zotero.dataDir", $dataPath);
user_pref("extensions.zotero.firstRun", false);
user_pref("extensions.zotero.firstRun2", false);
user_pref("extensions.zotero.automaticScraperUpdates", false);
user_pref("app.update.auto", false);
user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
"@
[IO.File]::WriteAllText((Join-Path $profile 'user.js'), $preferences)
$resultPath = Join-Path $testRoot 'result.json'
$harness = @'

var realStartup = startup;
startup = async function(data, reason) {
  // Return promptly so Zotero can finish startup and create its main window.
  runIntegration(data, reason);
};
async function runIntegration(data, reason) {
  const testIO = IOUtils;
  const results = [];
  const delay = ms => new Promise(resolve => {
    const timer = Cc["@mozilla.org/timer;1"].createInstance(Ci.nsITimer);
    timer.initWithCallback(() => resolve(), ms, Ci.nsITimer.TYPE_ONE_SHOT);
  });
  const waitFor = async (predicate, label) => {
    for (let i = 0; i < 120; i++) {
      if (await predicate()) return;
      await delay(250);
    }
    throw new Error("Timed out: " + label);
  };
  const check = (condition, label) => {
    if (!condition) throw new Error(label);
    results.push(label);
  };
  // Gecko getters do not reliably reflect native visibility. Verify with Win32.
  const { ctypes } = ChromeUtils.importESModule("resource://gre/modules/ctypes.sys.mjs");
  const user32 = ctypes.open("user32.dll");
  const isVisible = user32.declare("IsWindowVisible", ctypes.winapi_abi, ctypes.int32_t, ctypes.voidptr_t);
  const postMessage = user32.declare("PostMessageW", ctypes.winapi_abi, ctypes.int32_t, ctypes.voidptr_t, ctypes.uint32_t, ctypes.uintptr_t, ctypes.intptr_t);
  const visible = win => !!isVisible(ctypes.voidptr_t(ctypes.UInt64(miniTray.baseWindow(win).nativeHandle)));
  try {
    await realStartup(data, reason);
    await waitFor(() => miniTray?.ready && Zotero.getMainWindows().some(win => miniTray.windows.has(win) && win.document.readyState === "complete"), "tray and window ready");
    const win = Zotero.getMainWindow();
    check(visible(win), "starts visible");
    for (let i = 0; i < 3; i++) {
      const event = new win.Event("close", { cancelable: true });
      check(!win.dispatchEvent(event), "close cancelled " + i);
      check(!visible(win), "window hidden " + i);
      await testIO.writeUTF8(miniTray.paths.join(miniTray.directory, "restore"), "");
      await waitFor(() => visible(win), "restore");
      results.push("IPC restore " + i);
    }
    postMessage(ctypes.voidptr_t(ctypes.UInt64(miniTray.baseWindow(win).nativeHandle)), 0x0010, 0, 0);
    await waitFor(() => !visible(win), "native WM_CLOSE hides window");
    check(!win.closed, "native WM_CLOSE keeps Zotero running");
    await testIO.writeUTF8(miniTray.paths.join(miniTray.directory, "restore"), "");
    await waitFor(() => visible(win), "restore after native close");
    results.push("native WM_CLOSE hides and restores");
    win.close();
    check(!win.closed && !visible(win), "window.close hides without closing");
    await testIO.writeUTF8(miniTray.paths.join(miniTray.directory, "restore"), "");
    await waitFor(() => visible(win), "restore after window.close");
    const closeButton = win.document.querySelector(".titlebar-close");
    check(!!closeButton, "custom titlebar close button exists");
    closeButton.doCommand();
    check(!win.closed && !visible(win), "custom titlebar X hides without closing");
    await testIO.writeUTF8(miniTray.paths.join(miniTray.directory, "restore"), "");
    await waitFor(() => visible(win), "restore after titlebar close");
    win.dispatchEvent(new win.Event("close", { cancelable: true }));
    miniTray.process.kill();
    await waitFor(() => visible(win), "helper crash restores window");
    check(!miniTray.ready, "helper crash disables interception");
    check(win.dispatchEvent(new win.Event("close", { cancelable: true })), "close allowed after helper crash");
    miniTray.stop();
    miniTray = new MiniTray(testIO, PathUtils);
    await miniTray.start(data.rootURI, data.version);
    await waitFor(() => miniTray.ready, "helper restarted");
    win.dispatchEvent(new win.Event("close", { cancelable: true }));
    const helper = miniTray.process;
    miniTray.stop();
    check(visible(win), "disable restores hidden window");
    await waitFor(() => !helper.isRunning, "helper exits on disable");
    results.push("helper exits on disable");
    miniTray = new MiniTray(testIO, PathUtils);
    await miniTray.start(data.rootURI, data.version);
    await waitFor(() => miniTray.ready, "tray ready for quit test");
    const cancelQuit = { observe: subject => { subject.QueryInterface(Ci.nsISupportsPRBool).data = true; } };
    Services.obs.addObserver(cancelQuit, "quit-application-requested");
    await testIO.writeUTF8(miniTray.paths.join(miniTray.directory, "quit"), "");
    await waitFor(async () => !await testIO.exists(miniTray.paths.join(miniTray.directory, "quit")), "cancelled quit consumed");
    await delay(500);
    check(!miniTray.quitting && !win.closed, "cancelled quit resets interception");
    Services.obs.removeObserver(cancelQuit, "quit-application-requested");
    win.dispatchEvent(new win.Event("close", { cancelable: true }));
    check(!visible(win), "can hide after cancelled quit");
    await testIO.writeJSON(__RESULT_PATH__, { ok: true, version: Services.appinfo.version, parentProcessId: Services.appinfo.processID, helperDirectory: miniTray.directory, results });
    await testIO.writeUTF8(miniTray.paths.join(miniTray.directory, "quit"), "");
  } catch (error) {
    await testIO.writeJSON(__RESULT_PATH__, { ok: false, error: String(error), stack: error.stack, results });
  } finally {
    user32.close();
    if (!results.includes("can hide after cancelled quit")) {
      miniTray?.stop();
      Services.startup.quit(Ci.nsIAppStartup.eAttemptQuit);
    }
  }
}
'@
$harness = $harness.Replace('__RESULT_PATH__', ($resultPath | ConvertTo-Json -Compress))
$bootstrap = [IO.File]::ReadAllText((Join-Path $projectRoot 'bootstrap.js')) + $harness
[IO.File]::WriteAllText((Join-Path $addon 'bootstrap.js'), $bootstrap)
Add-Type -AssemblyName System.IO.Compression
$package = [IO.File]::Create((Join-Path $profile 'extensions\zotero-mini-tray@local.xpi'))
$zip = [IO.Compression.ZipArchive]::new($package, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($name in @('manifest.json', 'bootstrap.js', 'helper/tray-helper.exe', 'helper/TrayHelper.cs')) {
        $target = $zip.CreateEntry($name).Open()
        $inputFile = [IO.File]::OpenRead((Join-Path $addon $name))
        try { $inputFile.CopyTo($target) } finally { $inputFile.Dispose(); $target.Dispose() }
    }
} finally { $zip.Dispose(); $package.Dispose() }
$process = Start-Process -FilePath $ZoteroPath -ArgumentList @('-no-remote', '-profile', ('"' + $profile + '"'), '-purgecaches', '-ZoteroDebugText') -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testRoot 'stdout.log') -RedirectStandardError (Join-Path $testRoot 'stderr.log')
$deadline = [DateTime]::UtcNow.AddSeconds(90)
while (!(Test-Path -LiteralPath $resultPath) -and [DateTime]::UtcNow -lt $deadline) {
    Start-Sleep -Milliseconds 500
}
if (!(Test-Path -LiteralPath $resultPath)) {
    Write-Output "Test profile: $profile"
    throw 'No integration result; inspect the isolated profile. The test process may still be open.'
}
$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if ($result.ok) {
    $zoteroProcess = Get-Process -Id $result.parentProcessId -ErrorAction SilentlyContinue
    if ($zoteroProcess -and !$zoteroProcess.WaitForExit(10000)) { throw 'Tray quit did not exit Zotero' }
    $cleanupDeadline = [DateTime]::UtcNow.AddSeconds(5)
    while ((Test-Path -LiteralPath $result.helperDirectory) -and [DateTime]::UtcNow -lt $cleanupDeadline) { Start-Sleep -Milliseconds 100 }
    if (Test-Path -LiteralPath $result.helperDirectory) { throw 'Helper directory not cleaned after quit' }
    $result.results += 'tray quit exits Zotero and cleans helper directory'
}
$result | ConvertTo-Json -Depth 5
if (!$result.ok) { exit 1 }
