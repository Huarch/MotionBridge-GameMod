using System.Drawing.Drawing2D;
using System.Net.Http.Json;
using System.Numerics;
using System.Runtime.InteropServices;
using System.Text.Json.Serialization;

namespace FallenDollTCodeOverlay;

internal static class Program
{
    [STAThread]
    private static void Main()
    {
        ApplicationConfiguration.Initialize();
        Application.Run(new OverlayForm());
    }
}

internal sealed class OverlayForm : Form
{
    private const int HotkeyId = 0x4644;
    private const int WmHotkey = 0x0312;
    private const int VkF12 = 0x7B;
    private readonly HttpClient _http = new() { BaseAddress = new Uri("http://127.0.0.1:17890/"), Timeout = TimeSpan.FromMilliseconds(450) };
    private readonly System.Windows.Forms.Timer _timer = new() { Interval = 100 };
    private readonly OverlayCanvas _canvas = new() { Dock = DockStyle.Fill };
    private bool _fetching;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, int modifiers, int virtualKey);
    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    [DllImport("user32.dll")]
    private static extern bool ReleaseCapture();
    [DllImport("user32.dll")]
    private static extern IntPtr SendMessage(IntPtr hWnd, int message, int wParam, int lParam);

    public OverlayForm()
    {
        Text = "Fallen Doll · TCode Simulator";
        ClientSize = new Size(424, 530);
        StartPosition = FormStartPosition.Manual;
        Location = new Point(26, 80);
        FormBorderStyle = FormBorderStyle.None;
        ShowInTaskbar = false;
        TopMost = true;
        BackColor = Color.FromArgb(18, 22, 29);
        Opacity = 0.96;
        Controls.Add(_canvas);
        _canvas.MouseDown += (_, eventArgs) =>
        {
            if (eventArgs.Button != MouseButtons.Left) return;
            if (_canvas.IsPinButton(eventArgs.Location))
            {
                TopMost = !TopMost;
                _canvas.Pinned = TopMost;
                _canvas.Invalidate();
                return;
            }
            ReleaseCapture();
            SendMessage(Handle, 0xA1, 0x2, 0); // WM_NCLBUTTONDOWN / HTCAPTION
        };
        _timer.Tick += async (_, _) => await RefreshAsync();
        Load += (_, _) =>
        {
            RegisterHotKey(Handle, HotkeyId, 0, VkF12);
            _timer.Start();
            Hide();
        };
        FormClosed += (_, _) =>
        {
            _timer.Stop();
            UnregisterHotKey(Handle, HotkeyId);
            _http.Dispose();
        };
    }

    protected override CreateParams CreateParams
    {
        get
        {
            const int WsExToolWindow = 0x00000080;
            const int WsExNoActivate = 0x08000000;
            var result = base.CreateParams;
            result.ExStyle |= WsExToolWindow | WsExNoActivate;
            return result;
        }
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == WmHotkey && m.WParam.ToInt32() == HotkeyId)
        {
            if (Visible) Hide();
            else { Show(); BringToFront(); }
            return;
        }
        base.WndProc(ref m);
    }

    private async Task RefreshAsync()
    {
        if (_fetching) return;
        _fetching = true;
        try
        {
            var snapshot = await _http.GetFromJsonAsync<BridgeState>("state");
            _canvas.State = snapshot ?? BridgeState.Offline;
        }
        catch
        {
            _canvas.State = BridgeState.Offline;
        }
        finally
        {
            _fetching = false;
            _canvas.Invalidate();
        }
    }
}

internal sealed class OverlayCanvas : Control
{
    private static readonly string[] AxisOrder = ["L0", "L1", "L2", "R0", "R1", "R2"];
    public BridgeState State { get; set; } = BridgeState.Offline;
    public bool Pinned { get; set; } = true;

    public OverlayCanvas()
    {
        DoubleBuffered = true;
        Font = new Font("Segoe UI", 9F);
    }

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.Clear(Color.FromArgb(21, 24, 31));
        var active = State.Connected;
        var accent = active ? Color.FromArgb(56, 204, 150) : Color.FromArgb(139, 155, 172);
        using var title = new Font("Segoe UI Semibold", 10.5F);
        using var strong = new Font("Consolas", 8.7F, FontStyle.Bold);
        using var normal = new Font("Consolas", 8.3F);
        using var muted = new SolidBrush(Color.FromArgb(180, 196, 207));
        using var bright = new SolidBrush(Color.FromArgb(238, 243, 247));
        g.DrawString("MOTION PREVIEW", title, bright, 16, 13);
        DrawPill(g, Pinned ? "置顶: 开" : "置顶: 关", Pinned ? Color.FromArgb(45, 85, 127) : Color.FromArgb(58, 65, 76), 260, 13, 84, 22, strong);
        DrawPill(g, active ? "LIVE" : "IDLE", active ? Color.FromArgb(21, 99, 70) : Color.FromArgb(58, 65, 76), 354, 13, 54, 22, strong);
        var montage = ShortName(State.Montage);
        g.DrawString(Trim(montage, 48), normal, muted, 16, 42);
        g.DrawString($"{State.Position:0.000}s   {State.Rate:0.00}×   curve {State.Phase * 100:0}%", strong, bright, 16, 61);
        DrawProgress(g, 16, 82, 392, 5, State.Phase, accent);
        DrawRig(g, 212, 238, active ? accent : Color.FromArgb(115, 130, 145));

        for (var i = 0; i < AxisOrder.Length; i++)
        {
            var axis = AxisOrder[i];
            var value = State.Axes.TryGetValue(axis, out var v) ? v : 5000;
            var x = 16 + (i % 3) * 134;
            var y = 432 + (i / 3) * 34;
            DrawAxisChip(g, axis, value, x, y, accent, strong, normal);
        }
        var status = State.TimeoutReason switch
        {
            null => "Profile curve is being sampled from exported bones.",
            "unsupported-or-idle-montage" => "Idle/unsupported montage: all simulated axes are neutral.",
            _ => $"Safe neutral: {State.TimeoutReason}",
        };
        g.DrawString(Trim(status, 61), normal, muted, 16, 503);
    }

    public bool IsPinButton(Point location) => location.X >= 260 && location.X <= 344 && location.Y >= 13 && location.Y <= 35;

    private void DrawRig(Graphics g, int centerX, int centerY, Color accent)
    {
        int Value(string axis) => State.Axes.TryGetValue(axis, out var value) ? value : 5000;
        var l0 = Math.Clamp((Value("L0") - 3000) / 4000.0, 0, 1);
        var l1 = Math.Clamp((Value("L1") - 4500) / 1000.0, 0, 1);
        var l2 = Math.Clamp((Value("L2") - 4500) / 1000.0, 0, 1);
        var r0 = Math.Clamp((Value("R0") - 4250) / 1500.0, 0, 1);
        var r1 = (Value("R1") - 5000) / 5000.0;
        var r2 = (Value("R2") - 5000) / 5000.0;

        var objectX = centerX + (float)((l2 - .5) * 78 + (l1 - .5) * 20);
        var objectY = centerY + (float)((l0 - .5) * 112 + (l1 - .5) * 26);
        var depthScale = (float)(0.86 + l1 * .26);
        var tilt = (float)(r1 * 16 + r2 * 11);
        using var travel = new Pen(Color.FromArgb(65, 191, 207, 221), 2) { DashStyle = DashStyle.Dash };
        g.DrawLine(travel, centerX, centerY - 118, centerX, centerY + 118);
        using var neutral = new Pen(Color.FromArgb(54, 190, 202, 214), 1);
        g.DrawEllipse(neutral, centerX - 76, centerY - 101, 152, 202);

        var saved = g.Save();
        g.TranslateTransform(objectX, objectY);
        g.RotateTransform(tilt);
        g.ScaleTransform(depthScale, depthScale);
        DrawMotionCylinder(g, accent, r0);
        g.Restore(saved);
    }

    private void DrawMotionCylinder(Graphics g, Color accent, double twist)
    {
        const int width = 152, height = 202;
        const int left = -width / 2, top = -height / 2;
        using var body = new LinearGradientBrush(new Rectangle(left, top, width, height), Color.FromArgb(125, 138, 152), Color.FromArgb(248, 250, 252), LinearGradientMode.Horizontal);
        using var topCap = new SolidBrush(Color.FromArgb(239, 243, 246));
        using var bottomCap = new SolidBrush(Color.FromArgb(164, 174, 185));
        using var outline = new Pen(Color.FromArgb(116, 130, 144), 1);
        g.FillRectangle(body, left, top + 16, width, height - 32);
        g.FillEllipse(topCap, left, top, width, 32);
        g.FillEllipse(bottomCap, left, top + height - 32, width, 32);
        g.DrawEllipse(outline, left, top, width, 32);
        g.DrawLine(outline, left, top + 16, left, top + height - 16);
        g.DrawLine(outline, left + width, top + 16, left + width, top + height - 16);

        using var l0 = new SolidBrush(Color.FromArgb(220, accent));
        g.FillRectangle(l0, left + 8, -4, width - 16, 8);
        g.FillEllipse(l0, left + 8, -8, width - 16, 16);
        DrawBlock(g, left - 30, -12, Color.FromArgb(244, 48, 49), "L1");
        DrawBlock(g, left + width - 2, -12, Color.FromArgb(137, 73, 230), "L2");

        using var ring = new Pen(Color.FromArgb(235, 255, 186, 58), 7);
        g.DrawArc(ring, left + 7, top + 42, width - 14, 22, 15, 330);
        var dotAngle = twist * Math.PI * 2;
        var dotX = (float)(Math.Cos(dotAngle) * (width / 2 - 10));
        var dotY = top + 53 + (float)Math.Sin(dotAngle) * 9;
        using var dot = new SolidBrush(Color.FromArgb(255, 232, 147, 45));
        g.FillEllipse(dot, dotX - 5, dotY - 5, 10, 10);

        var lineTop = top + height + 14;
        using var progress = new Pen(Color.FromArgb(210, 225, 230), 2);
        g.DrawLine(progress, 0, lineTop, 0, lineTop + 64);
        var phaseY = lineTop + (float)(State.Phase * 64);
        using var phaseDot = new SolidBrush(accent);
        g.FillEllipse(phaseDot, -6, phaseY - 6, 12, 12);
    }

    private static void DrawBlock(Graphics g, int x, int y, Color color, string label)
    {
        using var shadow = new SolidBrush(Color.FromArgb(70, 0, 0, 0));
        using var fill = new SolidBrush(color);
        g.FillRectangle(shadow, x + 3, y + 4, 32, 28);
        g.FillRectangle(fill, x, y, 32, 28);
        using var font = new Font("Consolas", 8F, FontStyle.Bold);
        g.DrawString(label, font, Brushes.White, x + 5, y + 7);
    }

    private static void DrawJoint(Graphics g, PointF point, Color color)
    {
        using var brush = new SolidBrush(color);
        g.FillEllipse(brush, point.X - 4, point.Y - 4, 8, 8);
    }

    private static void DrawCylinder(Graphics g, PointF start, PointF end, float diameter, Color shadow, Color highlight)
    {
        using var outer = new Pen(Color.FromArgb(238, shadow), diameter + 3) { StartCap = LineCap.Round, EndCap = LineCap.Round };
        using var body = new Pen(Color.FromArgb(255, shadow), diameter) { StartCap = LineCap.Round, EndCap = LineCap.Round };
        using var shine = new Pen(Color.FromArgb(225, highlight), Math.Max(2, diameter * 0.26F)) { StartCap = LineCap.Round, EndCap = LineCap.Round };
        g.DrawLine(outer, start, end);
        g.DrawLine(body, start, end);
        var length = Math.Max(1, Math.Sqrt(Math.Pow(end.X - start.X, 2) + Math.Pow(end.Y - start.Y, 2)));
        var offsetX = (float)(-(end.Y - start.Y) / length * diameter * 0.18);
        var offsetY = (float)((end.X - start.X) / length * diameter * 0.18);
        g.DrawLine(shine, new PointF(start.X + offsetX, start.Y + offsetY), new PointF(end.X + offsetX, end.Y + offsetY));
        using var cap = new SolidBrush(Color.FromArgb(245, highlight));
        g.FillEllipse(cap, start.X - diameter * 0.26F, start.Y - diameter * 0.26F, diameter * 0.52F, diameter * 0.52F);
        g.FillEllipse(cap, end.X - diameter * 0.26F, end.Y - diameter * 0.26F, diameter * 0.52F, diameter * 0.52F);
    }

    private static P3 RingPoint(int index, double radius, double z)
    {
        var theta = -Math.PI / 2 + index * Math.PI * 2 / 6;
        return new P3(Math.Cos(theta) * radius, Math.Sin(theta) * radius, z);
    }

    private static P3 Rotate(P3 p, double twist, double roll, double pitch)
    {
        var x1 = p.X;
        var y1 = p.Y * Math.Cos(twist) - p.Z * Math.Sin(twist);
        var z1 = p.Y * Math.Sin(twist) + p.Z * Math.Cos(twist);
        var x2 = x1 * Math.Cos(roll) + z1 * Math.Sin(roll);
        var z2 = -x1 * Math.Sin(roll) + z1 * Math.Cos(roll);
        return new P3(x2 * Math.Cos(pitch) - y1 * Math.Sin(pitch), x2 * Math.Sin(pitch) + y1 * Math.Cos(pitch), z2);
    }

    private static PointF Project(P3 p, int cx, int cy) => new((float)(cx + p.X * 74 + p.Y * 42), (float)(cy - p.Z * 78 + p.Y * 22 - p.X * 16));

    private static void DrawAxis(Graphics g, string axis, int value, int x, int y, int width, Color accent, Font strong, Font normal)
    {
        const int min = 3000, max = 7000;
        var normalized = Math.Clamp((value - min) / (double)(max - min), 0, 1);
        g.DrawString(axis, strong, Brushes.White, x, y);
        using var track = new SolidBrush(Color.FromArgb(43, 51, 63));
        using var fill = new SolidBrush(axis is "L0" or "R0" ? accent : Color.FromArgb(97, 118, 138));
        var trackWidth = width - 80;
        g.FillRectangle(track, x + 36, y + 5, trackWidth, 13);
        g.FillRectangle(fill, x + 36, y + 5, (int)(trackWidth * normalized), 13);
        using var marker = new Pen(Color.FromArgb(235, 240, 245), 1);
        g.DrawLine(marker, x + 36 + trackWidth / 2, y + 3, x + 36 + trackWidth / 2, y + 20);
        g.DrawString(value.ToString("0000"), normal, Brushes.Gainsboro, x + width - 37, y);
    }

    private static void DrawAxisChip(Graphics g, string axis, int value, int x, int y, Color accent, Font strong, Font normal)
    {
        var color = axis switch
        {
            "L0" => accent,
            "L1" => Color.FromArgb(244, 48, 49),
            "L2" => Color.FromArgb(137, 73, 230),
            "R0" => Color.FromArgb(232, 147, 45),
            _ => Color.FromArgb(86, 101, 118),
        };
        using var fill = new SolidBrush(Color.FromArgb(46, color));
        using var line = new Pen(Color.FromArgb(128, color));
        g.FillRectangle(fill, x, y, 122, 27);
        g.DrawRectangle(line, x, y, 122, 27);
        using var dot = new SolidBrush(color);
        g.FillEllipse(dot, x + 8, y + 9, 9, 9);
        g.DrawString(axis, strong, Brushes.Gainsboro, x + 25, y + 6);
        g.DrawString(value.ToString("0000"), normal, Brushes.White, x + 67, y + 6);
    }

    private static void DrawProgress(Graphics g, int x, int y, int width, int height, double value, Color color)
    {
        using var track = new SolidBrush(Color.FromArgb(44, 51, 61));
        using var fill = new SolidBrush(color);
        g.FillRectangle(track, x, y, width, height);
        g.FillRectangle(fill, x, y, (int)(width * Math.Clamp(value, 0, 1)), height);
    }

    private static void DrawPill(Graphics g, string text, Color color, int x, int y, int width, int height, Font font)
    {
        using var brush = new SolidBrush(color);
        using var path = new GraphicsPath();
        path.AddArc(x, y, height, height, 90, 180);
        path.AddArc(x + width - height, y, height, height, 270, 180);
        path.CloseFigure();
        g.FillPath(brush, path);
        var size = g.MeasureString(text, font);
        g.DrawString(text, font, Brushes.White, x + (width - size.Width) / 2, y + (height - size.Height) / 2 - 1);
    }

    private static string ShortName(string? value) => string.IsNullOrWhiteSpace(value) ? "Waiting for a supported animation…" : value[(value.LastIndexOf('.') + 1)..];
    private static string Trim(string text, int length) => text.Length <= length ? text : text[..(length - 1)] + "…";

    private readonly record struct P3(double X, double Y, double Z)
    {
        public static P3 operator +(P3 a, P3 b) => new(a.X + b.X, a.Y + b.Y, a.Z + b.Z);
    }
}

internal sealed class BridgeState
{
    public static BridgeState Offline { get; } = new() { Connected = false, TimeoutReason = "bridge-offline" };
    [JsonPropertyName("connected")] public bool Connected { get; init; }
    [JsonPropertyName("montage")] public string? Montage { get; init; }
    [JsonPropertyName("position")] public double Position { get; init; }
    [JsonPropertyName("phase")] public double Phase { get; init; }
    [JsonPropertyName("rate")] public double Rate { get; init; }
    [JsonPropertyName("axes")] public Dictionary<string, int> Axes { get; init; } = new();
    [JsonPropertyName("timeoutReason")] public string? TimeoutReason { get; init; }
}
