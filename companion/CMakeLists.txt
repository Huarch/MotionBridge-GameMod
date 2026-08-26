cmake_minimum_required(VERSION 3.24)

project(MotionBridge VERSION 0.1.0 LANGUAGES CXX)

option(MOTION_BRIDGE_BUILD_GUI "Build the Qt Quick desktop application" ON)
option(MOTION_BRIDGE_BUILD_TESTS "Build core regression tests" ON)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(fd_companion_core
    src/core/motion_engine.cpp
    src/core/tcode.cpp
)
target_include_directories(fd_companion_core PUBLIC include)
target_compile_features(fd_companion_core PUBLIC cxx_std_20)

if(MSVC)
    target_compile_options(fd_companion_core PRIVATE /W4 /permissive-)
else()
    target_compile_options(fd_companion_core PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(MOTION_BRIDGE_BUILD_TESTS)
    enable_testing()
    add_executable(fd_companion_core_tests tests/core_tests.cpp)
    target_link_libraries(fd_companion_core_tests PRIVATE fd_companion_core)
    add_test(NAME fd_companion_core_tests COMMAND fd_companion_core_tests)
endif()

if(MOTION_BRIDGE_BUILD_GUI)
    find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui LinguistTools Network Quick Quick3D SerialPort WebSockets)
    qt_standard_project_setup(REQUIRES 6.8)

    qt_add_executable(MotionBridge
        src/app/main.cpp
        src/app/companion_controller.hpp
        src/app/companion_controller.cpp
        src/app/companion_settings.hpp
        src/app/companion_settings.cpp
        src/app/language_controller.hpp
        src/app/language_controller.cpp
        src/app/realtime_pipeline.hpp
        src/app/realtime_pipeline.cpp
        src/app/device_router.hpp
        src/app/obj_geometry.hpp
        src/app/obj_geometry.cpp
        src/app/fallen_doll_input.cpp
        src/app/fallen_doll_input.hpp
        src/app/device_router.cpp
    )
    if(WIN32 AND MINGW)
        # CMake's default MinGW RC rule passes the absolute source path to
        # windres. windres then loses the quotes while invoking its
        # preprocessor when the workspace path contains spaces. Compile from
        # the icon directory with a relative input name so portable checkout
        # paths remain supported.
        set(MOTION_BRIDGE_ICON_OBJECT "${CMAKE_CURRENT_BINARY_DIR}/motion-bridge-icon.o")
        file(RELATIVE_PATH MOTION_BRIDGE_ICON_OBJECT_RELATIVE
             "${CMAKE_CURRENT_SOURCE_DIR}/assets/icons"
             "${MOTION_BRIDGE_ICON_OBJECT}")
        add_custom_command(
            OUTPUT "${MOTION_BRIDGE_ICON_OBJECT}"
            COMMAND "${CMAKE_RC_COMPILER}"
                    -i motion-bridge.rc
                    -o "${MOTION_BRIDGE_ICON_OBJECT_RELATIVE}"
                    -O coff
            WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/assets/icons"
            DEPENDS
                assets/icons/motion-bridge.rc
                assets/icons/motion-bridge.ico
            VERBATIM
        )
        set_source_files_properties(
            "${MOTION_BRIDGE_ICON_OBJECT}"
            PROPERTIES GENERATED TRUE EXTERNAL_OBJECT TRUE
        )
        target_sources(MotionBridge PRIVATE "${MOTION_BRIDGE_ICON_OBJECT}")
    elseif(WIN32)
        target_sources(MotionBridge PRIVATE assets/icons/motion-bridge.rc)
    endif()
    qt_add_qml_module(MotionBridge
        URI MotionBridge.App
        VERSION 1.0
        QML_FILES
            qml/Main.qml
            qml/AxisCard.qml
            qml/LinkRod.qml
            qml/OsrPreview.qml
        RESOURCES
            assets/models/sr6/base.obj
            assets/models/sr6/lid.obj
            assets/models/sr6/receiver.obj
            assets/models/sr6/arm.obj
            assets/models/sr6/bearing-arm.obj
            assets/models/sr6/left-pitcher.obj
            assets/models/sr6/right-pitcher.obj
            assets/models/sr6/main-arm-servos.obj
            assets/models/sr6/case.obj
            assets/models/sr6/LICENSE-osr-emu.txt
            assets/icons/motion-bridge.svg
    )
    target_include_directories(MotionBridge PRIVATE include)
    target_link_libraries(MotionBridge PRIVATE
        fd_companion_core Qt6::Core Qt6::Gui Qt6::Network Qt6::Quick Qt6::Quick3D Qt6::SerialPort Qt6::WebSockets
    )
    qt_add_translations(
        TARGETS MotionBridge
        IMMEDIATE_CALL
        TS_FILES translations/companion_zh_CN.ts
        RESOURCE_PREFIX /i18n
        LUPDATE_OPTIONS -no-obsolete
    )
    set_target_properties(MotionBridge PROPERTIES WIN32_EXECUTABLE TRUE)
endif()
