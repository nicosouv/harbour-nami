import QtQuick 2.0
import Sailfish.Silica 1.0

Page {
    id: page

    allowedOrientations: Orientation.All

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        VerticalScrollDecorator {}

        Column {
            id: column
            width: page.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("About")
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            Image {
                anchors.horizontalCenter: parent.horizontalCenter
                // App launcher icon (resolved from hicolor by the theme)
                source: "image://theme/harbour-nami"
                width: Theme.iconSizeLauncher * 2
                height: width
                sourceSize.width: width
                sourceSize.height: height
            }

            Item {
                width: parent.width
                height: Theme.paddingMedium
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Nami"
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeHuge
            }

            Label {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "v" + appVersion
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeMedium
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Face Recognition Gallery")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Intelligent photo organization using on-device face recognition")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            SectionHeader {
                text: qsTr("Features")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: "• " + qsTr("100% on-device processing, no internet required") + "\n" +
                      "• " + qsTr("Automatic face detection and recognition") + "\n" +
                      "• " + qsTr("People gallery in list or grid layout") + "\n" +
                      "• " + qsTr("Link people to your device contacts") + "\n" +
                      "• " + qsTr("Events grouped by day, with multi-day trips and an offline route map") + "\n" +
                      "• " + qsTr("Memories from previous years, plus a year-by-year recap") + "\n" +
                      "• " + qsTr("Scan folders of your choice, SD card included") + "\n" +
                      "• " + qsTr("Data export and full deletion (GDPR)")
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            SectionHeader {
                text: qsTr("Technology")
            }

            DetailItem {
                label: qsTr("Platform")
                value: "Sailfish OS"
            }

            DetailItem {
                label: qsTr("Framework")
                value: "Qt 5 / Silica"
            }

            DetailItem {
                label: qsTr("ML Engine")
                value: "OpenCV / ONNX"
            }

            SectionHeader {
                text: qsTr("Contributors")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Thanks to Frank Paul Silye for the Norwegian Bokmål translation")
                color: Theme.primaryColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            SectionHeader {
                text: qsTr("Clip music")
            }

            // Pixabay asks for no attribution. The links are here anyway:
            // somebody wrote this music, and a clip made with it says so
            // nowhere else.
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("The four soundtracks come from Pixabay and are free to use.")
                color: Theme.secondaryColor
                font.pixelSize: Theme.fontSizeExtraSmall
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: [
                    { style: qsTr("Sentimental"),
                      url: "https://pixabay.com/music/acoustic-group-warm-nostalgic-sentimental-music-471262/" },
                    { style: qsTr("Energetic"),
                      url: "https://pixabay.com/music/upbeat-energetic-energetic-music-507828/" },
                    { style: qsTr("Polaroid"),
                      url: "https://pixabay.com/music/beats-polaroid-lo-fi-515821/" },
                    { style: qsTr("Bauhaus"),
                      url: "https://pixabay.com/music/corporate-hi-tech-loop-151203/" }
                ]

                delegate: BackgroundItem {
                    width: parent.width
                    height: Theme.itemSizeExtraSmall

                    Label {
                        x: Theme.horizontalPageMargin
                        width: parent.width - 2 * Theme.horizontalPageMargin
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.style
                        color: highlighted ? Theme.highlightColor : Theme.primaryColor
                        font.pixelSize: Theme.fontSizeSmall
                        truncationMode: TruncationMode.Fade
                    }

                    onClicked: Qt.openUrlExternally(modelData.url)
                }
            }

            SectionHeader {
                text: qsTr("License")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Open Source Software")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
            }

            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Source Code")
                onClicked: Qt.openUrlExternally("https://github.com/nicosouv/harbour-nami")
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }
    }
}
