#!/bin/bash
# Step 3: Rename MABEAM Modules
echo "Renaming Foundation.Mabeam to Mabeam in all .ex and .exs files..."
find /home/home/p/g/n/elixir_ml/foundation/lib /home/home/p/g/n/elixir_ml/foundation/test -type f \( -name "*.ex" -o -name "*.exs" \) -exec sed -i 's/Foundation.Mabeam/Mabeam/g' {} +
echo "Done."
