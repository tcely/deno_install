#!/bin/sh
# Copyright 2019 the Deno authors. All rights reserved. MIT license.
# TODO(everyone): Keep this script simple and easily auditable.

set -e

find_sum_binary() {
	for cmd in busybox busybox-static sha256sum; do
		command -v "${cmd}" && break
	done; unset -v cmd ;
}

find_unzip_binary() {
	for cmd in busybox busybox-static unzip 7z 7za 7zz bsdtar sqlite3; do
    	command -v "${cmd}" && break
	done; unset -v cmd ;
}

check_unzip_binary() {
	case "${1}" in
		(*/busybox*) "${1}" unzip --help >/dev/null 2>&1 ;;
		(*/unzip*) return 0 ;;
		(*/7z*) return 0 ;;
		(*/bsdtar*) return 0 ;;
		(*/sqlite3) "${1}" -A -nc >/dev/null 2>&1 ;;
		(*) return 1 ;;
	esac
}

extract_with_unzip_binary() (
	# destination_directory binary_path
	dir="$(realpath -e "${1}")"
	shift
	cmd="${1}"
	shift
	digest="${1}"
	shift

	set -eu
	work_dir="$(mktemp -d -t -p "${dir}" .tmp.deno.XXXXXXXX)" && \
		trap "rm -v -rf -- '${work_dir}'" EXIT
	cd "${work_dir}"
	cat > file.zip

	if [ -n "${digest}" ]; then
		printf >> SUMS -- '%s *file.zip' "${digest}"
		sum_cmd="$(find_sum_binary)"
		case "${sum_cmd}" in
			(*/busybox*) "${sum_cmd}" sha256sum -cs SUMS ;;
			(*/sha256sum) "${sum_cmd}" --status -c SUMS ;;
			(*) false ;;
		esac
		rm SUMS
	fi
	case "${cmd}" in
		(*/busybox*) "${cmd}" unzip file.zip ;;
		(*/unzip*) "${cmd}" file.zip ;;
		(*/7z*) "${cmd}" x file.zip ;;
		(*/bsdtar*) "${cmd}" -xf file.zip ;;
		(*/sqlite3) "${cmd}" -A -xf file.zip ;;
	esac

	chmod +x deno
	./deno -V >/dev/null 2>&1
	test '!' -f ../deno || mv ../deno ../.removed.deno.$$
	mv deno ../deno
	rm -f file.zip ../.removed.deno.$$
	cd ..
	rmdir "${work_dir}"
)

extract_cmd="$(find_unzip_binary)"
if ! check_unzip_binary "${extract_cmd}"; then
	echo "Error: either unzip or 7z is required to install Deno (see: https://github.com/denoland/deno_install#either-unzip-or-7z-is-required )." 1>&2
	exit 1
fi

if [ "$OS" = "Windows_NT" ]; then
	target="x86_64-pc-windows-msvc"
else
	case "$(uname -sm)" in
	"Darwin x86_64") target="x86_64-apple-darwin" ;;
	"Darwin arm64") target="aarch64-apple-darwin" ;;
	"Linux aarch64") target="aarch64-unknown-linux-gnu" ;;
	"Linux x86_64") target="x86_64-unknown-linux-gnu" ;;
	*) echo "Error: unsupported target: $(uname -sm)" 1>&2 ; exit 1 ;;
	esac
fi

print_help_and_exit() {
	echo "Setup script for installing deno

Options:
  -y, --yes
    Skip interactive prompts and accept defaults
  --no-modify-path
    Don't add deno to the PATH environment variable
  -h, --help
    Print help
"
	echo "Note: Deno was not installed"
	exit 0
}

# Initialize variables
should_run_shell_setup=false

# Simple arg parsing - look for help flag, otherwise
# ignore args starting with '-' and take the first
# positional arg as the deno version to install
for arg in "$@"; do
	case "$arg" in
	"-h")
		print_help_and_exit
		;;
	"--help")
		print_help_and_exit
		;;
	"-y")
		should_run_shell_setup=true
		;;
	"--yes")
		should_run_shell_setup=true
		;;
	"-"*) ;;
	*)
		if [ -z "$deno_version" ]; then
			deno_version="$arg"
		fi
		;;
	esac
done
if [ -z "$deno_version" ]; then
	deno_version="$(curl -s https://dl.deno.land/release-latest.txt)"
fi

deno_uri="https://dl.deno.land/release/${deno_version}/deno-${target}.zip"
deno_install="${DENO_INSTALL:-$HOME/.deno}"
bin_dir="$deno_install/bin"
exe="$bin_dir/deno"

if [ ! -d "$bin_dir" ]; then
	mkdir -p "$bin_dir"
fi

curl --fail --location --progress-bar -- "${deno_uri}" | \
	extract_with_unzip_binary "${bin_dir}" "${extract_cmd}" \
	$(curl --fail --location -- "${deno_uri}.sha256sum")
if $exe eval 'const [major, minor] = Deno.version.deno.split(".").map(Number); if (major < 2 || (major === 2 && minor < 6)) Deno.exit(1)'; then
	"$exe" x --install-alias
	# shellcheck disable=SC2016
	echo 'Installed dx alias, if this conflicts with an existing command, you can remove it with `rm $(which dx)` and choose a new name with `dx --install-alias <new-name>`'
fi
echo "Deno was installed successfully to $exe"

run_shell_setup() {
	$exe run -A --reload jsr:@deno/installer-shell-setup/bundled "$deno_install" "$@"
}

# If stdout is a terminal, see if we can run shell setup script (which includes interactive prompts)
if { [ -z "$CI" ] && [ -t 1 ]; } || $should_run_shell_setup; then
	if $exe eval 'const [major, minor] = Deno.version.deno.split(".").map(Number); if (major < 1 || (major === 1 && minor < 42)) Deno.exit(1)'; then
		if $should_run_shell_setup; then
			run_shell_setup -y "$@" # doublely sure to pass -y to run_shell_setup in this case
		else
			if [ -t 0 ]; then
				run_shell_setup "$@"
			else
				# This script is probably running piped into sh, so we don't have direct access to stdin.
				# Instead, explicitly connect /dev/tty to stdin
				run_shell_setup "$@" </dev/tty
			fi
		fi
	fi
fi
if command -v deno >/dev/null; then
	echo "Run 'deno --help' to get started"
else
	echo "Run '$exe --help' to get started"
fi
echo
echo "Stuck? Join our Discord https://discord.gg/deno"
