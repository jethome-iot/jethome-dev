// See CMakeLists.txt in this directory: compiled and run by the Dockerfile's
// verification layer, then deleted. Each test asserts something a `--version`
// print cannot reach.
#include <cstring>

#include <MQTTAsync.h>
#include <gmock/gmock.h>
#include <gtest/gtest.h>

namespace {

class Clock {
public:
  virtual ~Clock() = default;
  virtual int now() const = 0;
};

class MockClock : public Clock {
public:
  MOCK_METHOD(int, now, (), (const, override));
};

// GMock is a separate library from GTest and a separate apt package; linking one
// says nothing about the other, and a project consuming this image needs both.
TEST(HostImageSmoke, GMockLinksAndMatches) {
  MockClock clock;
  EXPECT_CALL(clock, now()).WillOnce(::testing::Return(42));
  EXPECT_THAT(clock.now(), ::testing::Eq(42));
}

// Calls into libpaho-mqtt3a and checks what answered. A library that installed
// as a stub, or a second copy arriving from somewhere else, links just as well
// as the pinned one - the version it reports is what tells them apart, and it is
// compared against the commit this image was built from rather than merely
// printed.
TEST(HostImageSmoke, PahoLinksAndReportsThePinnedVersion) {
  MQTTAsync_nameValue* info = MQTTAsync_getVersionInfo();
  ASSERT_NE(info, nullptr);

  const char* version = nullptr;
  for (MQTTAsync_nameValue* entry = info; entry->name != nullptr; ++entry) {
    if (std::strcmp(entry->name, "Version") == 0) {
      version = entry->value;
      break;
    }
  }

  ASSERT_NE(version, nullptr) << "paho reported no Version entry";
  EXPECT_STREQ(version, PAHO_EXPECTED_VERSION);
}

}  // namespace
