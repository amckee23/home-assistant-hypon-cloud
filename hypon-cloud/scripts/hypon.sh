#!/usr/bin/with-contenv bashio

declare LOGIN_TEMPLATE='{"username":"","password":"","oem":null}'
declare HYPON_URL="https://api.hypon.cloud/v2"
declare ACCEPT_HEADER="accept: application/json"
declare CONTENT_HEADER="content-type: application/json;charset=UTF-8"

# ------------------------------------------------------------------------------
# Authenticate with the Hypon Cloud Platform
#
# Arguments
#  $1 The template value for the sensor
#  $2 The value to use for the sensor
#  $3 The name of the sensor
# ------------------------------------------------------------------------------
loginHypon () {
    local username
    local password
    local loginData

    local loginResponse

    username=$(bashio::config 'username')
    password=$(bashio::config 'password')
    loginData=$(echo "$LOGIN_TEMPLATE" | jq .username="\"$username\"" | jq .password="\"$password\"" | jq .oem=null)

    bashio::log.info "Login Start"

    loginResponse=$(curl -s "$HYPON_URL/login" \
      -H "$ACCEPT_HEADER" \
      -H "$CONTENT_HEADER" \
      -H 'User-Agent: Mozilla/5.0' \
      --data-raw "$loginData")
      
      token=$(echo "$loginResponse" | jq -er '.data.token') || {
        bashio::log.error "Login Failed"
        return 1
      }

      bashio::log.info "Login End"
      echo "$token"
}

# ------------------------------------------------------------------------------
# Retrieve solar data from the Hypon Cloud Platform
#
# Arguments
#  $1 The authentication token to use
# ------------------------------------------------------------------------------
retrieveSolarData () {
  local authToken=${1}
  local system_id
  local dataUrl
  local dataRequest

    system_id=$(bashio::config 'system_id')
    dataUrl="$HYPON_URL/plant/$system_id/energy2?day=$(date +%d)&month=$(date +%m)&type=day&year=$(date +%Y)"

        bashio::log.info "Load Solar Data Start"

    dataRequest=$(curl -s "$dataUrl" \
                              -H "$ACCEPT_HEADER" \
                              -H 'User-Agent: Mozilla/5.0' \
                              -H "authorization: Bearer $authToken")

    if ! echo "$dataRequest" | jq -e . >/dev/null 2>&1; then
      bashio::log.error "Solar data response is not valid JSON"
      echo "{}"
      return 0
    fi

        bashio::log.info "Load Solar Data End"

    echo "$dataRequest"
}

# ------------------------------------------------------------------------------
# Retrieve real time solar data from the Hypon Cloud Platform
#
# Arguments
#  $1 The authentication token to use
# ------------------------------------------------------------------------------
retrieveRealTimeSolarData () {
  local authToken=${1}
  local system_id
  local dataUrl
  local dataRequest

    bashio::log.info "Load Realtime Start"

    system_id=$(bashio::config 'system_id')
    dataUrl="$HYPON_URL/plant/$system_id/monitor?refresh=true"
    dataRequest=$(curl -s "$dataUrl" \
                              -H "$ACCEPT_HEADER" \
                              -H 'User-Agent: Mozilla/5.0' \
                              -H "authorization: Bearer $authToken")

    if ! echo "$dataRequest" | jq -e . >/dev/null 2>&1; then
      bashio::log.error "Realtime data response is not valid JSON"
      echo "{}"
      return 0
    fi
    
    bashio::log.info "Load Realtime Data End"
    echo "$dataRequest"
}

# ------------------------------------------------------------------------------
# Send a payload to the inverter config endpoint.
#
# Arguments
#  $1 The authentication token to use
#  $2 JSON payload body
# ------------------------------------------------------------------------------
sendInverterConfigPayload () {
  local authToken=${1}
  local payload=${2}
  local configEndpoint
  local configMethod
  local response
  local responseCode
  local responseMessage

  configEndpoint=$(bashio::config 'config_put_endpoint')
  if [ -z "$configEndpoint" ] || [ "$configEndpoint" = "null" ]; then
    configEndpoint="/inverter/config"
  fi

  if [[ "$configEndpoint" != /* ]]; then
    configEndpoint="/$configEndpoint"
  fi

  configMethod=$(bashio::config 'config_put_method')
  if [ -z "$configMethod" ] || [ "$configMethod" = "null" ]; then
    configMethod="PUT"
  fi
  configMethod=$(echo "$configMethod" | tr '[:lower:]' '[:upper:]')

  response=$(curl -s "$HYPON_URL$configEndpoint" \
    -X "$configMethod" \
    -H "$ACCEPT_HEADER" \
    -H "$CONTENT_HEADER" \
    -H 'User-Agent: Mozilla/5.0' \
    -H "authorization: Bearer $authToken" \
    --data-raw "$payload")

  if echo "$response" | jq -e . >/dev/null 2>&1; then
    responseCode=$(echo "$response" | jq -r '.code // "unknown"')
    responseMessage=$(echo "$response" | jq -r '.message // "unknown"')
  else
    responseCode="non_json"
    responseMessage="Non-JSON response from Hypon API"
  fi

  if [ "$responseCode" = "20000" ]; then
    bashio::log.info "TimeMode settings applied successfully"
    return 0
  fi

  bashio::log.error "Failed to apply TimeMode settings. method=$configMethod endpoint=$configEndpoint code=$responseCode message=$responseMessage"
  bashio::log.debug "TimeMode config response: $response"
  return 1
}

# ------------------------------------------------------------------------------
# Wait for inverter response endpoint to return HTTP 200.
#
# Arguments
#  $1 The authentication token to use
#  $2 Inverter serial number
#  $3 Timeout in seconds
#  $4 Poll interval in seconds
# ------------------------------------------------------------------------------
waitForInverterResponse200 () {
  local authToken=${1}
  local inverterSn=${2}
  local timeoutSeconds=${3}
  local intervalSeconds=${4}
  local elapsed=0
  local response
  local httpCode
  local responseBody

  while [ "$elapsed" -lt "$timeoutSeconds" ]
  do
    response=$(curl -s "$HYPON_URL/inverter/$inverterSn/response" \
      -H "$ACCEPT_HEADER" \
      -H 'User-Agent: Mozilla/5.0' \
      -H "authorization: Bearer $authToken" \
      --write-out '\n%{http_code}')

    httpCode=${response##*$'\n'}
    responseBody=${response%$'\n'*}

    if [ "$httpCode" = "200" ]; then
      bashio::log.info "Inverter response endpoint returned HTTP 200"
      return 0
    fi

    bashio::log.debug "Waiting for inverter response endpoint. http=$httpCode elapsed=${elapsed}s"
    sleep "$intervalSeconds"
    elapsed=$((elapsed + intervalSeconds))
  done

  bashio::log.error "Timed out waiting for inverter response endpoint HTTP 200"
  bashio::log.debug "Last inverter response body: $responseBody"
  return 1
}

