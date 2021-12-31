cmake_minimum_required(VERSION 3.8 FATAL_ERROR)

find_program(CLANG_FORMAT_EXE NAMES "clang-format" DOC "Path to clang-format executable")

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED TRUE)

set(VOLUMETRIC_LIGHTING_SOURCES ${PROJECT_SOURCE_DIR}/src/main.cpp
                                ${PROJECT_SOURCE_DIR}/external/dwSampleFramework/extras/shadow_map.cpp
                                ${PROJECT_SOURCE_DIR}/external/dwSampleFramework/extras/shadow_map.h
                                ${PROJECT_SOURCE_DIR}/external/dwSampleFramework/extras/hosek_wilkie_sky_model.cpp
                                ${PROJECT_SOURCE_DIR}/external/dwSampleFramework/extras/hosek_wilkie_sky_model.h)
file(GLOB_RECURSE SHADER_SOURCES ${PROJECT_SOURCE_DIR}/src/*.glsl)

if (APPLE)
    add_executable(VolumetricLighting MACOSX_BUNDLE ${VOLUMETRIC_LIGHTING_SOURCES} ${SHADER_SOURCES} ${ASSET_SOURCES})
    set(MACOSX_BUNDLE_BUNDLE_NAME "VolumetricLighting") 
    set_source_files_properties(${SHADER_SOURCES} PROPERTIES MACOSX_PACKAGE_LOCATION Resources/shaders)
    set_source_files_properties(${ASSET_SOURCES} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
else()
    add_executable(VolumetricLighting ${VOLUMETRIC_LIGHTING_SOURCES}) 
endif()

target_link_libraries(VolumetricLighting dwSampleFramework)

if (NOT APPLE)
    add_custom_command(TARGET VolumetricLighting POST_BUILD COMMAND ${CMAKE_COMMAND} -E copy_directory ${CMAKE_SOURCE_DIR}/src/shaders $<TARGET_FILE_DIR:VolumetricLighting>/shaders)
endif()

if(CLANG_FORMAT_EXE)
    add_custom_target(VolumetricLighting-clang-format COMMAND ${CLANG_FORMAT_EXE} -i -style=file ${VOLUMETRIC_LIGHTING_SOURCES} ${SHADER_SOURCES})
endif()

set_property(TARGET VolumetricLighting PROPERTY VS_DEBUGGER_WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/bin/$(Configuration)")