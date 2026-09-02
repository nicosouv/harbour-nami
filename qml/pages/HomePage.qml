import QtQuick 2.6
import Sailfish.Silica 1.0
import "../components"
import "../js/faceutils.js" as FaceUtils
import "../js/memories.js" as Memories

// The app's first screen: what there is to look at right now. The full
// people list, with its search and its sort order, is one swipe to the left
// (PeoplePage, attached below).
Page {
    id: page

    allowedOrientations: Orientation.All

    property int totalPeople: 0
    property int totalPhotos: 0

    // Faces the app has found and nobody has named. The one thing the home
    // ever asks of you, and only when there is something to ask: every
    // identification makes the next scan better at guessing.
    property int facesToIdentify: 0

    // Photos on the card that have never been through the pipeline. Counted
    // off the first frame, never in a binding: it is a walk over the whole
    // gallery, names only, but a walk all the same.
    property int photosToScan: 0

    // Nothing has ever been scanned, as opposed to scanned and holding
    // nobody. Two different empty pages: one needs telling what the app is,
    // the other needs telling why it found no one.
    property bool neverScanned: true

    function scanFolders() {
        var raw = facePipeline.getSetting("scan_folders", "")
        return raw.length > 0
            ? raw.split("\n").filter(function (f) { return f.length > 0 })
            : [facePipeline.getSetting("gallery_path", defaultGalleryPath)]
    }

    function startScan() {
        pageStack.push(Qt.resolvedUrl("ScanningPage.qml"))
    }

    // The day's memory, shown full width. One card rather than a carousel:
    // if the app has something worth remembering today it should say so
    // once and loudly, not offer ten equal thumbnails.
    property var heroMemory: null

    // The rest of the memories, which is where trips and busy days surface.
    // A separate feed of "recent events" would be a second source of truth
    // for the same question, and the two would drift.
    property int stripCount: 8

    MemoryLabels {
        id: memoryLabels
    }

    // pushAttached() must happen once and only once. Guarding on
    // pageStack.depth would depend on whether an attached page counts
    // towards it, which is not worth betting the navigation on.
    property bool peopleAttached: false

    // Faces on the home page before the people page takes over. Enough to
    // recognise the household, not enough to become the list itself.
    property int recentPeopleCount: 12

    ListModel {
        id: recentPeopleModel
    }

    ListModel {
        id: memoriesModel
    }

    function refreshMemories() {
        if (!facePipeline || !facePipeline.initialized) return

        // Best first, dismissed ones already left out
        var all = facePipeline.getMemories()
        var heroIndex = Memories.heroIndex(all, new Date())
        heroMemory = heroIndex >= 0 ? all[heroIndex] : null

        // The phrasing is worked out here rather than in the delegates: the
        // translator is installed once at startup, so a title cannot change
        // language while the page is alive, and a delegate that formats
        // dates on every rebind pays for it on every flick
        var shown = 0
        for (var i = 0; i < all.length && shown < stripCount; i++) {
            // Whichever one leads today, not whichever one leads the list
            if (i === heroIndex) continue

            var memory = all[i]
            var item = {
                memory_id: memory.memory_id,
                cover_photo: memory.cover_photo,
                display_title: memoryLabels.title(memory),
                display_subtitle: memoryLabels.subtitle(memory)
            }
            if (shown < memoriesModel.count) {
                memoriesModel.set(shown, item)
            } else {
                memoriesModel.append(item)
            }
            shown++
        }
        while (memoriesModel.count > shown) {
            memoriesModel.remove(memoriesModel.count - 1)
        }
    }

    function openMemory(memoryId, title) {
        pageStack.push(Qt.resolvedUrl("MemoryDetailPage.qml"), {
            memoryId: memoryId,
            title: title
        })
    }

    function refresh() {
        if (!facePipeline || !facePipeline.initialized) return

        var people = facePipeline.getAllPeople()

        totalPeople = people.length
        totalPhotos = 0
        for (var i = 0; i < people.length; i++) {
            totalPhotos += people[i].photo_count
        }

        // Two COUNTs, already computed by the statistics query
        var stats = facePipeline.getStatistics()
        facesToIdentify = stats.unmapped_faces || 0
        neverScanned = (stats.total_photos || 0) === 0

        // Most recently photographed first: a home page is about now, and
        // the person with the biggest back catalogue is not necessarily
        // anyone you saw this year
        people.sort(function (a, b) {
            var aLast = a.last_photo || 0
            var bLast = b.last_photo || 0
            if (aLast !== bLast) return bLast - aLast
            return b.photo_count - a.photo_count
        })

        // Updated in place rather than cleared: this runs on every return to
        // the home page, and clear() would throw the row back to its start
        // every time someone comes back from a person
        var shown = Math.min(people.length, recentPeopleCount)
        for (var j = 0; j < shown; j++) {
            if (j < recentPeopleModel.count) {
                recentPeopleModel.set(j, people[j])
            } else {
                recentPeopleModel.append(people[j])
            }
        }
        while (recentPeopleModel.count > shown) {
            recentPeopleModel.remove(recentPeopleModel.count - 1)
        }
    }

    function openPerson(personId, name) {
        pageStack.push(Qt.resolvedUrl("PersonDetailPage.qml"), {
            personId: personId,
            personName: name
        })
    }

    onStatusChanged: {
        if (status !== PageStatus.Active) return

        if (!peopleAttached) {
            peopleAttached = true
            pageStack.pushAttached(Qt.resolvedUrl("PeoplePage.qml"))
        }
        refresh()
        refreshMemories()
    }

    Component.onCompleted: {
        refresh()
        refreshMemories()
        recipeTimer.start()
    }

    // The recipes run synchronously and walk a good part of the gallery, so
    // they are not something to do before the first frame. Throttled to once
    // a day inside, so this costs one settings lookup on every other launch.
    Timer {
        id: recipeTimer
        interval: 600
        onTriggered: {
            if (!facePipeline || !facePipeline.initialized) return
            if (facePipeline.generateMemories() > 0) {
                refreshMemories()
            }
            // Same reason as above: a walk over the gallery has no business
            // happening before the page has drawn
            photosToScan = facePipeline.unscannedPhotoCount(scanFolders())

            // Asked once, here, for its side effect: the first call opens
            // GStreamer and scans its plugin registry, and that belongs in
            // the same quiet moment as the rest of this rather than in the
            // pull-down of the first memory somebody opens
            facePipeline.canExportVideo()
        }
    }

    Connections {
        target: facePipeline
        onScanCompleted: {
            refresh()
            // A scan is the one moment new photos exist, so it is worth
            // asking the recipes again rather than waiting for tomorrow
            facePipeline.generateMemories(true)
            refreshMemories()
            photosToScan = 0
        }
    }

    SilicaFlickable {
        id: flickable
        anchors.fill: parent
        contentHeight: content.height + Theme.paddingLarge

        PullDownMenu {
            MenuItem { text: qsTr("About"); onClicked: pageStack.push(Qt.resolvedUrl("AboutPage.qml")) }
            MenuItem { text: qsTr("Settings"); onClicked: pageStack.push(Qt.resolvedUrl("SettingsPage.qml")) }
            MenuItem {
                text: qsTr("Memories")
                enabled: facePipeline && facePipeline.initialized
                onClicked: pageStack.push(Qt.resolvedUrl("MemoriesPage.qml"))
            }
            MenuItem {
                text: qsTr("Events")
                enabled: facePipeline && facePipeline.initialized
                onClicked: pageStack.push(Qt.resolvedUrl("EventsPage.qml"))
            }
            MenuItem {
                text: qsTr("Identify Faces")
                enabled: facePipeline && facePipeline.initialized
                onClicked: pageStack.push(Qt.resolvedUrl("IdentifyFacesPage.qml"))
            }
            MenuItem {
                text: qsTr("Scan Gallery")
                enabled: facePipeline && facePipeline.initialized && !facePipeline.processing
                onClicked: pageStack.push(Qt.resolvedUrl("ScanningPage.qml"))
            }
        }

        Column {
            id: content
            width: parent.width
            spacing: Theme.paddingLarge

            PageHeader {
                title: qsTr("Nami")
                // The counts as a quiet line under the title, the way the
                // people list has always shown them
                description: totalPeople > 0
                    ? (totalPeople + " "
                       + (totalPeople === 1 ? qsTr("person") : qsTr("people"))
                       + "  ·  " + totalPhotos + " "
                       + (totalPhotos === 1 ? qsTr("photo") : qsTr("photos")))
                    : ""
            }

            // What the app is, said once, on the empty library. This used to
            // sit above the people list; the home page is where a first
            // launch actually lands.
            // Only on a first launch, and with the one action it needs. A
            // gallery that has been scanned and simply holds nobody is a
            // different page: it does not want the pitch again, it wants to
            // know why nothing was found.
            Column {
                width: parent.width
                spacing: Theme.paddingMedium
                visible: totalPeople === 0 && neverScanned

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    text: qsTr("Face Recognition Gallery")
                    color: Theme.highlightColor
                    font.pixelSize: Theme.fontSizeLarge
                    wrapMode: Text.WordWrap
                }

                Label {
                    x: Theme.horizontalPageMargin
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    text: qsTr("Automatically organize your photos by faces. All processing happens on your device for complete privacy.")
                    color: Theme.secondaryHighlightColor
                    font.pixelSize: Theme.fontSizeSmall
                    wrapMode: Text.WordWrap
                }

                Item { width: 1; height: Theme.paddingMedium }

                // The one screen where a button earns its frame: on a first
                // launch there is exactly one thing to do, and burying it in
                // a pull-down menu asks someone to discover the app before
                // they can start it.
                Button {
                    x: Theme.horizontalPageMargin
                    text: photosToScan > 0
                          ? qsTr("Scan %1 photos").arg(photosToScan)
                          : qsTr("Scan gallery")
                    enabled: facePipeline && facePipeline.initialized
                             && !facePipeline.processing
                    onClicked: startScan()
                }
            }

            // The memory of the day. Full width, no frame, no rounded
            // corners: the photograph is the card.
            //
            // Portrait rather than 16:9, and deliberately more than half the
            // screen. One image with presence beats three blocks that each
            // half-fill their row, and it makes the space below it read as
            // chosen rather than left over.
            Item {
                id: hero
                width: parent.width
                height: width * 1.25
                visible: heroMemory !== null

                Image {
                    id: heroImage
                    anchors.fill: parent
                    source: heroMemory ? "file://" + heroMemory.cover_photo : ""
                    fillMode: Image.PreserveAspectCrop
                    // The only image on the page large enough for the 512px
                    // thumbnail cache to show, so it is decoded from the
                    // original at the size it is drawn
                    sourceSize.width: hero.width
                    autoTransform: true
                    asynchronous: true
                    clip: true
                    opacity: heroArea.pressed ? 0.6 : 1.0
                    Behavior on opacity { FadeAnimation {} }
                }

                // The title has to stay readable over a photo nobody chose
                // for its contrast
                Rectangle {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                    }
                    height: parent.height * 0.6
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "transparent" }
                        GradientStop { position: 1.0; color: Theme.rgba("black", 0.8) }
                    }
                }

                Column {
                    anchors {
                        left: parent.left
                        right: parent.right
                        bottom: parent.bottom
                        leftMargin: Theme.horizontalPageMargin
                        rightMargin: Theme.horizontalPageMargin
                        bottomMargin: Theme.paddingLarge
                    }

                    Label {
                        width: parent.width
                        text: memoryLabels.title(heroMemory)
                        color: "white"
                        font.pixelSize: Theme.fontSizeExtraLarge
                        truncationMode: TruncationMode.Fade
                    }

                    Label {
                        width: parent.width
                        text: memoryLabels.subtitle(heroMemory)
                        color: Theme.rgba("white", 0.7)
                        font.pixelSize: Theme.fontSizeExtraSmall
                        truncationMode: TruncationMode.Fade
                        visible: text.length > 0
                    }
                }

                MouseArea {
                    id: heroArea
                    anchors.fill: parent
                    onClicked: {
                        if (heroMemory) {
                            openMemory(heroMemory.memory_id,
                                       memoryLabels.title(heroMemory))
                        }
                    }
                }
            }

            // Everything else the recipes found: trips, busy days, people.
            // No section heading, same reasoning as the people row below.
            ListView {
                id: memoryStrip

                property real cardWidth: page.width * 0.44

                width: parent.width
                height: cardWidth * 0.66 + Theme.itemSizeExtraSmall
                visible: count > 0

                orientation: ListView.Horizontal
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                spacing: Theme.paddingMedium
                clip: true
                model: memoriesModel

                header: Item { width: Theme.horizontalPageMargin; height: 1 }
                footer: Item { width: Theme.horizontalPageMargin; height: 1 }

                delegate: BackgroundItem {
                    id: memoryCard
                    width: memoryStrip.cardWidth
                    height: memoryStrip.height

                    Column {
                        width: parent.width
                        spacing: Theme.paddingSmall

                        Image {
                            width: parent.width
                            height: memoryStrip.cardWidth * 0.66
                            source: FaceUtils.thumbUrl(model.cover_photo)
                            fillMode: Image.PreserveAspectCrop
                            autoTransform: true
                            clip: true
                            asynchronous: true
                        }

                        Label {
                            width: parent.width
                            text: model.display_title
                            color: memoryCard.highlighted ? Theme.highlightColor
                                                          : Theme.primaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            truncationMode: TruncationMode.Fade
                        }
                    }

                    onClicked: openMemory(model.memory_id, model.display_title)
                }
            }

            // No heading above this row on purpose: a line of faces says what
            // it is, and a label would only push the content further down.
            ListView {
                id: peopleRow

                property real cellSize: Theme.itemSizeLarge

                width: parent.width
                height: cellSize + Theme.itemSizeExtraSmall
                visible: count > 0

                orientation: ListView.Horizontal
                // Nested in a vertical flickable: without pinning the
                // direction the two fight over every drag and neither moves
                flickableDirection: Flickable.HorizontalFlick
                boundsBehavior: Flickable.StopAtBounds
                spacing: Theme.paddingMedium
                clip: true
                model: recentPeopleModel

                // Page margins as header and footer rather than as ListView
                // margins, which do not exist on every Qt version this runs on
                header: Item { width: Theme.horizontalPageMargin; height: 1 }
                footer: Item { width: Theme.horizontalPageMargin; height: 1 }

                delegate: BackgroundItem {
                    id: personItem
                    width: peopleRow.cellSize
                    height: peopleRow.height

                    Column {
                        anchors.centerIn: parent
                        width: parent.width
                        spacing: Theme.paddingSmall

                        Item {
                            width: peopleRow.cellSize
                            height: width

                            Image {
                                id: avatar
                                anchors.fill: parent
                                source: FaceUtils.personAvatarUrl(facePipeline, model.person_id)
                                sourceSize.width: width
                                sourceSize.height: height
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }

                            Image {
                                anchors.centerIn: parent
                                source: "image://theme/icon-m-contact"
                                width: Theme.iconSizeMedium
                                height: width
                                sourceSize.width: width
                                sourceSize.height: height
                                visible: avatar.status !== Image.Ready
                                opacity: 0.4
                            }
                        }

                        Label {
                            width: parent.width
                            text: model.name || qsTr("Unknown")
                            color: personItem.highlighted ? Theme.highlightColor
                                                          : Theme.primaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            truncationMode: TruncationMode.Fade
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }

                    onClicked: openPerson(model.person_id, model.name)
                }
            }

            // What the home asks of you, and only while there is something
            // to ask. A row that is always there is a row nobody reads;
            // these appearing mean there is work waiting, and them going
            // away means there is none.
            //
            // The icon rather than an emoji: it is drawn in the theme's own
            // colour and at the theme's own size, so it belongs to the page
            // instead of being pasted onto it.
            Column {
                width: parent.width
                spacing: 0

                ActionLine {
                    width: parent.width
                    visible: photosToScan > 0 && !neverScanned
                    icon: "image://theme/icon-m-image"
                    text: photosToScan === 1
                          ? qsTr("1 new photo to scan")
                          : qsTr("%1 new photos to scan").arg(photosToScan)
                    onClicked: startScan()
                }

                ActionLine {
                    width: parent.width
                    visible: facesToIdentify > 0
                    icon: "image://theme/icon-m-people"
                    text: facesToIdentify === 1
                          ? qsTr("1 face to identify")
                          : qsTr("%1 faces to identify").arg(facesToIdentify)
                    onClicked: pageStack.push(Qt.resolvedUrl("IdentifyFacesPage.qml"))
                }
            }
        }

        // Only for a gallery that has been through the pipeline and holds
        // nobody. A first launch is answered above, by the block that says
        // what the app is and offers the one button that starts it.
        ViewPlaceholder {
            enabled: totalPeople === 0 && !neverScanned
            text: qsTr("No faces found")
            hintText: qsTr("Check which folders are scanned in Settings")
        }

        VerticalScrollDecorator {}
    }
}
