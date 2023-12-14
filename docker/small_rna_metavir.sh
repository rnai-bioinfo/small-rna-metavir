# TODO: Arg "prefered runtime"
# TODO: Arg "config file path"

is_verbose="true"
runtime=""

# ===========================================================================
# ---  Set container runtime ------------------------------------------------
# ===========================================================================

# Check if Docker is present and running
if [ "$is_verbose" = "true" ]; then
    echo "Searching for Docker runtime..."
fi

if command -v docker &> /dev/null && docker run hello-world &>/dev/null; then
    runtime="docker"
else

    # Check if podman is present and running
    if [ "$is_verbose" = "true" ]; then
        echo "Docker runtime not detected"
        echo ""
        echo "Searching podman runtime..."
    fi

    if command -v podman &> /dev/null && podman run hello-world &> /dev/null; then
        runtime="podman"
    elif [ "$is_verbose" = "true" ]; then
        echo "podman runtime not detected"
    fi
fi

if [ -z "$runtime" ]; then
    echo "[ERROR] You need a container runtime. Neither Docker nor podman could be found."
    exit 1
fi

if [ "$is_verbose" = "true" ]; then
    echo "Using $runtime runtime..."
fi

# ===========================================================================
# --- Set image up ----------------------------------------------------------
# ===========================================================================

# OK
exit 0