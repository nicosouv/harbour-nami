import QtQuick 2.6
import Sailfish.Silica 1.0
import Nemo.DBus 2.0
import "../components"

Page {
    id: page

    property int personId: -1
    property string personName: ""
    property string contactId: ""
    property var faceManager: facePipeline

    // Full photo list as returned by the pipeline (already newest first).
    // photosModel holds the filtered/sorted view of it.
    property var allPhotos: []
    property bool newestFirst: true
    property bool unconfirmedOnly: false
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

    function openInContacts() {
        var cid = parseInt(contactId)
        if (cid > 0) {
            contactsUi.typedCall("showContact", { "type": "i", "value": cid })
        }
    }

    // Photos with this person
    ListModel {
        id: photosModel
    }

    function loadPhotos() {
        if (!faceManager || !faceManager.initialized || personId < 0) return

        allPhotos = faceManager.getPersonPhotos(personId)
        rebuildPhotoModel()
    }

    function recountTotals() {
        var unconfirmed = 0
        for (var i = 0; i < allPhotos.length; i++) {
            if (allPhotos[i].verified !== true) unconfirmed++
        }
        totalPhotos = allPhotos.length
        unconfirmedTotal = unconfirmed
    }

    // Rebuild the visible grid from allPhotos. getPersonPhotos() already sorts
    // newest first, so "oldest first" is just a reversal.
    function rebuildPhotoModel() {
        photosModel.clear()

        var visible = []
        for (var i = 0; i < allPhotos.length; i++) {
            if (unconfirmedOnly && allPhotos[i].verified === true) continue
            visible.push(allPhotos[i])
        }
        recountTotals()

        if (!newestFirst) {
            visible.reverse()
        }

        for (var j = 0; j < visible.length; j++) {
            photosModel.append(visible[j])
        }
    }

    // Drop one row without rebuilding the whole grid, so the other photos do
    // not blink out and back in.
    function dropRow(photoId) {
        for (var i = 0; i < photosModel.count; i++) {
            // Called from a signal handler, never from a binding: get() inside
            // a binding is what crashed the identify page.
            if (photosModel.get(i).photo_id === photoId) {
                photosModel.remove(i)
                break
            }
        }
        recountTotals()
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
    onUnconfirmedOnlyChanged: rebuildPhotoModel()

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
                enabled: photosModel.count > 0 && !selection.active
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

            PageHeader {
                title: personName
            }

            // Statistics card
            Item {
                width: parent.width
                height: statsCard.height

                Rectangle {
                    id: statsCard
                    width: parent.width - 2 * Theme.horizontalPageMargin
                    height: statsColumn.height + 2 * Theme.paddingMedium
                    x: Theme.horizontalPageMargin
                    radius: Theme.paddingSmall
                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.1)

                    Column {
                        id: statsColumn
                        width: parent.width - 2 * Theme.paddingMedium
                        anchors.centerIn: parent
                        spacing: Theme.paddingSmall

                        Label {
                            // Always the real total, never the filtered count
                            text: totalPhotos + " " + (totalPhotos === 1 ? qsTr("photo") : qsTr("photos"))
                            font.pixelSize: Theme.fontSizeHuge
                            font.bold: true
                            color: Theme.highlightColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Label {
                            text: qsTr("with this person")
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.secondaryColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }

                        Label {
                            visible: unconfirmedTotal > 0
                            text: qsTr("%n match(es) to confirm", "", unconfirmedTotal)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.highlightColor
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
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

            SectionHeader {
                text: qsTr("Photos")
                visible: photosModel.count > 0 && !selection.active
            }

            // Filter and sort, on the page rather than in the pulley menu:
            // the current state has to be readable without opening anything.
            Item {
                width: parent.width
                height: chipRow.height
                visible: photosModel.count > 0 && !selection.active

                Row {
                    id: chipRow
                    x: Theme.horizontalPageMargin
                    spacing: Theme.paddingMedium

                    FilterChip {
                        text: qsTr("All")
                        selected: !unconfirmedOnly
                        onClicked: unconfirmedOnly = false
                    }

                    FilterChip {
                        text: qsTr("To confirm (%1)").arg(unconfirmedTotal)
                        visible: unconfirmedTotal > 0
                        selected: unconfirmedOnly
                        onClicked: unconfirmedOnly = true
                    }
                }

                FilterChip {
                    anchors {
                        right: parent.right
                        rightMargin: Theme.horizontalPageMargin - Theme.paddingMedium
                        verticalCenter: chipRow.verticalCenter
                    }
                    text: newestFirst ? qsTr("Newest first") : qsTr("Oldest first")
                    selected: true
                    onClicked: newestFirst = !newestFirst
                }
            }

            // The selection bar itself is anchored to the page, below

            // Photo grid
            Grid {
                id: photoGrid
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                columns: 3
                spacing: Theme.paddingSmall

                // 3 cells plus 2 gaps have to fit the width. Sizing cells at
                // width/3 overflows by two gaps, which pushed the last column
                // off the right edge of the screen.
                property real cellSize: (width - (columns - 1) * spacing) / columns

                Repeater {
                    model: photosModel

                    delegate: ListItem {
                        id: photoItem
                        width: photoGrid.cellSize
                        // No explicit height: ListItem grows when its context
                        // menu opens, and this plain Grid reflows the row to
                        // match. Pinning the height is what made the menu draw
                        // on top of the neighbouring photos.
                        contentHeight: width

                        // Wrap content in Item to fix ContextMenu positioning
                        contentItem.children: [
                            Image {
                                id: photoImage
                                anchors.fill: parent
                                source: model.file_path ? "file://" + model.file_path : ""
                                fillMode: Image.PreserveAspectCrop
                                autoTransform: true
                                rotation: model.rotation || 0
                                asynchronous: true
                                clip: true

                                // Limit source size to save memory
                                sourceSize.width: 400
                                sourceSize.height: 400

                                BusyIndicator {
                                    anchors.centerIn: parent
                                    running: parent.status === Image.Loading
                                    size: BusyIndicatorSize.Small
                                }

                                // Border with different color for verified vs auto-matched
                                Rectangle {
                                    anchors.fill: parent
                                    color: "transparent"
                                    border.color: model.verified ? Theme.rgba(Theme.secondaryHighlightColor, 0.8) : Theme.rgba(Theme.highlightColor, 0.3)
                                    border.width: model.verified ? 2 : 1
                                }

                                // Selection state
                                Rectangle {
                                    anchors.fill: parent
                                    visible: selection.active
                                    color: selection.isSelected(model.file_path)
                                           ? Theme.rgba(Theme.highlightBackgroundColor, 0.45)
                                           : Theme.rgba("black", 0.35)
                                    z: 90

                                    Icon {
                                        anchors.centerIn: parent
                                        source: "image://theme/icon-m-acknowledge"
                                        opacity: selection.isSelected(model.file_path) ? 1 : 0.25
                                    }
                                }

                                // Verified badge (manual identification - checkmark)
                                Rectangle {
                                    visible: model.verified === true
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: Theme.paddingSmall
                                    width: Theme.iconSizeSmall
                                    height: Theme.iconSizeSmall
                                    radius: width / 2
                                    color: Theme.rgba("#4CAF50", 0.95)
                                    border.color: "white"
                                    border.width: 2
                                    z: 100

                                    Label {
                                        anchors.centerIn: parent
                                        text: "✓"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: true
                                        color: "white"
                                    }
                                }

                                // Auto-matched badge (AI icon)
                                Rectangle {
                                    visible: model.verified === false && model.similarity_score > 0
                                    anchors.top: parent.top
                                    anchors.right: parent.right
                                    anchors.margins: Theme.paddingSmall
                                    width: Theme.iconSizeSmall
                                    height: Theme.iconSizeSmall
                                    radius: width / 2
                                    color: Theme.rgba("#2196F3", 0.9)
                                    border.color: "white"
                                    border.width: 2
                                    z: 100

                                    Label {
                                        anchors.centerIn: parent
                                        text: "✦"
                                        font.pixelSize: Theme.fontSizeSmall
                                        font.bold: true
                                        color: "white"
                                    }
                                }

                                // Similarity score badge (for auto-matched)
                                Rectangle {
                                    visible: model.verified === false && model.similarity_score > 0
                                    anchors.bottom: parent.bottom
                                    anchors.right: parent.right
                                    anchors.margins: Theme.paddingSmall
                                    width: scoreLabel.width + Theme.paddingSmall
                                    height: scoreLabel.height + Theme.paddingSmall / 2
                                    radius: Theme.paddingSmall / 2
                                    color: Theme.rgba(Theme.highlightBackgroundColor, 0.8)
                                    z: 100

                                    Label {
                                        id: scoreLabel
                                        anchors.centerIn: parent
                                        text: Math.round(model.similarity_score * 100) + "%"
                                        font.pixelSize: Theme.fontSizeTiny
                                        color: Theme.primaryColor
                                    }
                                }
                            }
                        ]

                        onClicked: {
                            if (selection.active) {
                                selection.toggle(model.file_path)
                                return
                            }
                            pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"), {
                                photoPath: model.file_path
                            })
                        }

                        // Built only on first long press, so a grid of a few
                        // hundred photos does not carry a menu per cell
                        menu: selection.active ? null : photoMenu

                        Component {
                            id: photoMenu

                            ContextMenu {
                                MenuItem {
                                    // Accept this one suggestion without
                                    // confirming every match at once
                                    text: qsTr("Confirm this match")
                                    visible: model.verified === false
                                    onClicked: page.setPhotoConfirmed(model.face_id,
                                                                      model.photo_id, true)
                                }

                                MenuItem {
                                    // Undo for a mistaken confirmation, and
                                    // the only way back out of "Confirm all"
                                    text: qsTr("Undo confirmation")
                                    visible: model.verified === true
                                    onClicked: page.setPhotoConfirmed(model.face_id,
                                                                      model.photo_id, false)
                                }

                                MenuItem {
                                    text: qsTr("Remove from person")
                                    onClicked: page.removePhotoFromPerson(model.photo_id)
                                }

                                MenuItem {
                                    text: qsTr("View full photo")
                                    onClicked: {
                                        pageStack.push(Qt.resolvedUrl("PhotoViewerPage.qml"), {
                                            photoPath: model.file_path
                                        })
                                    }
                                }

                                MenuItem {
                                    text: qsTr("Share")
                                    onClicked: shareAction.sharePhoto(model.file_path)
                                }
                            }
                        }
                    }
                }
            }

            ViewPlaceholder {
                enabled: photosModel.count === 0
                text: unconfirmedOnly ? qsTr("Nothing left to confirm")
                                      : qsTr("No photos")
                hintText: unconfirmedOnly
                          ? qsTr("Every match for this person has been confirmed")
                          : qsTr("This person hasn't been detected in any photos yet")
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
