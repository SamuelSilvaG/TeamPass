#!/bin/sh
mkdir -p ${VOL}
cd ${VOL}

if [ ! -f ${VOL}/index.php ];
then
	echo "Initial setup..."
	git config --global --add safe.directory ${VOL}
	if [ -z ${GIT_TAG} ]; then
	    # Clone the default branch into the web root
		git clone --depth 1 $REPO_URL ${VOL}
	else
		# Clone the requested tag into the web root
		git clone --depth 1 --branch $GIT_TAG $REPO_URL ${VOL}
	fi
	mkdir -p ${VOL}/sk
	mkdir -p ${VOL}/includes/libraries/csrfp/log
	chown -Rf nginx:nginx ${VOL}
	git config --global --add safe.directory ${VOL}
	# Apply fixes
	if [ -f /apply-fixes.sh ]; then
		/apply-fixes.sh
	fi
fi

if [ -f ${VOL}/includes/config/settings.php ] ;
then
	echo "Teampass is ready."
	rm -rf ${VOL}/install
else
	echo "Teampass is not configured yet. Open it in a web browser to run the install process."
	echo "Use ${VOL}/sk for the absolute path of your saltkey."
	echo "When setup is complete, restart this image to remove the install directory."
fi

# Pass off to the image's script
exec /start.sh

