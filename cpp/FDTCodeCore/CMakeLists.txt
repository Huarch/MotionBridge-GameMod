add_library(FDTCodeCore STATIC
    src/motion_core.cpp
    src/runtime_pipeline.cpp
    src/telemetry_v1.cpp
)

target_include_directories(FDTCodeCore PUBLIC include)
target_compile_features(FDTCodeCore PUBLIC cxx_std_20)
target_compile_options(FDTCodeCore PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/W4 /permissive->)
if (WIN32)
    target_link_libraries(FDTCodeCore PRIVATE ws2_32)
endif()

if (FD_TCODE_BUILD_TESTS)
    add_executable(FDTCodeCoreTests tests/motion_core_tests.cpp)
    target_link_libraries(FDTCodeCoreTests PRIVATE FDTCodeCore)
    add_test(NAME FDTCodeCoreTests COMMAND FDTCodeCoreTests)
endif()
