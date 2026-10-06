#ifndef RUNNER_AUDIO_JOIN_FADE_H_
#define RUNNER_AUDIO_JOIN_FADE_H_
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <stdexcept>
#include <vector>

// Half of a de-click envelope on either side of an internal discontinuity.
// No overlap, extra samples, gain above one or changes to the cut clock.
inline void ApplyAudioJoinFade(std::vector<int16_t>& pcm, uint32_t channels,
    int64_t position, int64_t range_start, int64_t range_end,
    int64_t half_fade_samples, bool fade_in, bool fade_out) {
  if (channels < 1 || channels > 2 || pcm.size() % channels != 0 ||
      pcm.size() > 48000 * channels || half_fade_samples < 0 || half_fade_samples > 2400 ||
      range_start < 0 || range_end <= range_start || position < range_start ||
      static_cast<int64_t>(pcm.size() / channels) > range_end - position)
    throw std::runtime_error("Invalid sound join");
  const auto fade = std::min(half_fade_samples, (range_end - range_start) / 2);
  if (fade == 0 || (!fade_in && !fade_out)) return;
  const auto ramp = [fade](int64_t distance) {
    if (distance >= fade) return 1.0;
    if (fade == 1) return 0.0;
    return std::sin(static_cast<double>(distance) / (fade - 1) * 1.5707963267948966);
  };
  for (size_t frame = 0; frame < pcm.size() / channels; ++frame) {
    const auto sample = position + static_cast<int64_t>(frame);
    const double gain = std::min(fade_in ? ramp(sample - range_start) : 1.0,
      fade_out ? ramp(range_end - sample - 1) : 1.0);
    if (gain >= 1) continue;
    for (uint32_t channel = 0; channel < channels; ++channel) {
      const auto index = frame * channels + channel;
      pcm[index] = static_cast<int16_t>(std::lround(pcm[index] * gain));
    }
  }
}
#endif
