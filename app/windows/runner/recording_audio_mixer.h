#ifndef RUNNER_RECORDING_AUDIO_MIXER_H_
#define RUNNER_RECORDING_AUDIO_MIXER_H_
#include <algorithm>
#include <cstdint>
#include <vector>

// Worker-only stereo PCM16 mixer. Each input has already been mapped through
// RecordingClock. A bounded two-second ring absorbs endpoint/encoder latency;
// output fills idle gaps with silence. Late/duplicate samples cannot mix twice.
// The microphone remains mono for metering/Voice; only its saved copy is stereo.
class RecordingAudioMixer {
 public:
  static constexpr std::int64_t kRate = 48000;
  static constexpr std::int64_t kCapacity = kRate * 2;
  RecordingAudioMixer() : sum_(static_cast<size_t>(kCapacity) * 2, 0) {}
  std::int64_t Position() const { return position_; }
  bool Add(bool microphone, std::int64_t first, const std::int16_t* pcm, size_t frames) {
    if (first < 0 || !pcm || frames > static_cast<size_t>(kCapacity) ||
        first > position_ + kCapacity - static_cast<std::int64_t>(frames)) return false;
    auto& previous = microphone ? microphone_end_ : system_end_;
    const auto end = first + static_cast<std::int64_t>(frames);
    const auto begin = std::max({first, previous, position_});
    const size_t channels = microphone ? 1 : 2;
    for (auto frame = begin; frame < end; ++frame) {
      const auto source = static_cast<size_t>(frame - first) * channels;
      const auto target = static_cast<size_t>(frame % kCapacity) * 2;
      sum_[target] += pcm[source];
      sum_[target + 1] += pcm[source + channels - 1];
    }
    previous = std::max(previous, end);
    return true;
  }
  bool Read(size_t frames, std::vector<std::int16_t>& pcm) {
    if (frames > static_cast<size_t>(kCapacity)) return false;
    pcm.resize(frames * 2);
    for (size_t frame = 0; frame < frames; ++frame) {
      const auto source = static_cast<size_t>((position_ + static_cast<std::int64_t>(frame)) % kCapacity) * 2;
      for (size_t channel = 0; channel < 2; ++channel) {
        // Saturating sum keeps either input at its chosen level and prevents
        // integer wrap if their peaks coincide. No gain on the live mic meter.
        pcm[frame * 2 + channel] = static_cast<std::int16_t>(
            std::clamp(sum_[source + channel], -32768, 32767));
        sum_[source + channel] = 0;
      }
    }
    position_ += static_cast<std::int64_t>(frames);
    return true;
  }
 private:
  std::int64_t position_ = 0, microphone_end_ = 0, system_end_ = 0;
  std::vector<std::int32_t> sum_;
};
#endif
