#!/bin/sh

# Copyright © 2016 Simon McVittie
#
# SPDX-License-Identifier: MIT
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation
# files (the "Software"), to deal in the Software without
# restriction, including without limitation the rights to use, copy,
# modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
# HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
# WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
# DEALINGS IN THE SOFTWARE.

set -e
set -x

NULL=
srcdir="$(pwd)"
builddir="$(mktemp -d -t "builddir.XXXXXX")"
prefix="$(mktemp -d -t "prefix.XXXXXX")"

if [ -z "$dbus_ci_parallel" ]; then
	dbus_ci_parallel=2
fi

if [ -n "$ci_docker" ]; then
	exec docker run \
		--env=ci_distro="${ci_distro}" \
		--env=ci_docker="" \
		--env=ci_suite="${ci_suite}" \
		--env=dbus_ci_parallel="${dbus_ci_parallel}" \
		--env=dbus_ci_system_python="${dbus_ci_system_python-}" \
		--privileged \
		ci-image \
		tools/ci-build.sh \
		"$@"
fi

if [ -n "$dbus_ci_system_python" ]; then
	# Reset to standard paths to use the Ubuntu version of python
	unset LDFLAGS
	unset PYTHONPATH
	unset PYTHON_CFLAGS
	unset PYTHON_CONFIGURE_OPTS
	unset VIRTUAL_ENV
	export PATH=/usr/bin:/bin
	export PYTHON="$(command -v "$dbus_ci_system_python")"
fi

NOCONFIGURE=1 ./autogen.sh

e=0
(
	cd "$builddir" && "${srcdir}/configure" \
		--enable-installed-tests \
		--prefix="$prefix" \
		--with-python-prefix='${prefix}' \
		--with-python-exec-prefix='${exec_prefix}' \
		"$@" \
		${NULL}
) || e=1
if [ "x$e" != x0 ]; then
	cat "$builddir/config.log"
fi
test "x$e" = x0

make="make -j${dbus_ci_parallel} V=1 VERBOSE=1"

$make -C "$builddir"
$make -C "$builddir" check
$make -C "$builddir" distcheck
$make -C "$builddir" install
( cd "$prefix" && find . -ls )

dbus_ci_pyversion="$(${PYTHON:-python3} -c 'import sysconfig; print(sysconfig.get_config_var("VERSION"))')"
export PYTHONPATH="$prefix/lib/python$dbus_ci_pyversion/site-packages:$PYTHONPATH"
export XDG_DATA_DIRS="$prefix/share:/usr/local/share:/usr/share"
gnome-desktop-testing-runner dbus-python

# re-run the tests with dbus-python only installed via pip
if [ -n "$VIRTUAL_ENV" ]; then
	rm -fr "${prefix}/lib/python$dbus_ci_pyversion/site-packages"
	pip install -vvv "${builddir}"/dbus-python-*.tar.gz
	gnome-desktop-testing-runner dbus-python
fi
