using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace BgClickerApp
{
    static class Win32
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct POINT
        {
            public int X;
            public int Y;
        }

        public const uint WM_HOTKEY      = 0x0312;
        public const uint WM_MOUSEMOVE   = 0x0200;
        public const uint WM_LBUTTONDOWN = 0x0201;
        public const uint WM_LBUTTONUP   = 0x0202;
        public const uint WM_RBUTTONDOWN = 0x0204;
        public const uint WM_RBUTTONUP   = 0x0205;

        public const int MK_LBUTTON = 0x0001;
        public const int MK_RBUTTON = 0x0002;

        public const uint VK_F8  = 0x77;
        public const uint VK_F9  = 0x78;
        public const uint VK_F10 = 0x79;

        public const int WS_EX_LAYERED     = 0x00080000;
        public const int WS_EX_TRANSPARENT = 0x00000020;
        public const int WS_EX_TOOLWINDOW  = 0x00000080;
        public const int WS_EX_TOPMOST     = 0x00000008;
        public const int WS_EX_NOACTIVATE  = 0x08000000;

        [DllImport("user32.dll")]
        public static extern bool SetProcessDPIAware();

        [DllImport("user32.dll")]
        public static extern bool GetCursorPos(out POINT lpPoint);

        [DllImport("user32.dll")]
        public static extern IntPtr WindowFromPoint(POINT Point);

        [DllImport("user32.dll")]
        public static extern IntPtr GetAncestor(IntPtr hwnd, uint gaFlags);

        [DllImport("user32.dll")]
        public static extern bool ScreenToClient(IntPtr hWnd, ref POINT lpPoint);

        [DllImport("user32.dll")]
        public static extern bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("user32.dll")]
        public static extern bool IsWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool PostMessageW(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [StructLayout(LayoutKind.Sequential)]
        public struct SIZE
        {
            public int cx;
            public int cy;
        }

        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        public struct BLENDFUNCTION
        {
            public byte BlendOp;
            public byte BlendFlags;
            public byte SourceConstantAlpha;
            public byte AlphaFormat;
        }

        public const byte AC_SRC_OVER  = 0x00;
        public const byte AC_SRC_ALPHA = 0x01;
        public const int  ULW_ALPHA    = 0x02;

        [DllImport("user32.dll")]
        public static extern bool UpdateLayeredWindow(
            IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize,
            IntPtr hdcSrc, ref POINT pptSrc, uint crKey, ref BLENDFUNCTION pblend, int dwFlags);

        [DllImport("user32.dll")]
        public static extern IntPtr GetDC(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);

        [DllImport("gdi32.dll")]
        public static extern IntPtr CreateCompatibleDC(IntPtr hDC);

        [DllImport("gdi32.dll")]
        public static extern bool DeleteDC(IntPtr hdc);

        [DllImport("gdi32.dll")]
        public static extern IntPtr SelectObject(IntPtr hDC, IntPtr hObject);

        [DllImport("gdi32.dll")]
        public static extern bool DeleteObject(IntPtr hObject);

        [DllImport("user32.dll")]
        public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        public static IntPtr MakeLParam(int x, int y)
        {
            return (IntPtr)((y << 16) | (x & 0xFFFF));
        }

        public static string GetClass(IntPtr hwnd)
        {
            var sb = new StringBuilder(256);
            GetClassName(hwnd, sb, sb.Capacity);
            return sb.ToString();
        }

        public static string GetTitle(IntPtr hwnd)
        {
            var sb = new StringBuilder(256);
            GetWindowText(hwnd, sb, sb.Capacity);
            return sb.ToString();
        }
    }

    // 透明穿透的纯红细线准星标记（Per-Pixel Alpha，无锯齿紫边，不抢焦点、不拦鼠标）
    class MarkerForm : Form
    {
        private int _screenX = -10000;
        private int _screenY = -10000;

        public MarkerForm()
        {
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            TopMost = true;
            StartPosition = FormStartPosition.Manual;
            Size = new Size(29, 29);
        }

        protected override bool ShowWithoutActivation
        {
            get { return true; }
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                cp.ExStyle |= Win32.WS_EX_LAYERED | Win32.WS_EX_TRANSPARENT | Win32.WS_EX_TOOLWINDOW | Win32.WS_EX_TOPMOST | Win32.WS_EX_NOACTIVATE;
                return cp;
            }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            RenderLayered();
        }

        public void MoveToScreenPoint(int screenX, int screenY)
        {
            if (_screenX == screenX && _screenY == screenY) return;
            _screenX = screenX;
            _screenY = screenY;
            if (IsHandleCreated) RenderLayered();
        }

        private void RenderLayered()
        {
            int w = Width;
            int h = Height;
            float cx = (w - 1) / 2.0f;
            float cy = (h - 1) / 2.0f;

            using (var bmp = new Bitmap(w, h, System.Drawing.Imaging.PixelFormat.Format32bppArgb))
            {
                using (var g = Graphics.FromImage(bmp))
                {
                    g.Clear(Color.Transparent);
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;

                    Color mainColor = Color.FromArgb(255, 255, 32, 32);

                    // 1px 纯红细线外环 + 细线十字准星
                    using (var thinPen = new Pen(mainColor, 1.0f))
                    {
                        g.DrawEllipse(thinPen, cx - 7.5f, cy - 7.5f, 15.0f, 15.0f);
                        g.DrawLine(thinPen, cx - 12.5f, cy, cx - 4.5f, cy);
                        g.DrawLine(thinPen, cx + 4.5f, cy, cx + 12.5f, cy);
                        g.DrawLine(thinPen, cx, cy - 12.5f, cx, cy - 4.5f);
                        g.DrawLine(thinPen, cx, cy + 4.5f, cx, cy + 12.5f);
                    }

                    // 中心小红点
                    using (var dotBrush = new SolidBrush(mainColor))
                    {
                        g.FillEllipse(dotBrush, cx - 1.5f, cy - 1.5f, 3.0f, 3.0f);
                    }
                }

                IntPtr screenDc = Win32.GetDC(IntPtr.Zero);
                IntPtr memDc = Win32.CreateCompatibleDC(screenDc);
                IntPtr hBitmap = IntPtr.Zero;
                IntPtr oldBitmap = IntPtr.Zero;
                try
                {
                    hBitmap = bmp.GetHbitmap(Color.FromArgb(0));
                    oldBitmap = Win32.SelectObject(memDc, hBitmap);

                    var size = new Win32.SIZE { cx = w, cy = h };
                    var srcPt = new Win32.POINT { X = 0, Y = 0 };
                    var dstPt = new Win32.POINT { X = _screenX - w / 2, Y = _screenY - h / 2 };
                    var blend = new Win32.BLENDFUNCTION
                    {
                        BlendOp = Win32.AC_SRC_OVER,
                        BlendFlags = 0,
                        SourceConstantAlpha = 255,
                        AlphaFormat = Win32.AC_SRC_ALPHA
                    };

                    Win32.UpdateLayeredWindow(Handle, screenDc, ref dstPt, ref size, memDc, ref srcPt, 0, ref blend, Win32.ULW_ALPHA);
                }
                finally
                {
                    Win32.ReleaseDC(IntPtr.Zero, screenDc);
                    if (hBitmap != IntPtr.Zero)
                    {
                        Win32.SelectObject(memDc, oldBitmap);
                        Win32.DeleteObject(hBitmap);
                    }
                    Win32.DeleteDC(memDc);
                }
            }
        }
    }

    public class MainForm : Form
    {
        private const int HOTKEY_F8  = 1001;
        private const int HOTKEY_F9  = 1002;
        private const int HOTKEY_F10 = 1003;

        // 目标状态
        private IntPtr _targetHwnd = IntPtr.Zero;
        private int _relX;
        private int _relY;

        // 运行控制
        private volatile bool _running;
        private volatile bool _paused;
        private long _clickCount;
        private Thread _workerThread;
        private readonly ManualResetEventSlim _wakeEvent = new ManualResetEventSlim(false);

        // UI 控件
        private Label _lblProcess;
        private Label _lblWindow;
        private Label _lblChild;
        private Label _lblCoord;
        private NumericUpDown _numInterval;
        private NumericUpDown _numJitter;
        private NumericUpDown _numHold;
        private NumericUpDown _numCount;
        private ComboBox _cmbButton;
        private CheckBox _chkTopMost;
        private CheckBox _chkShowMarker;
        private Button _btnPick;
        private Button _btnStartPause;
        private Button _btnStop;
        private Label _lblStatus;
        private Label _lblClicks;
        private Label _lblHotkeyHint;

        private MarkerForm _marker;
        private System.Windows.Forms.Timer _markerSyncTimer;
        private System.Windows.Forms.Timer _pickCountdownTimer;
        private int _pickCountdownSec;

        public MainForm()
        {
            Text = "后台连点器 (PostMessage)";
            Font = new Font("Microsoft YaHei UI", 9.5f);
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(440, 445);
            BackColor = Color.FromArgb(248, 250, 252);
            TopMost = true;

            BuildUi();

            _marker = new MarkerForm();
            _markerSyncTimer = new System.Windows.Forms.Timer { Interval = 150 };
            _markerSyncTimer.Tick += (s, e) => SyncMarkerPosition();
            _markerSyncTimer.Start();
        }

        private void BuildUi()
        {
            // 1. 目标窗口组
            var grpTarget = new GroupBox
            {
                Text = " 目标窗口（鼠标指到目标位置按 F8 锁定） ",
                Location = new Point(14, 12),
                Size = new Size(412, 132),
                ForeColor = Color.FromArgb(30, 41, 59)
            };

            _lblProcess = MakeInfoLabel("进程：未锁定", 14, 26);
            _lblWindow  = MakeInfoLabel("窗口：-", 14, 50);
            _lblChild   = MakeInfoLabel("子窗：-", 14, 74);
            _lblCoord   = MakeInfoLabel("坐标：-", 14, 98);
            _lblCoord.ForeColor = Color.FromArgb(37, 99, 235);

            grpTarget.Controls.AddRange(new Control[] { _lblProcess, _lblWindow, _lblChild, _lblCoord });
            Controls.Add(grpTarget);

            // 2. 参数设置组
            var grpSettings = new GroupBox
            {
                Text = " 连点参数 ",
                Location = new Point(14, 152),
                Size = new Size(412, 148),
                ForeColor = Color.FromArgb(30, 41, 59)
            };

            grpSettings.Controls.Add(new Label { Text = "间隔 (ms):", Location = new Point(14, 30), AutoSize = true });
            _numInterval = new NumericUpDown { Location = new Point(92, 26), Width = 92, Minimum = 10, Maximum = 600000, Value = 50, Increment = 10 };

            grpSettings.Controls.Add(new Label { Text = "随机抖动 (±ms):", Location = new Point(204, 30), AutoSize = true });
            _numJitter = new NumericUpDown { Location = new Point(316, 26), Width = 80, Minimum = 0, Maximum = 10000, Value = 0, Increment = 10 };

            grpSettings.Controls.Add(new Label { Text = "按住 (ms):", Location = new Point(14, 66), AutoSize = true });
            _numHold = new NumericUpDown { Location = new Point(92, 62), Width = 92, Minimum = 0, Maximum = 5000, Value = 10, Increment = 5 };

            grpSettings.Controls.Add(new Label { Text = "次数 (0=无限):", Location = new Point(204, 66), AutoSize = true });
            _numCount = new NumericUpDown { Location = new Point(316, 62), Width = 80, Minimum = 0, Maximum = 10000000, Value = 0, Increment = 10 };

            grpSettings.Controls.Add(new Label { Text = "按键:", Location = new Point(14, 104), AutoSize = true });
            _cmbButton = new ComboBox
            {
                Location = new Point(92, 100),
                Width = 92,
                DropDownStyle = ComboBoxStyle.DropDownList
            };
            _cmbButton.Items.AddRange(new object[] { "鼠标左键", "鼠标右键" });
            _cmbButton.SelectedIndex = 0;

            _chkTopMost = new CheckBox
            {
                Text = "窗口置顶",
                Location = new Point(204, 102),
                AutoSize = true,
                Checked = true
            };
            _chkTopMost.CheckedChanged += (s, e) => TopMost = _chkTopMost.Checked;

            _chkShowMarker = new CheckBox
            {
                Text = "红点标记",
                Location = new Point(304, 102),
                AutoSize = true,
                Checked = true
            };
            _chkShowMarker.CheckedChanged += (s, e) => SyncMarkerPosition();

            grpSettings.Controls.AddRange(new Control[]
            {
                _numInterval, _numJitter, _numHold, _numCount, _cmbButton, _chkTopMost, _chkShowMarker
            });
            Controls.Add(grpSettings);

            // 3. 控制按钮（F8 / F9 / F10 并排）
            _btnPick = new Button
            {
                Text = "锁定位置 (F8)",
                Location = new Point(14, 314),
                Size = new Size(132, 42),
                BackColor = Color.FromArgb(15, 23, 42),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold),
                Cursor = Cursors.Hand
            };
            _btnPick.FlatAppearance.BorderSize = 0;
            _btnPick.Click += (s, e) => StartDelayedPick();

            _btnStartPause = new Button
            {
                Text = "开始 (F9)",
                Location = new Point(154, 314),
                Size = new Size(132, 42),
                BackColor = Color.FromArgb(37, 99, 235),
                ForeColor = Color.White,
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold),
                Cursor = Cursors.Hand
            };
            _btnStartPause.FlatAppearance.BorderSize = 0;
            _btnStartPause.Click += (s, e) => ToggleStartPause();

            _btnStop = new Button
            {
                Text = "停止 (F10)",
                Location = new Point(294, 314),
                Size = new Size(132, 42),
                BackColor = Color.FromArgb(226, 232, 240),
                ForeColor = Color.FromArgb(51, 65, 85),
                FlatStyle = FlatStyle.Flat,
                Font = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold),
                Enabled = false,
                Cursor = Cursors.Hand
            };
            _btnStop.FlatAppearance.BorderSize = 0;
            _btnStop.Click += (s, e) => StopClicking("已手动停止");

            Controls.Add(_btnPick);
            Controls.Add(_btnStartPause);
            Controls.Add(_btnStop);

            // 4. 状态卡片
            var pnlStatus = new Panel
            {
                Location = new Point(14, 368),
                Size = new Size(412, 42),
                BackColor = Color.White,
                BorderStyle = BorderStyle.FixedSingle
            };

            _lblStatus = new Label
            {
                Text = "状态：待机（请按 F8 锁定目标）",
                Location = new Point(10, 11),
                Size = new Size(255, 20),
                ForeColor = Color.FromArgb(71, 85, 105)
            };

            _lblClicks = new Label
            {
                Text = "已点：0 次",
                Location = new Point(270, 11),
                Size = new Size(130, 20),
                TextAlign = ContentAlignment.MiddleRight,
                Font = new Font("Microsoft YaHei UI", 9.5f, FontStyle.Bold),
                ForeColor = Color.FromArgb(15, 23, 42)
            };

            pnlStatus.Controls.Add(_lblStatus);
            pnlStatus.Controls.Add(_lblClicks);
            Controls.Add(pnlStatus);

            _lblHotkeyHint = new Label
            {
                Text = "全局热键：F8 锁定位置 | F9 开始/暂停 | F10 停止",
                Location = new Point(14, 418),
                Size = new Size(412, 20),
                TextAlign = ContentAlignment.MiddleCenter,
                Font = new Font("Microsoft YaHei UI", 8.5f),
                ForeColor = Color.FromArgb(100, 116, 139)
            };
            Controls.Add(_lblHotkeyHint);
        }

        private Label MakeInfoLabel(string text, int x, int y)
        {
            return new Label
            {
                Text = text,
                Location = new Point(x, y),
                Size = new Size(386, 20),
                AutoEllipsis = true
            };
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            bool ok8  = Win32.RegisterHotKey(Handle, HOTKEY_F8,  0, Win32.VK_F8);
            bool ok9  = Win32.RegisterHotKey(Handle, HOTKEY_F9,  0, Win32.VK_F9);
            bool ok10 = Win32.RegisterHotKey(Handle, HOTKEY_F10, 0, Win32.VK_F10);
            if (!ok8 || !ok9 || !ok10)
            {
                _lblHotkeyHint.Text = "提示：部分全局热键被其他软件占用，可用界面按钮操作";
                _lblHotkeyHint.ForeColor = Color.FromArgb(180, 83, 9);
            }
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            StopClicking("程序退出");
            Win32.UnregisterHotKey(Handle, HOTKEY_F8);
            Win32.UnregisterHotKey(Handle, HOTKEY_F9);
            Win32.UnregisterHotKey(Handle, HOTKEY_F10);
            if (_markerSyncTimer != null) _markerSyncTimer.Stop();
            if (_pickCountdownTimer != null) _pickCountdownTimer.Stop();
            if (_marker != null && !_marker.IsDisposed) _marker.Close();
            base.OnFormClosing(e);
        }

        private void StartDelayedPick()
        {
            if (_pickCountdownTimer == null)
            {
                _pickCountdownTimer = new System.Windows.Forms.Timer { Interval = 1000 };
                _pickCountdownTimer.Tick += (s, e) =>
                {
                    _pickCountdownSec--;
                    if (_pickCountdownSec <= 0)
                    {
                        CancelDelayedPick();
                        PickTargetAtCursor();
                    }
                    else
                    {
                        _btnPick.Text = string.Format("移到目标 ({0}s)", _pickCountdownSec);
                        SetStatus(string.Format("请在 {0} 秒内把鼠标移到目标位置（或直接按 F8）", _pickCountdownSec), Color.FromArgb(37, 99, 235));
                    }
                };
            }

            _pickCountdownSec = 2;
            _btnPick.Text = "移到目标 (2s)";
            _btnPick.BackColor = Color.FromArgb(37, 99, 235);
            SetStatus("请在 2 秒内把鼠标移到目标位置（或直接按 F8）", Color.FromArgb(37, 99, 235));
            _pickCountdownTimer.Stop();
            _pickCountdownTimer.Start();
        }

        private void CancelDelayedPick()
        {
            if (_pickCountdownTimer != null) _pickCountdownTimer.Stop();
            _btnPick.Text = "锁定位置 (F8)";
            _btnPick.BackColor = Color.FromArgb(15, 23, 42);
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == Win32.WM_HOTKEY)
            {
                int id = m.WParam.ToInt32();
                if (id == HOTKEY_F8) PickTargetAtCursor();
                else if (id == HOTKEY_F9) ToggleStartPause();
                else if (id == HOTKEY_F10) StopClicking("收到 F10 已停止");
                return;
            }
            base.WndProc(ref m);
        }

        private void PickTargetAtCursor()
        {
            CancelDelayedPick();
            Win32.POINT pt;
            if (!Win32.GetCursorPos(out pt)) return;

            IntPtr hwnd = Win32.WindowFromPoint(pt);
            if (hwnd == IntPtr.Zero) return;

            // 防止锁到自己或红点窗口
            IntPtr root = Win32.GetAncestor(hwnd, 2); // GA_ROOT
            if (root == Handle || (_marker != null && root == _marker.Handle))
            {
                SetStatus("请把鼠标移到目标软件窗口上再按 F8", Color.FromArgb(180, 83, 9));
                return;
            }

            Win32.POINT clientPt = pt;
            Win32.ScreenToClient(hwnd, ref clientPt);

            uint pid;
            Win32.GetWindowThreadProcessId(hwnd, out pid);
            string procName = "未知进程";
            try { procName = Process.GetProcessById((int)pid).ProcessName; } catch { }

            string rootTitle = Win32.GetTitle(root);
            if (string.IsNullOrWhiteSpace(rootTitle)) rootTitle = "(无标题)";
            string childClass = Win32.GetClass(hwnd);
            string childTitle = Win32.GetTitle(hwnd);

            _targetHwnd = hwnd;
            _relX = clientPt.X;
            _relY = clientPt.Y;

            _lblProcess.Text = string.Format("进程：{0} (PID: {1})", procName, pid);
            _lblWindow.Text  = string.Format("窗口：{0}", rootTitle);
            _lblChild.Text   = string.Format("子窗：{0} [{1}] (0x{2:X})",
                string.IsNullOrEmpty(childTitle) ? "(无标题)" : childTitle, childClass, hwnd.ToInt64());
            _lblCoord.Text   = string.Format("坐标：相对 ({0}, {1})  |  屏幕 ({2}, {3})",
                _relX, _relY, pt.X, pt.Y);

            SyncMarkerPosition();

            if (!_running)
            {
                SetStatus("已锁定目标，按 F9 开始连点", Color.FromArgb(22, 163, 74));
            }
        }

        private void SyncMarkerPosition()
        {
            if (_marker == null || _marker.IsDisposed) return;

            if (!_chkShowMarker.Checked || _targetHwnd == IntPtr.Zero || !Win32.IsWindow(_targetHwnd) || !Win32.IsWindowVisible(_targetHwnd))
            {
                if (_marker.Visible) _marker.Hide();
                return;
            }

            var pt = new Win32.POINT { X = _relX, Y = _relY };
            if (Win32.ClientToScreen(_targetHwnd, ref pt))
            {
                _marker.MoveToScreenPoint(pt.X, pt.Y);
                if (!_marker.Visible) _marker.Show();
            }
        }

        private void ToggleStartPause()
        {
            if (_targetHwnd == IntPtr.Zero || !Win32.IsWindow(_targetHwnd))
            {
                SetStatus("尚未锁定有效目标，请先指到目标按 F8", Color.FromArgb(220, 38, 38));
                return;
            }

            if (!_running)
            {
                StartClicking();
            }
            else
            {
                _paused = !_paused;
                _wakeEvent.Set();
                if (_paused)
                {
                    _btnStartPause.Text = "继续 (F9)";
                    _btnStartPause.BackColor = Color.FromArgb(217, 119, 6);
                    SetStatus("已暂停（按 F9 继续）", Color.FromArgb(180, 83, 9));
                }
                else
                {
                    _btnStartPause.Text = "暂停 (F9)";
                    _btnStartPause.BackColor = Color.FromArgb(22, 163, 74);
                    SetStatus("运行中（后台连点，不抢鼠标）", Color.FromArgb(22, 163, 74));
                }
            }
        }

        private void StartClicking()
        {
            _running = true;
            _paused = false;
            Interlocked.Exchange(ref _clickCount, 0);
            _lblClicks.Text = "已点：0 次";
            _wakeEvent.Reset();

            _btnStartPause.Text = "暂停 (F9)";
            _btnStartPause.BackColor = Color.FromArgb(22, 163, 74);
            _btnStop.Enabled = true;
            _btnStop.BackColor = Color.FromArgb(220, 38, 38);
            _btnStop.ForeColor = Color.White;
            SetControlsEditable(false);
            SetStatus("运行中（后台连点，不抢鼠标）", Color.FromArgb(22, 163, 74));

            int intervalMs = (int)_numInterval.Value;
            int jitterMs   = (int)_numJitter.Value;
            int holdMs     = (int)_numHold.Value;
            long maxCount  = (long)_numCount.Value;
            bool rightBtn  = _cmbButton.SelectedIndex == 1;

            _workerThread = new Thread(() => WorkerLoop(intervalMs, jitterMs, holdMs, maxCount, rightBtn))
            {
                IsBackground = true
            };
            _workerThread.Start();
        }

        private void StopClicking(string reason)
        {
            if (!_running) return;
            _running = false;
            _paused = false;
            _wakeEvent.Set();

            if (InvokeRequired)
            {
                try { BeginInvoke(new Action(() => ResetUiAfterStop(reason))); } catch { }
            }
            else
            {
                ResetUiAfterStop(reason);
            }
        }

        private void ResetUiAfterStop(string reason)
        {
            _btnStartPause.Text = "开始 (F9)";
            _btnStartPause.BackColor = Color.FromArgb(37, 99, 235);
            _btnStop.Enabled = false;
            _btnStop.BackColor = Color.FromArgb(226, 232, 240);
            _btnStop.ForeColor = Color.FromArgb(51, 65, 85);
            SetControlsEditable(true);
            SetStatus(reason, Color.FromArgb(71, 85, 105));
        }

        private void SetControlsEditable(bool enabled)
        {
            _numInterval.Enabled = enabled;
            _numJitter.Enabled   = enabled;
            _numHold.Enabled     = enabled;
            _numCount.Enabled    = enabled;
            _cmbButton.Enabled   = enabled;
        }

        private void SetStatus(string text, Color color)
        {
            _lblStatus.Text = "状态：" + text;
            _lblStatus.ForeColor = color;
        }

        private void WorkerLoop(int intervalMs, int jitterMs, int holdMs, long maxCount, bool rightBtn)
        {
            var rng = new Random();
            uint downMsg = rightBtn ? Win32.WM_RBUTTONDOWN : Win32.WM_LBUTTONDOWN;
            uint upMsg   = rightBtn ? Win32.WM_RBUTTONUP   : Win32.WM_LBUTTONUP;
            IntPtr downW = (IntPtr)(rightBtn ? Win32.MK_RBUTTON : Win32.MK_LBUTTON);

            while (_running)
            {
                if (_paused)
                {
                    _wakeEvent.Wait(100);
                    _wakeEvent.Reset();
                    continue;
                }

                IntPtr hwnd = _targetHwnd;
                if (hwnd == IntPtr.Zero || !Win32.IsWindow(hwnd))
                {
                    StopClicking("目标窗口已关闭，自动停止");
                    break;
                }

                IntPtr lParam = Win32.MakeLParam(_relX, _relY);
                Win32.PostMessageW(hwnd, Win32.WM_MOUSEMOVE, IntPtr.Zero, lParam);
                Win32.PostMessageW(hwnd, downMsg, downW, lParam);
                if (holdMs > 0)
                {
                    if (_wakeEvent.Wait(holdMs))
                    {
                        _wakeEvent.Reset();
                        if (!_running)
                        {
                            Win32.PostMessageW(hwnd, upMsg, IntPtr.Zero, lParam);
                            break;
                        }
                    }
                }
                Win32.PostMessageW(hwnd, upMsg, IntPtr.Zero, lParam);

                long count = Interlocked.Increment(ref _clickCount);
                try
                {
                    BeginInvoke(new Action(() =>
                    {
                        _lblClicks.Text = string.Format("已点：{0} 次", count);
                    }));
                }
                catch { }

                if (maxCount > 0 && count >= maxCount)
                {
                    StopClicking(string.Format("已完成预定次数 ({0} 次)", maxCount));
                    break;
                }

                int delay = intervalMs - holdMs;
                if (jitterMs > 0)
                {
                    delay += rng.Next(-jitterMs, jitterMs + 1);
                }
                if (delay < 5) delay = 5;

                if (_wakeEvent.Wait(delay))
                {
                    _wakeEvent.Reset();
                }
            }
        }
    }

    static class Program
    {
        [STAThread]
        static void Main()
        {
            Win32.SetProcessDPIAware();
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }
}
