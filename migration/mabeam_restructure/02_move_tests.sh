#!/bin/bash
# Step 2: Relocate MABEAM Test Files
echo "Moving MABEAM tests from test/foundation/mabeam to test/mabeam..."
mkdir -p /home/home/p/g/n/elixir_ml/foundation/test/mabeam
mv /home/home/p/g/n/elixir_ml/foundation/test/foundation/mabeam/* /home/home/p/g/n/elixir_ml/foundation/test/mabeam/
rmdir /home/home/p/g/n/elixir_ml/foundation/test/foundation/mabeam
echo "Done."
