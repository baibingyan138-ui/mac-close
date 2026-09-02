APP := app/合盖运行控制.app
DESKTOP_APP := $(HOME)/Desktop/合盖运行控制.app
VERSION := 2.0.0
PACKAGE := dist/合盖运行控制-v$(VERSION)-macos.zip

.PHONY: app test install package assert_install_target

app:
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources/Scripts"
	swiftc -parse-as-library -O -framework AppKit -framework SwiftUI gui/ClamshellControl.swift -o "$(APP)/Contents/MacOS/合盖运行控制"
	cp scripts/*.command "$(APP)/Contents/Resources/Scripts/"
	chmod 755 "$(APP)/Contents/MacOS/合盖运行控制" "$(APP)"/Contents/Resources/Scripts/*.command
	rm -f "$(APP)/Contents/MacOS/applet" "$(APP)/Contents/PkgInfo" "$(APP)/Contents/Resources/Assets.car" "$(APP)/Contents/Resources/Scripts/main.scpt" "$(APP)/Contents/Resources/applet.rsrc"
	codesign --force --deep --sign - "$(APP)"

test: app
	plutil -lint "$(APP)/Contents/Info.plist"
	codesign --verify --deep --strict "$(APP)"
	"$(APP)/Contents/MacOS/合盖运行控制" --self-test
	"$(APP)/Contents/Resources/Scripts/合盖持续运行.command" --self-test
	"$(APP)/Contents/Resources/Scripts/合盖持续运行_电池临时.command" --self-test

assert_install_target:
	@case "$(DESKTOP_APP)" in "$(HOME)/Desktop/"*.app) ;; *) echo "Refusing unsafe install target: $(DESKTOP_APP)"; exit 2;; esac

install: assert_install_target test
	rm -rf "$(DESKTOP_APP).new"
	ditto "$(APP)" "$(DESKTOP_APP).new"
	xattr -cr "$(DESKTOP_APP).new"
	codesign --force --deep --sign - "$(DESKTOP_APP).new"
	codesign --verify --deep --strict "$(DESKTOP_APP).new"
	rm -rf "$(DESKTOP_APP)"
	mv "$(DESKTOP_APP).new" "$(DESKTOP_APP)"

package: test
	mkdir -p dist
	rm -f "$(PACKAGE)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP)" "$(PACKAGE)"
	unzip -t "$(PACKAGE)"
