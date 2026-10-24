using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

internal static class TrayHelper
{
    private static string stateDirectory;

    [STAThread]
    private static int Main(string[] args)
    {
        int parentProcessId;
        if (args.Length != 3 || !int.TryParse(args[0], out parentProcessId))
            return 2;

        stateDirectory = Path.GetFullPath(args[1]);
        string executablePath = Path.GetFullPath(args[2]);
        Process parent = null;
        NotifyIcon tray = null;
        ContextMenuStrip menu = null;
        Timer timer = null;
        Icon icon = null;

        try
        {
            parent = Process.GetProcessById(parentProcessId);
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            icon = Icon.ExtractAssociatedIcon(executablePath);
            menu = new ContextMenuStrip();
            menu.Items.Add("Open Zotero", null, delegate { SendCommand("restore"); });
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Exit Zotero", null, delegate { SendCommand("quit"); });

            tray = new NotifyIcon();
            tray.Icon = icon;
            tray.Text = "Zotero - click to restore";
            tray.ContextMenuStrip = menu;
            tray.MouseClick += delegate(object sender, MouseEventArgs eventArgs)
            {
                if (eventArgs.Button == MouseButtons.Left) SendCommand("restore");
            };
            tray.Visible = true;

            timer = new Timer();
            timer.Interval = 250;
            timer.Tick += delegate
            {
                if (parent.HasExited || File.Exists(Path.Combine(stateDirectory, "stop")))
                    Application.ExitThread();
            };
            timer.Start();

            SendCommand("ready");
            Application.Run();
            return 0;
        }
        catch (Exception error)
        {
            try
            {
                if (Directory.Exists(stateDirectory))
                    File.WriteAllText(Path.Combine(stateDirectory, "error.log"), error.ToString());
            }
            catch { }
            return 1;
        }
        finally
        {
            if (timer != null) { timer.Stop(); timer.Dispose(); }
            if (tray != null) { tray.Visible = false; tray.Dispose(); }
            if (menu != null) menu.Dispose();
            if (icon != null) icon.Dispose();
            if (parent != null) parent.Dispose();
            try
            {
                if (Directory.Exists(stateDirectory)) Directory.Delete(stateDirectory, true);
            }
            catch { }
        }
    }

    private static void SendCommand(string name)
    {
        File.WriteAllText(Path.Combine(stateDirectory, name), "");
    }
}
