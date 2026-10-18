#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include "storage_consent.h"
#include "worker_launcher.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <commctrl.h>
#include <dwmapi.h>
#include <iomanip>
#include <memory>
#include <shobjidl.h>
#include <sstream>
#include <string>
#include <thread>
#include <vector>
#include <windows.h>
#include <windowsx.h>
#include <appmodel.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.AccessCache.h>
#include <winrt/Windows.Storage.Pickers.h>
#include <winrt/Windows.Storage.h>
#include <winrt/Windows.System.h>

using namespace winrt;
using namespace Windows::Storage;
using namespace Windows::Storage::AccessCache;
using namespace Windows::Storage::Pickers;

namespace {
constexpr wchar_t source_key[] = L"phase4.sourceToken",
                  destination_key[] = L"phase4.destinationToken",
                  output_key[] = L"phase4.outputName",
                  resume_key[] = L"phase4.resumePending";
constexpr wchar_t source_access[] = L"phase4-source",
                  destination_access[] = L"phase4-destination";
constexpr UINT msg_render = WM_APP, msg_progress = WM_APP + 1,
               msg_complete = WM_APP + 2, msg_initialize = WM_APP + 3;
constexpr UINT msg_selection = WM_APP + 4;
enum class page {
  welcome,
  source,
  destination,
  review,
  progress,
  result,
  failure
};
enum ids {
  primary = 100,
  secondary,
  output_edit,
  progress_bar,
  result_icon,
  progress_title,
  files_metric,
  bytes_metric,
  elapsed_metric,
  eyebrow_text,
  muted_text,
  caption_minimize,
  caption_maximize,
  caption_close
};
struct completion {
  bool ok{};
  std::wstring error;
  gami::storage::worker_result worker;
};
struct selection_result {
  bool source{};
  std::wstring token;
  std::wstring path;
  StorageFolder folder{nullptr};
  gami::storage::location_classification classification;
};

HWND window{};
HFONT title_font{}, body_font{}, small_font{}, icon_font{}, mono_font{},
    brand_font{}, brand_tool_font{};
HBRUSH white_brush{};
HICON brand_icon{};
std::vector<std::wstring> private_font_paths;
std::vector<HWND> controls;
page current{page::welcome};
std::wstring source_token, destination_token, source_path, destination_path,
    output_name{L"gami-hash.csv"}, last_error;
gami::storage::location_classification source_class, destination_class;
StorageFolder selected_source{nullptr}, selected_destination{nullptr};
gami::storage::worker_result last_result;
gami::storage::storage_progress last_progress;
std::atomic_bool running{}, cancel_requested{};
bool resume_pending{}, close_after_cancel{};
bool preview_mode{};
bool has_progress{};
bool interactive_resize{};
std::chrono::steady_clock::time_point started;
constexpr wchar_t hover_property[] = L"GamiActionButtonHovered";

LRESULT CALLBACK caption_button_subclass(HWND hwnd, UINT message, WPARAM wp,
                                         LPARAM lp, UINT_PTR, DWORD_PTR) {
  if (message == WM_MOUSEMOVE && !GetPropW(hwnd, hover_property)) {
    SetPropW(hwnd, hover_property, reinterpret_cast<HANDLE>(1));
    TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, hwnd, 0};
    TrackMouseEvent(&tracking);
    InvalidateRect(hwnd, nullptr, TRUE);
  } else if (message == WM_MOUSELEAVE) {
    RemovePropW(hwnd, hover_property);
    InvalidateRect(hwnd, nullptr, TRUE);
  } else if (message == WM_NCDESTROY) {
    RemovePropW(hwnd, hover_property);
    RemoveWindowSubclass(hwnd, caption_button_subclass, 1);
  }
  return DefSubclassProc(hwnd, message, wp, lp);
}

LRESULT CALLBACK action_button_subclass(HWND hwnd, UINT message, WPARAM wp,
                                        LPARAM lp, UINT_PTR, DWORD_PTR) {
  if (message == WM_MOUSEMOVE && !GetPropW(hwnd, hover_property)) {
    SetPropW(hwnd, hover_property, reinterpret_cast<HANDLE>(1));
    TRACKMOUSEEVENT tracking{sizeof(tracking), TME_LEAVE, hwnd, 0};
    TrackMouseEvent(&tracking);
    InvalidateRect(hwnd, nullptr, TRUE);
  } else if (message == WM_MOUSELEAVE) {
    RemovePropW(hwnd, hover_property);
    InvalidateRect(hwnd, nullptr, TRUE);
  } else if (message == WM_SETCURSOR && IsWindowEnabled(hwnd)) {
    SetCursor(LoadCursorW(nullptr, IDC_HAND));
    return TRUE;
  } else if (message == WM_NCDESTROY) {
    RemovePropW(hwnd, hover_property);
    RemoveWindowSubclass(hwnd, action_button_subclass, 1);
  }
  return DefSubclassProc(hwnd, message, wp, lp);
}

std::wstring executable_directory() {
  wchar_t image[32768]{};
  GetModuleFileNameW(nullptr, image, static_cast<DWORD>(std::size(image)));
  std::wstring path(image);
  auto separator = path.find_last_of(L"\\/");
  return separator == std::wstring::npos ? L"." : path.substr(0, separator);
}

void load_private_fonts() {
  auto root = executable_directory() + L"\\Assets\\Fonts\\";
  private_font_paths = {root + L"Inter-Variable.ttf",
                        root + L"JetBrainsMono-Variable.ttf"};
  for (auto const &path : private_font_paths)
    AddFontResourceExW(path.c_str(), FR_PRIVATE, nullptr);
}

void unload_private_fonts() {
  for (auto const &path : private_font_paths)
    RemoveFontResourceExW(path.c_str(), FR_PRIVATE, nullptr);
  private_font_paths.clear();
}

bool has_package_identity() {
  UINT32 length{};
  return GetCurrentPackageFullName(&length, nullptr) != APPMODEL_ERROR_NO_PACKAGE;
}

int scaled(int value) {
  return MulDiv(value, static_cast<int>(GetDpiForWindow(window)), 96);
}
int content_offset_x() {
  RECT client{};
  GetClientRect(window, &client);
  return std::max(0, (static_cast<int>(client.right) - scaled(980)) / 2);
}
int content_offset_y() {
  RECT client{};
  GetClientRect(window, &client);
  return std::max(0, (static_cast<int>(client.bottom) - scaled(716)) / 2);
}
void create_fonts(UINT dpi) {
  if (title_font)
    DeleteObject(title_font);
  if (body_font)
    DeleteObject(body_font);
  if (small_font)
    DeleteObject(small_font);
  if (icon_font)
    DeleteObject(icon_font);
  if (mono_font)
    DeleteObject(mono_font);
  if (brand_font)
    DeleteObject(brand_font);
  if (brand_tool_font)
    DeleteObject(brand_tool_font);
  body_font =
      CreateFontW(-MulDiv(15, dpi, 96), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                  DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                  CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Inter");
  title_font = CreateFontW(-MulDiv(28, dpi, 96), 0, 0, 0, FW_SEMIBOLD, FALSE,
                           FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                           CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                           DEFAULT_PITCH, L"Inter");
  small_font = CreateFontW(-MulDiv(13, dpi, 96), 0, 0, 0, FW_SEMIBOLD, FALSE,
                           FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                           CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                           DEFAULT_PITCH, L"Inter");
  icon_font = CreateFontW(-MulDiv(27, dpi, 96), 0, 0, 0, FW_SEMIBOLD, FALSE,
                          FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                          CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH,
                          L"Segoe UI Symbol");
  mono_font = CreateFontW(-MulDiv(13, dpi, 96), 0, 0, 0, FW_NORMAL, FALSE,
                          FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                          CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, FIXED_PITCH,
                          L"JetBrains Mono");
  brand_font = CreateFontW(-MulDiv(15, dpi, 96), 0, 0, 0, 650, FALSE, FALSE,
                           FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
                           CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
                           DEFAULT_PITCH, L"Inter");
  brand_tool_font =
      CreateFontW(-MulDiv(14, dpi, 96), 0, 0, 0, 450, FALSE, FALSE, FALSE,
                  DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                  CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Inter");
}
void clear() {
  for (auto h : controls)
    DestroyWindow(h);
  controls.clear();
}
HWND control(wchar_t const *cls, std::wstring const &text, DWORD style, int x,
             int y, int w, int h, int id = 0, HFONT font = nullptr) {
  auto caption = id >= caption_minimize && id <= caption_close;
  RECT client{};
  GetClientRect(window, &client);
  auto left = caption ? client.right - scaled(980 - x)
                      : scaled(x) + content_offset_x();
  auto top = caption ? scaled(y) : scaled(y) + content_offset_y();
  auto result =
      CreateWindowExW(0, cls, text.c_str(), WS_CHILD | WS_VISIBLE | style,
                      left, top, scaled(w), scaled(h), window,
                      reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)),
                      GetModuleHandleW(nullptr), nullptr);
  SendMessageW(result, WM_SETFONT,
               reinterpret_cast<WPARAM>(font ? font : body_font), TRUE);
  controls.push_back(result);
  if (caption)
    SetWindowSubclass(result, caption_button_subclass, 1, 0);
  return result;
}
HWND label(std::wstring const &text, int y, int h, HFONT font = nullptr) {
  auto id = (!font || font == body_font) ? muted_text : 0;
  return control(L"STATIC", text, SS_LEFT, 204, y, 572, h, id, font);
}
HWND styled_label(std::wstring const &text, int y, int h, int id,
                  HFONT font = nullptr) {
  return control(L"STATIC", text, SS_LEFT, 204, y, 572, h, id, font);
}
HWND eyebrow(std::wstring const &text, int y, int h = 20) {
  return styled_label(text, y, h, eyebrow_text, small_font);
}
HWND centered_label(std::wstring const &text, int y, int h,
                    HFONT font = nullptr, int id = 0) {
  if (!id && (!font || font == body_font))
    id = muted_text;
  return control(L"STATIC", text, id == result_icon ? SS_OWNERDRAW : SS_CENTER,
                 204, y, 572, h, id, font);
}
HWND button(std::wstring const &text, int id, int x, int y, int w,
            bool def = false) {
  auto result = control(
      L"BUTTON", text,
      WS_TABSTOP | BS_OWNERDRAW | (def ? BS_DEFPUSHBUTTON : 0), x, y, w, 42,
      id);
  SetWindowSubclass(result, action_button_subclass, 1, 0);
  return result;
}

RECT panel_rect() {
  switch (current) {
  case page::welcome:
    return {170, resume_pending ? 170 : 238, 810, resume_pending ? 544 : 526};
  case page::source:
  case page::destination:
    return {170, 214, 810, 566};
  case page::review:
    return {170, 176, 810, 604};
  case page::progress:
    return {170, 154, 810, 624};
  case page::result:
    return last_result.summary.canceled ? RECT{170, 223, 810, 551}
                                        : RECT{170, 182, 810, 594};
  case page::failure:
    return {170, 198, 810, 578};
  }
  return {170, 214, 810, 566};
}

void rounded_box(HDC dc, RECT rect, COLORREF fill, COLORREF border,
                 int radius = 12) {
  auto dx = content_offset_x(), dy = content_offset_y();
  rect = {scaled(rect.left) + dx, scaled(rect.top) + dy,
          scaled(rect.right) + dx, scaled(rect.bottom) + dy};
  auto brush = CreateSolidBrush(fill);
  auto pen = CreatePen(PS_SOLID, 1, border);
  auto old_brush = SelectObject(dc, brush);
  auto old_pen = SelectObject(dc, pen);
  RoundRect(dc, rect.left, rect.top, rect.right, rect.bottom, scaled(radius),
            scaled(radius));
  SelectObject(dc, old_brush);
  SelectObject(dc, old_pen);
  DeleteObject(brush);
  DeleteObject(pen);
}

void paint_chrome(HWND hwnd) {
  PAINTSTRUCT ps{};
  auto dc = BeginPaint(hwnd, &ps);
  RECT client{};
  GetClientRect(hwnd, &client);
  FillRect(dc, &client, white_brush);
  auto old_font = SelectObject(dc, brand_font);
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, RGB(21, 32, 53));
  if (brand_icon)
    DrawIconEx(dc, scaled(40), scaled(13), brand_icon, scaled(26), scaled(26),
               0, nullptr, DI_NORMAL);
  SIZE brand_size{};
  GetTextExtentPoint32W(dc, L"Authentic Memory", 16, &brand_size);
  RECT brand{scaled(77), scaled(13), scaled(77) + brand_size.cx, scaled(41)};
  DrawTextW(dc, L"Authentic Memory", 16, &brand,
            DT_LEFT | DT_VCENTER | DT_SINGLELINE);
  SelectObject(dc, brand_tool_font);
  auto dot_left = brand.right + scaled(7);
  SetTextColor(dc, RGB(148, 163, 184));
  RECT dot{dot_left, scaled(13), dot_left + scaled(8), scaled(41)};
  DrawTextW(dc, L"\x00B7", 1, &dot, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  SetTextColor(dc, RGB(71, 85, 105));
  RECT tool{dot.right + scaled(7), scaled(13), scaled(430), scaled(41)};
  DrawTextW(dc, L"Hashing Tool", -1, &tool,
            DT_LEFT | DT_VCENTER | DT_SINGLELINE);
  HPEN rule = CreatePen(PS_SOLID, 1, RGB(236, 239, 243));
  auto old_pen = SelectObject(dc, rule);
  MoveToEx(dc, 0, scaled(52), nullptr);
  LineTo(dc, client.right, scaled(52));
  rounded_box(dc, panel_rect(), RGB(255, 255, 255), RGB(236, 239, 243), 14);
  if (current == page::source)
    rounded_box(dc, {204, 389, 776, 461}, RGB(250, 251, 252),
                RGB(236, 239, 243), 10);
  if (current == page::welcome && resume_pending)
    rounded_box(dc, {204, 374, 776, 474}, RGB(245, 248, 246),
                RGB(231, 240, 235), 12);
  if (current == page::review) {
    rounded_box(dc, {204, 355, 776, 500}, RGB(255, 255, 255),
                RGB(236, 239, 243), 12);
    MoveToEx(dc, scaled(204) + content_offset_x(),
             scaled(427) + content_offset_y(), nullptr);
    LineTo(dc, scaled(776) + content_offset_x(),
           scaled(427) + content_offset_y());
  }
  if (current == page::result && !last_result.summary.canceled)
    rounded_box(dc, {204, 374, 776, 447}, RGB(250, 251, 252),
                RGB(236, 239, 243), 10);
  if (current == page::progress) {
    rounded_box(dc, {204, 340, 386, 420}, RGB(255, 255, 255),
                RGB(236, 239, 243), 10);
    rounded_box(dc, {395, 340, 586, 420}, RGB(255, 255, 255),
                RGB(236, 239, 243), 10);
    rounded_box(dc, {595, 340, 776, 420}, RGB(255, 255, 255),
                RGB(236, 239, 243), 10);
    rounded_box(dc, {204, 442, 776, 515}, RGB(250, 251, 252),
                RGB(236, 239, 243), 10);
  }
  SelectObject(dc, old_pen);
  SelectObject(dc, old_font);
  DeleteObject(rule);
  EndPaint(hwnd, &ps);
}

void draw_button(DRAWITEMSTRUCT const &item) {
  if (item.CtlID >= caption_minimize && item.CtlID <= caption_close) {
    FillRect(item.hDC, &item.rcItem, white_brush);
    auto hovered = GetPropW(item.hwndItem, hover_property) != nullptr;
    if (hovered || (item.itemState & ODS_SELECTED)) {
      auto fill = CreateSolidBrush(item.CtlID == caption_close
                                       ? RGB(253, 245, 247)
                                       : RGB(244, 246, 248));
      auto previous_fill = SelectObject(item.hDC, fill);
      auto previous_pen = SelectObject(item.hDC, GetStockObject(NULL_PEN));
      RoundRect(item.hDC, item.rcItem.left, item.rcItem.top,
                item.rcItem.right, item.rcItem.bottom, scaled(16), scaled(16));
      SelectObject(item.hDC, previous_pen);
      SelectObject(item.hDC, previous_fill);
      DeleteObject(fill);
    }
    auto color = item.CtlID == caption_close &&
                         (hovered || (item.itemState & ODS_SELECTED))
                     ? RGB(159, 18, 57)
                     : RGB(100, 116, 139);
    auto pen = CreatePen(PS_SOLID, std::max(1, scaled(1)), color);
    auto previous_pen = SelectObject(item.hDC, pen);
    auto previous_brush = SelectObject(item.hDC, GetStockObject(NULL_BRUSH));
    auto glyph = scaled(10);
    auto left = (item.rcItem.right - glyph) / 2;
    auto top = (item.rcItem.bottom - glyph) / 2;
    auto right = left + glyph;
    auto bottom = top + glyph;
    if (item.CtlID == caption_minimize) {
      auto middle = top + glyph / 2;
      MoveToEx(item.hDC, left, middle, nullptr);
      LineTo(item.hDC, right, middle);
    } else if (item.CtlID == caption_maximize && IsZoomed(window)) {
      Rectangle(item.hDC, left, top + scaled(2), right - scaled(2), bottom);
      MoveToEx(item.hDC, left + scaled(2), top + scaled(2), nullptr);
      LineTo(item.hDC, left + scaled(2), top);
      LineTo(item.hDC, right, top);
      LineTo(item.hDC, right, bottom - scaled(2));
      LineTo(item.hDC, right - scaled(2), bottom - scaled(2));
    } else if (item.CtlID == caption_maximize) {
      Rectangle(item.hDC, left, top, right, bottom);
    } else {
      MoveToEx(item.hDC, left, top, nullptr);
      LineTo(item.hDC, right, bottom);
      MoveToEx(item.hDC, right, top, nullptr);
      LineTo(item.hDC, left, bottom);
    }
    SelectObject(item.hDC, previous_brush);
    SelectObject(item.hDC, previous_pen);
    DeleteObject(pen);
    return;
  }
  bool primary_button = item.CtlID == primary;
  bool disabled = (item.itemState & ODS_DISABLED) != 0;
  bool hovered = GetPropW(item.hwndItem, hover_property) != nullptr;
  auto control_background =
      current == page::welcome && resume_pending && item.CtlID == secondary
          ? CreateSolidBrush(RGB(245, 248, 246))
          : nullptr;
  FillRect(item.hDC, &item.rcItem,
           control_background ? control_background : white_brush);
  if (control_background)
    DeleteObject(control_background);
  auto background = primary_button ? RGB(21, 32, 53) : RGB(255, 255, 255);
  auto foreground = primary_button ? RGB(255, 255, 255) : RGB(21, 32, 53);
  auto border = primary_button ? RGB(21, 32, 53) : RGB(148, 163, 184);
  if (item.itemState & ODS_SELECTED)
    background = primary_button ? RGB(36, 50, 77) : RGB(244, 246, 248);
  else if (hovered && !disabled) {
    background = primary_button ? RGB(36, 50, 77) : RGB(250, 251, 252);
    border = primary_button ? RGB(36, 50, 77) : RGB(21, 32, 53);
  }
  if (disabled) {
    foreground = RGB(148, 163, 184);
    background = RGB(244, 246, 248);
    border = RGB(220, 225, 231);
  }
  if (hovered && primary_button && !disabled) {
    auto shadow_brush = CreateSolidBrush(RGB(222, 226, 232));
    auto prior_shadow_brush = SelectObject(item.hDC, shadow_brush);
    auto prior_shadow_pen = SelectObject(item.hDC, GetStockObject(NULL_PEN));
    auto shadow = item.rcItem;
    OffsetRect(&shadow, 0, scaled(3));
    RoundRect(item.hDC, shadow.left, shadow.top, shadow.right, shadow.bottom,
              scaled(42), scaled(42));
    SelectObject(item.hDC, prior_shadow_pen);
    SelectObject(item.hDC, prior_shadow_brush);
    DeleteObject(shadow_brush);
  }
  auto brush = CreateSolidBrush(background);
  auto pen = CreatePen(PS_SOLID, scaled(1), border);
  auto old_brush = SelectObject(item.hDC, brush);
  auto old_pen = SelectObject(item.hDC, pen);
  RoundRect(item.hDC, item.rcItem.left, item.rcItem.top, item.rcItem.right,
            item.rcItem.bottom, scaled(42), scaled(42));
  SelectObject(item.hDC, body_font);
  SetBkMode(item.hDC, TRANSPARENT);
  SetTextColor(item.hDC, foreground);
  wchar_t text[128]{};
  GetWindowTextW(item.hwndItem, text, static_cast<int>(std::size(text)));
  auto text_rect = item.rcItem;
  DrawTextW(item.hDC, text, -1, &text_rect,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  SelectObject(item.hDC, old_brush);
  SelectObject(item.hDC, old_pen);
  DeleteObject(brush);
  DeleteObject(pen);
}

void draw_result_mark(DRAWITEMSTRUCT const &item) {
  FillRect(item.hDC, &item.rcItem, white_brush);
  auto failed = current == page::failure;
  auto canceled = current == page::result && last_result.summary.canceled;
  auto warning =
      current == page::result && last_result.summary.files_failed +
                                         last_result.summary.skipped +
                                         last_result.summary.warnings >
                                     0;
  auto background = failed     ? RGB(253, 245, 247)
                    : canceled ? RGB(244, 246, 248)
                    : warning  ? RGB(254, 247, 230)
                               : RGB(231, 240, 235);
  auto foreground = failed     ? RGB(159, 18, 57)
                    : canceled ? RGB(71, 85, 105)
                    : warning  ? RGB(120, 53, 15)
                               : RGB(31, 93, 58);
  auto height = item.rcItem.bottom - item.rcItem.top;
  auto width = item.rcItem.right - item.rcItem.left;
  auto diameter = height < width ? height : width;
  auto left = (item.rcItem.right - diameter) / 2;
  RECT circle{left, item.rcItem.top, left + diameter, item.rcItem.bottom};
  auto brush = CreateSolidBrush(background);
  auto prior_brush = SelectObject(item.hDC, brush);
  auto prior_pen = SelectObject(item.hDC, GetStockObject(NULL_PEN));
  Ellipse(item.hDC, circle.left, circle.top, circle.right, circle.bottom);
  SelectObject(item.hDC, icon_font);
  SetBkMode(item.hDC, TRANSPARENT);
  SetTextColor(item.hDC, foreground);
  wchar_t text[8]{};
  GetWindowTextW(item.hwndItem, text, static_cast<int>(std::size(text)));
  DrawTextW(item.hDC, text, -1, &circle,
            DT_CENTER | DT_VCENTER | DT_SINGLELINE);
  SelectObject(item.hDC, prior_brush);
  SelectObject(item.hDC, prior_pen);
  DeleteObject(brush);
}

std::wstring bytes(std::int64_t count) {
  wchar_t const *units[] = {L"B", L"KB", L"MB", L"GB", L"TB"};
  double n = static_cast<double>(std::max<std::int64_t>(0, count));
  size_t u{};
  while (n >= 1024 && u + 1 < std::size(units)) {
    n /= 1024;
    ++u;
  }
  std::wostringstream o;
  o << std::setprecision(3) << n << L' ' << units[u];
  return o.str();
}
std::wstring class_text(wchar_t const *name,
                        gami::storage::location_classification const &value) {
  return std::wstring(name) + L": " + gami::storage::kind_name(value.kind) +
         L"\r\n" + value.display_path + L"\r\nReason: " + value.reason;
}
void save(wchar_t const *key, std::wstring const &value) {
  ApplicationData::Current().LocalSettings().Values().Insert(key,
                                                             box_value(value));
}
std::wstring load(wchar_t const *key) {
  auto v = ApplicationData::Current().LocalSettings().Values();
  return v.HasKey(key)
             ? std::wstring(unbox_value_or<hstring>(v.Lookup(key), L""))
             : L"";
}
void save_flag(wchar_t const *key, bool value) {
  ApplicationData::Current().LocalSettings().Values().Insert(key,
                                                             box_value(value));
}
bool load_flag(wchar_t const *key) {
  auto v = ApplicationData::Current().LocalSettings().Values();
  return v.HasKey(key) && unbox_value_or<bool>(v.Lookup(key), false);
}
StorageFolder restore(std::wstring const &token) {
  if (token.empty())
    throw hresult_error(E_FAIL, L"No saved folder selection is available");
  return StorageApplicationPermissions::FutureAccessList()
      .GetFolderAsync(token)
      .get();
}
bool valid_name(std::wstring value) {
  if (value.size() < 5 || value.size() > 200 ||
      value.find_first_of(L"\\/:*?\"<>|\r\n") != std::wstring::npos)
    return false;
  std::transform(value.end() - 4, value.end(), value.end() - 4, towlower);
  return value.ends_with(L".csv");
}

std::wstring explain(std::wstring raw) {
  auto lower = raw;
  std::transform(lower.begin(), lower.end(), lower.begin(), towlower);
  if (lower.find(L"access is denied") != std::wstring::npos)
    return L"Windows denied access. Reconnect the share or cloud account, "
           L"confirm your permission, and select it again.\r\n\r\nTechnical "
           L"detail: " +
           raw;
  if (lower.find(L"reparse point") != std::wstring::npos ||
      lower.find(L"provider alias") != std::wstring::npos)
    return L"The collection contains a link or alias that could escape the "
           L"selected folder. Remove it or choose another "
           L"folder.\r\n\r\nTechnical detail: " +
           raw;
  if (lower.find(L"inside the selected source") != std::wstring::npos)
    return L"Choose a result location outside the collection. No output was "
           L"created.\r\n\r\nTechnical detail: " +
           raw;
  if (lower.find(L"network") != std::wstring::npos ||
      lower.find(L"provider") != std::wstring::npos ||
      lower.find(L"pipe closed") != std::wstring::npos)
    return L"The storage provider became unavailable. Reconnect it and use "
           L"Continue to resume saved progress.\r\n\r\nTechnical detail: " +
           raw;
  return L"The run could not continue. Your collection was not modified. Check "
         L"both selected locations and try again.\r\n\r\nTechnical detail: " +
         raw;
}

void render();
void fail(std::wstring text) {
  last_error = std::move(text);
  current = page::failure;
  render();
}
void pick(bool source) {
  std::thread([source] {
    init_apartment(apartment_type::multi_threaded);
    std::wstring stage = L"open the folder picker";
    try {
      FolderPicker picker;
      picker.FileTypeFilter().Append(L"*");
      check_hresult(picker.as<IInitializeWithWindow>()->Initialize(window));
      auto folder = picker.PickSingleFolderAsync().get();
      if (!folder)
        return;
      auto token = std::wstring(source ? source_access : destination_access);
      stage = L"persist the selected folder grant";
      try {
        StorageApplicationPermissions::FutureAccessList().AddOrReplace(token,
                                                                       folder);
      } catch (hresult_error const &e) {
        throw hresult_error(
            e.code(), hstring(L"cannot persist the selected folder grant: " +
                              std::wstring(e.message())));
      }
      gami::storage::location_classification cls;
      stage = L"classify the selected folder";
      try {
        cls = gami::storage::classify_storage_folder(folder);
      } catch (hresult_error const &e) {
        throw hresult_error(
            e.code(), hstring(L"cannot classify the selected folder: " +
                              std::wstring(e.message())));
      }
      auto result = std::make_unique<selection_result>();
      result->source = source;
      result->token = std::move(token);
      result->path = folder.Path();
      result->folder = folder;
      result->classification = std::move(cls);
      PostMessageW(window, msg_selection, 0,
                   reinterpret_cast<LPARAM>(result.release()));
    } catch (hresult_error const &e) {
      auto detail = L"Could not " + stage + L": " + std::wstring(e.message());
      PostMessageW(window, msg_complete, 0,
                   reinterpret_cast<LPARAM>(
                       new std::wstring(explain(detail))));
    }
  }).detach();
}

bool approve() {
  if (!gami::storage::requires_explicit_consent(source_class,
                                                destination_class))
    return true;
  auto text =
      class_text(L"Source", source_class) + L"\r\n\r\n" +
      class_text(L"Result", destination_class) +
      L"\r\n\r\nBrowsing and classification metadata may already have "
      L"contacted a provider. If you continue, source bytes may be fetched or "
      L"read over a network, and the CSV, checkpoint, or error report may be "
      L"written or synced remotely.\r\n\r\nContinue?";
  return MessageBoxW(window, text.c_str(), L"Network or cloud storage approval",
                     MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) == IDYES;
}

void start_run(bool resume) {
  if (running.exchange(true))
    return;
  auto return_page = current;
  cancel_requested = false;
  close_after_cancel = false;
  started = std::chrono::steady_clock::now();
  current = page::progress;
  render();
  UpdateWindow(window);
  std::wstring stage = L"restore access to the selected source folder";
  try {
    StorageFolder source{nullptr}, destination{nullptr};
    if (selected_source) {
      source = selected_source;
    } else {
      try {
        source = restore(source_token);
      } catch (hresult_error const &e) {
        throw hresult_error(
            e.code(), hstring(L"cannot restore access to the selected source "
                              L"folder: " + std::wstring(e.message())));
      }
    }
    if (selected_destination) {
      destination = selected_destination;
    } else {
      stage = L"restore access to the selected result folder";
      try {
        destination = restore(destination_token);
      } catch (hresult_error const &e) {
        throw hresult_error(
            e.code(), hstring(L"cannot restore access to the selected result "
                              L"folder: " + std::wstring(e.message())));
      }
    }
    stage = L"read the selected source folder identity";
    source_path = source.Path();
    stage = L"read the selected result folder identity";
    destination_path = destination.Path();
    stage = L"classify the selected source folder";
    source_class = gami::storage::classify_storage_folder(source);
    stage = L"classify the selected result folder";
    destination_class = gami::storage::classify_storage_folder(destination);
    if (!approve()) {
      running = false;
      current = return_page;
      render();
      return;
    }
    auto authorization =
        gami::storage::authorize_storage(source_class, destination_class, true);
    resume_pending = true;
    save_flag(resume_key, true);
    std::thread([source, destination, authorization, resume] {
      init_apartment(apartment_type::multi_threaded);
      auto done = std::make_unique<completion>();
      try {
        wchar_t image[32768]{};
        GetModuleFileNameW(nullptr, image,
                           static_cast<DWORD>(std::size(image)));
        std::wstring worker(image);
        worker.replace(worker.find_last_of(L"\\/") + 1, std::wstring::npos,
                       L"GamiHashContainedWorker.exe");
        done->worker = gami::storage::run_storage_worker(
            worker, source, destination, authorization, output_name, resume,
            &cancel_requested, [](auto const &p) {
              PostMessageW(window, msg_progress, 0,
                           reinterpret_cast<LPARAM>(
                               new gami::storage::storage_progress(p)));
            });
        done->ok = done->worker.exit_code == 0;
        if (!done->ok)
          done->error = L"The contained hashing worker stopped unexpectedly.";
      } catch (hresult_error const &e) {
        done->error = explain(e.message().c_str());
      } catch (std::exception const &e) {
        done->error = explain(gami::storage::wide(e.what()));
      }
      PostMessageW(window, msg_complete, 1,
                   reinterpret_cast<LPARAM>(done.release()));
    }).detach();
  } catch (hresult_error const &e) {
    running = false;
    fail(explain(L"Could not " + stage + L": " + std::wstring(e.message())));
  } catch (std::exception const &e) {
    running = false;
    fail(explain(gami::storage::wide(e.what())));
  }
}

void welcome() {
  auto title_y = resume_pending ? 214 : 274;
  auto copy_y = resume_pending ? 258 : 323;
  label(L"Create a checksum list of your collection.", title_y, 42,
        title_font);
  label(L"The program reads every file in a folder you choose and writes one "
        L"CSV file with a SHA-256 checksum per file, for handover to Authentic "
        L"Memory. Your files are only read. Nothing is changed, moved or "
        L"deleted.\r\n\r\nYou can stop at any time and continue later.",
        copy_y, resume_pending ? 108 : 112);
  if (resume_pending && !source_token.empty() && !destination_token.empty()) {
    eyebrow(L"INTERRUPTED RUN", 392);
    label(L"Saved progress is ready to continue", 418, 24, small_font);
    control(L"STATIC", source_path, SS_LEFT, 222, 445, 360, 22, 0, mono_font);
    button(L"Continue", secondary, 635, 398, 120);
    button(L"Choose folder", primary, 626, 490, 150, true);
  } else {
    button(L"Choose folder", primary, 626, 454, 150, true);
  }
}
void source_page() {
  eyebrow(L"STEP 1 OF 3", 251);
  label(L"Folder selected", 282, 42, title_font);
  label(L"All files in this folder and its subfolders will be recorded. Links "
        L"and special files are skipped and noted in the report.",
        329, 54);
  eyebrow(L"FOLDER", 405, 18);
  control(L"STATIC", source_path, SS_LEFT, 222, 431, 536, 22, 0, mono_font);
  button(L"Back", secondary, 442, 490, 120);
  button(L"Choose where to save", primary, 572, 490, 184, true);
}
void destination_page() {
  eyebrow(L"STEP 2 OF 3", 251);
  label(L"Choose the result file", 282, 42, title_font);
  label(L"Choose a destination folder outside the collection, then name the CSV.",
        329, 32);
  eyebrow(L"FILE NAME", 382, 18);
  auto edit = control(L"EDIT", output_name,
                      WS_TABSTOP | WS_BORDER | ES_AUTOHSCROLL, 204, 407, 572,
                      36, output_edit, mono_font);
  SendMessageW(edit, EM_SETLIMITTEXT, 200, 0);
  if (!destination_path.empty()) {
    eyebrow(L"DESTINATION", 454, 18);
    control(L"STATIC", destination_path, SS_LEFT, 204, 478, 572, 22, 0,
            mono_font);
  }
  button(L"Back", secondary, 442, 505, 120);
  button(L"Choose destination", primary, 572, 505, 184, true);
}
void review_page() {
  eyebrow(L"STEP 3 OF 3", 214);
  label(L"Ready to start", 245, 42, title_font);
  label(L"Depending on the amount of data this can take several hours. You can "
        L"keep using the computer, and you can stop and continue later at any time.",
        291, 54);
  eyebrow(L"FOLDER", 371, 18);
  control(L"STATIC", source_path, SS_LEFT, 220, 397, 540, 22, 0, mono_font);
  eyebrow(L"RESULT FILE", 443, 18);
  control(L"STATIC", destination_path + L"\\" + output_name, SS_LEFT, 220,
          469, 540, 22, 0, mono_font);
  button(L"Change", secondary, 524, 530, 120);
  button(resume_pending ? L"Continue" : L"Start", primary, 654, 530, 120,
         true);
}
void progress_page() {
  eyebrow(L"HASHING", 193);
  control(L"STATIC", L"Preparing", SS_LEFT, 204, 223, 572, 42,
          progress_title, title_font);
  label(L"Preparing and validating access...", 268, 28);
  control(PROGRESS_CLASSW, L"", PBS_SMOOTH, 204, 314, 572, 8, progress_bar);
  control(L"STATIC", L"FILES\r\n0 of 0", SS_LEFT, 220, 354, 150, 52,
          files_metric, small_font);
  control(L"STATIC", L"DATA READ\r\n0 B of 0 B", SS_LEFT, 411, 354, 160, 52,
          bytes_metric, small_font);
  control(L"STATIC", L"ELAPSED\r\n0 sec", SS_LEFT, 611, 354, 150, 52,
          elapsed_metric, small_font);
  control(L"STATIC", L"RESULT FILE", SS_LEFT, 220, 458, 520, 18, eyebrow_text,
          small_font);
  control(L"STATIC", destination_path + L"\\" + output_name, SS_LEFT, 220,
          484, 536, 22, 0, mono_font);
  button(L"Cancel", secondary, 656, 546, 120, true);
}
void result_page() {
  auto const &s = last_result.summary;
  if (s.canceled) {
    centered_label(L"||", 259, 54, icon_font, result_icon);
    centered_label(L"Stopped. Nothing is lost.", 337, 44, title_font);
    centered_label(L"Your progress is saved. Continue now, or close the program "
                   L"and continue another day: the next start will offer to pick "
                   L"up where you stopped.",
                   382, 72);
    button(L"Close", secondary, 498, 476, 120);
    button(L"Continue now", primary, 628, 476, 148, true);
    return;
  }
  auto issues = s.files_failed + s.skipped + s.warnings;
  centered_label(issues ? L"!" : L"\x2713", 216, 54, icon_font, result_icon);
  centered_label(issues ? L"Done, with items to review" : L"Done", 288, 42,
                 title_font);
  centered_label(std::to_wstring(s.files_hashed + s.files_resumed) +
                     L" files (" + bytes(s.bytes_total) + L") were recorded.",
                 330, 30);
  eyebrow(L"RESULT FILE", 390, 18);
  control(L"STATIC", destination_path + L"\\" + output_name, SS_LEFT, 220,
          416, 536, 22, 0, mono_font);
  centered_label(L"Please send the result file to tech@authenticmemory.org.",
                 470, 30);
  button(L"Close", secondary, 514, 518, 120);
  button(L"Open folder", primary, 644, 518, 132, true);
}
void failure_page() {
  centered_label(L"!", 230, 54, icon_font, result_icon);
  centered_label(L"The run could not continue", 304, 42, title_font);
  label(last_error, 355, 112);
  button(L"Back to start", primary, 626, 510, 150, true);
  if (!source_token.empty() && !destination_token.empty())
    button(L"Try Continue", secondary, 466, 510, 150);
}

void render() {
  clear();
  switch (current) {
  case page::welcome:
    welcome();
    break;
  case page::source:
    source_page();
    break;
  case page::destination:
    destination_page();
    break;
  case page::review:
    review_page();
    break;
  case page::progress:
    progress_page();
    break;
  case page::result:
    result_page();
    break;
  case page::failure:
    failure_page();
    break;
  }
  control(L"BUTTON", L"", WS_TABSTOP | BS_OWNERDRAW, 867, 10, 31, 31,
          caption_minimize);
  control(L"BUTTON", L"", WS_TABSTOP | BS_OWNERDRAW, 902, 10, 31, 31,
          caption_maximize);
  control(L"BUTTON", L"", WS_TABSTOP | BS_OWNERDRAW, 937, 10, 31, 31,
          caption_close);
  InvalidateRect(window, nullptr, TRUE);
}

void update_progress(gami::storage::storage_progress const &p) {
  last_progress = p;
  has_progress = true;
  if (current != page::progress)
    return;
  auto ratio = p.bytes_total   ? 1000.0 * p.bytes_done / p.bytes_total
               : p.files_total ? 1000.0 * p.files_done / p.files_total
                               : 0;
  SendDlgItemMessageW(window, progress_bar, PBM_SETRANGE32, 0, 1000);
  SendDlgItemMessageW(window, progress_bar, PBM_SETBARCOLOR, 0,
                      RGB(45, 106, 79));
  SendDlgItemMessageW(window, progress_bar, PBM_SETBKCOLOR, 0,
                      RGB(236, 239, 243));
  SendDlgItemMessageW(window, progress_bar, PBM_SETPOS,
                      static_cast<int>(std::clamp(ratio, 0.0, 1000.0)), 0);
  auto percent = std::clamp(ratio / 10.0, 0.0, 100.0);
  std::wostringstream heading;
  if (cancel_requested)
    heading << L"Stopping...";
  else if (p.phase == 0)
    heading << L"Counting files";
  else
    heading << std::fixed << std::setprecision(1) << percent << L"%";
  SetDlgItemTextW(window, progress_title, heading.str().c_str());
  auto elapsed = std::chrono::duration_cast<std::chrono::seconds>(
                     std::chrono::steady_clock::now() - started)
                     .count();
  auto files = L"FILES\r\n" + std::to_wstring(p.files_done) + L" of " +
               std::to_wstring(p.files_total);
  auto data = L"DATA READ\r\n" + bytes(p.bytes_done) + L" of " +
              bytes(p.bytes_total);
  auto time = L"ELAPSED\r\n" + std::to_wstring(elapsed) + L" sec";
  SetDlgItemTextW(window, files_metric, files.c_str());
  SetDlgItemTextW(window, bytes_metric, data.c_str());
  SetDlgItemTextW(window, elapsed_metric, time.c_str());
}

void open_folder() {
  try {
    Windows::System::Launcher::LaunchFolderAsync(restore(destination_token))
        .get();
  } catch (...) {
    MessageBoxW(window,
                L"Windows could not open the result folder. Open the displayed "
                L"path manually.",
                L"Could not open folder", MB_OK | MB_ICONWARNING);
  }
}

LRESULT CALLBACK procedure(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
  if (message == WM_PAINT) {
    paint_chrome(hwnd);
    return 0;
  }
  if (message == WM_DRAWITEM) {
    auto item = reinterpret_cast<DRAWITEMSTRUCT *>(lp);
    if (item && item->CtlType == ODT_BUTTON) {
      draw_button(*item);
      return TRUE;
    }
    if (item && item->CtlType == ODT_STATIC && item->CtlID == result_icon) {
      draw_result_mark(*item);
      return TRUE;
    }
  }
  if (message == WM_CTLCOLORSTATIC) {
    auto dc = reinterpret_cast<HDC>(wp);
    SetBkMode(dc, TRANSPARENT);
    auto id = GetDlgCtrlID(reinterpret_cast<HWND>(lp));
    SetTextColor(dc, id == result_icon
                         ? (current == page::failure ? RGB(159, 18, 57)
                                                     : RGB(31, 93, 58))
                     : id == eyebrow_text ? RGB(31, 93, 58)
                     : id == muted_text   ? RGB(71, 85, 105)
                                          : RGB(21, 32, 53));
    return reinterpret_cast<LRESULT>(GetStockObject(HOLLOW_BRUSH));
  }
  if (message == WM_CTLCOLOREDIT) {
    auto dc = reinterpret_cast<HDC>(wp);
    SetBkColor(dc, RGB(255, 255, 255));
    SetTextColor(dc, RGB(21, 32, 53));
    return reinterpret_cast<LRESULT>(white_brush);
  }
  if (message == WM_CREATE) {
    window = hwnd;
    return 0;
  }
  if (message == WM_ENTERSIZEMOVE) {
    interactive_resize = true;
    return 0;
  }
  if (message == WM_EXITSIZEMOVE) {
    interactive_resize = false;
    if (body_font) {
      render();
      if (current == page::progress && has_progress)
        update_progress(last_progress);
    }
    return 0;
  }
  if (message == WM_SIZE && wp != SIZE_MINIMIZED && body_font &&
      !interactive_resize) {
    render();
    if (current == page::progress && has_progress)
      update_progress(last_progress);
    return 0;
  }
  if (message == msg_render) {
    render();
    return 0;
  }
  if (message == msg_initialize) {
    try {
      init_apartment(apartment_type::multi_threaded);
      source_token = load(source_key);
      destination_token = load(destination_key);
      resume_pending = load_flag(resume_key);
      auto saved = load(output_key);
      if (valid_name(saved))
        output_name = saved;
    } catch (...) {
      source_token.clear();
      destination_token.clear();
      resume_pending = false;
    }
    render();
    return 0;
  }
  if (message == msg_selection) {
    std::unique_ptr<selection_result> result(
        reinterpret_cast<selection_result *>(lp));
    resume_pending = false;
    save_flag(resume_key, false);
    if (result->source) {
      source_token = std::move(result->token);
      source_path = std::move(result->path);
      source_class = std::move(result->classification);
      selected_source = result->folder;
      save(source_key, source_token);
      current = page::source;
    } else {
      destination_token = std::move(result->token);
      destination_path = std::move(result->path);
      destination_class = std::move(result->classification);
      selected_destination = result->folder;
      save(destination_key, destination_token);
      current = page::review;
    }
    render();
    return 0;
  }
  if (message == msg_progress) {
    std::unique_ptr<gami::storage::storage_progress> p(
        reinterpret_cast<gami::storage::storage_progress *>(lp));
    update_progress(*p);
    return 0;
  }
  if (message == msg_complete) {
    if (!wp) {
      std::unique_ptr<std::wstring> e(reinterpret_cast<std::wstring *>(lp));
      fail(*e);
      return 0;
    }
    std::unique_ptr<completion> d(reinterpret_cast<completion *>(lp));
    running = false;
    if (!d->ok)
      fail(d->error);
    else {
      last_result = std::move(d->worker);
      resume_pending = last_result.summary.canceled;
      save_flag(resume_key, resume_pending);
      current = page::result;
      render();
    }
    if (close_after_cancel)
      DestroyWindow(hwnd);
    return 0;
  }
  if (message == WM_COMMAND) {
    auto id = LOWORD(wp);
    if (id == caption_minimize) {
      ShowWindow(hwnd, SW_MINIMIZE);
      return 0;
    }
    if (id == caption_maximize) {
      ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
      return 0;
    }
    if (id == caption_close) {
      SendMessageW(hwnd, WM_CLOSE, 0, 0);
      return 0;
    }
    if (current == page::welcome) {
      if (id == primary)
        pick(true);
      else if (id == secondary)
        start_run(true);
    } else if (current == page::source) {
      if (id == primary) {
        current = page::destination;
        render();
      }
      else if (id == secondary) {
        current = page::welcome;
        render();
      }
    } else if (current == page::destination) {
      if (id == primary) {
        wchar_t name[256]{};
        GetWindowTextW(GetDlgItem(hwnd, output_edit), name, 256);
        output_name = name;
        if (!valid_name(output_name))
          MessageBoxW(hwnd,
                      L"Enter a simple CSV name, for example gami-hash.csv.",
                      L"Invalid file name", MB_OK | MB_ICONWARNING);
        else {
          save(output_key, output_name);
          pick(false);
        }
      } else if (id == secondary) {
        current = page::source;
        render();
      }
    } else if (current == page::review) {
      if (id == primary)
        start_run(false);
      else if (id == secondary) {
        current = page::destination;
        render();
      }
    } else if (current == page::progress && id == secondary) {
      cancel_requested = true;
      EnableWindow(GetDlgItem(hwnd, secondary), FALSE);
    } else if (current == page::result) {
      if (last_result.summary.canceled) {
        if (id == primary)
          start_run(true);
        else if (id == secondary) {
          current = page::welcome;
          render();
        }
      } else {
        if (id == primary)
          open_folder();
        else if (id == secondary) {
          current = page::welcome;
          render();
        }
      }
    } else if (current == page::failure) {
      if (id == primary) {
        current = page::welcome;
        render();
      } else if (id == secondary)
        start_run(true);
    }
    return 0;
  }
  if (message == WM_DPICHANGED) {
    auto r = reinterpret_cast<RECT *>(lp);
    SetWindowPos(hwnd, nullptr, r->left, r->top, r->right - r->left,
                 r->bottom - r->top, SWP_NOZORDER | SWP_NOACTIVATE);
    create_fonts(HIWORD(wp));
    render();
    return 0;
  }
  if (message == WM_NCCALCSIZE && wp)
    return 0;
  // The frame is fully client drawn. Letting DefWindowProc repaint the
  // inactive nonclient area adds a gray resize border after an app switch.
  if (message == WM_NCACTIVATE)
    return TRUE;
  if (message == WM_NCHITTEST) {
    POINT point{GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
    ScreenToClient(hwnd, &point);
    RECT client{};
    GetClientRect(hwnd, &client);
    auto edge = scaled(7);
    bool left = point.x < edge, right = point.x >= client.right - edge;
    bool top = point.y < edge, bottom = point.y >= client.bottom - edge;
    if (top && left) return HTTOPLEFT;
    if (top && right) return HTTOPRIGHT;
    if (bottom && left) return HTBOTTOMLEFT;
    if (bottom && right) return HTBOTTOMRIGHT;
    if (left) return HTLEFT;
    if (right) return HTRIGHT;
    if (top) return HTTOP;
    if (bottom) return HTBOTTOM;
    if (point.y < scaled(52) && point.x < client.right - scaled(130))
      return HTCAPTION;
    return HTCLIENT;
  }
  if (message == WM_GETMINMAXINFO) {
    auto info = reinterpret_cast<MINMAXINFO *>(lp);
    auto dpi = GetDpiForWindow(hwnd);
    info->ptMinTrackSize = {MulDiv(720, static_cast<int>(dpi), 96),
                            MulDiv(480, static_cast<int>(dpi), 96)};
    return 0;
  }
  if (message == WM_CLOSE && running) {
    if (MessageBoxW(
            hwnd, L"Stop the run? Progress already written will be kept.",
            L"GAMI Hash", MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2) != IDYES)
      return 0;
    cancel_requested = true;
    close_after_cancel = true;
    return 0;
  }
  if (message == WM_DESTROY) {
    PostQuitMessage(0);
    return 0;
  }
  return DefWindowProcW(hwnd, message, wp, lp);
}
} // namespace

void configure_preview() {
  auto command = std::wstring(GetCommandLineW());
  auto marker = command.find(L"--preview=");
  if (marker == std::wstring::npos)
    return;
  preview_mode = true;
  auto mode = command.substr(marker + 10);
  if (auto space = mode.find(L' '); space != std::wstring::npos)
    mode.resize(space);
  source_path = L"C:\\Users\\STUDENT\\Downloads\\files";
  destination_path = L"C:\\Users\\STUDENT\\Desktop";
  output_name = L"checksums_files_2026-10-17.csv";
  source_token = L"preview-source";
  destination_token = L"preview-destination";
  started = std::chrono::steady_clock::now() - std::chrono::seconds(5);
  if (mode == L"source") current = page::source;
  else if (mode == L"destination") current = page::destination;
  else if (mode == L"review") current = page::review;
  else if (mode == L"progress") current = page::progress;
  else if (mode == L"canceled") {
    current = page::result;
    last_result.summary.canceled = true;
  } else if (mode == L"resume") {
    current = page::review;
    resume_pending = true;
  } else if (mode == L"resume-welcome") {
    current = page::welcome;
    resume_pending = true;
  } else if (mode == L"result") {
    current = page::result;
    last_result.summary.files_hashed = 4;
    last_result.summary.bytes_total = 70349;
  } else if (mode == L"failure") {
    current = page::failure;
    last_error = L"Windows denied access. Reconnect the folder and try again.";
  }
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show) {
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  INITCOMMONCONTROLSEX common{sizeof(common),
                              ICC_PROGRESS_CLASS | ICC_STANDARD_CLASSES};
  InitCommonControlsEx(&common);
  white_brush = CreateSolidBrush(RGB(255, 255, 255));
  load_private_fonts();
  configure_preview();
  if (!preview_mode && !has_package_identity()) {
    MessageBoxW(nullptr,
                L"This executable must be installed from the GAMI Hash MSIX "
                L"package. Do not run GamiHash.exe from the stage folder.",
                L"Install GAMI Hash", MB_OK | MB_ICONINFORMATION);
    unload_private_fonts();
    DeleteObject(white_brush);
    return 2;
  }
  WNDCLASSW wc{};
  wc.lpfnWndProc = procedure;
  wc.hInstance = instance;
  wc.lpszClassName = L"GamiNativeWizard";
  wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  wc.hbrBackground = white_brush;
  brand_icon = static_cast<HICON>(LoadImageW(
      instance, MAKEINTRESOURCEW(1), IMAGE_ICON, 64, 64, LR_DEFAULTCOLOR));
  wc.hIcon = brand_icon ? brand_icon : LoadIconW(nullptr, IDI_APPLICATION);
  RegisterClassW(&wc);
  auto dpi = GetDpiForSystem();
  constexpr DWORD window_style =
      WS_POPUP | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU;
  RECT bounds{0, 0, MulDiv(980, static_cast<int>(dpi), 96),
              MulDiv(716, static_cast<int>(dpi), 96)};
  window = CreateWindowW(wc.lpszClassName, L"GAMI Hash", window_style,
                         CW_USEDEFAULT, CW_USEDEFAULT,
                         bounds.right - bounds.left, bounds.bottom - bounds.top,
                         nullptr, nullptr, instance, nullptr);
  if (!window)
    return static_cast<int>(GetLastError());
  auto corner_preference = DWMWCP_ROUND;
  DwmSetWindowAttribute(window, DWMWA_WINDOW_CORNER_PREFERENCE,
                        &corner_preference, sizeof(corner_preference));
  constexpr COLORREF no_border = 0xFFFFFFFE;
  DwmSetWindowAttribute(window, DWMWA_BORDER_COLOR, &no_border,
                        sizeof(no_border));
  dpi = GetDpiForWindow(window);
  RECT actual_bounds{0, 0, MulDiv(980, static_cast<int>(dpi), 96),
                     MulDiv(716, static_cast<int>(dpi), 96)};
  SetWindowPos(window, nullptr, 0, 0, actual_bounds.right - actual_bounds.left,
               actual_bounds.bottom - actual_bounds.top,
               SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
  create_fonts(dpi);
  render();
  if (preview_mode && current == page::progress)
    update_progress({1, 262, 562, 1395864371, 10522669875});
  ShowWindow(window, show == SW_HIDE ? SW_SHOWNORMAL : show);
  SetWindowPos(window, nullptr, 0, 0, actual_bounds.right - actual_bounds.left,
               actual_bounds.bottom - actual_bounds.top,
               SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE);
  UpdateWindow(window);
  if (!preview_mode)
    PostMessageW(window, msg_initialize, 0, 0);
  MSG message{};
  while (GetMessageW(&message, nullptr, 0, 0) > 0) {
    if (!IsDialogMessageW(window, &message)) {
      TranslateMessage(&message);
      DispatchMessageW(&message);
    }
  }
  DeleteObject(title_font);
  DeleteObject(body_font);
  DeleteObject(small_font);
  DeleteObject(icon_font);
  DeleteObject(mono_font);
  DeleteObject(brand_font);
  DeleteObject(brand_tool_font);
  if (brand_icon)
    DestroyIcon(brand_icon);
  unload_private_fonts();
  DeleteObject(white_brush);
  return static_cast<int>(message.wParam);
}
