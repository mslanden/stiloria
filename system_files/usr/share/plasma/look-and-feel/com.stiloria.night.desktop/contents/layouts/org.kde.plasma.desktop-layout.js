// Stiloria's desktop: a floating panel along the bottom with the start
// button, pinned apps, the tray and the clock; the Stiloria Helmet wallpaper;
// and the greeting, in ivory day and night, since the helmet's wall is dark.
var panel = new Panel;
panel.location = "bottom";
panel.height = 2 * Math.ceil(gridUnit * 2.6 / 2);
panel.floating = true;

var kickoff = panel.addWidget("org.kde.plasma.kickoff");
kickoff.currentConfigGroup = ["Shortcuts"];
kickoff.writeConfig("global", "Alt+F1");

var tasks = panel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers", [
    "applications:org.kde.dolphin.desktop",
    "applications:com.stiloria.desktop",
    "applications:steam.desktop",
    "applications:com.discordapp.Discord.desktop",
    "applications:org.mozilla.firefox.desktop",
    "applications:io.github.kolunmi.Bazaar.desktop",
    "applications:org.kde.konsole.desktop",
]);

panel.addWidget("org.kde.plasma.marginsseparator");
panel.addWidget("org.kde.plasma.systemtray");
panel.addWidget("org.kde.plasma.digitalclock");

var desktopsArray = desktopsForActivity(currentActivity());
for (var i = 0; i < desktopsArray.length; i++) {
    var desktop = desktopsArray[i];
    desktop.wallpaperPlugin = "org.kde.image";
    desktop.currentConfigGroup = ["Wallpaper", "org.kde.image", "General"];
    desktop.writeConfig("Image", "/usr/share/wallpapers/Stiloria-Helmet/");
    if (knownWidgetTypes.indexOf("com.stiloria.greeting") >= 0) {
        var greeting = desktop.addWidget("com.stiloria.greeting", 96, 64, 640, 304);
        greeting.currentConfigGroup = ["General"];
        greeting.writeConfig("textColor", "light");
    }
}
