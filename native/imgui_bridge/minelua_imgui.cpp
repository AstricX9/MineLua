#include "imgui.h"
#include "backends/imgui_impl_opengl3.h"

#include <algorithm>
#include <cmath>

#if defined(_WIN32)
#define MINELUA_EXPORT extern "C" __declspec(dllexport)
#else
#define MINELUA_EXPORT extern "C"
#endif

struct MineLuaDevUiState {
    int menu_open;
    int environment_open;
    int generation_open;
    int override_time;
    float time_of_day;
    float fog_strength;
    int generation_dirty;
    int regenerate_requested;
    int export_requested;
    int export_status;
    int seed;
    float continent_scale;
    float biome_scale;
    float region_scale;
    float mountain_scale;
    float river_scale;
    float forest_scale;
    float macro_warp_scale;
    float macro_warp_amount;
    float detail_scale;
    float relief_gain;
    float local_relief_gain;
    float erosion_strength;
    float river_carve_strength;
    float lake_carve_strength;
    float mountain_sharpness;
    float grass_tint_strength;
    float tree_density;
    float shoreline_width;
    float rocky_shore_threshold;
    float biome_climate_influence;
    float snow_temperature;
    float elevation_cooling;
    float freeze_temperature;
    int preview_mode;
    int preview_rebuild_requested;
    int want_capture_mouse;
    // Navigation. The loaded world is a ball a hundred metres across and
    // walking is 5 m/s, so getting anywhere means either a much faster fly
    // speed or a jump straight to a coordinate.
    int navigation_open;
    int fly_enabled;
    float fly_speed_multiplier;
    int freeze_streaming;
    int teleport_requested;
    int capture_requested;
    float teleport_latitude;
    float teleport_longitude;
    float teleport_altitude;
    float current_latitude;
    float current_longitude;
    float current_altitude;
    float time_scale;
};

static bool g_initialized = false;

// The Lua side mirrors MineLuaDevUiState in an ffi.cdef. If the two ever
// disagree the game writes past the end of the struct and corrupts whatever
// follows it, silently. Exporting the size lets the mirror check itself.
MINELUA_EXPORT int ml_imgui_state_size() {
    return (int)sizeof(MineLuaDevUiState);
}

static const char* TimeName(float hour) {
    if (hour < 5.0f) return "Night";
    if (hour < 7.0f) return "Sunrise";
    if (hour < 11.0f) return "Morning";
    if (hour < 14.0f) return "Midday";
    if (hour < 17.0f) return "Afternoon";
    if (hour < 19.0f) return "Sunset";
    if (hour < 21.0f) return "Dusk";
    return "Night";
}

static void ResetGeneration(MineLuaDevUiState* state) {
    state->seed = 1;
    state->continent_scale = 0.0025f;
    state->biome_scale = 0.00092f;
    state->region_scale = 0.00125f;
    state->mountain_scale = 0.00078f;
    state->river_scale = 0.00115f;
    state->forest_scale = 0.00165f;
    state->macro_warp_scale = 0.00062f;
    state->macro_warp_amount = 360.0f;
    state->detail_scale = 0.026f;
    state->relief_gain = 2.4f;
    state->local_relief_gain = 2.0f;
    state->erosion_strength = 0.0f;
    state->river_carve_strength = 0.86f;
    state->lake_carve_strength = 0.78f;
    state->mountain_sharpness = 1.65f;
    state->grass_tint_strength = 0.92f;
    state->tree_density = 0.78f;
    state->shoreline_width = 5.0f;
    state->rocky_shore_threshold = 0.24f;
    state->biome_climate_influence = 0.34f;
    state->snow_temperature = 0.18f;
    state->elevation_cooling = 0.0045f;
    state->freeze_temperature = 0.08f;
    state->generation_dirty = 1;
}

static bool ScaleSlider(const char* label, float* value, float minimum, float maximum) {
    ImGui::SetNextItemWidth(245.0f);
    return ImGui::SliderFloat(label, value, minimum, maximum, "%.6f", ImGuiSliderFlags_Logarithmic);
}

MINELUA_EXPORT int ml_imgui_init() {
    if (g_initialized) return 1;

    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.IniFilename = nullptr;
    io.LogFilename = nullptr;

    ImGui::StyleColorsDark();
    ImGuiStyle& style = ImGui::GetStyle();
    style.WindowRounding = 6.0f;
    style.FrameRounding = 4.0f;
    style.GrabRounding = 4.0f;
    style.WindowPadding = ImVec2(12.0f, 12.0f);
    style.ItemSpacing = ImVec2(8.0f, 7.0f);

    if (!ImGui_ImplOpenGL3_Init("#version 460 core")) {
        ImGui::DestroyContext();
        return 0;
    }

    g_initialized = true;
    return 1;
}

MINELUA_EXPORT void ml_imgui_shutdown() {
    if (!g_initialized) return;
    ImGui_ImplOpenGL3_Shutdown();
    ImGui::DestroyContext();
    g_initialized = false;
}

MINELUA_EXPORT void ml_imgui_new_frame(
    float width,
    float height,
    float delta_time,
    float mouse_x,
    float mouse_y,
    int mouse_buttons
) {
    if (!g_initialized) return;

    ImGui_ImplOpenGL3_NewFrame();
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(std::max(width, 1.0f), std::max(height, 1.0f));
    io.DeltaTime = std::max(delta_time, 1.0f / 1000.0f);
    io.AddMousePosEvent(mouse_x, mouse_y);
    io.AddMouseButtonEvent(0, (mouse_buttons & 1) != 0);
    io.AddMouseButtonEvent(1, (mouse_buttons & 2) != 0);
    io.AddMouseButtonEvent(2, (mouse_buttons & 4) != 0);
    ImGui::NewFrame();
}

MINELUA_EXPORT void ml_imgui_draw(MineLuaDevUiState* state) {
    if (!g_initialized || state == nullptr) return;

    bool open = state->menu_open != 0;
    if (open) {
        ImGui::SetNextWindowPos(ImVec2(12.0f, 12.0f), ImGuiCond_Always);
        ImGui::SetNextWindowBgAlpha(0.94f);
        ImGuiWindowFlags toolbar_flags = ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
            ImGuiWindowFlags_NoMove | ImGuiWindowFlags_AlwaysAutoResize | ImGuiWindowFlags_NoSavedSettings;
        if (ImGui::Begin("##MineLuaDeveloperToolstrip", &open, toolbar_flags)) {
            ImGui::TextUnformatted("MineLua Tools");
            ImGui::SameLine();
            if (ImGui::Button("Environment")) state->environment_open = state->environment_open ? 0 : 1;
            ImGui::SameLine();
            if (ImGui::Button("World Generation")) state->generation_open = state->generation_open ? 0 : 1;
            ImGui::SameLine();
            if (ImGui::Button("Navigation")) state->navigation_open = state->navigation_open ? 0 : 1;
            ImGui::SameLine();
            if (ImGui::Button(state->preview_mode ? "Exit RTS Preview" : "RTS Preview")) {
                state->preview_mode = state->preview_mode ? 0 : 1;
                if (state->preview_mode) state->preview_rebuild_requested = 1;
            }
            ImGui::SameLine();
            ImGui::TextDisabled("F4 closes");
        }
        ImGui::End();

        bool environment_open = state->environment_open != 0;
        if (environment_open) {
            ImGui::SetNextWindowPos(ImVec2(18.0f, 64.0f), ImGuiCond_FirstUseEver);
            ImGui::SetNextWindowSize(ImVec2(410.0f, 0.0f), ImGuiCond_FirstUseEver);
            if (ImGui::Begin("Environment", &environment_open, ImGuiWindowFlags_AlwaysAutoResize)) {
            if (ImGui::CollapsingHeader("World", ImGuiTreeNodeFlags_DefaultOpen)) {
                bool override_time = state->override_time != 0;
                if (ImGui::Checkbox("Override time of day", &override_time)) {
                    state->override_time = override_time ? 1 : 0;
                }

                ImGui::BeginDisabled(!override_time);
                ImGui::SetNextItemWidth(260.0f);
                ImGui::SliderFloat("Time", &state->time_of_day, 0.0f, 24.0f, "%.2f h");
                state->time_of_day = std::fmod(std::max(state->time_of_day, 0.0f), 24.0f);
                ImGui::SameLine();
                ImGui::TextUnformatted(TimeName(state->time_of_day));

                if (ImGui::Button("Sunrise")) state->time_of_day = 6.0f;
                ImGui::SameLine();
                if (ImGui::Button("Noon")) state->time_of_day = 12.0f;
                ImGui::SameLine();
                if (ImGui::Button("Sunset")) state->time_of_day = 18.0f;
                ImGui::SameLine();
                if (ImGui::Button("Midnight")) state->time_of_day = 0.0f;
                ImGui::EndDisabled();
            }

            if (ImGui::CollapsingHeader("Atmosphere", ImGuiTreeNodeFlags_DefaultOpen)) {
                ImGui::SetNextItemWidth(260.0f);
                ImGui::SliderFloat("Fog strength", &state->fog_strength, 0.0f, 3.0f, "%.2fx");
                state->fog_strength = std::clamp(state->fog_strength, 0.0f, 3.0f);
                ImGui::SameLine();
                if (ImGui::SmallButton("Reset##fog")) state->fog_strength = 1.0f;
                ImGui::TextDisabled("0 disables volumetric fog; 1 is the authored default.");
            }
            }
            ImGui::End();
            state->environment_open = environment_open ? 1 : 0;
        }

        bool navigation_open = state->navigation_open != 0;
        if (navigation_open) {
            // Sized to fit under the Environment window at 720p and left
            // scrollable rather than auto-resizing, so the Clock section at the
            // bottom stays reachable on a short display.
            ImGui::SetNextWindowPos(ImVec2(18.0f, 292.0f), ImGuiCond_FirstUseEver);
            ImGui::SetNextWindowSize(ImVec2(410.0f, 412.0f), ImGuiCond_FirstUseEver);
            if (ImGui::Begin("Navigation", &navigation_open)) {
                if (ImGui::CollapsingHeader("Free flight", ImGuiTreeNodeFlags_DefaultOpen)) {
                    bool flying = state->fly_enabled != 0;
                    if (ImGui::Checkbox("Fly (no collision)", &flying)) {
                        state->fly_enabled = flying ? 1 : 0;
                    }
                    ImGui::SetNextItemWidth(260.0f);
                    ImGui::SliderFloat("Speed", &state->fly_speed_multiplier, 1.0f, 4000.0f,
                        "%.0fx", ImGuiSliderFlags_Logarithmic);
                    state->fly_speed_multiplier = std::clamp(state->fly_speed_multiplier, 1.0f, 4000.0f);
                    if (ImGui::SmallButton("1x")) state->fly_speed_multiplier = 1.0f;
                    ImGui::SameLine();
                    if (ImGui::SmallButton("20x")) state->fly_speed_multiplier = 20.0f;
                    ImGui::SameLine();
                    if (ImGui::SmallButton("200x")) state->fly_speed_multiplier = 200.0f;
                    ImGui::SameLine();
                    if (ImGui::SmallButton("2000x")) state->fly_speed_multiplier = 2000.0f;

                    bool freeze = state->freeze_streaming != 0;
                    if (ImGui::Checkbox("Freeze chunk streaming", &freeze)) {
                        state->freeze_streaming = freeze ? 1 : 0;
                    }
                    ImGui::TextDisabled("Stops generating chunks so a fast fly-through does not");
                    ImGui::TextDisabled("queue thousands of them. Terrain already loaded stays.");
                }

                if (ImGui::CollapsingHeader("Teleport", ImGuiTreeNodeFlags_DefaultOpen)) {
                    ImGui::Text("Here: %.4f lat, %.4f lon, %.0f m", state->current_latitude,
                        state->current_longitude, state->current_altitude);
                    ImGui::SetNextItemWidth(150.0f);
                    ImGui::InputFloat("Latitude", &state->teleport_latitude, 1.0f, 10.0f, "%.4f");
                    state->teleport_latitude = std::clamp(state->teleport_latitude, -89.999f, 89.999f);
                    ImGui::SetNextItemWidth(150.0f);
                    ImGui::InputFloat("Longitude", &state->teleport_longitude, 1.0f, 10.0f, "%.4f");
                    ImGui::SetNextItemWidth(150.0f);
                    ImGui::InputFloat("Altitude (m)", &state->teleport_altitude, 10.0f, 1000.0f, "%.0f");
                    if (ImGui::Button("Go")) state->teleport_requested = 1;
                    ImGui::SameLine();
                    if (ImGui::Button("Copy current")) state->capture_requested = 1;
                    ImGui::SameLine();
                    if (ImGui::Button("Low orbit")) {
                        state->teleport_altitude = 400000.0f;
                        state->teleport_requested = 1;
                    }
                    ImGui::TextDisabled("Altitude is above sea level. The surface is found");
                    ImGui::TextDisabled("for you when the altitude is below it.");
                }

                if (ImGui::CollapsingHeader("Clock", ImGuiTreeNodeFlags_DefaultOpen)) {
                    ImGui::SetNextItemWidth(260.0f);
                    ImGui::SliderFloat("Time scale", &state->time_scale, 0.0f, 240.0f, "%.1fx",
                        ImGuiSliderFlags_Logarithmic);
                    state->time_scale = std::clamp(state->time_scale, 0.0f, 240.0f);
                    if (ImGui::SmallButton("Pause")) state->time_scale = 0.0f;
                    ImGui::SameLine();
                    if (ImGui::SmallButton("Normal")) state->time_scale = 1.0f;
                    ImGui::SameLine();
                    if (ImGui::SmallButton("60x")) state->time_scale = 60.0f;
                    ImGui::TextDisabled("A full rotation takes an hour at 1x: thirty minutes");
                    ImGui::TextDisabled("of daylight and thirty of night at the equator.");
                }
            }
            ImGui::End();
            state->navigation_open = navigation_open ? 1 : 0;
        }

        bool generation_open = state->generation_open != 0;
        if (generation_open) {
            ImGui::SetNextWindowPos(ImVec2(444.0f, 64.0f), ImGuiCond_FirstUseEver);
            ImGui::SetNextWindowSize(ImVec2(430.0f, 610.0f), ImGuiCond_FirstUseEver);
            if (ImGui::Begin("World Generation Tuner", &generation_open)) {
                ImGui::TextWrapped("Edits are staged, so they cannot create chunk seams. Rebuild the RTS preview for a fast overview, or explicitly regenerate full chunks.");
                ImGui::Separator();

                bool changed = false;
                if (ImGui::CollapsingHeader("Layout and biome density", ImGuiTreeNodeFlags_DefaultOpen)) {
                    ImGui::SetNextItemWidth(245.0f);
                    changed |= ImGui::InputInt("Seed", &state->seed, 1, 100);
                    changed |= ScaleSlider("Continent scale", &state->continent_scale, 0.00008f, 0.0025f);
                    changed |= ScaleSlider("Biome density", &state->biome_scale, 0.00015f, 0.006f);
                    changed |= ScaleSlider("Region scale", &state->region_scale, 0.0002f, 0.008f);
                    changed |= ScaleSlider("Mountain density", &state->mountain_scale, 0.00015f, 0.004f);
                    changed |= ScaleSlider("River density", &state->river_scale, 0.0002f, 0.006f);
                    changed |= ScaleSlider("Forest patch scale", &state->forest_scale, 0.00025f, 0.008f);
                    ImGui::TextDisabled("Higher scale = smaller, more frequent features.");
                }

                if (ImGui::CollapsingHeader("Terrain shaping", ImGuiTreeNodeFlags_DefaultOpen)) {
                    changed |= ScaleSlider("Macro warp scale", &state->macro_warp_scale, 0.0001f, 0.004f);
                    ImGui::SetNextItemWidth(245.0f);
                    changed |= ImGui::SliderFloat("Macro warp amount", &state->macro_warp_amount, 0.0f, 1200.0f, "%.0f blocks");
                    changed |= ScaleSlider("Surface detail scale", &state->detail_scale, 0.004f, 0.12f);
                    ImGui::SetNextItemWidth(245.0f);
                    changed |= ImGui::SliderFloat("Relief", &state->relief_gain, 0.35f, 5.0f, "%.2fx");
                    ImGui::SetNextItemWidth(245.0f);
                    changed |= ImGui::SliderFloat("Local relief", &state->local_relief_gain, 0.25f, 4.5f, "%.2fx");
                    ImGui::SetNextItemWidth(245.0f);
                    changed |= ImGui::SliderFloat("Mountain sharpness", &state->mountain_sharpness, 0.55f, 3.5f, "%.2f");
                }

                if (ImGui::CollapsingHeader("Erosion and carving", ImGuiTreeNodeFlags_DefaultOpen)) {
                    ImGui::SetNextItemWidth(245.0f);
                    changed |= ImGui::SliderFloat("Erosion smoothing", &state->erosion_strength, 0.0f, 1.0f, "%.2f");
                    ImGui::SetNextItemWidth(245.0f);
                    changed |= ImGui::SliderFloat("River carving", &state->river_carve_strength, 0.0f, 1.25f, "%.2f");
                    ImGui::SetNextItemWidth(245.0f);
                    changed |= ImGui::SliderFloat("Lake carving", &state->lake_carve_strength, 0.0f, 1.25f, "%.2f");
                    ImGui::TextDisabled("Erosion smooths fine relief and rounds mountain crests.");
                }

                if (ImGui::CollapsingHeader("Climate and shorelines", ImGuiTreeNodeFlags_DefaultOpen)) {
                    ImGui::SetNextItemWidth(245.0f);
                    changed |= ImGui::SliderFloat("Shoreline width", &state->shoreline_width, 0.0f, 12.0f, "%.1f blocks");
                    ImGui::SetNextItemWidth(245.0f);
                    changed |= ImGui::SliderFloat("Rocky coast threshold", &state->rocky_shore_threshold, 0.05f, 0.60f, "%.2f");
                    ImGui::SetNextItemWidth(245.0f);
                    changed |= ImGui::SliderFloat("Biome climate influence", &state->biome_climate_influence, 0.0f, 1.0f, "%.2f");
                    ImGui::SetNextItemWidth(245.0f);
                    changed |= ImGui::SliderFloat("Snow temperature", &state->snow_temperature, 0.02f, 0.40f, "%.2f");
                    ImGui::SetNextItemWidth(245.0f);
                    changed |= ImGui::SliderFloat("Elevation cooling", &state->elevation_cooling, 0.0f, 0.012f, "%.4f / block");
                    ImGui::SetNextItemWidth(245.0f);
                    changed |= ImGui::SliderFloat("Water freeze temperature", &state->freeze_temperature, 0.0f, 0.25f, "%.2f");
                    ImGui::TextDisabled("Temperature falls with height; moisture gates most snowfall.");
                }

                if (ImGui::CollapsingHeader("Surface and vegetation", ImGuiTreeNodeFlags_DefaultOpen)) {
                    ImGui::SetNextItemWidth(245.0f);
                    changed |= ImGui::SliderFloat("Tree density", &state->tree_density, 0.0f, 3.0f, "%.2fx");
                    ImGui::SetNextItemWidth(245.0f);
                    changed |= ImGui::SliderFloat("Grass tint", &state->grass_tint_strength, 0.0f, 1.0f, "%.2f");
                }

                if (changed) {
                    state->generation_dirty = 1;
                    state->export_status = 0;
                }

                ImGui::Separator();
                if (ImGui::Button("Rebuild RTS preview")) {
                    state->preview_mode = 1;
                    state->preview_rebuild_requested = 1;
                }
                ImGui::SameLine();
                if (ImGui::Button("Save tuning preset")) state->export_requested = 1;
                ImGui::SameLine();
                if (ImGui::Button("Reset defaults")) ResetGeneration(state);

                if (state->preview_mode) {
                    ImGui::TextDisabled("RTS: WASD pan, Q/E rotate, R/F zoom. Full chunks are paused.");
                }

                if (ImGui::Button("Apply and regenerate full chunks")) ImGui::OpenPopup("Regenerate terrain?");

                if (ImGui::BeginPopupModal("Regenerate terrain?", nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
                    ImGui::TextWrapped("This replaces all currently loaded chunks and discards block edits in them. Your saved default settings are not changed.");
                    if (ImGui::Button("Regenerate", ImVec2(120.0f, 0.0f))) {
                        state->regenerate_requested = 1;
                        ImGui::CloseCurrentPopup();
                    }
                    ImGui::SameLine();
                    if (ImGui::Button("Cancel", ImVec2(120.0f, 0.0f))) ImGui::CloseCurrentPopup();
                    ImGui::EndPopup();
                }

                if (state->export_status > 0) {
                    ImGui::TextColored(ImVec4(0.45f, 0.90f, 0.52f, 1.0f), "Saved: data/config/worldgen_tuning.json");
                } else if (state->export_status < 0) {
                    ImGui::TextColored(ImVec4(1.0f, 0.42f, 0.35f, 1.0f), "Could not save data/config/worldgen_tuning.json");
                }
            }
            ImGui::End();
            state->generation_open = generation_open ? 1 : 0;
        }
    }

    state->menu_open = open ? 1 : 0;
    state->want_capture_mouse = ImGui::GetIO().WantCaptureMouse ? 1 : 0;
}

MINELUA_EXPORT void ml_imgui_render() {
    if (!g_initialized) return;
    ImGui::Render();
    ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
}
