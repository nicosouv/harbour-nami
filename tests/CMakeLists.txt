# Tests build on their own, without the app.
#
#   cmake -S tests -B build-tests && cmake --build build-tests && ctest --test-dir build-tests
#
# Nothing here needs OpenCV or the ML models, so it runs on any machine with
# Qt5 - no Sailfish SDK, no cross-compilation, no device.
cmake_minimum_required(VERSION 3.5)
project(harbour-nami-tests LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt5 REQUIRED COMPONENTS Core Sql Test)
find_package(OpenSSL REQUIRED)

enable_testing()

set(NAMI_SRC ${CMAKE_CURRENT_LIST_DIR}/../src)

# Storage layer: schema, backup format, suggestion helpers
add_executable(tst_facedatabase
    ${CMAKE_CURRENT_LIST_DIR}/tst_facedatabase.cpp
    ${NAMI_SRC}/facedatabase.cpp
    ${NAMI_SRC}/logging.cpp
)
target_include_directories(tst_facedatabase PRIVATE ${NAMI_SRC})
target_link_libraries(tst_facedatabase Qt5::Core Qt5::Sql Qt5::Test)
add_test(NAME facedatabase COMMAND tst_facedatabase)

# Memories storage: idempotent regeneration and what the user owns of it
add_executable(tst_memories
    ${CMAKE_CURRENT_LIST_DIR}/tst_memories.cpp
    ${NAMI_SRC}/facedatabase.cpp
    ${NAMI_SRC}/logging.cpp
)
target_include_directories(tst_memories PRIVATE ${NAMI_SRC})
target_link_libraries(tst_memories Qt5::Core Qt5::Sql Qt5::Test)
add_test(NAME memories COMMAND tst_memories)

# Backup encryption: a bug here loses someone's whole library
add_executable(tst_backupcrypto
    ${CMAKE_CURRENT_LIST_DIR}/tst_backupcrypto.cpp
    ${NAMI_SRC}/backupcrypto.cpp
)
target_include_directories(tst_backupcrypto PRIVATE ${NAMI_SRC})
target_link_libraries(tst_backupcrypto Qt5::Core Qt5::Test OpenSSL::Crypto)
add_test(NAME backupcrypto COMMAND tst_backupcrypto)
