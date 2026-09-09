.PHONY: test build probe bundle install clean

test:
	swift test

build:
	swift build -c release

probe:
	swift run -c release idle-probe

bundle:
	./Scripts/bundle.sh

install: bundle
	rm -rf /Applications/Presence.app
	cp -R Presence.app /Applications/Presence.app
	@echo "installed to /Applications/Presence.app"

clean:
	rm -rf .build Presence.app
