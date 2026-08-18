import QtQuick 2.0
import Sailfish.Silica 1.0
import "../js/faceutils.js" as FaceUtils

Dialog {
    id: dialog

    property var peopleModel
    property int selectedPersonId: -1
    property bool createNew: true
    property string personName: ""

    // Reusable for other flows (e.g. merging people)
    property string titleText: qsTr("Who is this?")
    property string acceptLabel: qsTr("Identify")
    property bool allowCreate: true
    property int excludePersonId: -1

    // Opt-in device-contact linking (identify flow only, not merge)
    property bool allowContact: false
    property string selectedContactId: ""
    property string selectedContactName: ""

    // Autocomplete: filter existing people as the new-person name is typed,
    // so a person with a matching name can be picked instead of duplicated
    property string nameQuery: newNameField.text.trim().toLowerCase()

    function personMatches(name) {
        return nameQuery.length === 0 || name.toLowerCase().indexOf(nameQuery) !== -1
    }

    // Set while the name field is filled from a tapped suggestion, so the
    // "user is typing" handler below doesn't undo the selection right away
    property bool _fillingName: false

    function selectPerson(personId, name) {
        selectedPersonId = personId
        createNew = false
        // Keep the name visible in the field: emptying it here used to make
        // the pick look like it never happened
        if (allowCreate) {
            _fillingName = true
            newNameField.text = name
            _fillingName = false
        }
    }

    property int matchCount: {
        if (!peopleModel) return 0
        var n = 0
        for (var i = 0; i < peopleModel.count; i++) {
            var p = peopleModel.get(i)
            if (p.person_id !== excludePersonId && personMatches(p.name)) n++
        }
        return n
    }

    // Holds a copy, never the model item itself: keeping a reference to a
    // ListModel row and reading it after the model has been rebuilt is a
    // dangling read
    property var exactMatchPerson: {
        if (nameQuery.length === 0 || !peopleModel) return null
        for (var i = 0; i < peopleModel.count; i++) {
            var p = peopleModel.get(i)
            if (p.person_id !== excludePersonId && p.name.toLowerCase() === nameQuery) {
                return { person_id: p.person_id, name: p.name }
            }
        }
        return null
    }

    canAccept: (selectedContactId.length > 0) || (selectedPersonId > 0)
               || (createNew && allowCreate && newNameField.text.trim().length > 0)

    onAccepted: {
        if (createNew && allowCreate && selectedContactId.length === 0) {
            personName = newNameField.text.trim()
        }
        console.log("[identify] dialog accepted: createNew=", createNew,
                    "personId=", selectedPersonId, "name=", personName,
                    "contact=", selectedContactId)
    }

    Component.onDestruction: console.log("[identify] SelectPersonDialog destroyed")

    SilicaFlickable {
        anchors.fill: parent
        contentHeight: column.height

        Column {
            id: column
            width: parent.width
            spacing: Theme.paddingMedium

            DialogHeader {
                acceptText: dialog.acceptLabel
                cancelText: qsTr("Cancel")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: dialog.titleText
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
            }

            Item {
                width: parent.width
                height: Theme.paddingMedium
            }

            // Link directly to a device contact (creates a person named
            // after the contact and links it in one step)
            Button {
                anchors.horizontalCenter: parent.horizontalCenter
                text: qsTr("Link to a contact")
                visible: allowContact && facePipeline.contactsEnabled
                onClicked: {
                    var cd = pageStack.push(Qt.resolvedUrl("SelectContactDialog.qml"), {})
                    cd.accepted.connect(function() {
                        if (cd.selectedContactId.length > 0) {
                            selectedContactId = cd.selectedContactId
                            selectedContactName = cd.selectedContactName
                            // Let the contact dialog finish leaving before
                            // accepting this one: stacking a second stack
                            // transition on top of a running one is what the
                            // rest of the app avoids the same way (see
                            // MainPage.linkContact)
                            pageStack.completeAnimation()
                            dialog.accept()
                        }
                    })
                }
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: qsTr("Or create a person only in the app:")
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                wrapMode: Text.WordWrap
                visible: allowContact && allowCreate && facePipeline.contactsEnabled
            }

            // New person input
            TextField {
                id: newNameField
                width: parent.width
                label: createNew ? qsTr("New person") : qsTr("Selected person")
                placeholderText: qsTr("Enter name")
                focus: allowCreate
                visible: allowCreate

                EnterKey.enabled: text.trim().length > 0
                EnterKey.iconSource: "image://theme/icon-m-enter-accept"
                EnterKey.onClicked: {
                    if (canAccept) dialog.accept()
                }

                // Editing the name by hand means a new person again, unless
                // the text was just filled in by selectPerson()
                onTextChanged: {
                    if (_fillingName) {
                        return
                    }
                    createNew = true
                    selectedPersonId = -1
                }
            }

            // Warn before a same-named person gets created twice
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: exactMatchPerson ? qsTr("“%1” already exists — tap it below to avoid a duplicate").arg(exactMatchPerson.name) : ""
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeExtraSmall
                wrapMode: Text.WordWrap
                visible: allowCreate && exactMatchPerson !== null && createNew
            }

            // Separator
            Rectangle {
                width: parent.width - 2 * Theme.horizontalPageMargin
                height: 1
                x: Theme.horizontalPageMargin
                color: Theme.rgba(Theme.highlightColor, 0.1)
                visible: allowCreate && matchCount > 0
            }

            // Existing people, filtered to matches of the typed name (autocomplete)
            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: nameQuery.length > 0
                    ? qsTr("Matching people:")
                    : (allowCreate ? qsTr("Or select existing:") : qsTr("Select person:"))
                color: Theme.secondaryHighlightColor
                font.pixelSize: Theme.fontSizeSmall
                visible: matchCount > 0
            }

            Repeater {
                model: peopleModel

                delegate: BackgroundItem {
                    width: column.width
                    height: Theme.itemSizeSmall
                    visible: model.person_id !== dialog.excludePersonId && personMatches(model.name)
                    highlighted: selectedPersonId === model.person_id

                    Row {
                        anchors {
                            left: parent.left
                            leftMargin: Theme.horizontalPageMargin
                            right: parent.right
                            rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        spacing: Theme.paddingMedium

                        Item {
                            width: Theme.iconSizeMedium
                            height: Theme.iconSizeMedium
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                id: avatarImage
                                anchors.fill: parent
                                source: FaceUtils.personAvatarUrl(facePipeline, model.person_id)
                                sourceSize.width: width
                                sourceSize.height: height
                                asynchronous: true
                            }

                            Icon {
                                anchors.centerIn: parent
                                source: "image://theme/icon-m-person"
                                visible: avatarImage.status !== Image.Ready
                                color: selectedPersonId === model.person_id
                                    ? Theme.highlightColor
                                    : Theme.primaryColor
                            }
                        }

                        Label {
                            text: model.name
                            color: selectedPersonId === model.person_id
                                ? Theme.highlightColor
                                : Theme.primaryColor
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Icon {
                        anchors {
                            right: parent.right
                            rightMargin: Theme.horizontalPageMargin
                            verticalCenter: parent.verticalCenter
                        }
                        source: "image://theme/icon-s-installed"
                        color: Theme.highlightColor
                        visible: selectedPersonId === model.person_id
                    }

                    onClicked: dialog.selectPerson(model.person_id, model.name)
                }
            }

            ViewPlaceholder {
                enabled: !peopleModel || peopleModel.count === 0
                text: qsTr("No people yet")
                hintText: qsTr("Enter a name to create the first person")
            }
        }

        VerticalScrollDecorator {}
    }
}
