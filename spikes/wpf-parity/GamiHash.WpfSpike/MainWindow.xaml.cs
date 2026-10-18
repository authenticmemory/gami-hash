using Microsoft.Win32;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace GamiHash.WpfSpike;

public partial class MainWindow : Window
{
    private readonly string[] _args = Environment.GetCommandLineArgs();
    private EngineClient? _engine;
    private string _root = "";
    private string _output = "";
    private string _mode = "fresh";
    private DateTime _startedAt;
    private readonly DispatcherTimer _elapsedTimer = new() { Interval = TimeSpan.FromSeconds(1) };

    public MainWindow()
    {
        InitializeComponent();
        _elapsedTimer.Tick += (_, _) => ElapsedText.Text = FormatElapsed(DateTime.Now - _startedAt);
        ResumeCard.Visibility = _args.Contains("--resume-fixture") ? Visibility.Visible : Visibility.Collapsed;
        Loaded += async (_, _) => await ConnectGoBackendAsync();
        Closed += async (_, _) =>
        {
            if (_engine is not null) await _engine.DisposeAsync();
        };
        ContentRendered += (_, _) => CaptureIfRequested();
    }

    private async Task ConnectGoBackendAsync()
    {
        var engine = Path.Combine(AppContext.BaseDirectory, "GamiHashEngine.exe");
        if (!File.Exists(engine)) return;
        try
        {
            _engine = await EngineClient.StartAsync(engine);
            _engine.EventReceived += OnEngineEvent;
            _ = await _engine.InspectResumeAsync(Path.Combine(Path.GetTempPath(), "gami-hash-native-ui-gate.csv"));
            await RefreshResumeCardAsync();
        }
        catch (Exception error)
        {
            MessageBox.Show(this, error.Message, "GAMI Hash could not start", MessageBoxButton.OK, MessageBoxImage.Error);
            Close();
        }
    }

    private void ChooseFolder_Click(object sender, RoutedEventArgs e)
    {
        var picker = new OpenFolderDialog { Title = "Select the folder to hash", Multiselect = false };
        if (picker.ShowDialog(this) != true) return;
        _root = picker.FolderName;
        SelectedPath.Text = _root;
        WelcomeView.Visibility = Visibility.Collapsed;
        SelectedView.Visibility = Visibility.Visible;
    }

    private async void ChooseOutput_Click(object sender, RoutedEventArgs e)
    {
        if (_engine is null)
        {
            MessageBox.Show(this, "The GAMI Hash engine is unavailable.", "GAMI Hash", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }
        var baseName = Path.GetFileName(_root.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar));
        foreach (var invalid in Path.GetInvalidFileNameChars().Append(' ')) baseName = baseName.Replace(invalid, '_');
        if (baseName.Length > 60) baseName = baseName[..60];
        var picker = new SaveFileDialog
        {
            Title = "Save the GAMI hash manifest",
            Filter = "CSV manifest (*.csv)|*.csv",
            DefaultExt = ".csv",
            AddExtension = true,
            OverwritePrompt = false,
            FileName = $"checksums_{baseName}_{DateTime.Now:yyyy-MM-dd}.csv"
        };
        if (picker.ShowDialog(this) != true) return;

        try
        {
            var resume = await _engine.InspectResumeAsync(picker.FileName);
            var sameRoot = resume.Root is not null &&
                string.Equals(Path.GetFullPath(resume.Root).TrimEnd('\\'), Path.GetFullPath(_root).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
            if (resume.Resumable && !sameRoot)
                throw new InvalidOperationException("This result file belongs to a different folder. Choose another result file.");
            _mode = resume.Resumable ? "resume" : "fresh";
            var review = await _engine.PreflightAsync(_root, picker.FileName, _mode);
            _output = review.Output;
            ShowReady(review);
        }
        catch (Exception error)
        {
            MessageBox.Show(this, error.Message, "The selected locations cannot be used", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private async void Start_Click(object sender, RoutedEventArgs e)
    {
        if (_engine is null) return;
        ReadyView.Visibility = Visibility.Collapsed;
        ProgressView.Visibility = Visibility.Visible;
        ProgressOutput.Text = _output;
        ProgressBar.IsIndeterminate = true;
        ProgressTitle.Text = "Counting files";
        ProgressDetail.Text = "Counting files…";
        FilesText.Text = "0 of 0";
        BytesText.Text = "0 B of 0 B";
        _startedAt = DateTime.Now;
        ElapsedText.Text = "0 sec";
        _elapsedTimer.Start();
        RunStateStore.Write(_root, _output);
        await Dispatcher.Yield(DispatcherPriority.Render);
        try { await _engine.StartRunAsync(_root, _output, _mode); }
        catch (Exception error) { ShowFailure(error.Message); }
    }

    private async void Cancel_Click(object sender, RoutedEventArgs e)
    {
        if (_engine is null) return;
        CancelButton.IsEnabled = false;
        CancelButton.Content = "Stopping…";
        ProgressTitle.Text = "Stopping…";
        ProgressDetail.Text = "Finishing the current file. Progress is kept.";
        try { await _engine.CancelAsync(); }
        catch (Exception error) { ShowFailure(error.Message); }
    }

    private void OnEngineEvent(EngineEvent engineEvent) => Dispatcher.BeginInvoke(async () =>
    {
        if (engineEvent.Kind == "progress" && engineEvent.Progress is not null)
        {
            var progress = engineEvent.Progress;
            var scanning = progress.Phase == 0;
            ProgressBar.IsIndeterminate = scanning;
            if (!scanning)
            {
                var ratio = progress.BytesTotal > 0 ? (double)progress.BytesDone / progress.BytesTotal :
                    progress.FilesTotal > 0 ? (double)progress.FilesDone / progress.FilesTotal : 0;
                ProgressBar.Value = Math.Clamp(ratio * 100, 0, 100);
                ProgressTitle.Text = $"{ProgressBar.Value:F1}%";
                ProgressDetail.Text = "Hashing files…";
            }
            FilesText.Text = $"{progress.FilesDone:N0} of {progress.FilesTotal:N0}";
            BytesText.Text = $"{FormatBytes(progress.BytesDone)} of {FormatBytes(progress.BytesTotal)}";
        }
        else if (engineEvent.Kind == "result" && engineEvent.Result is not null)
        {
            var remaining = TimeSpan.FromMilliseconds(750) - (DateTime.Now - _startedAt);
            if (remaining > TimeSpan.Zero) await Task.Delay(remaining);
            _elapsedTimer.Stop();
            ShowResult(engineEvent.Result);
        }
        else if (engineEvent.Kind == "fatal") ShowFailure(engineEvent.Error ?? "The run failed.");
    });

    private async void Home_Click(object sender, RoutedEventArgs e)
    {
        _elapsedTimer.Stop();
        ResultView.Visibility = Visibility.Collapsed;
        ProgressView.Visibility = Visibility.Collapsed;
        ReadyView.Visibility = Visibility.Collapsed;
        SelectedView.Visibility = Visibility.Collapsed;
        WelcomeView.Visibility = Visibility.Visible;
        CancelButton.IsEnabled = true;
        CancelButton.Content = "Cancel";
        _root = "";
        _output = "";
        _mode = "fresh";
        await RefreshResumeCardAsync();
    }

    private void ShowResult(EngineResult result)
    {
        if (!result.Canceled) RunStateStore.Clear();
        ProgressView.Visibility = Visibility.Collapsed;
        ResultView.Visibility = Visibility.Visible;
        ResultTitle.Text = result.Canceled ? "Stopped. Nothing is lost." : "Done";
        ResultSummary.Text = result.Canceled
            ? "Your progress is saved. You can close the program and continue later."
            : $"{result.FilesHashed + result.FilesResumed:N0} files ({FormatBytes(result.BytesTotal)}) were recorded.";
        ResultOutput.Text = result.Output;
    }

    private void ShowReady(PreflightResult review)
    {
        ReviewRoot.Text = review.Root;
        ReviewOutput.Text = review.Output;
        StartButton.Content = review.WillResume ? "Continue" : "Start";
        StartButton.IsEnabled = true;
        WelcomeView.Visibility = Visibility.Collapsed;
        SelectedView.Visibility = Visibility.Collapsed;
        ReadyView.Visibility = Visibility.Visible;
    }

    private async Task RefreshResumeCardAsync()
    {
        if (_engine is null || _args.Contains("--resume-fixture")) return;
        var saved = RunStateStore.Read();
        if (saved is null) { ResumeCard.Visibility = Visibility.Collapsed; return; }
        var inspection = await _engine.InspectResumeAsync(saved.Output);
        if (!inspection.Resumable)
        {
            RunStateStore.Clear();
            ResumeCard.Visibility = Visibility.Collapsed;
            return;
        }
        ResumeCount.Text = $"{inspection.Rows:N0} files recorded so far";
        ResumePath.Text = inspection.Root ?? saved.Root;
        ResumeCard.Visibility = Visibility.Visible;
    }

    private async void Resume_Click(object sender, RoutedEventArgs e)
    {
        if (_engine is null) return;
        var saved = RunStateStore.Read();
        if (saved is null) return;
        try
        {
            _root = saved.Root;
            _output = saved.Output;
            _mode = "resume";
            ShowReady(await _engine.PreflightAsync(_root, _output, _mode));
        }
        catch (Exception error)
        {
            RunStateStore.Clear();
            MessageBox.Show(this, error.Message, "The interrupted run cannot be resumed", MessageBoxButton.OK, MessageBoxImage.Warning);
            await RefreshResumeCardAsync();
        }
    }

    private void ShowFailure(string message)
    {
        _elapsedTimer.Stop();
        ProgressView.Visibility = Visibility.Collapsed;
        ResultView.Visibility = Visibility.Visible;
        ResultTitle.Text = "The run could not continue";
        ResultSummary.Text = message;
        ResultOutput.Text = _output;
    }

    private static string FormatBytes(long bytes) => bytes switch
    {
        >= 1L << 30 => $"{bytes / (double)(1L << 30):F1} GB",
        >= 1L << 20 => $"{bytes / (double)(1L << 20):F1} MB",
        >= 1L << 10 => $"{bytes / (double)(1L << 10):F1} KB",
        _ => $"{bytes} B"
    };

    private static string FormatElapsed(TimeSpan elapsed) => elapsed.TotalHours >= 1
        ? $"{(int)elapsed.TotalHours} hr {elapsed.Minutes} min"
        : elapsed.TotalMinutes >= 1 ? $"{(int)elapsed.TotalMinutes} min {elapsed.Seconds} sec" : $"{elapsed.Seconds} sec";

    private void Back_Click(object sender, RoutedEventArgs e)
    {
        SelectedView.Visibility = Visibility.Collapsed;
        WelcomeView.Visibility = Visibility.Visible;
    }

    private void ChangeOutput_Click(object sender, RoutedEventArgs e)
    {
        ReadyView.Visibility = Visibility.Collapsed;
        SelectedView.Visibility = Visibility.Visible;
    }

    private void CaptureIfRequested()
    {
        var index = Array.IndexOf(_args, "--capture");
        if (index < 0 || index + 1 >= _args.Length) return;
        var path = Path.GetFullPath(_args[index + 1]);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var dpi = VisualTreeHelper.GetDpi(this);
        var bitmap = new RenderTargetBitmap((int)(ActualWidth * dpi.DpiScaleX), (int)(ActualHeight * dpi.DpiScaleY),
            96 * dpi.DpiScaleX, 96 * dpi.DpiScaleY, PixelFormats.Pbgra32);
        bitmap.Render(this);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = File.Create(path);
        encoder.Save(stream);
    }

    private void Minimize_Click(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;
    private void Maximize_Click(object sender, RoutedEventArgs e) =>
        WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
