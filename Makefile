# Release builds of both apps, into dist/:
#   make            both APKs + both Linux apps
#   make apk        dist/karots-onboard.apk, dist/karots-shelf.apk
#   make linux      dist/linux/karots-onboard/, dist/linux/karots-shelf/ (+ .tar.gz each)
#   make install-linux   launchers with their icons in this PC's app menu (any desktop)
# Windows can't be built here: push, then GitHub → Actions → Windows build → Artifacts
# (karots-onboard-windows, karots-shelf-windows).

APK := build/app/outputs/flutter-apk
BUNDLE := build/linux/x64/release/bundle
APPS := $(HOME)/.local/share/applications

# One at a time: the builds share build/ (and a -j in MAKEFLAGS would mix them).
.NOTPARALLEL:

.PHONY: all apk apk-onboard apk-shelf linux linux-onboard linux-shelf install-linux test clean

all: apk linux

apk: apk-onboard apk-shelf

apk-onboard:
	flutter build apk --release --flavor onboard -t lib/main.dart
	@mkdir -p dist && cp $(APK)/app-onboard-release.apk dist/karots-onboard.apk

apk-shelf:
	flutter build apk --release --flavor shelf -t lib/main_shelf.dart
	@mkdir -p dist && cp $(APK)/app-shelf-release.apk dist/karots-shelf.apk

linux: linux-onboard linux-shelf

# The bundle folder is shared, so each one is copied out before the next build.
linux-onboard:
	flutter build linux --release -t lib/main.dart
	@rm -rf dist/linux/karots-onboard && mkdir -p dist/linux && cp -r $(BUNDLE) dist/linux/karots-onboard
	@tar -czf dist/linux/karots-onboard.tar.gz -C dist/linux karots-onboard

linux-shelf:
	KS_SHELF=1 flutter build linux --release -t lib/main_shelf.dart
	@rm -rf dist/linux/karots-shelf && mkdir -p dist/linux && cp -r $(BUNDLE) dist/linux/karots-shelf
	@tar -czf dist/linux/karots-shelf.tar.gz -C dist/linux karots-shelf

# Wayland desktops (KDE, GNOME…) take an app's icon only from a launcher named after its id.
install-linux:
	@mkdir -p $(APPS)
	@$(call launcher,lk.karots.karots_suite_onboard,Karots Suite Onboard,karots-onboard,karots_suite_onboard,icon.png)
	@$(call launcher,lk.karots.karots_suite_shelf,Karots Shelf,karots-shelf,karots_shelf,icon_shelf.png)
	@echo "Launchers in $(APPS)"

# $(1) id, $(2) name, $(3) dist folder, $(4) binary, $(5) icon
define launcher
printf '[Desktop Entry]\nType=Application\nName=$(2)\nExec=$(CURDIR)/dist/linux/$(3)/$(4)\nPath=$(CURDIR)/dist/linux/$(3)\nIcon=$(CURDIR)/dist/linux/$(3)/data/flutter_assets/assets/$(5)\nStartupWMClass=$(1)\nCategories=Office;\nTerminal=false\n' > $(APPS)/$(1).desktop
endef

test:
	flutter test

clean:
	rm -rf dist
