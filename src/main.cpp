#ifdef QT_QML_DEBUG
#include <QtQuick>
#endif

#include <QGuiApplication>
#include <QQuickView>
#include <QQmlContext>
#include <QQmlEngine>
#include <QStandardPaths>
#include <QDir>
#include <QCoreApplication>

#include "facepipeline.h"
#include "facedetector.h"
#include "facerecognizer.h"
#include "facedatabase.h"

int main(int argc, char *argv[])
{
    // Setup application
    QScopedPointer<QGuiApplication> app(new QGuiApplication(argc, argv));
    app->setApplicationName("harbour-nami");
    app->setOrganizationName("harbour-nami");

    // Create QML view
    QScopedPointer<QQuickView> view(new QQuickView);

    // Get application data paths
    QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QString cacheDir = QStandardPaths::writableLocation(QStandardPaths::CacheLocation);
    QString picturesDir = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);

    // Create directories if needed
    QDir().mkpath(dataDir);
    QDir().mkpath(cacheDir);

    // Model paths (bundled with app)
    QString appDir = QCoreApplication::applicationDirPath() + "/../share/harbour-nami";
    QString detectorModelPath = appDir + "/models/face_detection_yunet_2023mar.onnx";
    QString recognizerModelPath = appDir + "/models/arcface_mobilefacenet.onnx";
    QString databasePath = dataDir + "/nami.db";

    qDebug() << "=== Harbour Nami Face Recognition ===";
    qDebug() << "Application directory:" << appDir;
    qDebug() << "Data directory:" << dataDir;
    qDebug() << "Cache directory:" << cacheDir;
    qDebug() << "Pictures directory:" << picturesDir;
    qDebug() << "Detector model:" << detectorModelPath;
    qDebug() << "Recognizer model:" << recognizerModelPath;
    qDebug() << "Database:" << databasePath;

    // Create face pipeline
    FacePipeline *pipeline = new FacePipeline(app.data());

    // Initialize pipeline
    bool initialized = pipeline->initialize(
        detectorModelPath,
        recognizerModelPath,
        databasePath
    );

    if (!initialized) {
        qCritical() << "Failed to initialize face pipeline!";
        qCritical() << "Make sure ML models are present in:" << appDir + "/models/";
        // Continue anyway - QML will show error page
    }

    // Expose to QML
    view->rootContext()->setContextProperty("facePipeline", pipeline);
    view->rootContext()->setContextProperty("appDataDir", dataDir);
    view->rootContext()->setContextProperty("appCacheDir", cacheDir);
    view->rootContext()->setContextProperty("defaultGalleryPath", picturesDir);

    // Set QML source
    view->setSource(QUrl::fromLocalFile(appDir + "/qml/harbour-nami.qml"));

    // Show view
    view->showFullScreen();

    return app->exec();
}
