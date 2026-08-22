#pragma once

#include <cstdint>
#include <string>

#include <fd_tcode/motion_core.hpp>

namespace fd_tcode
{
    struct TelemetrySnapshot
    {
        uint64_t sequence{};
        uint64_t monotonic_us{};
        std::string scene;
        std::string montage;
        std::string section;
        std::string profile_id;
        MotionOutput motion;
    };

    auto serialize_udp_v1(const TelemetrySnapshot& snapshot) -> std::string;

    // Owns only a loopback UDP socket. It is called from the game thread at a
    // capped cadence; it does not spawn a worker and never touches Unreal data.
    class UdpTelemetryPublisher
    {
      public:
        UdpTelemetryPublisher() = default;
        ~UdpTelemetryPublisher();
        UdpTelemetryPublisher(const UdpTelemetryPublisher&) = delete;
        auto operator=(const UdpTelemetryPublisher&) -> UdpTelemetryPublisher& = delete;

        auto open(uint16_t port = 17891) -> bool;
        auto send(const TelemetrySnapshot& snapshot) -> bool;
        auto close() -> void;

      private:
        uintptr_t m_socket{};
        uint16_t m_port{17891};
        bool m_winsock_started{};
    };
}
