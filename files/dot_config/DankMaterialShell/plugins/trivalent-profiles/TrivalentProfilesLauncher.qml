import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var pluginService: null
    property string trigger: "br"
    property var profiles: []

    signal itemsChanged()

    Component.onCompleted: {
        if (pluginService)
            trigger = pluginService.loadPluginData("trivalent-profiles", "trigger", "br")
        localState.reload()
    }

    FileView {
        id: localState
        path: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.config/trivalent/Local State"

        onLoaded: {
            try {
                const data = JSON.parse(text())
                const cache = data.profile.info_cache
                const result = [{ name: "Guest Profile", id: "GUEST_SESSION" }]
                for (const key in cache)
                    result.push({ name: cache[key].name, id: key })
                root.profiles = result
                root.itemsChanged()
            } catch (e) {
                console.error("TrivalentProfiles: failed to parse Local State:", e.message)
            }
        }

        onLoadFailed: function(err) {
            console.error("TrivalentProfiles: failed to load Local State:", path, err)
        }
    }

    function getItems(query) {
        const items = profiles.map(p => ({
            name: p.name,
            icon: "",
            comment: p.id === "GUEST_SESSION" ? "Private browsing – no data saved" : "Open Trivalent with this profile",
            action: "trivalent:" + encodeURIComponent(p.id),
            categories: ["Browser"]
        }))

        if (!query || query.length === 0) return items

        const q = query.toLowerCase()
        return items.filter(i => i.name.toLowerCase().includes(q))
    }

    function executeItem(item) {
        if (!item?.action) return

        const colon = item.action.indexOf(":")
        const type = item.action.substring(0, colon)
        const data = item.action.substring(colon + 1)

        if (type !== "trivalent") return

        const profileId = decodeURIComponent(data)
        if (profileId === "GUEST_SESSION") {
            Quickshell.execDetached(["trivalent", "--guest"])
        } else {
            Quickshell.execDetached(["trivalent", "--profile-directory=" + profileId])
        }
    }
}
