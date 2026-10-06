#pragma once
#include <atomic>
#include <cstdint>
#include <string>
#include <vector>

// UTF-8 tokenizer pieces may end inside an Arabic character. Concatenate their
// bytes before decoding text. Nothing here is suitable for diagnostic logging.
struct SpeechPiece {
  std::string bytes;
  int64_t start_us = 0, end_us = 0;
  float probability = 0;
};
struct LocalTranscript {
  int64_t duration_us = 0;
  std::vector<SpeechPiece> pieces;
};
std::vector<float> DecodeLocalSpeechAudio(const std::wstring& media,
    std::atomic<bool>& cancel);

// Explicit prototype core, not yet exposed in the shipping app. Reads local
// media through Windows' decoder only; no network/devices/temporary audio file.
// Cancellation releases the reader/model. The current bounded check accepts
// at most 15 minutes; production work must stream overlapping speech windows.
LocalTranscript TranscribeLocal(const std::wstring& model,
    const std::wstring& media, const std::string& language,
    const std::string& vocabulary, std::atomic<bool>& cancel);
