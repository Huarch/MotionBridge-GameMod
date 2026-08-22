cmake_minimum_required(VERSION 3.22)

project(FallenDollTCode LANGUAGES CXX)

include(CTest)

option(FD_TCODE_BUILD_TESTS "Build the standalone motion-core tests" ON)
set(FD_TCODE_UE4SS_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.deps/RE-UE4SS" CACHE PATH
    "RE-UE4SS source directory pinned to the installed UE4SS revision")

add_subdirectory(cpp/FDTCodeCore)

# The motion core is intentionally usable without UE4SS so its geometry and
# safety state machine can be tested before loading anything into the game.
# The DLL target is added only when the private UEPseudo submodule is present.
if (EXISTS "${FD_TCODE_UE4SS_SOURCE_DIR}/deps/first/Unreal/CMakeLists.txt")
    add_subdirectory("${FD_TCODE_UE4SS_SOURCE_DIR}" "${CMAKE_BINARY_DIR}/RE-UE4SS")
    add_subdirectory(cpp/FDTCode)
else()
    message(STATUS "FDTCode DLL disabled: UE4SS UEPseudo submodule is unavailable.")
    message(STATUS "Core tests remain buildable. Configure FD_TCODE_UE4SS_SOURCE_DIR after granting UE4SS development access.")
endif()
