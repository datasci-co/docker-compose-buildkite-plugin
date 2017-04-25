
# Show a prompt for a command
function plugin_prompt() {
  if [[ -z "${HIDE_PROMPT:-}" ]] ; then
    echo -ne "\033[90m$\033[0m" >&2
    printf " %q" "$@" >&2
    echo >&2
  fi
}

# Shows the command being run, and runs it
function plugin_prompt_and_run() {
  plugin_prompt "$@"
  "$@"
}

# Shows the command about to be run, and exits if it fails
function plugin_prompt_and_must_run() {
  plugin_prompt_and_run "$@" || exit $?
}

# Shorthand for reading env config
function plugin_read_config() {
  local var="BUILDKITE_PLUGIN_DOCKER_COMPOSE_${1}"
  local default="${2:-}"
  echo "${!var:-$default}"
}

# Read agent metadata for pre-built images, returns empty string on error
function plugin_get_build_image_metadata() {
  local service="$1"
  local key="docker-compose-plugin-built-image-tag-${service}"
  plugin_prompt buildkite-agent meta-data get "$key"
  buildkite-agent meta-data get "$key" 2>/dev/null || true
}

# Write agent metadata for pre-built images, exits on error
function plugin_set_build_image_metadata() {
  local service="$1"
  local value="$2"
  plugin_prompt_and_must_run buildkite-agent meta-data set \
    "docker-compose-plugin-built-image-tag-${service}" "$value"
}

# Reads either a value or a list from plugin config
function plugin_read_list() {
  local prefix="BUILDKITE_PLUGIN_DOCKER_COMPOSE_$1"
  local parameter="${prefix}_0"

  if [[ -n "${!parameter:-}" ]]; then
    local i=0
    local parameter="${prefix}_${i}"
    while [[ -n "${!parameter:-}" ]]; do
      echo "${!parameter}"
      i=$((i+1))
      parameter="${prefix}_${i}"
    done
  elif [[ -n "${!prefix:-}" ]]; then
    echo "${!prefix}"
  else
    return 1
  fi
}

# Returns the name of the docker compose project for this build
function docker_compose_project_name() {
  # No dashes or underscores because docker-compose will remove them anyways
  echo "buildkite${BUILDKITE_JOB_ID//-}"
}

# Returns the name of the docker compose container that corresponds to the
# given service
function docker_compose_container_name() {
  echo "$(docker_compose_project_name)_$1"
}

# Returns all docker compose config file names split by newlines
function docker_compose_config_files() {
  if ! config_files=( $( plugin_read_list CONFIG ) ) ; then
    echo "docker-compose.yml"
  fi

  # Process any (deprecated) colon delimited config paths
  for value in "${config_files[@]}" ; do
    echo "$value" | tr ':' '\n'
  done
}

# Returns the first docker compose config file name
function docker_compose_config_file() {
  if ! config_files=( $(docker_compose_config_files) ) ; then
    echo "docker-compose.yml"
  fi

  echo "${config_files[0]}"
}

# Returns the version of the first docker compose config file
function docker_compose_config_version() {
  sed -n "s/version: ['\"]\(.*\)['\"]/\1/p" < "$(docker_compose_config_file)"
}

# Build an docker-compose file that overrides the image for a given service
function build_image_override_file() {
  local service="$1"
  local image="$2"
  local version

  version="$(docker_compose_config_version)"
  build_image_override_file_with_version "$version" "$service" "$image"
}

# Build an docker-compose file that overrides the image for a given service and version
function build_image_override_file_with_version() {
  local version="$1"
  local service="$2"
  local image="$3"

  printf "version: '%s'\n" "$version"
  printf "services:\n"
  printf "  %s:\n" "$service"
  printf "    image: %s\n" "$image"
}

# Runs the docker-compose command, scoped to the project, with the given arguments
function run_docker_compose() {
  local command=(docker-compose)

  for file in $(docker_compose_config_files) ; do
    command+=(-f "$file")
  done

  command+=(-p "$(docker_compose_project_name)")

  plugin_prompt_and_run "${command[@]}" "$@"
}
