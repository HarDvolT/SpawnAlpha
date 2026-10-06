#include "recording_activity.h"
#include <sstream>

ActivityDetail SanitizeShortcut(UINT key, bool ctrl, bool alt, bool shift, bool win) {
  if (!ctrl || alt || win) return ActivityDetail::none;
  const std::string allowed = "ACSVXYZ";
  const auto index = allowed.find(static_cast<char>(key));
  if (key > 127 || index == std::string::npos) return ActivityDetail::none;
  return static_cast<ActivityDetail>(static_cast<int>(shift ? ActivityDetail::ctrlShiftA : ActivityDetail::ctrlA) + index);
}
std::string ActivityJson(const ActivityEvent& event, int64_t time_100ns) {
  static constexpr const char* kinds[] = {"cursor", "click", "key", "shortcut", "focus"};
  static constexpr const char* details[] = {"none", "arrow", "text", "hand", "other", "left", "right", "middle", "extra",
    "Ctrl+A", "Ctrl+C", "Ctrl+S", "Ctrl+V", "Ctrl+X", "Ctrl+Y", "Ctrl+Z",
    "Ctrl+Shift+A", "Ctrl+Shift+C", "Ctrl+Shift+S", "Ctrl+Shift+V", "Ctrl+Shift+X", "Ctrl+Shift+Y", "Ctrl+Shift+Z"};
  std::ostringstream json;
  json << "{\"type\":\"" << kinds[static_cast<int>(event.kind)] << "\",\"timeUs\":" << time_100ns / 10;
  json << ",\"width\":" << event.width << ",\"height\":" << event.height;
  if (event.kind == ActivityKind::cursor || event.kind == ActivityKind::click) {
    json << ",\"x\":" << event.x << ",\"y\":" << event.y << ",\"visible\":" << (event.visible ? "true" : "false");
  }
  if (event.kind == ActivityKind::focus) {
    json << ",\"x\":" << event.rect_x << ",\"y\":" << event.rect_y << ",\"rectWidth\":" << event.rect_width << ",\"rectHeight\":" << event.rect_height;
  }
  if (event.kind == ActivityKind::key) json << ",\"count\":1";
  else if (event.kind != ActivityKind::focus) json << ",\"detail\":\"" << details[static_cast<int>(event.detail)] << "\"";
  json << "}";
  return json.str();
}
ActivityWriter::~ActivityWriter() { if (file_ != INVALID_HANDLE_VALUE) CloseHandle(file_); }
HRESULT ActivityWriter::Start(const std::wstring& path) {
  if (file_ != INVALID_HANDLE_VALUE || path.empty()) return E_INVALIDARG;
  file_ = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file_ == INVALID_HANDLE_VALUE) return HRESULT_FROM_WIN32(GetLastError());
  return Line("{\"type\":\"header\",\"version\":1,\"coordinates\":\"sourcePixels\",\"keys\":\"timingOnly\"}");
}
HRESULT ActivityWriter::Line(const std::string& line) {
  const auto bytes = line + "\n";
  DWORD written = 0;
  if (!WriteFile(file_, bytes.data(), static_cast<DWORD>(bytes.size()), &written, nullptr)) return HRESULT_FROM_WIN32(GetLastError());
  return written == bytes.size() ? S_OK : E_FAIL;
}
HRESULT ActivityWriter::Write(const ActivityEvent& event, int64_t time_100ns) {
  const auto saved = Line(ActivityJson(event, time_100ns));
  if (SUCCEEDED(saved)) ++count_;
  return saved;
}
HRESULT ActivityWriter::Flush() {
  if (file_ == INVALID_HANDLE_VALUE) return S_OK;
  return FlushFileBuffers(file_) ? S_OK : HRESULT_FROM_WIN32(GetLastError());
}
HRESULT ActivityWriter::Finish(int64_t duration_100ns, bool complete) {
  if (file_ == INVALID_HANDLE_VALUE) return S_OK;
  const auto saved = Line("{\"type\":\"end\",\"timeUs\":" + std::to_string(duration_100ns / 10) +
      ",\"events\":" + std::to_string(count_) + ",\"complete\":" + (complete ? "true}" : "false}"));
  const auto flushed = Flush();
  CloseHandle(file_); file_ = INVALID_HANDLE_VALUE;
  return FAILED(saved) ? saved : flushed;
}
