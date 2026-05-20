#!/usr/bin/env bash

set -euo pipefail

dotnet run --project Zinc.Bootstrapper.csproj -c Release -- "$@"