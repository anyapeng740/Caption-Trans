set(SEARCH_PATHS
  "${CMAKE_BINARY_DIR}/plugins/ffmpeg_kit_extended_flutter/libffmpegkit.dll"
  "${CMAKE_BINARY_DIR}/install/libffmpegkit.dll"
  "${CMAKE_BINARY_DIR}/runner/Debug/libffmpegkit.dll"
)

foreach(path ${SEARCH_PATHS})
  if(EXISTS "${path}")
    message(STATUS "DEBUG: Found libffmpegkit.dll at ${path}")
    execute_process(COMMAND ${CMAKE_COMMAND} -E copy_if_different
      "${path}"
      "${CMAKE_BINARY_DIR}/runner/${BUILD_TYPE}"
    )
    return()
  endif()
endforeach()
