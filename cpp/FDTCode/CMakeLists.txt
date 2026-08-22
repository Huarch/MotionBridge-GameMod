set(FD_TCODE_GAME_MODS_DIR
    "D:/SteamLibrary/steamapps/common/Operation Lovecraft Fallen Doll Playtest/Paralogue/Binaries/Win64/ue4ss/Mods"
    CACHE PATH "UE4SS Mods directory used for the local development deployment")

add_library(FDTCode SHARED src/dllmain.cpp)
target_link_libraries(FDTCode PRIVATE UE4SS FDTCodeCore)
target_include_directories(FDTCode PRIVATE ../FDTCodeCore/include)
target_compile_features(FDTCode PRIVATE cxx_std_23)
target_compile_options(FDTCode PRIVATE $<$<CXX_COMPILER_ID:MSVC>:/W4 /permissive->)

add_custom_command(TARGET FDTCode POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${FD_TCODE_GAME_MODS_DIR}/FDTCode/dlls"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "$<TARGET_FILE:FDTCode>" "${FD_TCODE_GAME_MODS_DIR}/FDTCode/dlls/main.dll"
    COMMENT "Deploying FDTCode main.dll to the local UE4SS Mods folder")
