#include "speech_jobs.h"
#include "local_transcription.h"
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <mfapi.h>
#include <winrt/base.h>
#include <mutex>
#include <thread>
#include <stdexcept>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
using List = flutter::EncodableList;
const Value* Field(const Map& map, const char* key) {
  const auto found = map.find(Value(key)); return found == map.end() ? nullptr : &found->second;
}
std::string Text(const Map& map, const char* key) {
  const auto* value = Field(map, key);
  if (!value || !std::holds_alternative<std::string>(*value)) throw std::runtime_error("Invalid speech request");
  return std::get<std::string>(*value);
}
int64_t Integer(const Map& map, const char* key) {
  const auto* value = Field(map, key);
  if (value && std::holds_alternative<int64_t>(*value)) return std::get<int64_t>(*value);
  if (value && std::holds_alternative<int32_t>(*value)) return std::get<int32_t>(*value);
  throw std::runtime_error("Invalid speech request");
}
std::wstring Wide(const std::string& text) {
  if (text.empty() || text.size() > 32768) throw std::runtime_error("Invalid local file");
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), nullptr, 0);
  if (size <= 0) throw std::runtime_error("Invalid local file");
  std::wstring result(size, L'\0');
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(), static_cast<int>(text.size()), result.data(), size)) throw std::runtime_error("Invalid local file");
  return result;
}
Value Wire(const std::vector<LocalSpeechWindow>& windows) {
  List output;
  for (const auto& window : windows) {
    List pieces;
    for (const auto& piece : window.transcript.pieces) {
      pieces.emplace_back(Map{
        {Value("bytes"), Value(std::vector<uint8_t>(piece.bytes.begin(), piece.bytes.end()))},
        {Value("startUs"), Value(piece.start_us)}, {Value("endUs"), Value(piece.end_us)},
        {Value("probability"), Value(static_cast<double>(piece.probability))}});
    }
    output.emplace_back(Map{{Value("offsetUs"), Value(window.offset_us)},
      {Value("keepStartUs"), Value(window.keep_start_us)}, {Value("keepEndUs"), Value(window.keep_end_us)},
      {Value("durationUs"), Value(window.transcript.duration_us)}, {Value("pieces"), Value(pieces)}});
  }
  return Value(output);
}
}

struct SpeechJobs::Impl {
  explicit Impl(flutter::BinaryMessenger* messenger)
      : channel(messenger, "spawnalpha/speech", &flutter::StandardMethodCodec::GetInstance()) {
    channel.SetMethodCallHandler([this](const auto& call, auto reply) {
      try {
        if (call.method_name() == "supported") { reply->Success(Value(true)); return; }
        if (!call.arguments() || !std::holds_alternative<Map>(*call.arguments())) throw std::runtime_error("Invalid speech request");
        const auto& args = std::get<Map>(*call.arguments());
        if (call.method_name() == "start" || call.method_name() == "verify") {
          { std::lock_guard<std::mutex> guard(mutex); if (state == "working") { reply->Error("busy", "Speech processing is busy"); return; } }
          if (worker.joinable()) worker.join();
          const auto model = Wide(Text(args, "model"));
          const bool verify = call.method_name() == "verify";
          const auto media = verify ? std::wstring() : Wide(Text(args, "media"));
          const auto language = verify ? std::string() : Text(args, "language");
          const auto vocabulary = verify ? std::string() : Text(args, "vocabulary");
          const auto duration = verify ? 0 : Integer(args, "durationUs");
          cancel = false;
          { std::lock_guard<std::mutex> guard(mutex); ++session; state = "working"; progress = 0; verified = false; output = Value(); }
          worker = std::thread([this, model, media, language, vocabulary, duration, verify] {
            const auto com = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
            bool mf = false;
            try {
              winrt::check_hresult(com); winrt::check_hresult(MFStartup(MF_VERSION)); mf = true;
              bool valid = false; Value value;
              if (verify) valid = VerifyLocalSpeechModel(model, cancel);
              else value = Wire(TranscribeLocalWindows(model, media, language, vocabulary, duration, cancel,
                [this](double amount) { std::lock_guard<std::mutex> guard(mutex); progress = amount; }));
              std::lock_guard<std::mutex> guard(mutex);
              if (cancel) state = "cancelled";
              else { state = "ready"; output = std::move(value); verified = valid; progress = 1; }
            } catch (...) {
              std::lock_guard<std::mutex> guard(mutex); state = cancel ? "cancelled" : "failed";
            }
            if (mf) MFShutdown();
            if (SUCCEEDED(com)) CoUninitialize();
          });
          reply->Success(Value(session)); return;
        }
        const auto id = Integer(args, "sessionId");
        std::lock_guard<std::mutex> guard(mutex);
        if (id != session) { reply->Error("session", "Speech job unavailable"); return; }
        if (call.method_name() == "cancel") { cancel = true; reply->Success(); return; }
        if (call.method_name() == "status") {
          reply->Success(Value(Map{{Value("state"), Value(state)}, {Value("progress"), Value(progress)},
            {Value("verified"), Value(verified)}, {Value("windows"), output}})); return;
        }
        reply->NotImplemented();
      } catch (...) { reply->Error("invalid", "Speech processing unavailable"); }
    });
  }
  ~Impl() {
    channel.SetMethodCallHandler(nullptr); cancel = true;
    if (worker.joinable()) worker.join();
  }
  flutter::MethodChannel<Value> channel;
  std::mutex mutex;
  std::thread worker;
  std::atomic<bool> cancel{false};
  int64_t session = 0;
  std::string state = "idle";
  double progress = 0;
  bool verified = false;
  Value output;
};
SpeechJobs::SpeechJobs(flutter::BinaryMessenger* messenger) : impl_(std::make_unique<Impl>(messenger)) {}
SpeechJobs::~SpeechJobs() = default;
