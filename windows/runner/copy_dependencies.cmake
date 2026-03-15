# Robust build-time dependency copy script

message(STATUS "DEBUG: Running copy_dependencies.cmake")
message(STATUS "DEBUG: BINARY_DIR: ${BINARY_DIR}")
message(STATUS "DEBUG: OUTPUT_DIR: ${OUTPUT_DIR}")

# 1. Copy Core Flutter DLLs
if(EXISTS "${FLUTTER_LIBRARY}")
  execute_process(COMMAND ${CMAKE_COMMAND} -E copy_if_different "${FLUTTER_LIBRARY}" "${OUTPUT_DIR}")
endif()

if(EXISTS "${FLUTTER_ICU_DATA_FILE}")
  execute_process(COMMAND ${CMAKE_COMMAND} -E make_directory "${OUTPUT_DIR}/data")
  execute_process(COMMAND ${CMAKE_COMMAND} -E copy_if_different "${FLUTTER_ICU_DATA_FILE}" "${OUTPUT_DIR}/data")
endif()

# 1.1 Copy AOT Data (app.so) for Release/Profile
if(NOT BUILD_TYPE STREQUAL "Debug")
  file(GLOB_RECURSE app_so "${BINARY_DIR}/*/app.so")
  if(app_so)
    list(GET app_so 0 first_app_so)
    message(STATUS "DEBUG: Found app.so at ${first_app_so}")
    execute_process(COMMAND ${CMAKE_COMMAND} -E make_directory "${OUTPUT_DIR}/data")
    execute_process(COMMAND ${CMAKE_COMMAND} -E copy_if_different "${first_app_so}" "${OUTPUT_DIR}/data")
  endif()
endif()

# 2. Copy Assets
if(EXISTS "${PROJECT_BUILD_DIR}/flutter_assets")
  execute_process(COMMAND ${CMAKE_COMMAND} -E make_directory "${OUTPUT_DIR}/data/flutter_assets")
  execute_process(COMMAND ${CMAKE_COMMAND} -E copy_directory "${PROJECT_BUILD_DIR}/flutter_assets" "${OUTPUT_DIR}/data/flutter_assets")
endif()

# 3. Copy Plugin DLLs (Search and find)
set(DLL_NAMES
  "whisper_ggml_plus.dll"
  "ffmpeg_kit_extended_flutter_plugin.dll"
  "libffmpegkit.dll"
)

foreach(dll ${DLL_NAMES})
  file(GLOB_RECURSE found_dll "${BINARY_DIR}/*/${dll}")
  if(found_dll)
    list(GET found_dll 0 first_found) # Take the first one found
    message(STATUS "DEBUG: Found ${dll} at ${first_found}")
    execute_process(COMMAND ${CMAKE_COMMAND} -E copy_if_different "${first_found}" "${OUTPUT_DIR}")
  else()
    message(STATUS "DEBUG: Could not find ${dll} in ${BINARY_DIR}")
  endif()
endforeach()
