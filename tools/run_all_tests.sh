shopt -s nullglob # Allow expansion of patterns with no matches

for file in *.test.dart; do
  echo "Running: $file"
  dart "$file"
  exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    echo "Error running $file: Exit code $exit_code"
    break
  fi
done
