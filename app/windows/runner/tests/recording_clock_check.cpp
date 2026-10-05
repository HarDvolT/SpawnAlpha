#include "../recording_clock.h"
#include <iostream>
#include <stdexcept>
void Require(bool good) { if (!good) throw std::runtime_error("clock check"); }
int main() {
  try {
    RecordingClock clock(100000000);
    Require(clock.Time(99000000) == 0 && clock.Time(110000000) == 10000000);
    const auto pre = clock.Audio(99900000, 960, 48000);
    Require(pre.size() == 1 && pre[0].offset == 480 && pre[0].count == 480 && pre[0].time_100ns == 0);
    clock.Pause(true, 110000000); clock.Pause(true, 120000000);
    Require(clock.Time(125000000) == 10000000);
    const auto entering = clock.Audio(109900000, 960, 48000);
    Require(entering.size() == 1 && entering[0].count == 480 && entering[0].time_100ns == 9900000);
    Require(clock.Audio(111000000, 960, 48000).empty());
    clock.Pause(false, 120000000); clock.Pause(false, 120500000);
    Require(clock.Time(125000000) == 15000000);
    const auto leaving = clock.Audio(119900000, 960, 48000);
    Require(leaving.size() == 1 && leaving[0].offset == 480 && leaving[0].count == 480 && leaving[0].time_100ns == 10000000);
    const auto crossing = clock.Audio(109000000, 57600, 48000);
    Require(crossing.size() == 2 && crossing[0].count == 4800 && crossing[1].count == 4800);
    Require(crossing[1].time_100ns == 10000000);
    clock.Pause(true, 130000000); clock.Pause(false, 140000000);
    Require(clock.Time(150000000) == 30000000);
    Require(clock.Audio(100000000, 0, 48000).empty());
    std::cout << "Recording clock check passed: pre-start trimming, pause boundaries, resume, repeated pause.\n";
    return 0;
  } catch (...) { std::cerr << "Recording clock check failed.\n"; return 1; }
}
