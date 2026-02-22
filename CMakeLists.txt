cmake_minimum_required(VERSION 3.10)

# Make sure this matches ./NAM/version.h!
project(NAM VERSION 0.4.0)

set(CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED OFF)
set(CMAKE_CXX_EXTENSIONS OFF)

# Use libc++ on macOS, system default on Linux
if (CMAKE_SYSTEM_NAME STREQUAL "Darwin" OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
	set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -stdlib=libc++")
endif()

if (CMAKE_SYSTEM_NAME STREQUAL "Darwin" OR CMAKE_SYSTEM_NAME STREQUAL "iOS")
	include_directories(SYSTEM /usr/local/include)
elseif (CMAKE_SYSTEM_NAME STREQUAL "Linux")
	link_libraries(stdc++fs)
elseif (CMAKE_SYSTEM_NAME STREQUAL "Windows")
	add_compile_definitions(NOMINMAX WIN32_LEAN_AND_MEAN)
else()
	message(FATAL_ERROR "Unrecognized Platform!")
endif()

set(NAM_DEPS_PATH "${CMAKE_CURRENT_SOURCE_DIR}/Dependencies")
include_directories(SYSTEM "${NAM_DEPS_PATH}/eigen")

if (CMAKE_SYSTEM_NAME STREQUAL "iOS")
	# For iOS, build NAM as a static library instead of command-line tools
	file(GLOB_RECURSE NAM_SOURCES NAM/*.cpp NAM/*.c NAM/*.h)
	add_library(NAM STATIC ${NAM_SOURCES})
	target_include_directories(NAM PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
	target_include_directories(NAM SYSTEM PUBLIC
		${NAM_DEPS_PATH}/eigen
		${NAM_DEPS_PATH}/nlohmann
	)
	target_compile_features(NAM PUBLIC cxx_std_20)
	set_target_properties(NAM PROPERTIES
		CXX_VISIBILITY_PRESET hidden
		INTERPROCEDURAL_OPTIMIZATION TRUE
	)
else()
	add_subdirectory(tools)
endif()

#file(MAKE_DIRECTORY build/tools)

#add_custom_target(copy_tools ALL
#	${CMAKE_COMMAND} -E copy "$<TARGET_FILE:tools>" tools/
#	DEPENDS tools
#)
