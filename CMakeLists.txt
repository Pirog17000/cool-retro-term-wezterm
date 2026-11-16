cmake_minimum_required(VERSION 3.16)

project(cool-retro-term VERSION 1.2.0 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)
set(CMAKE_AUTOUIC ON)

find_package(Qt6 REQUIRED COMPONENTS Core Quick Widgets Qml Network Sql QuickControls2 ShaderTools)

# ---------------------------------------------------------------------------
# wezbridge: the wezterm-term emulation core (Rust) exposed through a C ABI.
# Built with cargo and imported as a shared library.
find_program(CARGO_EXECUTABLE cargo
    HINTS "$ENV{CARGO_HOME}/bin" "$ENV{USERPROFILE}/.cargo/bin" "$ENV{HOME}/.cargo/bin"
    REQUIRED)

set(WEZBRIDGE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/wezbridge")
set(WEZBRIDGE_TARGET_DIR "${CMAKE_BINARY_DIR}/wezbridge-target")
if(WIN32)
    set(WEZBRIDGE_LIBFILE "${WEZBRIDGE_TARGET_DIR}/release/wezbridge.dll")
    set(WEZBRIDGE_IMPLIB "${WEZBRIDGE_TARGET_DIR}/release/wezbridge.dll.lib")
elseif(APPLE)
    set(WEZBRIDGE_LIBFILE "${WEZBRIDGE_TARGET_DIR}/release/libwezbridge.dylib")
else()
    set(WEZBRIDGE_LIBFILE "${WEZBRIDGE_TARGET_DIR}/release/libwezbridge.so")
endif()

if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/third_party/wezterm/term/Cargo.toml")
    message(FATAL_ERROR "third_party/wezterm is missing: run `git submodule update --init --depth 1 third_party/wezterm`")
endif()

add_custom_target(wezbridge_build
    COMMAND "${CARGO_EXECUTABLE}" build --release --locked
            --manifest-path "${WEZBRIDGE_DIR}/Cargo.toml"
            --target-dir "${WEZBRIDGE_TARGET_DIR}"
    BYPRODUCTS "${WEZBRIDGE_LIBFILE}" ${WEZBRIDGE_IMPLIB}
    WORKING_DIRECTORY "${WEZBRIDGE_DIR}"
    COMMENT "Building wezbridge (wezterm-term core) with cargo"
    USES_TERMINAL
)

add_library(wezbridge SHARED IMPORTED GLOBAL)
set_target_properties(wezbridge PROPERTIES
    IMPORTED_LOCATION "${WEZBRIDGE_LIBFILE}"
    INTERFACE_INCLUDE_DIRECTORIES "${WEZBRIDGE_DIR}/include"
)
if(WIN32)
    set_target_properties(wezbridge PROPERTIES IMPORTED_IMPLIB "${WEZBRIDGE_IMPLIB}")
endif()
add_dependencies(wezbridge wezbridge_build)

add_subdirectory(qmltermwidget)
add_subdirectory(app)

if(UNIX AND NOT APPLE)
    install(FILES cool-retro-term.desktop DESTINATION share/applications)
    install(FILES icons/32x32/cool-retro-term.png DESTINATION share/icons/hicolor/32x32/apps)
    install(FILES icons/64x64/cool-retro-term.png DESTINATION share/icons/hicolor/64x64/apps)
    install(FILES icons/128x128/cool-retro-term.png DESTINATION share/icons/hicolor/128x128/apps)
    install(FILES icons/256x256/cool-retro-term.png DESTINATION share/icons/hicolor/256x256/apps)
endif()
