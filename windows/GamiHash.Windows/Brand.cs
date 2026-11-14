using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Shapes;

namespace GamiHash.Windows;

/// <summary>
/// Headings end on the brand's coral square, as on authenticmemory.org: when a
/// heading's text ends with a full stop, the period is drawn as a small square
/// turned like a fragment of the mark. Set it with <c>local:Brand.Heading</c> in
/// XAML or <see cref="SetHeading"/> in code. Screen readers get the full text.
/// </summary>
public static class Brand
{
    public static readonly DependencyProperty HeadingProperty = DependencyProperty.RegisterAttached(
        "Heading", typeof(string), typeof(Brand), new PropertyMetadata(null, OnHeadingChanged));

    public static string? GetHeading(DependencyObject element) => (string?)element.GetValue(HeadingProperty);

    public static void SetHeading(DependencyObject element, string? value) => element.SetValue(HeadingProperty, value);

    private static void OnHeadingChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not TextBlock block) return;
        var text = e.NewValue as string ?? "";
        block.Inlines.Clear();
        AutomationProperties.SetName(block, text);
        if (!text.EndsWith('.') || text.EndsWith("..", StringComparison.Ordinal))
        {
            block.Inlines.Add(new Run(text));
            return;
        }
        block.Inlines.Add(new Run(text[..^1]));
        // The square follows the heading's font size (0.17 em, as on the
        // website); its bottom edge sits on the baseline.
        var square = new Rectangle
        {
            Fill = Application.Current?.TryFindResource("Accent") as Brush
                ?? new SolidColorBrush(Color.FromRgb(0xF3, 0x9F, 0x7F)),
            RenderTransformOrigin = new Point(0.5, 0.5),
            RenderTransform = new RotateTransform(-24),
        };
        square.SetBinding(FrameworkElement.WidthProperty, EmBinding(block, 0.17));
        square.SetBinding(FrameworkElement.HeightProperty, EmBinding(block, 0.17));
        square.SetBinding(FrameworkElement.MarginProperty, new Binding(nameof(TextBlock.FontSize))
        {
            Source = block,
            Converter = new EmThickness(),
        });
        block.Inlines.Add(new InlineUIContainer(square) { BaselineAlignment = BaselineAlignment.Baseline });
    }

    private static Binding EmBinding(TextBlock block, double factor) => new(nameof(TextBlock.FontSize))
    {
        Source = block,
        Converter = new EmScale(factor),
    };

    private sealed class EmScale(double factor) : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
            value is double size ? size * factor : 0d;

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
            throw new NotSupportedException();
    }

    private sealed class EmThickness : IValueConverter
    {
        public object Convert(object value, Type targetType, object parameter, CultureInfo culture) =>
            value is double size ? new Thickness(size * 0.07, 0, size * 0.04, 0) : new Thickness();

        public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture) =>
            throw new NotSupportedException();
    }
}
