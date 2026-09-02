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

find_package(Qt5 REQUIRED COMPONENTS Core Gui Quick Sql Test)
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

# The edit decision list: where the cuts fall and where the camera looks.
# No pixels, no files, no database, which is the point of it.
add_executable(tst_memorycomposer
    ${CMAKE_CURRENT_LIST_DIR}/tst_memorycomposer.cpp
    ${NAMI_SRC}/memorycomposer.cpp
    ${NAMI_SRC}/memorystyle.cpp
    ${NAMI_SRC}/beatgrid.cpp
)
target_include_directories(tst_memorycomposer PRIVATE ${NAMI_SRC})
target_link_libraries(tst_memorycomposer Qt5::Core Qt5::Gui Qt5::Test)
add_test(NAME memorycomposer COMMAND tst_memorycomposer)

# Drawing the frames and picking what to compress them with. No GStreamer
# here: the library is opened by name at runtime, so this links against Qt
# alone and the choice of encoder is tested as what it is, a decision about
# a set of names.
add_executable(tst_clipexport
    ${CMAKE_CURRENT_LIST_DIR}/tst_clipexport.cpp
    ${NAMI_SRC}/cliprenderer.cpp
    ${NAMI_SRC}/encoder.cpp
    ${NAMI_SRC}/gstencoder.cpp
    ${NAMI_SRC}/memoryexporter.cpp
    ${NAMI_SRC}/memorycomposer.cpp
    ${NAMI_SRC}/memorystyle.cpp
    ${NAMI_SRC}/beatgrid.cpp
    ${NAMI_SRC}/logging.cpp
)
target_include_directories(tst_clipexport PRIVATE ${NAMI_SRC})
target_link_libraries(tst_clipexport Qt5::Core Qt5::Gui Qt5::Test)
add_test(NAME clipexport COMMAND tst_clipexport)

# The six recipes that decide what the app offers to remember
add_executable(tst_memorygenerator
    ${CMAKE_CURRENT_LIST_DIR}/tst_memorygenerator.cpp
    ${NAMI_SRC}/memorygenerator.cpp
    ${NAMI_SRC}/facedatabase.cpp
    ${NAMI_SRC}/logging.cpp
)
target_include_directories(tst_memorygenerator PRIVATE ${NAMI_SRC})
target_link_libraries(tst_memorygenerator Qt5::Core Qt5::Sql Qt5::Test)
add_test(NAME memorygenerator COMMAND tst_memorygenerator)

# EXIF dates: they decide which day every photo belongs to
add_executable(tst_exifreader
    ${CMAKE_CURRENT_LIST_DIR}/tst_exifreader.cpp
    ${NAMI_SRC}/exifreader.cpp
)
target_include_directories(tst_exifreader PRIVATE ${NAMI_SRC})
target_link_libraries(tst_exifreader Qt5::Core Qt5::Test)
add_test(NAME exifreader COMMAND tst_exifreader)

# Content hashes: what relinks a moved photo when a backup is restored
add_executable(tst_filehash
    ${CMAKE_CURRENT_LIST_DIR}/tst_filehash.cpp
    ${NAMI_SRC}/filehash.cpp
)
target_include_directories(tst_filehash PRIVATE ${NAMI_SRC})
target_link_libraries(tst_filehash Qt5::Core Qt5::Test)
add_test(NAME filehash COMMAND tst_filehash)

# Face crops: the geometry behind every avatar and thumbnail in the app
add_executable(tst_faceimageprovider
    ${CMAKE_CURRENT_LIST_DIR}/tst_faceimageprovider.cpp
    ${NAMI_SRC}/faceimageprovider.cpp
    ${NAMI_SRC}/logging.cpp
)
target_include_directories(tst_faceimageprovider PRIVATE ${NAMI_SRC})
target_link_libraries(tst_faceimageprovider Qt5::Core Qt5::Gui Qt5::Quick Qt5::Test)
add_test(NAME faceimageprovider COMMAND tst_faceimageprovider)

# The recognition engine end to end. Off by default: it is the only target
# that needs OpenCV (>= 4.8, the 4.6 DNN importer cannot read YuNet 2023mar),
# the ML models and the reference portraits, which is the whole reason the
# rest of this suite is kept free of them.
#
#   docker compose run --rm pipeline
#
option(WITH_PIPELINE_TESTS "Build the OpenCV recognition test" OFF)

if(WITH_PIPELINE_TESTS)
    find_package(OpenCV REQUIRED COMPONENTS core imgproc dnn objdetect)

    add_executable(tst_pipeline
        ${CMAKE_CURRENT_LIST_DIR}/tst_pipeline.cpp
        ${NAMI_SRC}/facedetector.cpp
        ${NAMI_SRC}/facerecognizer.cpp
        ${NAMI_SRC}/facedatabase.cpp
        ${NAMI_SRC}/logging.cpp
    )
    target_include_directories(tst_pipeline PRIVATE ${NAMI_SRC} ${OpenCV_INCLUDE_DIRS})
    target_compile_definitions(tst_pipeline PRIVATE
        NAMI_MODELS_DIR="${CMAKE_CURRENT_LIST_DIR}/../python/models"
        NAMI_FIXTURES_DIR="${CMAKE_CURRENT_LIST_DIR}/fixtures"
    )
    target_link_libraries(tst_pipeline
        Qt5::Core Qt5::Gui Qt5::Sql Qt5::Test ${OpenCV_LIBS})
    add_test(NAME pipeline COMMAND tst_pipeline)
else()
    message(STATUS "Recognition test off (-DWITH_PIPELINE_TESTS=ON to enable)")
endif()

# Backup encryption: a bug here loses someone's whole library
add_executable(tst_backupcrypto
    ${CMAKE_CURRENT_LIST_DIR}/tst_backupcrypto.cpp
    ${NAMI_SRC}/backupcrypto.cpp
)
target_include_directories(tst_backupcrypto PRIVATE ${NAMI_SRC})
target_link_libraries(tst_backupcrypto Qt5::Core Qt5::Test OpenSSL::Crypto)
add_test(NAME backupcrypto COMMAND tst_backupcrypto)
