#!/bin/bash
export GPM_RELAY_ONLY=1
exec bash "$(dirname "$0")/bridge.sh"
