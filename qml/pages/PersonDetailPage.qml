import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.DBus 2.0
import "../components"
import "../js/faceutils.js" as FaceUtils
import "../js/mosaic.js" as Mosaic

Page {
    id: page

    property int personId: -1
    property string personName: ""
    property string contactId: ""
    property var faceManager: facePipeline

    // Full photo list as returned by the pipeline (already newest first).
    // visiblePhotos is the filtered/sorted view, photoRows its mosaic layout.
    // Plain arrays rather than a ListModel: the layout needs a computed width
    // and height per photo, which are not model roles, and this keeps
    // ListModel.get() out of the delegates entirely.
    property var allPhotos: []
    property var visiblePhotos: []
    // [{ title, rows }] - the mosaic, cut into month sections
    property var photoGroups: []
    property bool newestFirst: true
    // Kept as plain properties (not functions) so bindings actually re-evaluate
    property int totalPhotos: 0
    property int unconfirmedTotal: 0

    allowedOrientations: Orientation.All

    function loadContact() {
        if (faceManager && faceManager.initialized && personId >= 0) {
            contactId = faceManager.personContactId(personId)
        }
    }

    // People app UI (Contacts permission grants talk access)
    DBusInterface {
        id: contactsUi
        bus: DBus.SessionBus
        service: "com.jolla.contacts.ui"
        path: "/com/jolla/contacts/ui"
        iface: "com.jolla.contacts.ui"
    }

    function openReview() {
        var review = pageStack.push(Qt.resolvedUrl("ReviewMatchesPage.qml"), {
            personId: personId,
            personName: personName
        })
        // Only reload when something was actually decided
        review.statusChanged.connect(function() {
            if (review.status === PageStatus.Deactivating && review.changed) {
                loadPhotos()
            }
        })
    }

    function openInContacts() {
        var cid = parseInt(contactId)
        if (cid > 0) {
            contactsUi.typedCall("showContact", { "type": "i", "value": cid })
        }
    }

    function loadPhotos() {
        if (!faceManager || !faceManager.initialized || personId < 0) return

        allPhotos = faceManager.getPersonPhotos(personId)
        rebuildPhotoModel()
    }

    // Built once per opening: the viewer browses the whole list, so the
    // tapped photo is just where it starts.
    function openViewer(path) {
        var paths = browsePaths()
        pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"), {
            photoPaths: paths,
            photoIndex: Math.max(0, paths.indexOf(path))
        })
    }

    // The order shown is the order to browse in
    function browsePaths() {
        var paths = []
        for (var i = 0; i < visiblePhotos.length; i++) {
            paths.push(visiblePhotos[i].file_path)
        }
        return paths
    }

    function recountTotals() {
        var unconfirmed = 0
        for (var i = 0; i < allPhotos.length; i++) {
            if (allPhotos[i].verified !== true) unconfirmed++
        }
        totalPhotos = allPhotos.length
        unconfirmedTotal = unconfirmed
    }

    // Rebuild the visible list from allPhotos. getPersonPhotos() already sorts
    // newest first, so "oldest first" is just a reversal.
    function rebuildPhotoModel() {
        var visible = allPhotos.slice()
        recountTotals()

        if (!newestFirst) {
            visible.reverse()
        }

        visiblePhotos = visible
        rebuildRows()
    }

    // Month of a photo, as the section it belongs under. Photos whose date
    // never made it into the file get an untitled section at the end rather
    // than a heading claiming they were taken in 1970.
    function sectionOf(photo) {
        if (!photo.timestamp) return ""
        return Qt.formatDate(new Date(photo.timestamp * 1000), "MMMM yyyy")
    }

    // Sections give the page a chronology to read. Without them it is a wall
    // of tiles with nothing to say about itself.
    function rebuildRows() {
        var avail = photoArea.width - 2 * Theme.horizontalPageMargin
        if (avail <= 0) {
            photoGroups = []
            return
        }
        var targetHeight = avail / 3

        var groups = []
        var bucket = []
        var bucketTitle = null

        function flush() {
            if (bucket.length === 0) return
            groups.push({
                title: bucketTitle,
                rows: Mosaic.layout(bucket, avail, targetHeight, Theme.paddingSmall)
            })
            bucket = []
        }

        for (var i = 0; i < visiblePhotos.length; i++) {
            var title = sectionOf(visiblePhotos[i])
            // visiblePhotos is already in date order, so equal keys are
            // always adjacent and one pass is enough
            if (bucketTitle !== null && title !== bucketTitle) {
                flush()
            }
            bucketTitle = title
            bucket.push(visiblePhotos[i])
        }
        flush()

        photoGroups = groups
    }

    function dropRow(photoId) {
        var remaining = []
        for (var i = 0; i < visiblePhotos.length; i++) {
            if (visiblePhotos[i].photo_id !== photoId) {
                remaining.push(visiblePhotos[i])
            }
        }
        visiblePhotos = remaining
        recountTotals()
        rebuildRows()
    }

    // The remorse lives on the page, not on the photo's delegate: the action
    // removes that photo from the model, which destroys the very item a
    // ListItem remorse would be attached to. Its callback is defined here too,
    // so it does not outlive the context menu that triggered it.
    function removePhotoFromPerson(photoId) {
        Remorse.popupAction(page, qsTr("Removing"), function() {
            if (!facePipeline.removePersonFromPhoto(personId, photoId)) {
                return
            }
            forgetPhoto(photoId)
            dropRow(photoId)
        })
    }

    // Drop a photo from the backing list too, otherwise it reappears on the
    // next filter/sort toggle.
    function forgetPhoto(photoId) {
        var remaining = []
        for (var i = 0; i < allPhotos.length; i++) {
            if (allPhotos[i].photo_id !== photoId) {
                remaining.push(allPhotos[i])
            }
        }
        allPhotos = remaining
    }

    onNewestFirstChanged: rebuildPhotoModel()

    Component.onCompleted: {
        loadPhotos()
        loadContact()
    }

    PhotoShareAction { id: shareAction }
    PhotoSelection { id: selection }

    function setPhotoConfirmed(faceId, photoId, confirmed) {
        var changed = confirmed ? facePipeline.confirmFace(faceId)
                                : facePipeline.unconfirmFace(faceId)
        if (!changed) return

        // Update the backing list in place so the grid does not jump
        for (var i = 0; i < allPhotos.length; i++) {
            if (allPhotos[i].photo_id === photoId) {
                allPhotos[i].verified = confirmed
                break
            }
        }
        rebuildPhotoModel()
    }

    SilicaFlickable {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            bottom: selectionBar.top
        }
        clip: true
        contentHeight: column.height

        PullDownMenu {
            // Selection and sorting live on the page itself; only actions that
            // apply to the person as a whole stay here.
            MenuItem {
                text: qsTr("Select photos")
                enabled: visiblePhotos.length > 0 && !selection.active
                onClicked: selection.begin("")
            }
            MenuItem {
                text: qsTr("Confirm all matches")
                enabled: unconfirmedTotal > 0
                onClicked: {
                    var confirmed = facePipeline.confirmAllFaces(personId)
                    if (confirmed > 0) {
                        loadPhotos()
                    }
                }
            }
            MenuItem {
                text: qsTr("Rename")
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/RenamePersonDialog.qml"), {
                        personId: personId,
                        currentName: personName
                    })
                    dialog.accepted.connect(function() {
                        facePipeline.updatePersonName(personId, dialog.newName)
                        personName = dialog.newName
                    })
                }
            }
            MenuItem {
                text: contactId.length > 0 ? qsTr("Change linked contact") : qsTr("Link to contact")
                visible: facePipeline.contactsEnabled
                onClicked: {
                    var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/SelectContactDialog.qml"), {
                        personName: personName
                    })
                    dialog.accepted.connect(function() {
                        // Same contact already linked to another person:
                        // most likely duplicates, offer to merge
                        var existingId = -1
                        var existingName = ""
                        var people = facePipeline.getAllPeople()
                        for (var i = 0; i < people.length; i++) {
                            if (people[i].contact_id === dialog.selectedContactId
                                    && people[i].person_id !== personId) {
                                existingId = people[i].person_id
                                existingName = people[i].name
                                break
                            }
                        }

                        if (existingId > 0) {
                            pageStack.completeAnimation()
                            var confirm = pageStack.push(Qt.resolvedUrl("../dialogs/ConfirmDialog.qml"), {
                                title: qsTr("Merge duplicates?"),
                                message: qsTr("%1 is already linked to this contact. Merge %2 into %1?").arg(existingName).arg(personName)
                            })
                            confirm.accepted.connect(function() {
                                facePipeline.mergePersons(personId, existingId)
                                pageStack.pop()
                            })
                            confirm.rejected.connect(function() {
                                facePipeline.linkPersonToContact(personId, dialog.selectedContactId)
                                contactId = dialog.selectedContactId
                                if (dialog.selectedContactName.length > 0) {
                                    facePipeline.updatePersonName(personId, dialog.selectedContactName)
                                    personName = dialog.selectedContactName
                                }
                            })
                        } else {
                            facePipeline.linkPersonToContact(personId, dialog.selectedContactId)
                            contactId = dialog.selectedContactId
                            // Adopt the contact's name for the person
                            if (dialog.selectedContactName.length > 0) {
                                facePipeline.updatePersonName(personId, dialog.selectedContactName)
                                personName = dialog.selectedContactName
                            }
                        }
                    })
                }
            }
            MenuItem {
                text: qsTr("Unlink contact")
                visible: facePipeline.contactsEnabled && contactId.length > 0
                onClicked: {
                    facePipeline.linkPersonToContact(personId, "")
                    contactId = ""
                }
            }
            MenuItem {
                text: qsTr("Delete")
                onClicked: {
                    Remorse.popupAction(page, qsTr("Deleting %1").arg(personName), function() {
                        facePipeline.deletePerson(personId)
                        pageStack.pop()
                    })
                }
            }
        }

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingLarge

            SectionHeader {
                section: "people"
                id: header
                title: personName

                // The face, next to the name: on the previous page every
                // person has a portrait, and tapping through to their own
                // page used to be the one place they disappeared from.
                Image {
                    anchors {
                        left: parent.left
                        leftMargin: Theme.horizontalPageMargin
                        verticalCenter: parent.verticalCenter
                    }
                    width: Theme.itemSizeSmall
                    height: width
                    source: FaceUtils.personAvatarUrl(facePipeline, personId)
                    sourceSize.width: width
                    sourceSize.height: height
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready
                }

                // Counts as a quiet line under the title rather than a boxed
                // panel: a frame is ornament, hierarchy comes from position.
                description: {
                    var parts = [totalPhotos + " "
                                 + (totalPhotos === 1 ? qsTr("photo") : qsTr("photos"))]
                    if (unconfirmedTotal > 0) {
                        parts.push(qsTr("%n to confirm", "", unconfirmedTotal))
                    }
                    return parts.join("  \u00b7  ")
                }
            }

            // Linked contact indicator + shortcut to the People app
            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                visible: contactId.length > 0 && facePipeline.contactsEnabled
                onClicked: openInContacts()

                Row {
                    anchors {
                        left: parent.left
                        leftMargin: Theme.horizontalPageMargin
                        right: parent.right
                        rightMargin: Theme.horizontalPageMargin
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: Theme.paddingMedium

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "image://theme/icon-m-contact"
                        color: Theme.highlightColor
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Open in Contacts")
                        color: Theme.highlightColor
                    }
                }
            }

            // The one thing that wants doing on this page, when there is
            // anything to do. Reviewing happens on its own screen, where a
            // face is big enough to actually recognise.
            BackgroundItem {
                width: parent.width
                height: Theme.itemSizeSmall
                visible: unconfirmedTotal > 0 && !selection.active
                onClicked: openReview()

                Row {
                    anchors {
                        left: parent.left
                        leftMargin: Theme.horizontalPageMargin
                        right: parent.right
                        rightMargin: Theme.horizontalPageMargin
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: Theme.paddingMedium

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("%n to confirm", "", unconfirmedTotal)
                        color: Theme.highlightColor
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        text: qsTr("Review")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.secondaryHighlightColor
                    }
                }
            }

            Item {
                width: parent.width
                height: sortChip.height
                visible: visiblePhotos.length > 0 && !selection.active

                FilterChip {
                    id: sortChip
                    anchors {
                        right: parent.right
                        rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                    }
                    text: newestFirst ? qsTr("Newest first") : qsTr("Oldest first")
                    selected: true
                    onClicked: newestFirst = !newestFirst
                }
            }

            // The selection bar itself is anchored to the page, below

            // Photo mosaic, cut into month sections: rows of equal height,
            // each photo at its own aspect ratio, every row justified to the
            // margin. Squeezing a landscape group shot into a square is what
            // made these unreadable; a uniform waffle with no headings is
            // what made the page read as a contact sheet rather than a page.
            Column {
                id: photoArea
                // Full width so section headings sit on the page's own
                // margin; the rows inset themselves
                width: parent.width
                spacing: Theme.paddingMedium

                onWidthChanged: page.rebuildRows()

                Repeater {
                    model: photoGroups

                    delegate: Column {
                        id: photoSection
                        width: photoArea.width
                        spacing: Theme.paddingSmall
                        // Named, because the nested delegates below shadow
                        // modelData with their own
                        property var group: modelData

                        // A plain label rather than SectionHeader: Silica
                        // right-aligns that one, which pushed long month names
                        // against the edge until they were clipped. Left is
                        // also the axis the photo rows below already sit on.
                        Label {
                            x: Theme.horizontalPageMargin
                            width: parent.width - 2 * Theme.horizontalPageMargin
                            text: photoSection.group.title
                            visible: photoSection.group.title.length > 0
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.highlightColor
                            truncationMode: TruncationMode.Fade
                        }

                        Repeater {
                            model: photoSection.group.rows

                            delegate: Row {
                                id: photoRow
                                x: Theme.horizontalPageMargin
                                spacing: Theme.paddingSmall
                                property var cells: modelData

                                Repeater {
                                    model: photoRow.cells

                                    delegate: ListItem {
                                        id: photoItem

                                        // Unwrapped once so the rest reads plainly
                                        property var photo: modelData.photo

                                        width: modelData.width
                                        // No explicit height: the ListItem grows
                                        // when its context menu opens, the Row
                                        // grows with it and the Column pushes the
                                        // following rows down, instead of the menu
                                        // landing on the neighbouring photos.
                                        contentHeight: modelData.height

                                        // Wrapped in contentItem so the
                                        // ContextMenu positions itself correctly
                                        contentItem.children: [
                                            Image {
                                                anchors.fill: parent
                                                source: FaceUtils.thumbUrl(photoItem.photo.file_path)
                                                // The tile already carries the
                                                // photo's own proportions, so
                                                // this crops almost nothing
                                                fillMode: Image.PreserveAspectCrop
                                                autoTransform: true
                                                rotation: photoItem.photo.rotation || 0
                                                asynchronous: true
                                                clip: true
                                                sourceSize.width: 500
                                                sourceSize.height: 500

                                                // A flat tone while loading: a
                                                // spinner in every tile is what
                                                // made the page look like a
                                                // building site
                                                Rectangle {
                                                    anchors.fill: parent
                                                    visible: parent.status !== Image.Ready
                                                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.12)
                                                }

                                                // Selection state
                                                Rectangle {
                                                    anchors.fill: parent
                                                    visible: selection.active
                                                    color: selection.isSelected(photoItem.photo.file_path)
                                                           ? Theme.rgba(Theme.highlightBackgroundColor, 0.45)
                                                           : Theme.rgba("black", 0.35)
                                                    z: 90

                                                    Icon {
                                                        anchors.centerIn: parent
                                                        source: "image://theme/icon-m-acknowledge"
                                                        opacity: selection.isSelected(photoItem.photo.file_path)
                                                                 ? 1 : 0.25
                                                    }
                                                }

                                                // Only what still waits on the
                                                // user is marked. A tick on every
                                                // confirmed photo decorates the
                                                // resting state and leaves the one
                                                // state that wants an action
                                                // competing with it.
                                                Rectangle {
                                                    visible: photoItem.photo.verified === false
                                                    anchors.top: parent.top
                                                    anchors.right: parent.right
                                                    anchors.margins: Theme.paddingSmall
                                                    width: Theme.iconSizeSmall
                                                    height: Theme.iconSizeSmall
                                                    radius: width / 2
                                                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.95)
                                                    z: 100

                                                    Label {
                                                        anchors.centerIn: parent
                                                        // A question, because that
                                                        // is what it asks: is this
                                                        // them?
                                                        text: "?"
                                                        font.pixelSize: Theme.fontSizeSmall
                                                        font.bold: true
                                                        color: Theme.primaryColor
                                                    }
                                                }
                                            }
                                        ]

                                        onClicked: {
                                            if (selection.active) {
                                                selection.toggle(photoItem.photo.file_path)
                                                return
                                            }
                                            page.openViewer(photoItem.photo.file_path)
                                        }

                                        // Built on first long press only, so a
                                        // page of a few hundred photos does not
                                        // carry a menu per tile
                                        menu: selection.active ? null : photoMenu

                                        Component {
                                            id: photoMenu

                                            ContextMenu {
                                                MenuItem {
                                                    // Accept this one suggestion
                                                    // without confirming the rest
                                                    text: qsTr("Confirm this match")
                                                    visible: photoItem.photo.verified === false
                                                    onClicked: page.setPhotoConfirmed(
                                                        photoItem.photo.face_id,
                                                        photoItem.photo.photo_id, true)
                                                }

                                                MenuItem {
                                                    // Undo for a mistaken
                                                    // confirmation, and the way
                                                    // back out of "Confirm all"
                                                    text: qsTr("Undo confirmation")
                                                    visible: photoItem.photo.verified === true
                                                    onClicked: page.setPhotoConfirmed(
                                                        photoItem.photo.face_id,
                                                        photoItem.photo.photo_id, false)
                                                }

                                                MenuItem {
                                                    text: qsTr("Remove from person")
                                                    onClicked: page.removePhotoFromPerson(
                                                        photoItem.photo.photo_id)
                                                }

                                                MenuItem {
                                                    text: qsTr("View full photo")
                                                    onClicked: {
                                                        page.openViewer(photoItem.photo.file_path)
                                                    }
                                                }

                                                MenuItem {
                                                    text: qsTr("Share")
                                                    onClicked: shareAction.sharePhoto(
                                                        photoItem.photo.file_path)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            ViewPlaceholder {
                enabled: visiblePhotos.length === 0
                text: qsTr("No photos")
                hintText: qsTr("This person hasn't been detected in any photos yet")
            }

            Item {
                width: parent.width
                height: Theme.paddingLarge
            }
        }

        VerticalScrollDecorator {}
    }

    PhotoSelectionBar {
        id: selectionBar
        photoSelection: selection
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        z: 200
        onShareRequested: {
            if (shareAction.sharePhotos(selection.paths)) selection.end()
        }
    }
}
