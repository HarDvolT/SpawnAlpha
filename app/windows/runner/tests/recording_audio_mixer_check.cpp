#include "../recording_audio_mixer.h"
#include "../recording_clock.h"
#include <iostream>
#include <stdexcept>

void Require(bool value) { if (!value) throw std::runtime_error("mixer check"); }
int main() {
  try {
    RecordingAudioMixer mixer;
    const int16_t mic[]{1000, -1000, 32000, -32000};
    const int16_t system[]{200, 300, 400, 500, 2000, 3000, -2000, -3000};
    Require(mixer.Add(true, 2, mic, 4));
    Require(mixer.Add(false, 2, system, 4));
    Require(mixer.Add(true, 2, mic, 4));  // Duplicate cannot double voice.
    std::vector<int16_t> output;
    Require(mixer.Read(7, output));
    Require(output == std::vector<int16_t>({0, 0, 0, 0, 1200, 1300, -600, -500,
                                         32767, 32767, -32768, -32768, 0, 0}));
    Require(mixer.Add(true, 0, mic, 4));  // Already flushed packets stay late.
    Require(!mixer.Add(false, mixer.Position() + RecordingAudioMixer::kCapacity, system, 4));
    Require(mixer.Read(static_cast<size_t>(RecordingAudioMixer::kCapacity - 9), output));
    Require(std::all_of(output.begin(), output.end(), [](auto v) { return v == 0; }));
    Require(mixer.Add(false, mixer.Position() + 1, system, 4));
    Require(mixer.Read(6, output));  // Ring wrap clears old sums.
    Require(output == std::vector<int16_t>({0, 0, 200, 300, 400, 500, 2000, 3000, -2000, -3000, 0, 0}));

    RecordingClock clock(10000000);
    clock.Pause(true, 10000500); clock.Pause(false, 10001750);
    RecordingAudioMixer paused;
    const std::vector<int16_t> voices(12, 100);
    const std::vector<int16_t> stereo(24, 250);
    for (const auto& slice : clock.Audio(10000000, 12, 48000)) {
      const auto frame = (slice.time_100ns * 48000 + 5000000) / 10000000;
      Require(paused.Add(true, frame, voices.data() + slice.offset, slice.count));
      Require(paused.Add(false, frame, stereo.data() + slice.offset * 2, slice.count));
    }
    Require(paused.Read(10, output));
    // Six paused frames are removed identically; rounding leaves six active.
    Require(std::count(output.begin(), output.end(), 350) == 12);
    Require(paused.Read(10, output));
    Require(std::all_of(output.begin(), output.end(), [](auto v) { return v == 0; }));
    std::cout << "Audio mixer check passed: stereo, voice, silence, duplicates, clipping, ring bounds and shared pauses.\n";
    return 0;
  } catch (...) { std::cerr << "Audio mixer check failed.\n"; return 1; }
}
