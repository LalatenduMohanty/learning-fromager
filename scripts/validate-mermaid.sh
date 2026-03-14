#!/usr/bin/env bash
# Extracts Mermaid code blocks from Markdown files and validates them
# using the Mermaid CLI (mmdc).
#
# Usage: ./scripts/validate-mermaid.sh [file ...]
#   If no files are given, all *.md files in the repo are checked recursively.

set -euo pipefail

# Determine files to check
if [[ $# -gt 0 ]]; then
    files=("$@")
else
    mapfile -t files < <(find . -name '*.md' -type f -not -path '*/node_modules/*' -not -path '*/.git/*' | sort)
fi

if [[ ${#files[@]} -eq 0 ]]; then
    echo "No Markdown files found."
    exit 0
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

errors=0
total=0

for mdfile in "${files[@]}"; do
    # Extract mermaid blocks: content between ```mermaid and ```
    block_num=0
    in_block=false
    block_content=""

    while IFS= read -r line; do
        if [[ "$in_block" == false ]] && [[ "$line" =~ ^\`\`\`mermaid ]]; then
            in_block=true
            block_content=""
            block_num=$((block_num + 1))
            continue
        fi

        if [[ "$in_block" == true ]]; then
            if [[ "$line" =~ ^\`\`\` ]]; then
                in_block=false
                total=$((total + 1))

                # Write block to temp file and validate
                block_file="$tmpdir/block_${total}.mmd"
                printf '%s\n' "$block_content" > "$block_file"

                mmdc_args=(-i "$block_file" -o "$tmpdir/out_${total}.svg")
                if [[ -n "${PUPPETEER_CONFIG:-}" ]]; then
                    mmdc_args+=(-p "$PUPPETEER_CONFIG")
                fi
                if ! mmdc "${mmdc_args[@]}" 2>"$tmpdir/err_${total}.txt" 1>/dev/null; then
                    errors=$((errors + 1))
                    echo "FAIL: $mdfile (mermaid block #$block_num)"
                    sed 's/^/  /' "$tmpdir/err_${total}.txt"
                else
                    echo "OK:   $mdfile (mermaid block #$block_num)"
                fi
            else
                block_content="${block_content}${line}"$'\n'
            fi
        fi
    done < "$mdfile"

    if [[ "$in_block" == true ]]; then
        errors=$((errors + 1))
        echo "FAIL: $mdfile (mermaid block #$block_num) - unclosed code fence"
    fi
done

echo ""
echo "Validated $total mermaid block(s) across ${#files[@]} file(s): $errors error(s)"

if [[ $errors -gt 0 ]]; then
    exit 1
fi
