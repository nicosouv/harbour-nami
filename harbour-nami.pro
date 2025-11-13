TARGET = harbour-nami

CONFIG += sailfishapp

QT += concurrent multimedia

SOURCES += src/harbour-nami.cpp

DISTFILES += qml/harbour-nami.qml \
    qml/cover/CoverPage.qml \
    qml/pages/MainPage.qml \
    qml/pages/SettingsPage.qml \
    qml/pages/AboutPage.qml \
    qml/pages/ScanningPage.qml \
    qml/pages/PersonPage.qml \
    qml/pages/UnknownFacesPage.qml \
    qml/components/InfoBanner.qml \
    qml/components/FaceRecognitionManager.qml \
    qml/dialogs/ConfirmDialog.qml \
    qml/dialogs/RenamePersonDialog.qml \
    qml/dialogs/IdentifyFaceDialog.qml \
    python/*.py \
    python/models/*.md \
    rpm/harbour-nami.changes \
    rpm/harbour-nami.spec \
    rpm/harbour-nami.yaml \
    translations/*.ts \
    harbour-nami.desktop

SAILFISHAPP_ICONS = 86x86 108x108 128x128 172x172

CONFIG += sailfishapp_i18n

TRANSLATIONS += translations/harbour-nami-de.ts \
                translations/harbour-nami-fr.ts \
                translations/harbour-nami-it.ts \
                translations/harbour-nami-es.ts \
                translations/harbour-nami-fi.ts

# Install Python files
python.files = python
python.path = /usr/share/$${TARGET}
INSTALLS += python
