#!/bin/bash
set -euo pipefail

NO_CACHE="${NO_CACHE:-}"
COUNT="${COUNT:-0}"

clean () {
	rm -f ???_build-*.log
}

build () {
	DIR="$1"
	TAG="$2"
	NAME="${TAG#*/}"
	shift
	shift

	OCI=".oci.${TAG//\//-}"
	COUNT=$(( $COUNT + 1 ))
	LOG=$(printf "%03d_build-%s.log" "$COUNT" "$NAME")
	DEFAULT_JOBS=$(( ( $(nproc --all) + 1 ) / 2 ))
	JOBS="${JOBS:-$DEFAULT_JOBS}"
	BUILDX_DRIVER=$(docker buildx inspect --bootstrap 2>/dev/null | awk -F': ' '/^Driver:/ {print $2}')
	if [ -z "${BUILDX_DRIVER:-}" ]; then
		BUILDX_DRIVER="unknown"
	fi
	# Default to --load unless we can confirm an OCI-capable driver.
	USE_LOAD=1
	if [ "$BUILDX_DRIVER" = "docker-container" ] || [ "$BUILDX_DRIVER" = "kubernetes" ]; then
		USE_LOAD=0
	fi
	if [ -n "${FORCE_LOAD:-}" ]; then
		USE_LOAD=1
	fi

	echo "*" | tee "$LOG"
	echo "* $(date): building $NAME (using JOBS=$JOBS)" | tee -a "$LOG"
	echo "* $(date): log in $LOG" | tee -a "$LOG"
	echo "*" | tee -a "$LOG"
	if [ -n "${CIRCLECI:-}" ] || [ -n "${CI:-}" ] || [ "$USE_LOAD" -eq 1 ]; then
		if ! time DOCKER_BUILDKIT=1 BUILDKIT_PROGRESS=plain docker buildx build \
			"$DIR" \
			"$@" \
			-t "$TAG":latest \
			--progress=plain \
			--build-arg="JOBS=$JOBS" \
			-f "$DIR"/"$NAME"/Dockerfile \
			--load \
			2>&1 | tee -a "$LOG"; then
			echo "* $(date): failed $NAME (driver=$BUILDX_DRIVER, output=load)" | tee -a "$LOG"
			exit 1
		fi
	else
		if ! time DOCKER_BUILDKIT=1 BUILDKIT_PROGRESS=plain docker buildx build \
			"$DIR" \
			"$@" \
			-t "$TAG":latest \
			--progress=plain \
			--build-arg="JOBS=$JOBS" \
			-f "$DIR"/"$NAME"/Dockerfile \
			--output=type=oci,tar=false,dest="${OCI}" \
			--output=type=oci,tar=true,dest="${OCI}.tar" \
			2>&1 | tee -a "$LOG"; then
			echo "* $(date): failed $NAME (driver=$BUILDX_DRIVER, output=oci)" | tee -a "$LOG"
			exit 1
		fi
		if ! time docker load -i "${OCI}.tar" 2>&1 | tee -a "$LOG"; then
			echo "* $(date): failed $NAME (driver=$BUILDX_DRIVER, docker load)" | tee -a "$LOG"
			exit 1
		fi
	fi
	echo "*" | tee -a "$LOG"
	echo "* $(date): finished $NAME" | tee -a "$LOG"
	echo "*" | tee -a "$LOG"
}

list () {
	REF="$1"

	date
	docker image list -f "reference=${REF}"
}
