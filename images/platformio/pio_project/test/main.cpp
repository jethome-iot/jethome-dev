// Minimal stub file for PlatformIO package downloading
// This file is only used during Docker build to trigger package downloads


#ifdef ESP_PLATFORM
#ifdef ARDUINO
void setup() {}
void loop() {}
#else
// ESP-IDF or native platform main
extern "C" void app_main() {}
#endif
#else
int main() { return 0; }
#endif