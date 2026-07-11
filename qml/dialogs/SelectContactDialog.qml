import QtQuick 2.0
import Sailfish.Silica 1.0
import org.nemomobile.contacts 1.0

Dialog {
    id: dialog

    // Result: chosen contact, empty when the user unlinks
    property string selectedContactId: ""
    property string selectedContactName: ""
    property string personName: ""

    PeopleModel {
        id: contactsModel
        filterType: PeopleModel.FilterAll
        requiredProperty: PeopleModel.NoPropertyRequired
        filterPattern: searchField.text
    }

    SilicaListView {
        id: listView
        anchors.fill: parent
        model: contactsModel

        header: Column {
            width: listView.width

            DialogHeader {
                acceptText: qsTr("Link")
                cancelText: qsTr("Cancel")
            }

            Label {
                x: Theme.horizontalPageMargin
                width: parent.width - 2 * Theme.horizontalPageMargin
                text: personName.length > 0
                      ? qsTr("Link %1 to a contact").arg(personName)
                      : qsTr("Link to a contact")
                color: Theme.highlightColor
                font.pixelSize: Theme.fontSizeLarge
                wrapMode: Text.WordWrap
            }

            SearchField {
                id: searchField
                width: parent.width
                placeholderText: qsTr("Search contacts")
                EnterKey.iconSource: "image://theme/icon-m-enter-close"
                EnterKey.onClicked: focus = false
            }
        }

        delegate: BackgroundItem {
            id: contactItem
            width: listView.width
            highlighted: down || dialog.selectedContactId === model.contactId

            Row {
                anchors {
                    left: parent.left
                    leftMargin: Theme.horizontalPageMargin
                    right: parent.right
                    rightMargin: Theme.horizontalPageMargin
                    verticalCenter: parent.verticalCenter
                }
                spacing: Theme.paddingMedium

                Image {
                    id: contactAvatar
                    width: Theme.iconSizeMedium
                    height: Theme.iconSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                    source: model.avatarUrl || ""
                    sourceSize.width: width
                    sourceSize.height: height
                    asynchronous: true
                    visible: status === Image.Ready
                }

                Icon {
                    width: Theme.iconSizeMedium
                    height: Theme.iconSizeMedium
                    anchors.verticalCenter: parent.verticalCenter
                    source: "image://theme/icon-m-contact"
                    visible: contactAvatar.status !== Image.Ready
                    color: contactItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: model.displayLabel || qsTr("Unnamed contact")
                    color: contactItem.highlighted ? Theme.highlightColor : Theme.primaryColor
                    truncationMode: TruncationMode.Fade
                    width: contactItem.width - Theme.iconSizeMedium - 2 * Theme.horizontalPageMargin - Theme.paddingMedium
                }
            }

            onClicked: {
                dialog.selectedContactId = "" + model.contactId
                dialog.selectedContactName = model.displayLabel || ""
                dialog.accept()
            }
        }

        ViewPlaceholder {
            enabled: listView.count === 0
            text: qsTr("No contacts")
            hintText: qsTr("No contact matches your search")
        }

        VerticalScrollDecorator {}
    }
}
