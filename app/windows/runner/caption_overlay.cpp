#include "caption_overlay.h"
#include "local_media_path.h"
#include <d2d1_1.h>
#include <dwrite_3.h>
#include <winrt/base.h>
#include <filesystem>
#include <cwctype>
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
bool WhiteSpace(wchar_t c) {
  return iswspace(c) != 0 || c == 0x85 || c == 0xa0 || c == 0x1680 ||
    (c >= 0x2000 && c <= 0x200a) || c == 0x2028 || c == 0x2029 || c == 0x202f || c == 0x205f || c == 0x3000;
}
D2D1_COLOR_F Color(uint32_t argb) {
  return {((argb >> 16) & 255) / 255.0f, ((argb >> 8) & 255) / 255.0f,
    (argb & 255) / 255.0f, (argb >> 24) / 255.0f};
}
double Residual(double time, double mass, double stiffness, double damping) {
  const auto a = damping / (2 * mass), b = std::sqrt(stiffness / mass - a * a);
  return std::exp(-a * time) * (std::cos(b * time) + a / b * std::sin(b * time));
}
double Pop(double time, const CaptionLayout& style) {
  const auto a = style.pop_damping / (2 * style.pop_mass), b = std::sqrt(style.pop_stiffness / style.pop_mass - a * a);
  const auto peak_time = std::atan(b / a) / b, peak = std::exp(-a * peak_time) * std::sin(b * peak_time);
  const auto impulse = std::exp(-a * time) * std::sin(b * time) / peak;
  return std::clamp(1 - (1 - style.pop_start) * Residual(time, style.pop_mass, style.pop_stiffness, style.pop_damping) +
    style.pop_amplitude * impulse, style.pop_start, style.pop_max);
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
    Require(!style.karaoke || (Fraction(style.underline_size, 1, 8) && Fraction(style.underline_gap, 0, 12)));
    int64_t previous = 0; size_t total = 0;
    for (const auto& word : words) {
      total += word.text.size();
      Require(word.start_us >= previous && word.end_us > word.start_us && word.end_us <= duration_us &&
        !word.text.empty() && word.text.size() <= 4096 && total <= 4 * 1024 * 1024 &&
        std::none_of(word.text.begin(), word.text.end(), [](wchar_t letter) { return letter <= 0x1f || letter == 0x7f; }));
      previous = word.end_us;
      Require(word.words.size() <= (style.punch ? 3 : 7) &&
        (!(style.karaoke || style.cue || style.punch) || !word.words.empty()) &&
        (!style.punch || word.words.size() == 1 || std::none_of(word.words.begin(), word.words.end(), [](const auto& w) { return w.stress; })));
      UINT offset = 0; int64_t word_end = word.start_us;
      for (const auto& timed : word.words) {
        const auto end = static_cast<size_t>(timed.offset) + timed.length;
        Require(timed.offset == offset && timed.length > 0 && end <= word.text.size() &&
          timed.start_us >= word_end && timed.end_us > timed.start_us && timed.end_us <= word.end_us);
        Require(std::none_of(word.text.begin() + timed.offset, word.text.begin() + end,
          [](wchar_t c) { return WhiteSpace(c); }));
        Require(!(word.text[timed.offset] >= 0xdc00 && word.text[timed.offset] <= 0xdfff) &&
          !(word.text[end - 1] >= 0xd800 && word.text[end - 1] <= 0xdbff));
        Require(end == word.text.size() || word.text[end] == L' ');
        offset = static_cast<UINT>(end + 1); word_end = timed.end_us;
      }
      Require(word.words.empty() || (offset == word.text.size() + 1 &&
        word.words.front().start_us == word.start_us && word.words.back().end_us == word.end_us));
    }
    captions = words; options = style;
    frame_height = static_cast<float>(height);
    Require(!(style.cue && style.punch) && !(style.cue && style.karaoke) && !(style.punch && style.karaoke));
    advanced = style.cue || style.punch || (style.karaoke && std::any_of(words.begin(), words.end(), [](const auto& phrase) {
      return std::any_of(phrase.words.begin(), phrase.words.end(), [](const auto& word) { return word.stress || word.energy || word.pace != 0; });
    }));
    if (advanced) {
      Require(Fraction(style.rise, 0, 40) && Fraction(style.pop_start, .2, 1) && Fraction(style.pop_max, 1, 1.5) &&
        Fraction(style.pop_amplitude, 0, .4) && Fraction(style.punch_start, .2, 1) &&
        Fraction(style.stress_width, 100, 150) && Fraction(style.punch_width, 100, 150) &&
        Fraction(style.slower_width, 100, 150) && Fraction(style.faster_width, 50, 100));
      for (const auto spring : {std::vector<double>{style.smooth_mass, style.smooth_stiffness, style.smooth_damping},
          std::vector<double>{style.pop_mass, style.pop_stiffness, style.pop_damping}}) {
        Require(Fraction(spring[0], .1, 10) && Fraction(spring[1], 1, 1000) && Fraction(spring[2], 1, 200) &&
          spring[2] * spring[2] < 4 * spring[0] * spring[1]);
      }
    }
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
    if (style.karaoke) {
      check_hresult(context->CreateSolidColorBrush(Color(style.waiting_color), waiting.put()));
      check_hresult(context->CreateSolidColorBrush(Color(style.underline_color), underline.put()));
    }
    if (advanced) {
      check_hresult(context->CreateSolidColorBrush(Color(style.stress_color), stress.put()));
      check_hresult(context->CreateSolidColorBrush(Color(style.energy_color), energy.put()));
      check_hresult(context->CreateSolidColorBrush(D2D1::ColorF(D2D1::ColorF::Black, 0), transparent.put()));
    }
  }
  com_ptr<IDXGIDevice> device_as_dxgi(ID3D11Device* device) {
    com_ptr<ID3D11Device> owned; owned.copy_from(device); return owned.as<IDXGIDevice>();
  }
  void Layout(size_t wanted) {
    if (layout && current == wanted) return;
    current = wanted; layout = nullptr; boxes.clear();
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
      const auto envelope = advanced && options.motion ? static_cast<float>(options.pop_max) : 1;
      const auto layout_width = max_width / envelope;
      check_hresult(factory->CreateTextLayout(text.c_str(), static_cast<UINT32>(text.size()), format.get(), layout_width,
        bottom_edge - safe_top - padding * 2, attempt.put()));
      if (advanced) {
        const auto varied = attempt.as<IDWriteTextLayout4>();
        for (const auto& word : captions[wanted].words) {
          const auto weight = word.stress ? 800u : options.weight;
          const auto width = word.stress ? (options.punch ? options.punch_width : options.stress_width) :
            word.pace < 0 ? options.slower_width : word.pace > 0 ? options.faster_width : 100;
          const DWRITE_FONT_AXIS_VALUE axes[] = {{DWRITE_FONT_AXIS_TAG_WEIGHT, static_cast<float>(weight)},
            {DWRITE_FONT_AXIS_TAG_WIDTH, static_cast<float>(width)}};
          check_hresult(varied->SetFontAxisValues(axes, 2, {word.offset, word.length}));
          check_hresult(attempt->SetFontWeight(static_cast<DWRITE_FONT_WEIGHT>(weight), {word.offset, word.length}));
          // Reem Kufi has no width axis: use proportional static type for pace,
          // and the already-decorated Arabic text for stress. All fit first.
          if (options.rtl && !word.stress && word.pace != 0)
            check_hresult(attempt->SetFontSize(font * static_cast<float>(width / 100), {word.offset, word.length}));
        }
        // Reserve the pop's horizontal room in the spaces before fitting.
        // Touch only spaces, so Arabic joining and whole-word shaping survive.
        if (options.motion && !options.punch) {
          std::vector<float> reserves;
          for (const auto& word : captions[wanted].words) {
            float reserve = 0;
            if (word.stress) {
              UINT count = 0;
              const auto measured = attempt->HitTestTextRange(word.offset, word.length, 0, 0, nullptr, 0, &count);
              Require(SUCCEEDED(measured) || measured == E_NOT_SUFFICIENT_BUFFER);
              Require(count > 0 && count <= text.size());
              std::vector<DWRITE_HIT_TEST_METRICS> measured_boxes(count);
              check_hresult(attempt->HitTestTextRange(word.offset, word.length, 0, 0, measured_boxes.data(), count, &count));
              for (const auto& box : measured_boxes) reserve += box.width * static_cast<float>((options.pop_max - 1) / 2);
            }
            reserves.push_back(reserve);
          }
          for (size_t i = 0; i + 1 < reserves.size(); ++i) {
            const auto& word = captions[wanted].words[i];
            check_hresult(varied->SetCharacterSpacing(reserves[i] + reserves[i + 1], 0, 0, {word.offset + word.length, 1}));
          }
        }
      }
      DWRITE_TEXT_METRICS metrics{}; check_hresult(attempt->GetMetrics(&metrics));
      if (metrics.lineCount <= 2 && metrics.height <= bottom_edge - safe_top - padding * 2 &&
          metrics.widthIncludingTrailingWhitespace <= layout_width + .1f) {
        // Glyph descenders/diacritics can extend beyond line metrics, especially
        // Arabic. Measure ink against the actual line box before placing it.
        check_hresult(attempt->SetMaxHeight(metrics.height));
        DWRITE_OVERHANG_METRICS overhang{}; check_hresult(attempt->GetOverhangMetrics(&overhang));
        if (std::max(0.0f, overhang.left) > padding || std::max(0.0f, overhang.right) > padding) continue;
        const auto top = std::max(0.0f, overhang.top);
        const auto extra = options.karaoke ? static_cast<float>(options.underline_size + options.underline_gap) * scale : 0;
        const auto room = (envelope - 1) * (metrics.height + top + std::max(0.0f, overhang.bottom));
        const auto rise = advanced && options.cue && options.motion ? static_cast<float>(options.rise) * scale : 0;
        const auto footprint = metrics.height + top + std::max(0.0f, overhang.bottom) + static_cast<float>(options.shadow_offset) * scale + extra + room + rise;
        if (footprint > bottom_edge - safe_top - padding * 2) continue;
        layout = attempt; text_height = footprint; text_top = top + room / 2;
        text_width = metrics.widthIncludingTrailingWhitespace * envelope;
        layout_inset = (max_width - layout_width) / 2;
        if (options.karaoke || advanced) {
          for (const auto& word : captions[wanted].words) {
            UINT count = 0;
            const auto measured = layout->HitTestTextRange(word.offset, word.length, 0, 0, nullptr, 0, &count);
            Require(SUCCEEDED(measured) || measured == E_NOT_SUFFICIENT_BUFFER);
            Require(count > 0 && count <= text.size());
            std::vector<DWRITE_HIT_TEST_METRICS> hit_boxes(count);
            check_hresult(layout->HitTestTextRange(word.offset, word.length, 0, 0, hit_boxes.data(), count, &count));
            hit_boxes.resize(count);
            std::sort(hit_boxes.begin(), hit_boxes.end(), [](const auto& a, const auto& b) { return a.textPosition < b.textPosition; });
            boxes.push_back(std::move(hit_boxes));
          }
        }
        return;
      }
    }
    throw std::runtime_error("Caption needs wording review");
  }
  void MotionWords(D2D1_POINT_2F origin, int64_t output_us) {
    const auto& phrase = captions[index];
    for (size_t i = 0; i < phrase.words.size(); ++i) {
      const auto& word = phrase.words[i];
      const bool begun = output_us >= word.start_us;
      if (!begun && !options.karaoke && !options.punch) continue;
      auto* color = !begun && options.karaoke ? waiting.get() : word.stress ? stress.get() : word.energy ? energy.get() : ink.get();
      float factor = 1, rise = 0;
      const auto since = static_cast<double>(output_us - word.start_us) / 1000000;
      if (options.motion) {
        if (options.punch) {
          const auto chunk_time = static_cast<double>(output_us - phrase.start_us) / 1000000;
          factor = static_cast<float>(std::clamp(1 - (1 - options.punch_start) *
            Residual(chunk_time, options.pop_mass, options.pop_stiffness, options.pop_damping), options.punch_start, options.pop_max));
        }
        if (begun && word.stress) factor = static_cast<float>(Pop(since, options));
        if (begun && options.cue) rise = static_cast<float>(options.rise * std::clamp(
          Residual(since, options.smooth_mass, options.smooth_stiffness, options.smooth_damping), 0.0, 1.0)) * scale;
      }
      float x = 0, y = 0, total = 0;
      for (const auto& box : boxes[i]) { x += (box.left + box.width / 2) * box.width; y += (box.top + box.height / 2) * box.width; total += box.width; }
      Require(total > 0);
      const auto center = options.punch ? D2D1::Point2F((left + right_edge) / 2, origin.y + text_height / 2) : D2D1::Point2F(origin.x + x / total, origin.y + y / total);
      context->SetTransform(D2D1::Matrix3x2F::Scale(factor, factor, center) * D2D1::Matrix3x2F::Translation(0, rise));
      check_hresult(layout->SetDrawingEffect(transparent.get(), {0, static_cast<UINT>(phrase.text.size())}));
      check_hresult(layout->SetDrawingEffect(shadow.get(), {word.offset, word.length}));
      context->DrawTextLayout(D2D1::Point2F(origin.x, origin.y + static_cast<float>(options.shadow_offset) * scale), layout.get(), transparent.get());
      check_hresult(layout->SetDrawingEffect(color, {word.offset, word.length}));
      context->DrawTextLayout(origin, layout.get(), transparent.get());
    }
    context->SetTransform(D2D1::Matrix3x2F::Identity());
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
    const auto top = options.punch ? std::clamp(frame_height / 2 - text_height / 2 - padding, safe_top,
      bottom_edge - text_height - padding * 2) : bottom_edge - text_height - padding * 2;
    const auto radius = static_cast<float>(options.radius) * scale;
    context->BeginDraw();
    const auto center = (left + right_edge) / 2;
    context->FillRoundedRectangle(D2D1::RoundedRect(D2D1::RectF(center - text_width / 2 - padding, top,
      center + text_width / 2 + padding, top + text_height + padding * 2), radius, radius), plate.get());
    const auto origin = D2D1::Point2F(left + padding + layout_inset, top + padding + text_top);
    // Drawing effects override the default brush. Clear them for the common
    // shadow before applying word colors; shaping and geometry stay fixed.
    const auto& phrase = captions[index];
    if (advanced) {
      MotionWords(origin, output_us);
    } else {
    if (options.karaoke) check_hresult(layout->SetDrawingEffect(nullptr, {0, static_cast<UINT>(phrase.text.size())}));
    context->DrawTextLayout(D2D1::Point2F(origin.x, origin.y + static_cast<float>(options.shadow_offset) * scale), layout.get(), shadow.get());
    if (options.karaoke) {
      check_hresult(layout->SetDrawingEffect(waiting.get(), {0, static_cast<UINT>(phrase.text.size())}));
      for (const auto& word : phrase.words) if (word.start_us <= output_us)
        check_hresult(layout->SetDrawingEffect(ink.get(), {word.offset, word.length}));
    }
    context->DrawTextLayout(origin, layout.get(), ink.get());
    }
    if (options.karaoke) {
      for (size_t i = 0; i < phrase.words.size(); ++i) {
        const auto& word = phrase.words[i];
        if (output_us < word.start_us || output_us >= word.end_us) continue;
        const auto progress = options.motion ? static_cast<double>(output_us - word.start_us) / (word.end_us - word.start_us) : 1;
        float width = 0;
        for (const auto& box : boxes[i]) width += box.width;
        auto remaining = width * static_cast<float>(progress);
        for (const auto& box : boxes[i]) {
          const auto amount = std::min(remaining, box.width); remaining -= amount;
          if (amount <= 0) break;
          const auto x = origin.x + box.left + ((box.bidiLevel & 1) ? box.width - amount : 0);
          const auto y = origin.y + box.top + box.height + static_cast<float>(options.underline_gap) * scale;
          context->FillRectangle(D2D1::RectF(x, y, x + amount, y + static_cast<float>(options.underline_size) * scale), underline.get());
        }
      }
    }
    const auto drawn = context->EndDraw(); context->SetTarget(nullptr); check_hresult(drawn);
  }
  com_ptr<IDWriteFactory5> factory;
  com_ptr<IDWriteFontCollection1> collection;
  com_ptr<IDWriteFontFallback> fallback;
  com_ptr<IDWriteTextLayout> layout;
  com_ptr<ID2D1DeviceContext> context;
  com_ptr<ID2D1Bitmap1> target;
  com_ptr<ID3D11Texture2D> target_frame;
  com_ptr<ID2D1SolidColorBrush> ink, plate, shadow, waiting, underline, stress, energy, transparent;
  std::vector<std::vector<DWRITE_HIT_TEST_METRICS>> boxes;
  std::vector<RenderCaption> captions;
  CaptionLayout options;
  size_t index = 0, current = SIZE_MAX;
  bool advanced = false;
  float frame_height = 0, layout_inset = 0;
  float scale = 0, left = 0, right_edge = 0, safe_top = 0, bottom_edge = 0, padding = 0, max_width = 0, text_height = 0, text_width = 0, text_top = 0;
};
CaptionOverlay::CaptionOverlay() : impl_(std::make_unique<Impl>()) {}
CaptionOverlay::~CaptionOverlay() = default;
void CaptionOverlay::Open(ID3D11Device* device, UINT width, UINT height, int64_t duration_us,
    const std::vector<RenderCaption>& words, const CaptionLayout& style) { impl_->Open(device, width, height, duration_us, words, style); }
void CaptionOverlay::Draw(ID3D11Texture2D* frame, int64_t output_us) { impl_->Draw(frame, output_us); }
