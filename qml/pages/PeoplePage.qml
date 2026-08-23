import QtQuick 2.0
import Sailfish.Silica 1.0
import "../components"
import "../js/faceutils.js" as FaceUtils

Page {
    id: page

    allowedOrientations: Orientation.All

    // People model (source data)
    ListModel {
        id: peopleModel
    }

    // Filtered model (for search)
    ListModel {
        id: filteredPeopleModel
    }

    // Search query
    property string searchQuery: ""

    // "photos" | "name" | "recent"; persisted, so the choice survives a restart
    property string sortMode: "photos"
    // Guards the initial load against writing the setting straight back
    property bool sortReady: false

    // Layout: 0 = list, otherwise number of grid columns (2 or 4)
    property int gridColumns: 0

    // Statistics
    property int totalPeople: 0
    property int totalPhotos: 0

    function reloadSortMode() {
        if (facePipeline && facePipeline.initialized) {
            var stored = facePipeline.getSetting("people_sort_mode", "photos")
            sortMode = (stored === "name" || stored === "recent") ? stored : "photos"
        }
        sortReady = true
    }

    onSortModeChanged: {
        if (!sortReady || !facePipeline || !facePipeline.initialized) return
        facePipeline.setSetting("people_sort_mode", sortMode)
        filterAndSort()
    }

    function reloadViewMode() {
        if (facePipeline && facePipeline.initialized) {
            var mode = facePipeline.getSetting("people_view_mode", "list")
            // "grid" is the legacy value for the 2-column grid
            gridColumns = (mode === "grid4") ? 4
                        : (mode === "grid2" || mode === "grid") ? 2
                        : 0
        }
    }

    // Refresh people list
    function refreshPeople() {
        if (!facePipeline || !facePipeline.initialized) return

        var people = facePipeline.getAllPeople()

        // Calculate statistics
        totalPeople = people.length
        totalPhotos = 0

        // Updated in place: this model is handed to SelectPersonDialog when
        // merging, and refreshPeople() runs from that dialog's accepted
        // handler, while it is still alive and bound to it. clear() would
        // destroy the delegates it is using at that very moment.
        for (var i = 0; i < people.length; i++) {
            if (i < peopleModel.count) {
                peopleModel.set(i, people[i])
            } else {
                peopleModel.append(people[i])
            }
            totalPhotos += people[i].photo_count
        }
        while (peopleModel.count > people.length) {
            peopleModel.remove(peopleModel.count - 1)
        }

        // Apply filter and sort
        filterAndSort()
    }

    // Filter and sort people
    function filterAndSort() {
        // Collect filtered items
        var items = []
        for (var i = 0; i < peopleModel.count; i++) {
            var person = peopleModel.get(i)

            // Filter by search query
            if (searchQuery === "" || person.name.toLowerCase().indexOf(searchQuery.toLowerCase()) >= 0) {
                items.push({
                    person_id: person.person_id,
                    name: person.name,
                    photo_count: person.photo_count,
                    contact_id: person.contact_id || "",
                    last_photo: person.last_photo || 0
                })
            }
        }

        // Sort items
        if (sortMode === "name") {
            items.sort(function(a, b) {
                return a.name.toLowerCase().localeCompare(b.name.toLowerCase())
            })
        } else if (sortMode === "recent") {
            // Most recently photographed first; people whose photos carry no
            // usable date sink to the bottom rather than posing as 1970
            items.sort(function(a, b) {
                if (a.last_photo !== b.last_photo) return b.last_photo - a.last_photo
                return a.name.toLowerCase().localeCompare(b.name.toLowerCase())
            })
        } else { // sortMode === "photos"
            items.sort(function(a, b) {
                return b.photo_count - a.photo_count
            })
        }

        // Update the model in place: clear()+append resets the view on
        // every keystroke and steals focus from the search field
        for (var j = 0; j < items.length; j++) {
            if (j < filteredPeopleModel.count) {
                filteredPeopleModel.set(j, items[j])
            } else {
                filteredPeopleModel.append(items[j])
            }
        }
        while (filteredPeopleModel.count > items.length) {
            filteredPeopleModel.remove(filteredPeopleModel.count - 1)
        }
    }

    // === Actions (shared between list and grid layouts) ===

    function openPerson(personId, name) {
        pageStack.push(Qt.resolvedUrl("PersonDetailPage.qml"), {
            personId: personId,
            personName: name
        })
    }

    function renamePerson(personId, name) {
        var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/RenamePersonDialog.qml"), {
            personId: personId,
            currentName: name
        })
        dialog.accepted.connect(function() {
            facePipeline.updatePersonName(personId, dialog.newName)
            refreshPeople()
        })
    }

    function mergePerson(personId, name) {
        var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/SelectPersonDialog.qml"), {
            peopleModel: peopleModel,
            allowCreate: false,
            excludePersonId: personId,
            titleText: qsTr("Merge %1 into...").arg(name),
            acceptLabel: qsTr("Merge")
        })
        dialog.accepted.connect(function() {
            if (dialog.selectedPersonId > 0) {
                facePipeline.mergePersons(personId, dialog.selectedPersonId)
                refreshPeople()
            }
        })
    }

    function deletePerson(personId, name) {
        Remorse.popupAction(page, qsTr("Deleting %1").arg(name), function() {
            facePipeline.deletePerson(personId)
            refreshPeople()
        })
    }

    function applyContactLink(personId, contactId, contactName) {
        facePipeline.linkPersonToContact(personId, contactId)
        // Adopt the contact's name for the linked person
        if (contactName.length > 0) {
            facePipeline.updatePersonName(personId, contactName)
        }
        refreshPeople()
    }

    function linkContact(personId, name) {
        var dialog = pageStack.push(Qt.resolvedUrl("../dialogs/SelectContactDialog.qml"), {
            personName: name
        })
        dialog.accepted.connect(function() {
            // Same contact already linked to another person: these are most
            // likely duplicates of the same human, offer to merge them
            var existingId = -1
            var existingName = ""
            for (var i = 0; i < peopleModel.count; i++) {
                var p = peopleModel.get(i)
                if (p.contact_id === dialog.selectedContactId && p.person_id !== personId) {
                    existingId = p.person_id
                    existingName = p.name
                    break
                }
            }

            if (existingId > 0) {
                pageStack.completeAnimation()
                var confirm = pageStack.push(Qt.resolvedUrl("../dialogs/ConfirmDialog.qml"), {
                    title: qsTr("Merge duplicates?"),
                    message: qsTr("%1 is already linked to this contact. Merge %2 into %1?").arg(existingName).arg(name)
                })
                confirm.accepted.connect(function() {
                    facePipeline.mergePersons(personId, existingId)
                    refreshPeople()
                })
                confirm.rejected.connect(function() {
                    applyContactLink(personId, dialog.selectedContactId, dialog.selectedContactName)
                })
            } else {
                applyContactLink(personId, dialog.selectedContactId, dialog.selectedContactName)
            }
        })
    }

    function unlinkContact(personId) {
        facePipeline.linkPersonToContact(personId, "")
        refreshPeople()
    }

    // Same actions the list layout offers in its context menu, for the grid
    // layout where an inline menu would be drawn over the neighbouring cells
    function openPersonActions(personId, name, contactId) {
        var linked = contactId && contactId.length > 0
        var sheet = pageStack.push(Qt.resolvedUrl("ActionSheetPage.qml"), {
            heading: name || qsTr("Unknown"),
            actions: [
                { id: "rename", text: qsTr("Rename") },
                { id: "link", text: linked ? qsTr("Change linked contact")
                                           : qsTr("Link to contact"),
                  enabled: facePipeline.contactsEnabled },
                { id: "unlink", text: qsTr("Unlink contact"),
                  enabled: facePipeline.contactsEnabled && linked },
                { id: "merge", text: qsTr("Merge into..."),
                  enabled: peopleModel.count > 1 },
                { id: "delete", text: qsTr("Delete") }
            ]
        })
        sheet.chosen.connect(function (actionId) {
            switch (actionId) {
            case "rename": renamePerson(personId, name); break
            case "link":   linkContact(personId, name); break
            case "unlink": unlinkContact(personId); break
            case "merge":  mergePerson(personId, name); break
            case "delete": deletePerson(personId, name); break
            }
        })
    }

    // === Navigation (shared by both layouts) ===

    function openIdentify() { pageStack.push(Qt.resolvedUrl("IdentifyFacesPage.qml")) }
    function openScan() { pageStack.push(Qt.resolvedUrl("ScanningPage.qml")) }

    Component.onCompleted: {
        reloadViewMode()
        reloadSortMode()
        if (facePipeline && facePipeline.initialized) {
            refreshPeople()
        }
    }

    // Coming back from Settings or a person page: re-read the layout choice
    // and reload people (deletions/renames done on the detail page would
    // otherwise not show until the next scan)
    onStatusChanged: {
        if (status === PageStatus.Active) {
            reloadViewMode()
            reloadSortMode()
            refreshPeople()
        }
    }

    Connections {
        target: facePipeline
        onScanCompleted: refreshPeople()
    }

    // Shared header for both layouts
    Component {
        id: peopleHeader

        Column {
            width: parent.width
            spacing: 0

            PageHeader {
                title: qsTr("People")
                // The counts as a quiet line under the title. A boxed panel
                // is ornament: hierarchy comes from position and scale.
                description: totalPeople > 0
                    ? (totalPeople + " "
                       + (totalPeople === 1 ? qsTr("person") : qsTr("people"))
                       + "  \u00b7  " + totalPhotos + " "
                       + (totalPhotos === 1 ? qsTr("photo") : qsTr("photos")))
                    : ""
            }

            // Search field
            SearchField {
                id: searchField
                width: parent.width
                placeholderText: qsTr("Search people")
                visible: totalPeople > 0

                // One-way binding only: writing text back while typing
                // breaks keyboard composition and defocuses the field
                onTextChanged: {
                    searchQuery = text
                    filterAndSort()
                }

                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }

            // Sort criteria on the page rather than in the pulley menu: which
            // one is active has to be readable without opening anything
            Row {
                x: Theme.horizontalPageMargin
                spacing: Theme.paddingMedium
                visible: totalPeople > 0

                FilterChip {
                    text: qsTr("Photos")
                    selected: sortMode === "photos"
                    onClicked: sortMode = "photos"
                }
                FilterChip {
                    text: qsTr("Name")
                    selected: sortMode === "name"
                    onClicked: sortMode = "name"
                }
                FilterChip {
                    text: qsTr("Recent")
                    selected: sortMode === "recent"
                    onClicked: sortMode = "recent"
                }
            }

            // The chips sat directly on top of the first row of faces; the
            // underline marking the active one needs room to read as one
            Item {
                width: parent.width
                height: Theme.paddingLarge
                visible: totalPeople > 0
            }
        }
    }

    // === List layout ===
    Component {
        id: listLayout

        SilicaListView {
            id: listView
            anchors.fill: parent
            model: filteredPeopleModel
            header: peopleHeader
            // Keep the view from grabbing focus away from the search field
            currentIndex: -1

            // Only what acts on people. About, Settings, Memories and Events
            // are the app's own navigation and live on the home page, one
            // swipe to the right, rather than being repeated on every page.
            PullDownMenu {
                MenuItem {
                    text: qsTr("Identify Faces")
                    enabled: facePipeline && facePipeline.initialized
                    onClicked: openIdentify()
                }
                MenuItem {
                    text: qsTr("Scan Gallery")
                    enabled: facePipeline && facePipeline.initialized && !facePipeline.processing
                    onClicked: openScan()
                }
            }

            delegate: ListItem {
                id: listItem
                width: ListView.view.width
                contentHeight: Theme.itemSizeMedium

                Row {
                    anchors {
                        left: parent.left
                        leftMargin: Theme.horizontalPageMargin
                        right: parent.right
                        rightMargin: Theme.horizontalPageMargin
                        verticalCenter: parent.verticalCenter
                    }
                    spacing: Theme.paddingMedium

                    // Face thumbnail (best face of the person, icon fallback)
                    Rectangle {
                        width: Theme.itemSizeSmall
                        height: Theme.itemSizeSmall
                        radius: Theme.itemSizeSmall / 2
                        color: Theme.rgba(Theme.highlightBackgroundColor, 0.2)

                        Image {
                            id: avatarImage
                            anchors.fill: parent
                            source: FaceUtils.personAvatarUrl(facePipeline, model.person_id)
                            sourceSize.width: width
                            sourceSize.height: height
                            asynchronous: true
                        }

                        Image {
                            anchors.centerIn: parent
                            source: "image://theme/icon-m-contact"
                            width: Theme.iconSizeMedium
                            height: Theme.iconSizeMedium
                            visible: avatarImage.status !== Image.Ready
                        }
                    }

                    Column {
                        width: parent.width - Theme.itemSizeSmall - Theme.paddingMedium
                        anchors.verticalCenter: parent.verticalCenter

                        Row {
                            width: parent.width
                            spacing: Theme.paddingSmall

                            Label {
                                text: model.name || qsTr("Unknown")
                                color: listItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                                truncationMode: TruncationMode.Fade
                                width: Math.min(implicitWidth, parent.width - (linkedIcon.visible ? linkedIcon.width + parent.spacing : 0))
                            }

                            Image {
                                id: linkedIcon
                                anchors.verticalCenter: parent.verticalCenter
                                // Tinted like secondary text so it reads as
                                // metadata, not as an action button
                                source: "image://theme/icon-m-contact?" + Theme.secondaryColor
                                width: Theme.iconSizeExtraSmall
                                height: Theme.iconSizeExtraSmall
                                sourceSize.width: width
                                sourceSize.height: height
                                visible: facePipeline.contactsEnabled && model.contact_id && model.contact_id.length > 0
                            }
                        }

                        Label {
                            text: model.photo_count + " " + (model.photo_count === 1 ? qsTr("photo") : qsTr("photos"))
                            color: listItem.highlighted ? Theme.secondaryHighlightColor : Theme.secondaryColor
                            font.pixelSize: Theme.fontSizeExtraSmall
                            truncationMode: TruncationMode.Fade
                            width: parent.width
                        }
                    }
                }

                menu: ContextMenu {
                    MenuItem {
                        text: qsTr("Rename")
                        onClicked: renamePerson(model.person_id, model.name)
                    }
                    MenuItem {
                        text: (model.contact_id && model.contact_id.length > 0)
                              ? qsTr("Change linked contact")
                              : qsTr("Link to contact")
                        visible: facePipeline.contactsEnabled
                        onClicked: linkContact(model.person_id, model.name)
                    }
                    MenuItem {
                        text: qsTr("Unlink contact")
                        visible: facePipeline.contactsEnabled && model.contact_id && model.contact_id.length > 0
                        onClicked: unlinkContact(model.person_id)
                    }
                    MenuItem {
                        text: qsTr("Merge into...")
                        visible: peopleModel.count > 1
                        onClicked: mergePerson(model.person_id, model.name)
                    }
                    MenuItem {
                        text: qsTr("Delete")
                        onClicked: deletePerson(model.person_id, model.name)
                    }
                }

                onClicked: openPerson(model.person_id, model.name)
            }

            ViewPlaceholder {
                enabled: listView.count === 0
                text: qsTr("No faces detected yet")
                hintText: qsTr("Pull down to scan your gallery")
            }

            VerticalScrollDecorator {}
        }
    }

    // === Grid layout ===
    Component {
        id: gridLayout

        SilicaGridView {
            id: grid
            anchors.fill: parent
            model: filteredPeopleModel
            header: peopleHeader
            // Keep the view from grabbing focus away from the search field
            currentIndex: -1

            property int columns: gridColumns > 0 ? gridColumns : 2
            property bool dense: columns >= 4

            cellWidth: width / columns
            cellHeight: cellWidth + (dense ? Theme.itemSizeExtraSmall : Theme.itemSizeSmall)

            // Only what acts on people. About, Settings, Memories and Events
            // are the app's own navigation and live on the home page, one
            // swipe to the right, rather than being repeated on every page.
            PullDownMenu {
                MenuItem {
                    text: qsTr("Identify Faces")
                    enabled: facePipeline && facePipeline.initialized
                    onClicked: openIdentify()
                }
                MenuItem {
                    text: qsTr("Scan Gallery")
                    enabled: facePipeline && facePipeline.initialized && !facePipeline.processing
                    onClicked: openScan()
                }
            }

            delegate: ListItem {
                width: grid.cellWidth
                contentHeight: grid.cellHeight

                // No inline ContextMenu here: a SilicaGridView lays its cells
                // out on a fixed cellHeight and cannot push the next row down,
                // so an opened menu is drawn over the neighbouring people. The
                // list layout above keeps its ContextMenu, which works because
                // a ListView does reflow.
                onPressAndHold: openPersonActions(model.person_id, model.name,
                                                 model.contact_id)

                Column {
                    anchors.fill: parent
                    anchors.margins: grid.dense ? Theme.paddingSmall : Theme.paddingMedium
                    spacing: Theme.paddingSmall

                    Item {
                        id: avatarFrame
                        width: parent.width
                        height: width

                        Image {
                            id: gridAvatar
                            anchors.fill: parent
                            // Round crop on a transparent frame: no colored
                            // square showing behind the circle
                            source: FaceUtils.personAvatarUrl(facePipeline, model.person_id)
                            sourceSize.width: width
                            sourceSize.height: height
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }

                        Image {
                            anchors.centerIn: parent
                            source: "image://theme/icon-m-contact"
                            visible: gridAvatar.status !== Image.Ready
                            opacity: 0.4
                        }

                        // Discreet linked-contact badge, sitting on the
                        // circle's lower-right edge
                        Rectangle {
                            anchors {
                                bottom: parent.bottom
                                right: parent.right
                                margins: parent.width * 0.05
                            }
                            width: Theme.iconSizeSmall
                            height: width
                            radius: width / 2
                            color: Theme.rgba("black", 0.5)
                            visible: facePipeline.contactsEnabled && model.contact_id && model.contact_id.length > 0

                            Image {
                                anchors.centerIn: parent
                                source: "image://theme/icon-m-contact?#ffffff"
                                width: parent.width * 0.6
                                height: width
                                sourceSize.width: width
                                sourceSize.height: height
                            }
                        }
                    }

                    Label {
                        width: parent.width
                        text: model.name || qsTr("Unknown")
                        color: Theme.primaryColor
                        font.pixelSize: grid.dense ? Theme.fontSizeExtraSmall : Theme.fontSizeSmall
                        truncationMode: TruncationMode.Fade
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                onClicked: openPerson(model.person_id, model.name)
            }

            ViewPlaceholder {
                enabled: grid.count === 0
                text: qsTr("No faces detected yet")
                hintText: qsTr("Pull down to scan your gallery")
            }

            VerticalScrollDecorator {}
        }
    }

    // Only one layout is instantiated at a time
    Loader {
        anchors.fill: parent
        sourceComponent: gridColumns > 0 ? gridLayout : listLayout
    }
}
