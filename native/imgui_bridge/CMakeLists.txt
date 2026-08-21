cmake_minimum_required(VERSION 3.20)
project(MineLuaImGui LANGUAGES CXX)

set(IMGUI_DIR "${CMAKE_CURRENT_LIST_DIR}/../../third_party/imgui")
set(MINELUA_ROOT "${CMAKE_CURRENT_LIST_DIR}/../..")

add_library(minelua_imgui SHARED
  minelua_imgui.cpp
  "${IMGUI_DIR}/imgui.cpp"
  "${IMGUI_DIR}/imgui_draw.cpp"
  "${IMGUI_DIR}/imgui_tables.cpp"
  "${IMGUI_DIR}/imgui_widgets.cpp"
  "${IMGUI_DIR}/backends/imgui_impl_opengl3.cpp"
)

# Keep the developer bridge replaceable while a previous game session still
# has the original DLL mapped (Windows locks loaded DLL files).
set_target_properties(minelua_imgui PROPERTIES OUTPUT_NAME "minelua_imgui_tools_v2")

target_include_directories(minelua_imgui PRIVATE
  "${IMGUI_DIR}"
  "${IMGUI_DIR}/backends"
)
target_compile_features(minelua_imgui PRIVATE cxx_std_17)
target_compile_definitions(minelua_imgui PRIVATE WIN32_LEAN_AND_MEAN NOMINMAX)
target_link_libraries(minelua_imgui PRIVATE opengl32)

foreach(config Debug Release RelWithDebInfo MinSizeRel)
  string(TOUPPER "${config}" config_upper)
  set_target_properties(minelua_imgui PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY_${config_upper} "${MINELUA_ROOT}/lib"
    LIBRARY_OUTPUT_DIRECTORY_${config_upper} "${MINELUA_ROOT}/lib"
  )
endforeach()
