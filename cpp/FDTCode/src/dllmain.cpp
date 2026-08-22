#include <atomic>
#include <algorithm>
#include <cmath>

#include <DynamicOutput/DynamicOutput.hpp>
#include <Mod/CppUserModBase.hpp>
#include <UE4SSProgram.hpp>

using namespace RC;

namespace
{
    struct PreviewPoint { float x{}; float y{}; float z{}; };

    auto rotate_preview(PreviewPoint point, float yaw, float pitch) -> PreviewPoint
    {
        const float cy = std::cos(yaw), sy = std::sin(yaw);
        const float cp = std::cos(pitch), sp = std::sin(pitch);
        const PreviewPoint yawed{point.x * cy - point.z * sy, point.y, point.x * sy + point.z * cy};
        return {yawed.x, yawed.y * cp - yawed.z * sp, yawed.y * sp + yawed.z * cp};
    }

    auto project_preview(PreviewPoint point, ImVec2 center, float scale, float yaw, float pitch) -> ImVec2
    {
        const auto rotated = rotate_preview(point, yaw, pitch);
        return {center.x + rotated.x * scale, center.y - rotated.y * scale + rotated.z * scale * 0.35f};
    }
}

// This first DLL deliberately contains no Unreal object reads. It establishes
// ABI compatibility, hotkeys, and a UI boundary before the generated headers
// approve the reflected GetSocketTransform parameter layout.
class FDTCodeMod final : public CppUserModBase
{
  public:
    FDTCodeMod()
    {
        ModName = STR("FDTCode");
        ModVersion = STR("0.1.0");
        ModDescription = STR("Fallen Doll runtime motion simulator; device output disabled");
        ModAuthors = STR("FDTCode project");

        register_keydown_event(Input::Key::F11, [this] {
            const bool enabled = !m_simulation_enabled.load();
            m_simulation_enabled.store(enabled);
            Output::send(STR("[FDTCode] Simulation {}\n"), enabled ? STR("enabled") : STR("disabled"));
        });
        register_keydown_event(Input::Key::F12, [this] {
            m_panel_visible.store(!m_panel_visible.load());
        });
        Output::send(STR("[FDTCode] Loaded. F11 toggles simulation; F12 toggles the FDTCode debug page. Device output is disabled.\n"));
    }

    auto on_unreal_init() -> void override
    {
        Output::send(STR("[FDTCode] Unreal initialized. Runtime bone collector is gated pending generated parameter verification.\n"));
    }

    auto on_ui_init() -> void override
    {
        UE4SS_ENABLE_IMGUI();
        register_tab(STR("FDTCode"), [](CppUserModBase* base) {
            auto* mod = dynamic_cast<FDTCodeMod*>(base);
            if (!mod || !mod->m_panel_visible.load()) return;

            bool simulation_enabled = mod->m_simulation_enabled.load();
            ImGui::TextUnformatted("Fallen Doll TCode — SIMULATION ONLY");
            ImGui::Separator();
            if (ImGui::Checkbox("Realtime simulation (F11)", &simulation_enabled)) mod->m_simulation_enabled.store(simulation_enabled);
            ImGui::TextUnformatted("Device output: disabled");
            ImGui::TextUnformatted("Bone collector: awaiting verified GetSocketTransform layout");
            ImGui::TextUnformatted("Bridge: UDP v1 -> 127.0.0.1:17891");
            ImGui::TextUnformatted("Use F12 to hide/show this page.");
            mod->draw_motion_preview();
        });
    }

  private:
    // This preview consumes only plain normalized axes. When the collector is
    // enabled, the game thread will publish a copied snapshot into this class;
    // the ImGui thread must never query a UObject here.
    auto draw_motion_preview() -> void
    {
        ImGui::Separator();
        ImGui::TextUnformatted("Motion preview — free reference/target cylinders");
        ImGui::SliderFloat("Camera yaw", &m_preview_yaw, -3.14f, 3.14f);
        ImGui::SliderFloat("Camera pitch", &m_preview_pitch, -1.25f, 1.25f);
        const ImVec2 size{ImGui::GetContentRegionAvail().x, 220.0f};
        const ImVec2 origin = ImGui::GetCursorScreenPos();
        ImGui::InvisibleButton("FDTCodePreview", size);
        const bool dragging = ImGui::IsItemActive() && ImGui::IsMouseDragging(ImGuiMouseButton_Left);
        if (dragging)
        {
            const ImVec2 delta = ImGui::GetIO().MouseDelta;
            m_preview_yaw += delta.x * 0.01f;
            m_preview_pitch = std::clamp(m_preview_pitch + delta.y * 0.01f, -1.45f, 1.45f);
        }

        auto* draw = ImGui::GetWindowDrawList();
        draw->AddRectFilled(origin, {origin.x + size.x, origin.y + size.y}, IM_COL32(18, 24, 34, 255), 6.0f);
        const ImVec2 center{origin.x + size.x * 0.5f, origin.y + size.y * 0.56f};
        const float scale = 55.0f;

        // Reference cylinder: vertical contact axis. Target cylinder is free
        // to move around it from L0/L1/L2 and rotate from R0/R1/R2. Initial
        // values are neutral until a copied runtime snapshot arrives.
        const float l0 = m_preview_l0.load();
        const float l1 = m_preview_l1.load();
        const float l2 = m_preview_l2.load();
        const PreviewPoint reference_base{0.0f, -1.2f, 0.0f};
        const PreviewPoint reference_tip{0.0f, 1.2f, 0.0f};
        const PreviewPoint target_base{(l2 - 0.5f) * 2.2f, (0.5f - l0) * 2.4f - 0.45f, (l1 - 0.5f) * 2.2f};
        const PreviewPoint target_tip{target_base.x, target_base.y + 0.7f, target_base.z};
        const auto ref_a = project_preview(reference_base, center, scale, m_preview_yaw, m_preview_pitch);
        const auto ref_b = project_preview(reference_tip, center, scale, m_preview_yaw, m_preview_pitch);
        const auto target_a = project_preview(target_base, center, scale, m_preview_yaw, m_preview_pitch);
        const auto target_b = project_preview(target_tip, center, scale, m_preview_yaw, m_preview_pitch);
        draw->AddLine(ref_a, ref_b, IM_COL32(84, 180, 255, 255), 20.0f);
        draw->AddLine(ref_a, ref_b, IM_COL32(200, 236, 255, 255), 2.0f);
        draw->AddLine(target_a, target_b, IM_COL32(255, 167, 79, 255), 16.0f);
        draw->AddLine(target_a, target_b, IM_COL32(255, 236, 200, 255), 2.0f);
        draw->AddText({origin.x + 10.0f, origin.y + 10.0f}, IM_COL32(210, 220, 230, 255), "Blue: reference axis  Orange: free target cylinder");
    }

    std::atomic_bool m_simulation_enabled{false};
    std::atomic_bool m_panel_visible{true};
    std::atomic<float> m_preview_l0{0.5f};
    std::atomic<float> m_preview_l1{0.5f};
    std::atomic<float> m_preview_l2{0.5f};
    float m_preview_yaw{0.55f};
    float m_preview_pitch{0.25f};
};

#define FD_TCODE_API __declspec(dllexport)
extern "C"
{
    FD_TCODE_API CppUserModBase* start_mod() { return new FDTCodeMod(); }
    FD_TCODE_API void uninstall_mod(CppUserModBase* mod) { delete mod; }
}
