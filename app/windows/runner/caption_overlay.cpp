#include "caption_overlay.h"
#include "local_media_path.h"
#include <d2d1_1.h>
#include <dwrite_3.h>
#include <winrt/base.h>
#include <filesystem>
#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace {
using winrt::com_ptr;
using winrt::check_hresult;
void Require(bool value) { if (!value) throw std::runtime_error("Invalid caption layout"); }
bool Fraction(double value, double low, double high) {
  return std::isfinite(value) && value >= low && value <= high;
}
D2D1_COLOR_F Color(uint32_t argb) {
  return {((argb >> 16) & 255) / 255.0f, ((argb >> 8) & 255) / 255.0f,
    (argb & 255) / 255.0f, (argb >> 24) / 255.0f};
}
std::filesystem::path FontFolder() {
  wchar_t module[32768]{};
  const auto count = GetModuleFileNameW(nullptr, module, 32768);
  Require(count > 0 && count < 32768);
  return std::filesystem::path(module).parent_path() / L"data" / L"flutter_assets" / L"assets" / L"fonts";
}
}
struct CaptionOverlay::Impl {
  void Open(ID3D11Device* device, UINT width, UINT height, int64_t duration_us,
      const std::vector<RenderCaption>& words, const CaptionLayout& style) {
    if (words.empty()) return;
    Require(words.size() <= 100000 && width >= 2 && height >= 2 && width <= 4096 && height <= 4096);
    Require(Fraction(style.edge, .01, .2) && Fraction(style.bottom, .01, .4) &&
      Fraction(style.safe_top, .01, .4) && Fraction(style.safe_bottom, .01, .4) &&
      Fraction(style.safe_right, .01, .4) && Fraction(style.font_size, 20, 150) &&
      Fraction(style.line_height, style.font_size, 180) && Fraction(style.min_size, 16, style.font_size) &&
      Fraction(style.padding, 0, 40) && Fraction(style.radius, 0, 40) &&
      Fraction(style.shadow_offset, 0, 8) && style.weight >= 100 && style.weight <= 900);
    int64_t previous = 0; size_t total = 0;
    for (const auto& word : words) {
      total += word.text.size();
      Require(word.start_us >= previous && word.end_us > word.start_us && word.end_us <= duration_us &&
        !word.text.empty() && word.text.size() <= 4096 && total <= 4 * 1024 * 1024 &&
        std::none_of(word.text.begin(), word.text.end(), [](wchar_t letter) { return letter <= 0x1f || letter == 0x7f; }));
      previous = word.end_us;
    }
    captions = words; options = style;
    scale = static_cast<float>(std::min(width, height)) / 1080.0f;
    const bool vertical = height > width;
    const auto right = vertical ? style.safe_right : style.edge;
    const auto bottom = vertical ? style.safe_bottom : style.bottom;
    left = static_cast<float>(width * style.edge); right_edge = static_cast<float>(width * (1 - right));
    safe_top = static_cast<float>(height * style.safe_top); bottom_edge = static_cast<float>(height * (1 - bottom));
    padding = static_cast<float>(style.padding) * scale;
    max_width = right_edge - left - padding * 2;
    Require(max_width > 0 && bottom_edge > safe_top + padding * 2);
    check_hresult(DWriteCreateFactory(DWRITE_FACTORY_TYPE_ISOLATED, __uuidof(IDWriteFactory5), reinterpret_cast<IUnknown**>(factory.put())));
    com_ptr<IDWriteFontSetBuilder1> builder; check_hresult(factory->CreateFontSetBuilder(builder.put()));
    for (const auto* name : {L"Anybody-Variable.ttf", L"ReemKufi-Variable.ttf"}) {
      const auto path = (FontFolder() / name).wstring(); CheckLocalMediaPath(path);
      com_ptr<IDWriteFontFile> file; check_hresult(factory->CreateFontFileReference(path.c_str(), nullptr, file.put()));
      check_hresult(builder->AddFontFile(file.get()));
    }
    com_ptr<IDWriteFontSet> set; check_hresult(builder->CreateFontSet(set.put()));
    check_hresult(factory->CreateFontCollectionFromFontSet(set.get(), collection.put()));
    for (const auto* family : {L"Anybody", L"Reem Kufi"}) {
      UINT32 family_index = 0; BOOL exists = FALSE;
      check_hresult(collection->FindFamilyName(family, &family_index, &exists)); Require(exists != FALSE);
    }
    const wchar_t* families[] = {L"Reem Kufi", L"Anybody"};
    const DWRITE_UNICODE_RANGE all{0, 0x10ffff};
    com_ptr<IDWriteFontFallbackBuilder> fallback_builder;
    check_hresult(factory->CreateFontFallbackBuilder(fallback_builder.put()));
    check_hresult(fallback_builder->AddMapping(&all, 1, families, 2, collection.get(), nullptr, nullptr, 1));
    check_hresult(fallback_builder->CreateFontFallback(fallback.put()));
    com_ptr<ID2D1Factory1> d2d; check_hresult(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, d2d.put()));
    com_ptr<ID2D1Device> d2d_device;
    const auto dxgi = device_as_dxgi(device);
    check_hresult(d2d->CreateDevice(dxgi.get(), d2d_device.put()));
    check_hresult(d2d_device->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, context.put()));
    context->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
    check_hresult(context->CreateSolidColorBrush(Color(style.text_color), ink.put()));
    check_hresult(context->CreateSolidColorBrush(Color(style.plate_color), plate.put()));
    check_hresult(context->CreateSolidColorBrush(Color(style.plate_color), shadow.put()));
  }
  com_ptr<IDXGIDevice> device_as_dxgi(ID3D11Device* device) {
    com_ptr<ID3D11Device> owned; owned.copy_from(device); return owned.as<IDXGIDevice>();
  }
  void Layout(size_t wanted) {
    if (layout && current == wanted) return;
    current = wanted; layout = nullptr;
    float size = static_cast<float>(options.font_size) * scale;
    const auto minimum = static_cast<float>(options.min_size) * scale;
    // Try bounded sizes, checking the complete shaped text at each step. No
    // ellipsis, clipping, arbitrary dropped words or invented time boundaries.
    for (UINT step = 0; step <= 12; ++step) {
      const auto font = std::max(minimum, size - (size - minimum) * step / 12);
      com_ptr<IDWriteTextFormat> format;
      check_hresult(factory->CreateTextFormat(options.rtl ? L"Reem Kufi" : L"Anybody", collection.get(),
        static_cast<DWRITE_FONT_WEIGHT>(options.weight), DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL,
        font, options.rtl ? L"ar" : L"en", format.put()));
      check_hresult(format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER));
      check_hresult(format->SetReadingDirection(options.rtl ? DWRITE_READING_DIRECTION_RIGHT_TO_LEFT : DWRITE_READING_DIRECTION_LEFT_TO_RIGHT));
      check_hresult(format->SetWordWrapping(DWRITE_WORD_WRAPPING_WRAP));
      check_hresult(format.as<IDWriteTextFormat1>()->SetFontFallback(fallback.get()));
      const auto line = font * static_cast<float>(options.line_height / options.font_size);
      check_hresult(format->SetLineSpacing(DWRITE_LINE_SPACING_METHOD_UNIFORM, line, font));
      const auto& text = captions[wanted].text;
      com_ptr<IDWriteTextLayout> attempt;
      check_hresult(factory->CreateTextLayout(text.c_str(), static_cast<UINT32>(text.size()), format.get(), max_width,
        bottom_edge - safe_top - padding * 2, attempt.put()));
      DWRITE_TEXT_METRICS metrics{}; check_hresult(attempt->GetMetrics(&metrics));
      if (metrics.lineCount <= 2 && metrics.height <= bottom_edge - safe_top - padding * 2 &&
          metrics.widthIncludingTrailingWhitespace <= max_width + .1f) {
        // Glyph descenders/diacritics can extend beyond line metrics, especially
        // Arabic. Measure ink against the actual line box before placing it.
        check_hresult(attempt->SetMaxHeight(metrics.height));
        DWRITE_OVERHANG_METRICS overhang{}; check_hresult(attempt->GetOverhangMetrics(&overhang));
        if (std::max(0.0f, overhang.left) > padding || std::max(0.0f, overhang.right) > padding) continue;
        const auto top = std::max(0.0f, overhang.top);
        const auto footprint = metrics.height + top + std::max(0.0f, overhang.bottom) + static_cast<float>(options.shadow_offset) * scale;
        if (footprint > bottom_edge - safe_top - padding * 2) continue;
        layout = attempt; text_height = footprint; text_top = top;
        text_width = metrics.widthIncludingTrailingWhitespace; return;
      }
    }
    throw std::runtime_error("Caption needs wording review");
  }
  void Draw(ID3D11Texture2D* frame, int64_t output_us) {
    if (captions.empty()) return;
    while (index < captions.size() && captions[index].end_us <= output_us) ++index;
    if (index == captions.size() || captions[index].start_us > output_us) return;
    Layout(index);
    if (target_frame.get() != frame) {
      target = nullptr; target_frame.copy_from(frame);
      const auto surface = target_frame.as<IDXGISurface>();
      const auto properties = D2D1::BitmapProperties1(D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_IGNORE), 96, 96);
      check_hresult(context->CreateBitmapFromDxgiSurface(surface.get(), &properties, target.put()));
    }
    context->SetTarget(target.get());
    const auto top = bottom_edge - text_height - padding * 2;
    const auto radius = static_cast<float>(options.radius) * scale;
    context->BeginDraw();
    const auto center = (left + right_edge) / 2;
    context->FillRoundedRectangle(D2D1::RoundedRect(D2D1::RectF(center - text_width / 2 - padding, top,
      center + text_width / 2 + padding, bottom_edge), radius, radius), plate.get());
    const auto origin = D2D1::Point2F(left + padding, top + padding + text_top);
    context->DrawTextLayout(D2D1::Point2F(origin.x, origin.y + static_cast<float>(options.shadow_offset) * scale), layout.get(), shadow.get());
    context->DrawTextLayout(origin, layout.get(), ink.get());
    const auto drawn = context->EndDraw(); context->SetTarget(nullptr); check_hresult(drawn);
  }
  com_ptr<IDWriteFactory5> factory;
  com_ptr<IDWriteFontCollection1> collection;
  com_ptr<IDWriteFontFallback> fallback;
  com_ptr<IDWriteTextLayout> layout;
  com_ptr<ID2D1DeviceContext> context;
  com_ptr<ID2D1Bitmap1> target;
  com_ptr<ID3D11Texture2D> target_frame;
  com_ptr<ID2D1SolidColorBrush> ink, plate, shadow;
  std::vector<RenderCaption> captions;
  CaptionLayout options;
  size_t index = 0, current = SIZE_MAX;
  float scale = 0, left = 0, right_edge = 0, safe_top = 0, bottom_edge = 0, padding = 0, max_width = 0, text_height = 0, text_width = 0, text_top = 0;
};
CaptionOverlay::CaptionOverlay() : impl_(std::make_unique<Impl>()) {}
CaptionOverlay::~CaptionOverlay() = default;
void CaptionOverlay::Open(ID3D11Device* device, UINT width, UINT height, int64_t duration_us,
    const std::vector<RenderCaption>& words, const CaptionLayout& style) { impl_->Open(device, width, height, duration_us, words, style); }
void CaptionOverlay::Draw(ID3D11Texture2D* frame, int64_t output_us) { impl_->Draw(frame, output_us); }
