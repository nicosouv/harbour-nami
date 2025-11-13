cmake_minimum_required(VERSION 3.5)

project(harbour-nami VERSION 0.2.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

# Find Qt5
find_package(Qt5 REQUIRED COMPONENTS Core Gui Qml Quick Sql Concurrent)

# Find OpenCV
find_package(OpenCV REQUIRED COMPONENTS core imgproc dnn)

# ONNX Runtime - manual for now (will be bundled)
set(ONNXRUNTIME_INCLUDE_DIR "${CMAKE_SOURCE_DIR}/3rdparty/onnxruntime/include")
set(ONNXRUNTIME_LIB_DIR "${CMAKE_SOURCE_DIR}/3rdparty/onnxruntime/lib")

# Sources
set(SOURCES
    src/main.cpp
    src/facedetector.cpp
    src/facerecognizer.cpp
    src/facedatabase.cpp
    src/facepipeline.cpp
)

# Headers
set(HEADERS
    src/facedetector.h
    src/facerecognizer.h
    src/facedatabase.h
    src/facepipeline.h
)

# QML files
set(QML_FILES
    qml/harbour-nami.qml
    qml/pages/MainPage.qml
    qml/pages/PhotoGridPage.qml
    qml/pages/PersonDetailPage.qml
    qml/pages/UnknownFacesPage.qml
    qml/pages/SettingsPage.qml
    qml/pages/ScanningPage.qml
    qml/components/FaceRecognitionManager.qml
    qml/components/PhotoThumbnail.qml
    qml/components/FaceThumbnail.qml
    qml/cover/CoverPage.qml
)

# Create executable
add_executable(${PROJECT_NAME}
    ${SOURCES}
    ${HEADERS}
)

# Include directories
target_include_directories(${PROJECT_NAME} PRIVATE
    ${CMAKE_SOURCE_DIR}/src
    ${ONNXRUNTIME_INCLUDE_DIR}
    ${OpenCV_INCLUDE_DIRS}
)

# Link libraries
target_link_libraries(${PROJECT_NAME}
    Qt5::Core
    Qt5::Gui
    Qt5::Qml
    Qt5::Quick
    Qt5::Sql
    Qt5::Concurrent
    ${OpenCV_LIBS}
    ${ONNXRUNTIME_LIB_DIR}/libonnxruntime.so
)

# Installation
install(TARGETS ${PROJECT_NAME}
    RUNTIME DESTINATION bin
)

install(DIRECTORY qml
    DESTINATION share/${PROJECT_NAME}
)

install(DIRECTORY translations
    DESTINATION share/${PROJECT_NAME}
    FILES_MATCHING PATTERN "*.qm"
)

install(DIRECTORY python/models
    DESTINATION share/${PROJECT_NAME}
    FILES_MATCHING PATTERN "*.onnx"
)

install(FILES harbour-nami.desktop
    DESTINATION share/applications
)

# Desktop file validation
find_program(DESKTOP_FILE_VALIDATE desktop-file-validate)
if(DESKTOP_FILE_VALIDATE)
    add_custom_target(validate_desktop ALL
        COMMAND ${DESKTOP_FILE_VALIDATE} ${CMAKE_SOURCE_DIR}/harbour-nami.desktop
    )
endif()
