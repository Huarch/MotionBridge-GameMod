#include <fd_tcode/telemetry_v1.hpp>

#include <iomanip>
#include <sstream>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#endif

namespace fd_tcode
{
    namespace
    {
        auto escaped(const std::string& value) -> std::string
        {
            std::string out;
            out.reserve(value.size() + 8);
            for (const char c : value)
            {
                switch (c)
                {
                case '\\': out += "\\\\"; break;
                case '"': out += "\\\""; break;
                case '\n': out += "\\n"; break;
                case '\r': out += "\\r"; break;
                case '\t': out += "\\t"; break;
                default: out += c; break;
                }
            }
            return out;
        }

        auto quote(const std::string& value) -> std::string { return '"' + escaped(value) + '"'; }
        auto number(double value) -> std::string { std::ostringstream out; out << std::fixed << std::setprecision(6) << value; return out.str(); }
    }

    auto serialize_udp_v1(const TelemetrySnapshot& snapshot) -> std::string
    {
        const auto& axes = snapshot.motion.axes;
        const auto& raw = snapshot.motion.raw;
        std::ostringstream out;
        out << "{\"version\":1,\"sequence\":" << snapshot.sequence
            << ",\"monotonicUs\":" << snapshot.monotonic_us
            << ",\"scene\":" << quote(snapshot.scene)
            << ",\"montage\":" << quote(snapshot.montage)
            << ",\"section\":" << quote(snapshot.section)
            << ",\"state\":" << quote(to_string(snapshot.motion.state))
            << ",\"profileId\":" << quote(snapshot.profile_id)
            << ",\"binding\":{\"reference\":" << quote(snapshot.motion.reference_id)
            << ",\"target\":" << quote(snapshot.motion.target_id) << "}"
            << ",\"contact\":{\"valid\":" << (snapshot.motion.contact_valid ? "true" : "false")
            << ",\"distance\":" << number(raw.radial_distance)
            << ",\"radius\":" << number(snapshot.motion.contact_radius) << "}"
            << ",\"rawGeometry\":{\"referenceLength\":" << number(raw.reference_length)
            << ",\"axialDistance\":" << number(raw.axial_distance)
            << ",\"radialDistance\":" << number(raw.radial_distance)
            << ",\"twistDegrees\":" << number(raw.twist_degrees)
            << ",\"pitchDegrees\":" << number(raw.pitch_degrees)
            << ",\"rollDegrees\":" << number(raw.roll_degrees) << "}"
            << ",\"axes\":{\"L0\":" << number(axes.l0) << ",\"L1\":" << number(axes.l1)
            << ",\"L2\":" << number(axes.l2) << ",\"R0\":" << number(axes.r0)
            << ",\"R1\":" << number(axes.r1) << ",\"R2\":" << number(axes.r2) << "}"
            << ",\"reason\":" << quote(snapshot.motion.reason) << '}';
        return out.str();
    }

    UdpTelemetryPublisher::~UdpTelemetryPublisher() { close(); }

    auto UdpTelemetryPublisher::open(uint16_t port) -> bool
    {
#ifdef _WIN32
        if (m_socket != 0) return m_port == port;
        WSADATA data{};
        if (WSAStartup(MAKEWORD(2, 2), &data) != 0) return false;
        m_winsock_started = true;
        const SOCKET socket = ::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
        if (socket == INVALID_SOCKET) { close(); return false; }
        m_socket = static_cast<uintptr_t>(socket);
        m_port = port;
        return true;
#else
        return false;
#endif
    }

    auto UdpTelemetryPublisher::send(const TelemetrySnapshot& snapshot) -> bool
    {
#ifdef _WIN32
        if (!open()) return false;
        sockaddr_in destination{};
        destination.sin_family = AF_INET;
        destination.sin_port = htons(m_port);
        destination.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        const std::string payload = serialize_udp_v1(snapshot);
        return ::sendto(static_cast<SOCKET>(m_socket), payload.data(), static_cast<int>(payload.size()), 0,
                        reinterpret_cast<const sockaddr*>(&destination), sizeof(destination)) != SOCKET_ERROR;
#else
        (void)snapshot;
        return false;
#endif
    }

    auto UdpTelemetryPublisher::close() -> void
    {
#ifdef _WIN32
        if (m_socket != 0) { closesocket(static_cast<SOCKET>(m_socket)); m_socket = 0; }
        if (m_winsock_started) { WSACleanup(); m_winsock_started = false; }
#endif
    }
}
