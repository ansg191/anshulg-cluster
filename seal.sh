#!/usr/bin/env bash
#
# Copyright (c) 2024. Anshul Gupta
# All rights reserved.
#

# This script encrypts secrets using kubeseal

set -eu

CONTROLLER_NAMESPACE="kube-system"
CONTROLLER_NAME="sealed-secrets"

# Finds unencrypted files
find_unencrypted_files() {
	find "$1" -type f -name "*.unencrypted.yaml"
}

main() {
	local search_dir="$1"
	local unencrypted_files
	mapfile -t unencrypted_files < <(find_unencrypted_files "$search_dir")

	for file in "${unencrypted_files[@]}"; do
		local sealed_file="${file//\.unencrypted/}"
		echo "Encrypting $file to $sealed_file"
		kubeseal --controller-name="$CONTROLLER_NAME" --controller-namespace="$CONTROLLER_NAMESPACE" -f "$file" -w "$sealed_file"
	done
}

usage() {
	echo "Usage: $0 [-n namespace] [-c controller name] <dir>" 1>&2
	exit 1
}

while getopts ":n:c:" arg; do
	case $arg in
	n)
		CONTROLLER_NAMESPACE="$OPTARG"
		;;
	c)
		CONTROLLER_NAME="$OPTARG"
		;;
	*)
		usage
		;;
	esac
done
shift $((OPTIND - 1))

# Check if the directory is provided, otherwise use the current directory
SEARCH_DIR="${1:-.}"

main "$SEARCH_DIR"
