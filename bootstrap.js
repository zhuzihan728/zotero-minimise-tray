/* global Zotero, Services, Cc, Ci, IOUtils, PathUtils */
var miniTray;

function install() {}
function uninstall() {}

async function startup({ rootURI, version }) {
  if (!Zotero.isWin) return;
  miniTray = new MiniTray(IOUtils, PathUtils);
  try {
    await miniTray.start(rootURI, version);
  } catch (error) {
    Zotero.logError(error);
    miniTray.stop();
  }
}

function shutdown() {
  miniTray?.stop();
  miniTray = null;
}

function onMainWindowLoad({ window }) {
  miniTray?.attach(window);
}

function onMainWindowUnload({ window }) {
  miniTray?.detach(window);
}

class MiniTray {
  constructor(io, paths) {
    this.io = io;
    this.paths = paths;
    this.windows = new Map();
    this.hidden = new Set();
    this.ready = false;
    this.stopped = false;
    this.quitting = false;
    this.granted = false;
    this.busy = false;
    this.quitObserver = { observe: (_subject, topic) => {
      this.quitting = true;
      if (topic === "quit-application-granted") this.granted = true;
      // A different extension or an unsaved-work dialog may cancel quitting.
      Services.tm.dispatchToMainThread(() => {
        if (!this.granted) this.quitting = false;
      });
    } };
  }

  async start(rootURI, version) {
    const directory = Services.dirsvc.get("TmpD", Ci.nsIFile);
    directory.append("zotero-mini-tray-state");
    directory.createUnique(Ci.nsIFile.DIRECTORY_TYPE, 0o700);
    this.directory = directory.path;
    const channel = Services.io.newChannelFromURI(
      Services.io.newURI(rootURI + "helper/tray-helper.exe"), null,
      Services.scriptSecurityManager.getSystemPrincipal(), null,
      Ci.nsILoadInfo.SEC_ALLOW_CROSS_ORIGIN_SEC_CONTEXT_IS_NULL,
      Ci.nsIContentPolicy.TYPE_OTHER
    );
    const input = channel.open();
    const binary = Cc["@mozilla.org/binaryinputstream;1"].createInstance(Ci.nsIBinaryInputStream);
    binary.setInputStream(input);
    const bytes = new Uint8Array(binary.readByteArray(binary.available()));
    binary.close();
    if (this.stopped) return this.cleanup();
    const profile = Services.dirsvc.get("ProfD", Ci.nsIFile).path;
    const helperDirectory = this.paths.join(profile, "zotero-mini-tray");
    await this.io.makeDirectory(helperDirectory, { permissions: 0o700, ignoreExisting: true });
    const safeVersion = String(version).replace(/[^0-9A-Za-z._-]/g, "_");
    const helperPath = this.paths.join(helperDirectory, `tray-helper-${safeVersion}.exe`);
    if (!await this.io.exists(helperPath)) await this.io.write(helperPath, bytes);
    if (this.stopped) return this.cleanup();
    const helper = Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsIFile);
    helper.initWithPath(helperPath);
    const executable = Services.dirsvc.get("XREExeF", Ci.nsIFile).path;
    this.process = Cc["@mozilla.org/process/util;1"].createInstance(Ci.nsIProcess);
    this.process.init(helper);
    const args = [String(Services.appinfo.processID), this.directory, executable];
    this.process.runwAsync(args, args.length, { observe: () => {
      this.ready = false;
      this.restore();
      if (!this.stopped) Zotero.logError(new Error("Mini Tray helper exited; normal window closing restored."));
      this.cleanup();
    } }, false);
    for (const topic of ["quit-application-requested", "quit-application-granted"]) {
      Services.obs.addObserver(this.quitObserver, topic);
    }
    this.observing = true;
    for (const window of Zotero.getMainWindows()) this.attach(window);
    this.timer = Cc["@mozilla.org/timer;1"].createInstance(Ci.nsITimer);
    this.timer.initWithCallback(() => this.tick(), 250, Ci.nsITimer.TYPE_REPEATING_SLACK);
  }

  baseWindow(window) {
    return window.docShell.treeOwner.QueryInterface(Ci.nsIBaseWindow);
  }

  attach(window) {
    if (this.stopped || this.windows.has(window)) return;
    const hide = () => {
      if (this.quitting || !this.ready || !this.process?.isRunning) return false;
      try {
        this.baseWindow(window).visibility = false;
        this.hidden.add(window);
        return true;
      } catch (error) {
        Zotero.logError(error);
        return false;
      }
    };
    const listener = event => {
      if (event.target !== window.document.documentElement && event.target !== window) return;
      if (hide()) {
        event.preventDefault();
        event.stopImmediatePropagation();
      }
    };
    // Zotero's custom titlebar calls window.close(), which does not emit the
    // cancellable native close event. Handle both paths, preserving real quit.
    const originalClose = window.close;
    const wrappedClose = function (...args) {
      if (!hide()) return originalClose.apply(window, args);
    };
    window.close = wrappedClose;
    window.addEventListener("close", listener, true);
    this.windows.set(window, { listener, originalClose, wrappedClose });
  }

  detach(window) {
    const state = this.windows.get(window);
    if (state) {
      window.removeEventListener("close", state.listener, true);
      if (window.close === state.wrappedClose) window.close = state.originalClose;
    }
    this.windows.delete(window);
    this.hidden.delete(window);
  }

  restore() {
    for (const window of this.hidden) {
      try {
        if (!window.closed) {
          this.baseWindow(window).visibility = true;
          window.restore();
          window.focus();
        }
      } catch (error) { Zotero.logError(error); }
    }
    this.hidden.clear();
  }

  async tick() {
    if (this.busy || this.stopped) return;
    this.busy = true;
    try {
      const ready = await this.io.exists(this.paths.join(this.directory, "ready"));
      if (this.stopped) return;
      this.ready = ready && this.process.isRunning;
      for (const command of ["restore", "quit"]) {
        const path = this.paths.join(this.directory, command);
        if (!await this.io.exists(path)) continue;
        await this.io.remove(path, { ignoreAbsent: true });
        if (this.stopped) return;
        this.restore();
        if (command === "restore" && !this.hidden.size) {
          const window = Zotero.getMainWindow();
          if (window) { window.restore(); window.focus(); }
        }
        if (command === "quit") {
          const cancel = Cc["@mozilla.org/supports-PRBool;1"].createInstance(Ci.nsISupportsPRBool);
          Services.obs.notifyObservers(cancel, "quit-application-requested", null);
          if (!cancel.data) Services.startup.quit(Ci.nsIAppStartup.eAttemptQuit);
        }
      }
    } catch (error) {
      this.ready = false;
      this.restore();
      Zotero.logError(error);
    } finally {
      this.busy = false;
    }
  }

  stop() {
    this.stopped = true;
    this.ready = false;
    this.timer?.cancel();
    this.restore();
    for (const window of this.windows.keys()) this.detach(window);
    if (this.observing) {
      for (const topic of ["quit-application-requested", "quit-application-granted"]) {
        Services.obs.removeObserver(this.quitObserver, topic);
      }
      this.observing = false;
    }
    if (this.directory && this.process?.isRunning) {
      // The helper checks this signal and disposes its NotifyIcon gracefully.
      const file = Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsIFile);
      file.initWithPath(this.paths.join(this.directory, "stop"));
      if (!file.exists()) file.create(Ci.nsIFile.NORMAL_FILE_TYPE, 0o600);
    } else {
      this.cleanup();
    }
  }

  cleanup() {
    if (this.directory) this.io.remove(this.directory, { recursive: true, ignoreAbsent: true }).catch(error => Zotero.logError(error));
  }
}
