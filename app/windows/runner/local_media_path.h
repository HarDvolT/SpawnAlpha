#ifndef RUNNER_LOCAL_MEDIA_PATH_H_
#define RUNNER_LOCAL_MEDIA_PATH_H_
#include <windows.h>
#include <filesystem>
#include <stdexcept>

// No URL, network share, alternate stream or link may escape local-only media.
// Errors deliberately omit the private path.
inline void CheckLocalMediaPath(const std::wstring& value, bool output = false) {
  const std::filesystem::path path(value);
  const auto drive = path.root_name().wstring();
  if (!path.is_absolute() || drive.size() != 2 || drive[1] != L':' ||
      value.find(L':', 2) != std::wstring::npos || value.size() > 32760 ||
      value.find(L'\0') != std::wstring::npos) {
    throw std::runtime_error("A local file is required");
  }
  const auto kind = GetDriveTypeW(path.root_path().c_str());
  if (kind != DRIVE_FIXED && kind != DRIVE_REMOVABLE) {
    throw std::runtime_error("A local file is required");
  }
  const auto attrs = GetFileAttributesW(path.c_str());
  if (output ? attrs != INVALID_FILE_ATTRIBUTES :
      attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_DIRECTORY)) {
    throw std::runtime_error("The local file is unavailable");
  }
  for (auto current = output ? path.parent_path() : path; !current.empty();) {
    const auto attributes = GetFileAttributesW(current.c_str());
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & FILE_ATTRIBUTE_REPARSE_POINT)) {
      throw std::runtime_error("A local file is required");
    }
    const auto parent = current.parent_path();
    if (parent == current) break;
    current = parent;
  }
}
#endif
