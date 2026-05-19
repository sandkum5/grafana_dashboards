#!/bin/bash

# Description: This script facilitates the automated export and import of Grafana dashboards.
# Configuration:
#   - GRAFANA_URL: Set the base URL for the target Grafana instance.
#   - TOKEN: Provide a valid API token with appropriate permissions.
#   - Backup_dir: Specify the local directory path for dashboard storage and retrieval.

GRAFANA_URL=${GRAFANA_URL:-"http://localhost:3000"}
GRAFANA_TOKEN=${GRAFANA_TOKEN:-"your_api_token_here"}

BACKUP_DIR="./dashboards"

# Helper: Recursively build the folder path string
get_folder_path() {
    local uid=$1
    if [[ -z "$uid" || "$uid" == "0" || "$uid" == "general" ]]; then
        echo "General"
        return
    fi
    
    local folder_json=$(curl -s -H "Authorization: Bearer $GRAFANA_TOKEN" "$GRAFANA_URL/api/folders/$uid")
    local title=$(echo "$folder_json" | jq -r '.title // "Unknown"')
    local parent_uid=$(echo "$folder_json" | jq -r '.parentUid // empty')
    
    if [[ -n "$parent_uid" ]]; then
        echo "$(get_folder_path "$parent_uid")/$title"
    else
        echo "$title"
    fi
}

export_dashboards() {
    echo "Exporting with nested folder structure..."
    mkdir -p "$BACKUP_DIR"

    results=$(curl -s -H "Authorization: Bearer $GRAFANA_TOKEN" "$GRAFANA_URL/api/search?type=dash-db")
    
    echo "$results" | jq -c '.[]' | while read -r item; do
        uid=$(echo "$item" | jq -r '.uid')
        folder_uid=$(echo "$item" | jq -r '.folderUid // "0"')
        
        full_path=$(get_folder_path "$folder_uid")
        dash_title=$(echo "$item" | jq -r '.title' | tr ' /' '__')
        
        echo "Exporting: [$full_path] -> $dash_title"
        mkdir -p "$BACKUP_DIR/$full_path"
        
        # FIXED: Joined into one line to prevent "unexpected token |" error
        curl -s -H "Authorization: Bearer $GRAFANA_TOKEN" "$GRAFANA_URL/api/dashboards/uid/$uid" | jq '.dashboard | .id=null' > "$BACKUP_DIR/$full_path/$dash_title.json"
    done
}

import_dashboards() {
    echo "Starting fixed import (General folder fix)..."

    CACHE_FILE=$(mktemp)
    echo "General:0" > "$CACHE_FILE"
    echo ".:0" >> "$CACHE_FILE"

    find "$BACKUP_DIR" -name "*.json" | while read -r dash_file; do
        full_dir=$(dirname "$dash_file")
        rel_path=${full_dir#$BACKUP_DIR/}
        
        # Determine if we are in General or a specific folder
        if [[ -z "$rel_path" || "$rel_path" == "." || "$rel_path" == "General" ]]; then
            target_folder_uid="general"
            is_general=true
        else
            is_general=false
            target_folder_uid=$(grep "^${rel_path}:" "$CACHE_FILE" | tail -n 1 | cut -d':' -f2)
            
            # (Folder resolution logic remains the same as your previous version...)
            if [ -z "$target_folder_uid" ]; then
                IFS='/' read -ra ADDR <<< "$rel_path"
                current_parent_uid=""
                segment_path=""
                for folder_name in "${ADDR[@]}"; do
                    [ -z "$folder_name" ] && continue
                    [ -z "$segment_path" ] && segment_path="$folder_name" || segment_path="$segment_path/$folder_name"
                    seg_uid=$(grep "^${segment_path}:" "$CACHE_FILE" | tail -n 1 | cut -d':' -f2)
                    if [ -z "$seg_uid" ]; then
                        payload=$(jq -n --arg title "$folder_name" --arg puid "$current_parent_uid" '{title: $title, parentUid: $puid}')
                        resp=$(curl -s -X POST -H "Authorization: Bearer $GRAFANA_TOKEN" -H "Content-Type: application/json" -d "$payload" "$GRAFANA_URL/api/folders")
                        seg_uid=$(echo "$resp" | jq -r '.uid // empty' 2>/dev/null)
                        [[ -z "$seg_uid" || "$seg_uid" == "null" ]] && seg_uid=$(curl -s -H "Authorization: Bearer $GRAFANA_TOKEN" "$GRAFANA_URL/api/search?type=dash-folder&query=$folder_name" | jq -r ".[] | select(.title==\"$folder_name\") | .uid" | head -n 1)
                        echo "${segment_path}:${seg_uid}" >> "$CACHE_FILE"
                    fi
                    current_parent_uid="$seg_uid"
                done
                target_folder_uid="$current_parent_uid"
            fi
        fi

        # FINAL IMPORT PAYLOAD
        echo "  -> Importing $(basename "$dash_file") into: ${rel_path:-General}"

        if [ "$is_general" = true ]; then
            # Use folderId: 0 for General folder compatibility
            import_payload=$(jq -n --slurpfile dash "$dash_file" \
                '{"dashboard": $dash[0], "folderId": 0, "overwrite": true}')
        else
            # Use folderUid for all other folders
            import_payload=$(jq -n --slurpfile dash "$dash_file" --arg fuid "$target_folder_uid" \
                '{"dashboard": $dash[0], "folderUid": $fuid, "overwrite": true}')
        fi
        
        curl -s -X POST -H "Authorization: Bearer $GRAFANA_TOKEN" \
             -H "Content-Type: application/json" \
             -d "$import_payload" \
             "$GRAFANA_URL/api/dashboards/db" | jq -c '{"status": .status, "msg": .message}'
    done
    rm "$CACHE_FILE"
}

case "$1" in
    export) export_dashboards ;;
    import) import_dashboards ;;
    *) echo "Usage: $0 {export|import}"; exit 1 ;;
esac


