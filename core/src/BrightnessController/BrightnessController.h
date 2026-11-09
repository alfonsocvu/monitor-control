#include <ddcutil_c_api.h>
#include <ddcutil_status_codes.h>

#include <atomic>
#include <cstdint>
#include <iostream>
#include <string>
#include <vector>

class BrightnessController {
 private:
  // Handles are opened per transaction: an open one holds libddcutil's
  // per-display lock and starves the watch thread.
  struct Display {
    DDCA_Display_Ref ref;
    std::string name;
    int consecutive_failures;
    int64_t benched_at_millis;
  };

  std::vector<Display> displays;
  static std::atomic<bool> displays_stale;
  static std::atomic<int64_t> last_event_millis;
  // TODO Make them configurable
  const int BRIGHTNESS_STEP = 10;
  const uint8_t VCP_BRIGHTNESS = 0x10;
  // DDC shares the DP AUX channel; using it while the link retrains wedges the
  // monitor.
  const int64_t SETTLE_MILLIS = 5000;
  const int MAX_CONSECUTIVE_FAILURES = 2;
  // A monitor on another input keeps HPD asserted and never raises an event.
  const int64_t BENCH_RETRY_MILLIS = 30000;
  // After a wake, libddcutil may never report a monitor as reconnected.
  const int64_t RESCAN_RETRY_MILLIS = 30000;
  size_t most_displays_seen = 0;
  int64_t last_rescan_millis = 0;
  bool rescan_wanted = false;

  static int64_t nowMillis();
  static void onDisplayStatusEvent(DDCA_Display_Status_Event event);
  void startWatchingDisplays();
  bool loadDisplays();
  bool redetectDisplays();
  bool shouldRetryRescan();
  bool isUsable(const Display& display);
  void noteResult(Display& display, DDCA_Status rc);
  DDCA_Status readBrightness(const Display& display, int* value);
  DDCA_Status writeBrightness(const Display& display, int value);
  void adjustBrightness(int delta);

 public:
  ~BrightnessController();
  bool init();
  void onBrightnessUp(int presses);
  void onBrightnessDown(int presses);
};
